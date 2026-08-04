-- Step 2: make public-schema access explicit and tenant-aware.
--
-- This migration intentionally removes direct client writes to global sports
-- data. Apply it to production only after the SofaScore sync has moved to a
-- trusted worker. SECURITY DEFINER maintenance functions and service_role keep
-- their owner-level access.

-- New tables and sequences must be exposed deliberately in the same migration
-- that creates them. This also opts the project into Supabase's 2026 explicit
-- Data API grant model for postgres-owned objects.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

-- Start from no direct client access. service_role retains its existing grants
-- and bypasses RLS for trusted backend work.
revoke all privileges on all tables in schema public from anon, authenticated;
revoke all privileges on all sequences in schema public from anon, authenticated;

-- All public tables are part of the exposed Data API schema and therefore need
-- RLS, including tables whose direct client grants remain empty.
do $migration$
declare
  table_record record;
  policy_record record;
begin
  for table_record in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
  loop
    execute format(
      'alter table public.%I enable row level security',
      table_record.table_name
    );
  end loop;

  -- Replace the old public/anonymous policies as one reviewed policy set.
  for policy_record in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      policy_record.policyname,
      policy_record.tablename
    );
  end loop;
end
$migration$;

-- A non-exposed helper avoids recursive policies on league_members. The
-- calling user's identity is checked inside the SECURITY DEFINER function and
-- the empty search_path prevents object-shadowing attacks.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create or replace function app_private.is_league_member(p_league_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.league_members lm
       where lm.league_id = p_league_id
         and lm.user_id = (select auth.uid())
     );
$function$;

revoke execute on function app_private.is_league_member(bigint)
  from public, anon, authenticated, service_role;
-- Policies execute with the caller's role, so authenticated needs EXECUTE on
-- the stored function OID. app_private itself remains outside the exposed Data
-- API schemas and the helper can only inspect membership for auth.uid().
grant execute on function app_private.is_league_member(bigint)
  to authenticated;

-- Reference and sports data are readable after login but are written only by
-- trusted backend code. No client role receives INSERT, UPDATE or DELETE.
grant select on table
  public.formation,
  public.marktwert_historie,
  public.matchrating,
  public.season,
  public.season_players,
  public.season_teams,
  public.spiel,
  public.spieler,
  public.spieler_analytics,
  public.spieltag,
  public.team,
  public.team_analytics,
  public.tournaments
to authenticated;

create policy formation_read_authenticated
  on public.formation for select to authenticated using (true);
create policy marktwert_historie_read_authenticated
  on public.marktwert_historie for select to authenticated using (true);
create policy matchrating_read_authenticated
  on public.matchrating for select to authenticated using (true);
create policy season_read_authenticated
  on public.season for select to authenticated using (true);
create policy season_players_read_authenticated
  on public.season_players for select to authenticated using (true);
create policy season_teams_read_authenticated
  on public.season_teams for select to authenticated using (true);
create policy spiel_read_authenticated
  on public.spiel for select to authenticated using (true);
create policy spieler_read_authenticated
  on public.spieler for select to authenticated using (true);
create policy spieler_analytics_read_authenticated
  on public.spieler_analytics for select to authenticated using (true);
create policy spieltag_read_authenticated
  on public.spieltag for select to authenticated using (true);
create policy team_read_authenticated
  on public.team for select to authenticated using (true);
create policy team_analytics_read_authenticated
  on public.team_analytics for select to authenticated using (true);
create policy tournaments_read_authenticated
  on public.tournaments for select to authenticated using (true);

-- Profiles are visible to the owner and to users who share at least one league.
grant select, insert on table public.profiles to authenticated;
grant update (username, avatar_url, bio) on table public.profiles to authenticated;

create policy profiles_read_shared_league
  on public.profiles for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (
      select 1
      from public.league_members target_membership
      where target_membership.user_id = profiles.user_id
        and (select app_private.is_league_member(target_membership.league_id))
    )
  );

create policy profiles_insert_own
  on public.profiles for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy profiles_update_own
  on public.profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- A league can be read when it is public or the caller belongs to it. Only its
-- administrator can update the client-editable presentation fields.
grant select on table public.leagues to authenticated;
grant update (settings, image_url) on table public.leagues to authenticated;

create policy leagues_read_public_or_member
  on public.leagues for select to authenticated
  using (
    is_public is true
    or admin_id = (select auth.uid())
    or (select app_private.is_league_member(id))
  );

create policy leagues_update_admin
  on public.leagues for update to authenticated
  using (admin_id = (select auth.uid()))
  with check (admin_id = (select auth.uid()));

-- Membership rows are visible only inside leagues the caller belongs to. A
-- user may change only their local tab order, never budget or admin status.
grant select on table public.league_members to authenticated;
grant update (position) on table public.league_members to authenticated;

create policy league_members_read_same_league
  on public.league_members for select to authenticated
  using ((select app_private.is_league_member(league_id)));

create policy league_members_update_own_position
  on public.league_members for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select on table public.league_players to authenticated;

create policy league_players_read_same_league
  on public.league_players for select to authenticated
  using ((select app_private.is_league_member(league_id)));

grant select on table public.league_activities to authenticated;

create policy league_activities_read_same_league
  on public.league_activities for select to authenticated
  using ((select app_private.is_league_member(league_id)));

-- Transfer listings and bids are isolated by league. Listing and ownership
-- mutations remain behind RPC functions; the client only creates/deletes its
-- own bids.
grant select on table public.transfer_market to authenticated;

create policy transfer_market_read_same_league
  on public.transfer_market for select to authenticated
  using ((select app_private.is_league_member(league_id)));

grant select, insert, delete on table public.transfer_bids to authenticated;
grant usage, select on sequence public.transfer_bids_id_seq to authenticated;

create policy transfer_bids_read_same_league
  on public.transfer_bids for select to authenticated
  using (
    exists (
      select 1
      from public.transfer_market tm
      where tm.id = transfer_bids.transfer_id
        and (select app_private.is_league_member(tm.league_id))
    )
  );

create policy transfer_bids_insert_own
  on public.transfer_bids for insert to authenticated
  with check (
    bidder_id = (select auth.uid())
    and amount > 0
    and exists (
      select 1
      from public.transfer_market tm
      where tm.id = transfer_bids.transfer_id
        and tm.is_active is true
        and tm.seller_id is distinct from (select auth.uid())
        and transfer_bids.amount >= tm.min_bid_price
        and (select app_private.is_league_member(tm.league_id))
    )
  );

create policy transfer_bids_delete_own
  on public.transfer_bids for delete to authenticated
  using (
    bidder_id = (select auth.uid())
    and exists (
      select 1
      from public.transfer_market tm
      where tm.id = transfer_bids.transfer_id
        and (select app_private.is_league_member(tm.league_id))
    )
  );

-- Matchday data is visible to league members. Only the owner can change their
-- unlocked formation fields; scoring and locks remain server-owned.
grant select on table
  public.user_matchday_points,
  public.user_matchday_players
to authenticated;
grant update (formation) on table public.user_matchday_points to authenticated;
grant update (formation_index) on table public.user_matchday_players to authenticated;

create policy user_matchday_points_read_same_league
  on public.user_matchday_points for select to authenticated
  using ((select app_private.is_league_member(league_id)));

create policy user_matchday_points_update_own_unlocked
  on public.user_matchday_points for update to authenticated
  using (
    user_id = (select auth.uid())
    and is_locked is false
    and (select app_private.is_league_member(league_id))
  )
  with check (
    user_id = (select auth.uid())
    and (select app_private.is_league_member(league_id))
  );

create policy user_matchday_players_read_same_league
  on public.user_matchday_players for select to authenticated
  using (
    exists (
      select 1
      from public.user_matchday_points ump
      where ump.id = user_matchday_players.matchday_point_id
        and (select app_private.is_league_member(ump.league_id))
    )
  );

create policy user_matchday_players_update_own_unlocked
  on public.user_matchday_players for update to authenticated
  using (
    is_locked is false
    and exists (
      select 1
      from public.user_matchday_points ump
      where ump.id = user_matchday_players.matchday_point_id
        and ump.user_id = (select auth.uid())
        and (select app_private.is_league_member(ump.league_id))
    )
  )
  with check (
    exists (
      select 1
      from public.user_matchday_points ump
      where ump.id = user_matchday_players.matchday_point_id
        and ump.user_id = (select auth.uid())
        and (select app_private.is_league_member(ump.league_id))
    )
  );

-- Replace the broad direct leagues UPDATE with a narrow member action.
create or replace function public.touch_league_activity(p_league_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if (select auth.uid()) is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  update public.leagues league
  set last_activity_at = now(),
      is_active = true
  where league.id = p_league_id
    and exists (
      select 1
      from public.league_members membership
      where membership.league_id = league.id
        and membership.user_id = (select auth.uid())
    );

  if not found then
    raise exception using
      errcode = '42501',
      message = 'League membership required';
  end if;
end;
$function$;

revoke execute on function public.touch_league_activity(bigint)
  from public, anon;
grant execute on function public.touch_league_activity(bigint)
  to authenticated;

-- Index policy predicates and the most common league-scoped reads. The unique
-- (league_id, user_id) membership index already covers the helper lookup.
create index if not exists idx_league_activities_league_id
  on public.league_activities (league_id);
create index if not exists idx_league_players_league_user
  on public.league_players (league_id, user_id);
create index if not exists idx_transfer_market_league_id
  on public.transfer_market (league_id);
create index if not exists idx_transfer_bids_transfer_id
  on public.transfer_bids (transfer_id);
create index if not exists idx_transfer_bids_bidder_id
  on public.transfer_bids (bidder_id);

-- These tables are intentionally server-only and therefore receive no direct
-- anon/authenticated grants or client policies:
--   api_debug_dump, api_sync_lock, game_settings, processed_transfers,
--   sync_tasks
