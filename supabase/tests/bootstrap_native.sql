-- Test-only substitutes for hosted Auth/Storage. No production credentials.
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
create schema auth;
create schema storage;
create schema extensions;
create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$
select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$
select current_setting('request.jwt.claim.role',true) $$;
create function auth.jwt() returns jsonb language sql stable as $$
select jsonb_build_object('sub',auth.uid(),'role',auth.role()) $$;
grant usage on schema auth,public to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;
create table storage.objects(id uuid primary key,bucket_id text,owner uuid,name text);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create publication supabase_realtime;
