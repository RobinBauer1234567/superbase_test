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
    order by t.priority desc, t.created_at asc, t.id
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
