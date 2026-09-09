-- Client queue access is mediated by narrow RPCs, not writable queue rows.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;
alter table public.sync_tasks add column attempts integer not null default 0;
alter table public.sync_tasks add column next_attempt_at timestamptz not null default now();
revoke all on public.sync_tasks from public, anon, authenticated;
grant select on public.sync_tasks to authenticated;
drop policy if exists "Jeder darf Sync-Tasks lesen" on public.sync_tasks;
drop policy if exists "User dürfen Sync-Tasks erstellen" on public.sync_tasks;
drop policy if exists "User dürfen Tasks updaten" on public.sync_tasks;
create policy sync_task_read on public.sync_tasks for select to authenticated using (true);

create or replace function private.claim_sync_task(p_user_id uuid)
returns setof public.sync_tasks language plpgsql security definer set search_path = '' as $$
begin
  if p_user_id is null or (coalesce(auth.jwt()->>'role','') <> 'service_role'
      and (auth.uid() is null or p_user_id is distinct from auth.uid())) then
    raise exception 'Cannot claim tasks for another user' using errcode = '42501';
  end if;
  return query
  with candidate as (
    select t.id from public.sync_tasks t
    join public.season s on s.id = t.season_id and s.is_active
    where (t.status = 'PENDING' and t.next_attempt_at <= now())
       or (t.status = 'PROCESSING' and t.locked_at < now() - interval '10 minutes')
    order by t.priority, t.created_at, t.id
    for update of t skip locked limit 1
  )
  update public.sync_tasks t set status = 'PROCESSING', locked_at = now(),
    locked_by = p_user_id, updated_at = now(), attempts = t.attempts + 1
  from candidate c where t.id = c.id returning t.*;
end $$;

create or replace function private.finish_sync_task(p_task_id uuid, p_error text, p_success boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null and coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'Authentication required' using errcode = '42501'; end if;
  -- Serialize dependency fan-in across clients finishing different squad tasks.
  perform 1 from public.season s join public.sync_tasks t on t.season_id=s.id
    where t.id=p_task_id for update of s;
  update public.sync_tasks set
    status = case when p_success then 'COMPLETED' when attempts >= 5 then 'FAILED' else 'PENDING' end,
    error_message = case when p_success then null else left(coalesce(p_error, 'Unknown error'),1500) end,
    next_attempt_at = now() + make_interval(secs => least(1800, 30 * power(2, least(attempts,6))::int)),
    locked_at = null, locked_by = null, updated_at = now()
  where id = p_task_id and status = 'PROCESSING' and (locked_by = auth.uid() or coalesce(auth.jwt()->>'role','')='service_role')
    and locked_at >= now() - interval '10 minutes';
  if not found then raise exception 'Task reservation is missing, expired or belongs to another user' using errcode = '42501'; end if;
end $$;

create or replace function private.renew_sync_task(p_task_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.sync_tasks set locked_at = now(), updated_at = now()
  where id = p_task_id and status = 'PROCESSING' and (locked_by = auth.uid() or coalesce(auth.jwt()->>'role','')='service_role')
    and locked_at >= now() - interval '10 minutes';
  if not found then raise exception 'Task reservation expired' using errcode = '42501'; end if;
end $$;

create or replace function public.get_next_sync_task(p_user_id uuid)
returns setof public.sync_tasks language sql security invoker set search_path = ''
as $$ select * from private.claim_sync_task(p_user_id) $$;
create or replace function public.complete_sync_task(p_task_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.finish_sync_task(p_task_id, null, true) $$;
create or replace function public.fail_sync_task(p_task_id uuid, p_error text)
returns void language sql security invoker set search_path = ''
as $$ select private.finish_sync_task(p_task_id, p_error, false) $$;
create function public.renew_sync_task(p_task_id uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.renew_sync_task(p_task_id) $$;

-- Manual updates use the same queue. No second importer runs in the UI.
create function private.request_match_sync(p_match_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare v_match record;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select sp.*, s.tournament_id into strict v_match from public.spiel sp
    join public.season s on s.id = sp.season_id and s.is_active where sp.id = p_match_id;
  perform pg_advisory_xact_lock(p_match_id);
  if not exists(select 1 from public.sync_tasks where match_id = p_match_id
      and task_type = 'UPDATE_MATCH' and (status in ('PENDING','PROCESSING','WAITING')
        or updated_at > now() - interval '2 minutes')) then
    insert into public.sync_tasks(task_type,tournament_id,season_id,match_id,status)
    values ('UPDATE_MATCH',v_match.tournament_id,v_match.season_id,p_match_id,'PENDING');
  end if;
end $$;
create function public.request_match_sync(p_match_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select private.request_match_sync(p_match_id) $$;

-- Retry initialization only for active seasons. Existing work remains intact.
create function private.request_season_sync(p_season_id bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare v_season public.season;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into strict v_season from public.season where id=p_season_id and is_active for update;
  if not v_season.is_initialized and not exists(select 1 from public.sync_tasks where season_id=p_season_id
      and task_type in ('FETCH_TEAMS','FETCH_TEAM_SQUAD','FETCH_SQUADS','FETCH_ROUNDS','FETCH_MATCHES')) then
    insert into public.sync_tasks(task_type,tournament_id,season_id,priority)
    values ('FETCH_TEAMS',v_season.tournament_id,p_season_id,10);
  end if;
end $$;
create function public.request_season_sync(p_season_id bigint)
returns void language sql security invoker set search_path = ''
as $$ select private.request_season_sync(p_season_id) $$;

-- A successful cron invocation is distinct from a successful season update.
create table private.market_value_runs (
  id bigint generated always as identity primary key,
  season_id bigint not null references public.season(id),
  run_date date not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null check (status in ('running','succeeded','failed')),
  updated_players integer not null default 0,
  error_message text,
  unique(season_id,run_date)
);
create or replace function public.daily_marktwert_update()
returns void language plpgsql security definer set search_path = '' as $$
declare v_season bigint; v_settings public.game_settings; v_count integer; v_run bigint;
begin
  -- Prevent overlapping manual/cron runs and a second adjustment on retries.
  if not pg_try_advisory_xact_lock(7194823109::bigint) then return; end if;
  for v_season in select id from public.season where is_active order by id loop
    v_run := null;
    insert into private.market_value_runs(season_id,run_date,status)
    values(v_season,(now() at time zone 'UTC')::date,'running')
    on conflict(season_id,run_date) do update set status='running',started_at=now(),error_message=null
      where market_value_runs.status='failed' returning id into v_run;
    if v_run is null then continue; end if;
    begin
      select * into strict v_settings from public.game_settings where id=1;
      perform public.update_all_matchup_faktors(v_season);
      perform public.update_all_spieler_analytics(v_season);
      update public.spieler_analytics set
        calculated_marktwert=round(v_settings.mw_multiplier * power(coalesce(expected_points,0),v_settings.mw_exponent)+v_settings.mw_base_value),
        marktwert=round(marktwert + ((v_settings.mw_multiplier * power(coalesce(expected_points,0),v_settings.mw_exponent)+v_settings.mw_base_value)-marktwert)*v_settings.mw_daily_adjustment),
        last_updated_at=now()
      where season_id=v_season;
      get diagnostics v_count = row_count;
      update private.market_value_runs set status='succeeded',updated_players=v_count,finished_at=clock_timestamp() where id=v_run;
    exception when others then
      update private.market_value_runs set status='failed',updated_players=0,
        error_message=sqlstate || ': ' || sqlerrm,finished_at=clock_timestamp() where id=v_run;
      raise warning 'Market value update failed for season %: %',v_season,sqlerrm;
    end;
  end loop;
end $$;
revoke all on private.market_value_runs from public, anon, authenticated;
grant select on private.market_value_runs to service_role;
revoke all on function public.daily_marktwert_update() from public, anon, authenticated;
grant execute on function public.daily_marktwert_update() to service_role;

revoke all on function private.claim_sync_task(uuid), private.finish_sync_task(uuid,text,boolean),
  private.renew_sync_task(uuid),private.request_match_sync(bigint),private.request_season_sync(bigint)
  from public,anon;
grant execute on function private.claim_sync_task(uuid), private.finish_sync_task(uuid,text,boolean),
  private.renew_sync_task(uuid),private.request_match_sync(bigint),private.request_season_sync(bigint)
  to authenticated,service_role;
revoke all on function public.get_next_sync_task(uuid),public.complete_sync_task(uuid),
  public.fail_sync_task(uuid,text),public.renew_sync_task(uuid),public.request_match_sync(bigint),public.request_season_sync(bigint)
  from public,anon;
grant execute on function public.get_next_sync_task(uuid),public.complete_sync_task(uuid),
  public.fail_sync_task(uuid,text),public.renew_sync_task(uuid),public.request_match_sync(bigint),public.request_season_sync(bigint)
  to authenticated,service_role;
create or replace function private.process_transfer_event(
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
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
  v_team_exists boolean;
  v_player_exists boolean;
begin
  if not v_is_service and (
    v_uid is null
    or not exists (
      select 1
      from public.sync_tasks st
      where st.locked_by = v_uid
        and st.status = 'PROCESSING'
        and st.locked_at >= now() - interval '10 minutes'
        and st.task_type = 'SYNC_TRANSFERS'
        and st.season_id = p_season_id
    )
  ) then
    raise exception 'An owned SYNC_TRANSFERS task is required.'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(p_transfer_id);
  if exists (
    select 1
    from public.processed_transfers pt
    where pt.transfer_id = p_transfer_id
  ) then
    return false;
  end if;

  select exists (
    select 1 from public.spieler s where s.id = p_player_id
  ) into v_player_exists;

  if not v_player_exists then
    insert into public.processed_transfers (transfer_id)
    values (p_transfer_id)
    on conflict (transfer_id) do nothing;
    return false;
  end if;

  if p_from_team_id is not null then
    update public.season_players sp
    set is_active = false
    where sp.player_id = p_player_id
      and sp.season_id = p_season_id
      and sp.team_id = p_from_team_id
      and sp.is_active = true;
  end if;

  if p_to_team_id is not null then
    select exists (
      select 1 from public.team t where t.id = p_to_team_id
    ) into v_team_exists;

    if v_team_exists then
      insert into public.season_players (
        season_id,
        player_id,
        team_id,
        is_active
      )
      values (
        p_season_id,
        p_player_id,
        p_to_team_id,
        true
      )
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


create or replace function public.process_transfer_event(p_transfer_id bigint,p_player_id bigint,p_from_team_id bigint,p_to_team_id bigint,p_season_id integer)
returns boolean language sql security invoker set search_path = '' as $$
select private.process_transfer_event(p_transfer_id,p_player_id,p_from_team_id,p_to_team_id,p_season_id)
$$;
revoke all on function private.process_transfer_event(bigint,bigint,bigint,bigint,integer) from public,anon;
revoke all on function public.process_transfer_event(bigint,bigint,bigint,bigint,integer) from public,anon;
grant execute on function private.process_transfer_event(bigint,bigint,bigint,bigint,integer) to authenticated,service_role;
grant execute on function public.process_transfer_event(bigint,bigint,bigint,bigint,integer) to authenticated,service_role;

-- Import writes remain available only while this user owns relevant work.
create function private.owns_sync_work(p_season bigint,p_types text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(auth.jwt()->>'role','')='service_role' or (auth.uid() is not null and exists (
    select 1 from public.sync_tasks t where t.locked_by=auth.uid() and t.status='PROCESSING'
      and t.locked_at >= now()-interval '10 minutes' and t.task_type=any(p_types)
      and (p_season is null or t.season_id=p_season)
  ))
$$;
revoke all on function private.owns_sync_work(bigint,text[]) from public,anon;
grant execute on function private.owns_sync_work(bigint,text[]) to authenticated;

-- Policies do not expose import data to signed-out callers. Server-side
-- calculation and trigger functions retain their existing owner privileges.
do $$ declare item record; begin
  for item in select * from (values
    ('spiel','season_id','{FETCH_MATCHES,UPDATE_SCHEDULE,UPDATE_MATCH}'),
    ('spieltag','season_id','{FETCH_ROUNDS,FETCH_MATCHES,UPDATE_SCHEDULE,UPDATE_MATCH}'),
    ('season_teams','season_id','{FETCH_TEAMS}'),
    ('season_players','season_id','{FETCH_TEAM_SQUAD,FETCH_SQUADS,SYNC_TRANSFERS}'),
    ('team','null','{FETCH_TEAMS}'),
    ('spieler','null','{FETCH_TEAM_SQUAD,FETCH_SQUADS,REPAIR_PLAYERS}')
  ) as t(table_name,season_column,task_types) loop
    execute format('alter table public.%I enable row level security',item.table_name);
    execute format('revoke all on public.%I from public,anon,authenticated',item.table_name);
    execute format('grant select,insert,update on public.%I to authenticated',item.table_name);
    execute format('create policy sync_read on public.%I for select to authenticated using(true)',item.table_name);
    execute format('create policy sync_insert on public.%I for insert to authenticated with check(private.owns_sync_work(%s,%L::text[]))',item.table_name,item.season_column,item.task_types);
    execute format('create policy sync_update on public.%I for update to authenticated using(private.owns_sync_work(%s,%L::text[])) with check(private.owns_sync_work(%s,%L::text[]))',item.table_name,item.season_column,item.task_types,item.season_column,item.task_types);
  end loop;
end $$;
drop policy if exists season_players_insert_authenticated on public.season_players;

-- Derived sports data is read by the app and written by the guarded RPCs/jobs.
do $$ declare table_name text; begin
  foreach table_name in array array['matchrating','spieler_analytics','team_analytics','processed_transfers'] loop
    execute format('alter table public.%I enable row level security',table_name);
    execute format('revoke all on public.%I from public,anon,authenticated',table_name);
    execute format('grant select on public.%I to authenticated',table_name);
    execute format('create policy sync_derived_read on public.%I for select to authenticated using(true)',table_name);
  end loop;
end $$;
alter table public.api_debug_dump enable row level security;
revoke all on public.api_debug_dump from public,anon,authenticated;

-- Existing privileged sports import RPCs also require an owned task.
-- Keep public signatures for Flutter; the implementations are not Data API endpoints.
alter function public.init_player_from_sofascore(bigint,bigint,text,integer,text,numeric[]) set schema private;
alter function private.init_player_from_sofascore(bigint,bigint,text,integer,text,numeric[]) rename to import_player_impl;
alter function public.process_match_lineups(bigint,bigint,jsonb) set schema private;
alter function private.process_match_lineups(bigint,bigint,jsonb) rename to import_lineups_impl;
revoke create on schema public from public,anon,authenticated;
alter function private.import_player_impl(bigint,bigint,text,integer,text,numeric[]) set search_path = public,pg_temp;
alter function private.import_lineups_impl(bigint,bigint,jsonb) set search_path = public,pg_temp;
create function private.import_player(p_player_id bigint,p_season_id bigint,p_formation text,p_lineup_index integer,p_api_position text,p_ratings numeric[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.owns_sync_work(p_season_id,array['FETCH_TEAM_SQUAD','FETCH_SQUADS','REPAIR_PLAYERS']) then
    raise exception 'An owned player import task is required' using errcode='42501';
  end if;
  perform private.import_player_impl(p_player_id,p_season_id,p_formation,p_lineup_index,p_api_position,p_ratings);
end $$;
create function public.init_player_from_sofascore(p_player_id bigint,p_season_id bigint,p_formation text,p_lineup_index integer,p_api_position text,p_ratings numeric[])
returns void language sql security invoker set search_path = '' as $$
select private.import_player(p_player_id,p_season_id,p_formation,p_lineup_index,p_api_position,p_ratings)
$$;
create function private.import_lineups(p_spiel_id bigint,p_season_id bigint,p_raw_json jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' and not exists(select 1 from public.sync_tasks t join public.spiel s on s.id=t.match_id and s.season_id=t.season_id
    where t.match_id=p_spiel_id and t.season_id=p_season_id and t.task_type='UPDATE_MATCH'
      and t.status='PROCESSING' and t.locked_by=auth.uid() and t.locked_at>=now()-interval '10 minutes') then
    raise exception 'An owned match import task is required' using errcode='42501';
  end if;
  perform private.import_lineups_impl(p_spiel_id,p_season_id,p_raw_json);
end $$;
create function public.process_match_lineups(p_spiel_id bigint,p_season_id bigint,p_raw_json jsonb)
returns void language sql security invoker set search_path = '' as $$
select private.import_lineups(p_spiel_id,p_season_id,p_raw_json)
$$;
revoke all on function private.import_player_impl(bigint,bigint,text,integer,text,numeric[]),
  private.import_lineups_impl(bigint,bigint,jsonb) from public,anon,authenticated;
revoke all on function private.import_player(bigint,bigint,text,integer,text,numeric[]),
  private.import_lineups(bigint,bigint,jsonb),public.init_player_from_sofascore(bigint,bigint,text,integer,text,numeric[]),
  public.process_match_lineups(bigint,bigint,jsonb) from public,anon;
grant execute on function private.import_player(bigint,bigint,text,integer,text,numeric[]),
  private.import_lineups(bigint,bigint,jsonb),public.init_player_from_sofascore(bigint,bigint,text,integer,text,numeric[]),
  public.process_match_lineups(bigint,bigint,jsonb) to authenticated,service_role;

notify pgrst, 'reload schema';
