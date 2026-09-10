-- Restore the functional 88f0576 client flow without reopening privileged maintenance RPCs.
-- Queue rows are observable by authenticated clients, but mutations go through ownership-checked RPCs.
revoke insert, update, delete on table public.sync_tasks from anon, authenticated;
revoke select on table public.sync_tasks from anon;
grant select on table public.sync_tasks to authenticated;

drop policy if exists "Jeder darf Sync-Tasks lesen" on public.sync_tasks;
drop policy if exists "User dürfen Sync-Tasks erstellen" on public.sync_tasks;
drop policy if exists "User dürfen Tasks updaten" on public.sync_tasks;
drop policy if exists sync_tasks_read_authenticated on public.sync_tasks;
create policy sync_tasks_read_authenticated
on public.sync_tasks for select to authenticated using (true);

create or replace function public.get_next_sync_task(p_user_id uuid)
returns setof public.sync_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
begin
  if not v_is_service and (v_uid is null or p_user_id is distinct from v_uid) then
    raise exception 'Cannot claim sync tasks for another user' using errcode = '42501';
  end if;

  return query
  with next_task as (
    select t.id
    from public.sync_tasks t
    where (
      t.status = 'PENDING'
      or (t.status = 'PROCESSING' and t.locked_at < now() - interval '10 minutes')
    )
    and (
      t.depends_on_task_id is null
      or exists (
        select 1 from public.sync_tasks parent
        where parent.id = t.depends_on_task_id and parent.status = 'COMPLETED'
      )
    )
    order by t.priority asc, t.created_at asc, t.id
    for update of t skip locked
    limit 1
  )
  update public.sync_tasks t
  set status = 'PROCESSING',
      locked_at = now(),
      locked_by = p_user_id,
      updated_at = now(),
      error_message = null
  from next_task n
  where t.id = n.id
  returning t.*;
end;
$$;

create or replace function public.complete_sync_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
begin
  if not v_is_service and v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.sync_tasks
  set status = 'COMPLETED',
      locked_at = null,
      locked_by = null,
      error_message = null,
      updated_at = now()
  where id = p_task_id
    and status = 'PROCESSING'
    and (v_is_service or locked_by = v_uid);

  if not found then
    raise exception 'Task reservation is missing or belongs to another user' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.fail_sync_task(p_task_id uuid, p_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
begin
  if not v_is_service and v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.sync_tasks
  set status = 'PENDING',
      locked_at = null,
      locked_by = null,
      error_message = left(coalesce(p_error, 'Unknown error'), 1500),
      updated_at = now()
  where id = p_task_id
    and status = 'PROCESSING'
    and (v_is_service or locked_by = v_uid);

  if not found then
    raise exception 'Task reservation is missing or belongs to another user' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.renew_sync_task(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
begin
  if not v_is_service and v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.sync_tasks
  set locked_at = now(), updated_at = now()
  where id = p_task_id
    and status = 'PROCESSING'
    and (v_is_service or locked_by = v_uid);

  if not found then
    raise exception 'Task reservation is missing or belongs to another user' using errcode = '42501';
  end if;
end;
$$;

-- cleanup_duplicate_matches stays server-only. mark_schedule_updated is the
-- authenticated entry point and may execute cleanup only after recent sync authorization.
create or replace function public.mark_schedule_updated(p_season_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
  v_allowed boolean := false;
begin
  if v_is_service then
    v_allowed := true;
  elsif v_uid is not null then
    select exists (
      select 1
      from public.api_sync_lock l
      where l.id = 1
        and l.is_locked_by = v_uid
        and l.last_sync_at > now() - interval '30 minutes'
    ) or exists (
      select 1
      from public.sync_tasks t
      where t.locked_by = v_uid
        and t.status = 'PROCESSING'
        and t.season_id = p_season_id
        and t.task_type in ('FETCH_MATCHES', 'UPDATE_SCHEDULE')
        and t.locked_at > now() - interval '10 minutes'
    ) into v_allowed;
  end if;

  if not v_allowed then
    raise exception 'An active sync permission is required' using errcode = '42501';
  end if;

  if not exists (select 1 from public.season s where s.id = p_season_id and s.is_active) then
    raise exception 'Season is not active' using errcode = '22023';
  end if;

  perform public.cleanup_duplicate_matches(p_season_id);
  update public.season set last_schedule_update = now() where id = p_season_id;
end;
$$;

-- Transfer import can only be performed by the client that owns the matching queue task.
create or replace function public.process_transfer_event(
  p_transfer_id bigint,
  p_player_id bigint,
  p_from_team_id bigint,
  p_to_team_id bigint,
  p_season_id integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
  v_team_exists boolean;
  v_player_exists boolean;
begin
  if not v_is_service and (
    v_uid is null or not exists (
      select 1 from public.sync_tasks st
      where st.locked_by = v_uid
        and st.status = 'PROCESSING'
        and st.locked_at > now() - interval '10 minutes'
        and st.task_type = 'SYNC_TRANSFERS'
        and st.season_id = p_season_id
    )
  ) then
    raise exception 'An owned SYNC_TRANSFERS task is required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(p_transfer_id);

  if exists (select 1 from public.processed_transfers pt where pt.transfer_id = p_transfer_id) then
    return false;
  end if;

  select exists (select 1 from public.spieler s where s.id = p_player_id)
  into v_player_exists;

  if not v_player_exists then
    insert into public.processed_transfers (transfer_id)
    values (p_transfer_id)
    on conflict (transfer_id) do nothing;
    return false;
  end if;

  if p_from_team_id is not null then
    update public.season_players
    set is_active = false
    where player_id = p_player_id
      and season_id = p_season_id
      and team_id = p_from_team_id
      and is_active = true;
  end if;

  if p_to_team_id is not null then
    select exists (select 1 from public.team t where t.id = p_to_team_id)
    into v_team_exists;

    if v_team_exists then
      insert into public.season_players (season_id, player_id, team_id, is_active)
      values (p_season_id, p_player_id, p_to_team_id, true)
      on conflict on constraint season_players_unique_combo
      do update set is_active = true;
    end if;
  end if;

  insert into public.processed_transfers (transfer_id)
  values (p_transfer_id)
  on conflict (transfer_id) do nothing;

  return true;
end;
$$;

-- Preserve the existing user-facing system transfer feature, but constrain it
-- to leagues the caller belongs to and the league's real season.
create or replace function public.generate_daily_transfers(
  p_league_id bigint,
  p_season_id bigint,
  p_amount integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  player_rec record;
  v_random_hours numeric;
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
begin
  if p_amount is null or p_amount < 1 or p_amount > 20 then
    raise exception 'p_amount must be between 1 and 20' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.leagues l
    where l.id = p_league_id and l.season_id = p_season_id
  ) then
    raise exception 'League/season mismatch' using errcode = '22023';
  end if;

  if not v_is_service and (
    v_uid is null or not exists (
      select 1 from public.league_members lm
      where lm.league_id = p_league_id and lm.user_id = v_uid
    )
  ) then
    raise exception 'League membership required' using errcode = '42501';
  end if;

  for player_rec in
    select s.id, sa.marktwert
    from public.spieler s
    join public.spieler_analytics sa
      on sa.spieler_id = s.id and sa.season_id = p_season_id
    where exists (
      select 1 from public.season_players sp
      where sp.player_id = s.id and sp.season_id = p_season_id
    )
    and not exists (
      select 1 from public.league_players lp
      where lp.player_id = s.id and lp.league_id = p_league_id
    )
    and not exists (
      select 1 from public.transfer_market tm
      where tm.player_id = s.id and tm.league_id = p_league_id and tm.is_active = true
    )
    and sa.marktwert is not null and sa.marktwert > 0
    order by random()
    limit p_amount
  loop
    v_random_hours := 24 + (random() * 48);
    insert into public.transfer_market (
      league_id, player_id, seller_id, listed_at, expires_at,
      min_bid_price, buy_now_price, is_active
    ) values (
      p_league_id, player_rec.id, null, now(),
      now() + (v_random_hours * interval '1 hour'),
      player_rec.marktwert, player_rec.marktwert + 3000000, true
    );
  end loop;
end;
$$;

-- Forward-compatible narrow queue request entry points used by the repaired coordinator.
create or replace function public.request_match_sync(p_match_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match record;
begin
  if auth.uid() is null and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select sp.id, sp.season_id, s.tournament_id
  into strict v_match
  from public.spiel sp
  join public.season s on s.id = sp.season_id and s.is_active
  where sp.id = p_match_id;

  perform pg_advisory_xact_lock(p_match_id);

  if not exists (
    select 1 from public.sync_tasks t
    where t.match_id = p_match_id
      and t.task_type = 'UPDATE_MATCH'
      and (
        t.status in ('PENDING','PROCESSING','WAITING')
        or t.updated_at > now() - interval '2 minutes'
      )
  ) then
    insert into public.sync_tasks(task_type,tournament_id,season_id,match_id,status,priority)
    values ('UPDATE_MATCH',v_match.tournament_id,v_match.season_id,p_match_id,'PENDING',5);
  end if;
end;
$$;

create or replace function public.request_season_sync(p_season_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season public.season;
begin
  if auth.uid() is null and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into strict v_season
  from public.season
  where id = p_season_id and is_active
  for update;

  if not v_season.is_initialized and not exists (
    select 1 from public.sync_tasks
    where season_id = p_season_id
      and task_type in ('FETCH_TEAMS','FETCH_TEAM_SQUAD','FETCH_SQUADS','FETCH_ROUNDS','FETCH_MATCHES')
      and status in ('PENDING','PROCESSING','WAITING')
  ) then
    insert into public.sync_tasks(task_type,tournament_id,season_id,status,priority)
    values ('FETCH_TEAMS',v_season.tournament_id,p_season_id,'PENDING',10);
  end if;
end;
$$;

revoke execute on function public.get_next_sync_task(uuid) from public, anon;
revoke execute on function public.complete_sync_task(uuid) from public, anon;
revoke execute on function public.fail_sync_task(uuid, text) from public, anon;
revoke execute on function public.renew_sync_task(uuid) from public, anon;
revoke execute on function public.cleanup_duplicate_matches(bigint) from public, anon, authenticated;
revoke execute on function public.mark_schedule_updated(bigint) from public, anon;
revoke execute on function public.process_transfer_event(bigint,bigint,bigint,bigint,integer) from public, anon;
revoke execute on function public.generate_daily_transfers(bigint,bigint,integer) from public, anon;
revoke execute on function public.process_expired_transfers() from public, anon;
revoke execute on function public.request_match_sync(bigint) from public, anon;
revoke execute on function public.request_season_sync(bigint) from public, anon;

grant execute on function public.get_next_sync_task(uuid) to authenticated, service_role;
grant execute on function public.complete_sync_task(uuid) to authenticated, service_role;
grant execute on function public.fail_sync_task(uuid, text) to authenticated, service_role;
grant execute on function public.renew_sync_task(uuid) to authenticated, service_role;
grant execute on function public.mark_schedule_updated(bigint) to authenticated, service_role;
grant execute on function public.process_transfer_event(bigint,bigint,bigint,bigint,integer) to authenticated, service_role;
grant execute on function public.generate_daily_transfers(bigint,bigint,integer) to authenticated, service_role;
grant execute on function public.process_expired_transfers() to authenticated, service_role;
grant execute on function public.request_match_sync(bigint) to authenticated, service_role;
grant execute on function public.request_season_sync(bigint) to authenticated, service_role;
