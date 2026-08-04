-- Step 3: replace public write policies with owner/admin-scoped access.
-- Public buckets remain publicly downloadable; Storage still evaluates these
-- policies for uploads, upserts, deletes, moves and authenticated object info.

-- The current largest image is below 1 MB. Five MiB leaves headroom while
-- preventing unbounded uploads, and all client uploads use JPEG paths/content.
update storage.buckets
set file_size_limit = 5 * 1024 * 1024,
    allowed_mime_types = array[
      'image/jpeg',
      'image/png',
      'image/webp'
    ]::text[]
where id in (
  'avatars',
  'league_images',
  'spielerbilder',
  'tournament_images',
  'wappen'
);

-- Replace the duplicated and globally writable policy set in one transaction.
do $migration$
declare
  policy_record record;
begin
  for policy_record in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
  loop
    execute format(
      'drop policy if exists %I on storage.objects',
      policy_record.policyname
    );
  end loop;
end
$migration$;

-- Storage policies need an authorization lookup that stays independent of
-- public.leagues RLS. The helper accepts only the complete object name and
-- compares it with the canonical path of a league administered by auth.uid().
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create or replace function app_private.can_manage_league_badge(p_object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
     and exists (
       select 1
       from public.leagues league
       where league.admin_id = (select auth.uid())
         and p_object_name = 'league_badges/' || league.id::text || '.jpg'
     );
$function$;

revoke execute on function app_private.can_manage_league_badge(text)
  from public, anon, authenticated, service_role;
grant execute on function app_private.can_manage_league_badge(text)
  to authenticated;

-- Avatar paths are canonical: <auth.uid()>.jpg. Public delivery is provided by
-- the bucket, while SELECT here is required for authenticated upserts.
create policy avatars_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and owner_id = (select auth.uid())::text
    and storage.filename(name) = (select auth.uid())::text || '.jpg'
  );

create policy avatars_insert_own
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and owner_id = (select auth.uid())::text
    and storage.filename(name) = (select auth.uid())::text || '.jpg'
    and coalesce((storage.foldername(name))[1], '') = ''
  );

create policy avatars_update_own
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and owner_id = (select auth.uid())::text
    and storage.filename(name) = (select auth.uid())::text || '.jpg'
  )
  with check (
    bucket_id = 'avatars'
    and owner_id = (select auth.uid())::text
    and storage.filename(name) = (select auth.uid())::text || '.jpg'
    and coalesce((storage.foldername(name))[1], '') = ''
  );

create policy avatars_delete_own
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and owner_id = (select auth.uid())::text
    and storage.filename(name) = (select auth.uid())::text || '.jpg'
  );

-- Flutter stores a league badge as league_badges/<league_id>.jpg in wappen.
-- Only the league administrator may create, inspect for upsert, replace or
-- delete that exact object. Team crests in wappen remain backend-owned.
create policy league_badges_select_admin
  on storage.objects for select to authenticated
  using (
    bucket_id = 'wappen'
    and (storage.foldername(name))[1] = 'league_badges'
    and (select app_private.can_manage_league_badge(name))
  );

create policy league_badges_insert_admin
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'wappen'
    and (storage.foldername(name))[1] = 'league_badges'
    and (select app_private.can_manage_league_badge(name))
  );

create policy league_badges_update_admin
  on storage.objects for update to authenticated
  using (
    bucket_id = 'wappen'
    and (storage.foldername(name))[1] = 'league_badges'
    and (select app_private.can_manage_league_badge(name))
  )
  with check (
    bucket_id = 'wappen'
    and (storage.foldername(name))[1] = 'league_badges'
    and (select app_private.can_manage_league_badge(name))
  );

create policy league_badges_delete_admin
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'wappen'
    and (storage.foldername(name))[1] = 'league_badges'
    and (select app_private.can_manage_league_badge(name))
  );

-- No client write policies are intentionally created for:
--   league_images, spielerbilder, tournament_images,
--   wappen/wappen/* team crests, or the private Overlay bucket.
-- Those assets are written only by a trusted backend/service role.
