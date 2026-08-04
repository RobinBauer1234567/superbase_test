-- Temporary authenticated client worker support.
--
-- Queue processing remains client-side until a trusted server worker is ready.
-- Every queue mutation is tied to auth.uid() so one authenticated client cannot
-- claim or complete a task under another user's lock.

create or replace function public.get_next_sync_task(p_user_id uuid)
returns setof public.sync_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if not v_is_service and (v_uid is null or p_user_id is distinct from v_uid) then
    raise exception 'Not allowed to claim sync tasks for another user.'
      using errcode = '42501';
  end if;

  return query
  with next_task as (
    select st.id
    from public.sync_tasks st
    where (
      st.status = 'PENDING'
      or (
        st.status = 'PROCESSING'
        and st.locked_at < now() - interval '10 minutes'
      )
    )
    order by st.priority asc, st.created_at asc
    for update skip locked
    limit 1
  )
  update public.sync_tasks st
  set
    status = 'PROCESSING',
    locked_at = now(),
    locked_by = case when v_is_service then p_user_id else v_uid end,
    error_message = null,
    updated_at = now()
  from next_task
  where st.id = next_task.id
  returning st.*;
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
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if not v_is_service and v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  update public.sync_tasks st
  set
    status = 'COMPLETED',
    locked_at = null,
    locked_by = null,
    error_message = null,
    updated_at = now()
  where st.id = p_task_id
    and st.status = 'PROCESSING'
    and (v_is_service or st.locked_by = v_uid);

  if not found then
    raise exception 'Sync task is not locked by the current user.'
      using errcode = '42501';
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
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
begin
  if not v_is_service and v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  update public.sync_tasks st
  set
    status = 'PENDING',
    locked_at = null,
    locked_by = null,
    error_message = left(coalesce(p_error, 'Unknown client worker error'), 1500),
    updated_at = now()
  where st.id = p_task_id
    and st.status = 'PROCESSING'
    and (v_is_service or st.locked_by = v_uid);

  if not found then
    raise exception 'Sync task is not locked by the current user.'
      using errcode = '42501';
  end if;
end;
$$;

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
        and st.task_type = 'SYNC_TRANSFERS'
        and st.season_id = p_season_id
    )
  ) then
    raise exception 'An owned SYNC_TRANSFERS task is required.'
      using errcode = '42501';
  end if;

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

revoke all on function public.get_next_sync_task(uuid) from public, anon;
revoke all on function public.complete_sync_task(uuid) from public, anon;
revoke all on function public.fail_sync_task(uuid, text) from public, anon;
revoke all on function public.process_transfer_event(bigint, bigint, bigint, bigint, integer) from public, anon;

grant execute on function public.get_next_sync_task(uuid) to authenticated, service_role;
grant execute on function public.complete_sync_task(uuid) to authenticated, service_role;
grant execute on function public.fail_sync_task(uuid, text) to authenticated, service_role;
grant execute on function public.process_transfer_event(bigint, bigint, bigint, bigint, integer) to authenticated, service_role;
