-- Inspected production table shapes, 2026-09-11. No production rows.
-- Test-only Auth/Cron stubs; legacy RPC definitions retained to exercise real worker permissions.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT jsonb_build_object('role',coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'authenticated')) $$;
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated,service_role;
CREATE SCHEMA cron;
CREATE TABLE cron.job(jobname text PRIMARY KEY,schedule text,command text);
CREATE FUNCTION cron.schedule(text,text,text) RETURNS bigint LANGUAGE sql AS $$ INSERT INTO cron.job VALUES ($1,$2,$3) ON CONFLICT(jobname) DO UPDATE SET schedule=excluded.schedule,command=excluded.command RETURNING 1::bigint $$;
CREATE TABLE public.leagues (
id bigint NOT NULL,
name text NOT NULL,
admin_id uuid NOT NULL,
season_id bigint,
starting_budget numeric(12,2) NOT NULL DEFAULT 100000.00,
settings jsonb DEFAULT '{}'::jsonb,
created_at timestamp with time zone NOT NULL DEFAULT now(),
is_public boolean DEFAULT false,
squad_limit integer,
num_starting_players integer DEFAULT 0,
starting_team_value bigint DEFAULT 0,
is_active boolean DEFAULT true,
last_activity_at timestamp with time zone DEFAULT now(),
image_url text,
tournament_id bigint,
PRIMARY KEY (id)
);
CREATE TABLE public.season (
id bigint NOT NULL,
name text NOT NULL,
is_active boolean DEFAULT true,
last_schedule_update timestamp with time zone DEFAULT '2000-01-01 00:00:00+00'::timestamp with time zone,
tournament_id bigint,
is_initialized boolean DEFAULT false,
PRIMARY KEY (id)
);
CREATE TABLE public.season_players (
season_id bigint NOT NULL,
player_id integer NOT NULL,
team_id integer NOT NULL,
is_active boolean NOT NULL DEFAULT true,
UNIQUE (season_id, player_id, team_id)
);
CREATE TABLE public.season_teams (
season_id bigint NOT NULL,
team_id integer NOT NULL,
PRIMARY KEY (season_id, team_id)
);
CREATE TABLE public.spiel (
id integer NOT NULL,
datum timestamp without time zone NOT NULL,
heimteam_id integer,
"auswärtsteam_id" integer,
ergebnis text,
status text,
round integer,
season_id bigint,
hometeam_formation text,
awayteam_formation text,
last_updated_at timestamp with time zone DEFAULT '2000-01-01 00:00:00+00'::timestamp with time zone,
incidents jsonb DEFAULT '[]'::jsonb,
home_color_primary text,
home_color_number text,
away_color_primary text,
away_color_number text,
home_goalkeeper_color_primary text,
away_goalkeeper_color_primary text,
UNIQUE (id),
PRIMARY KEY (id)
);
CREATE TABLE public.spieler_analytics (
spieler_id integer NOT NULL,
marktwert integer,
calculated_marktwert integer,
gesamtstatistiken jsonb DEFAULT '{}'::jsonb,
anzahl_spiele integer DEFAULT 0,
punkteschnitt numeric DEFAULT 0.0,
form numeric DEFAULT 0.0,
startelf_quote numeric DEFAULT 0.0,
expected_points numeric DEFAULT 0.0,
last_updated_at timestamp with time zone DEFAULT now(),
season_id bigint NOT NULL,
PRIMARY KEY (spieler_id, season_id)
);
CREATE TABLE public.spieltag (
round integer NOT NULL,
status text NOT NULL,
season_id bigint NOT NULL,
best_formation text,
matchday_start timestamp with time zone,
matchday_end timestamp with time zone,
PRIMARY KEY (round, season_id)
);
CREATE TABLE public.sync_tasks (
id uuid NOT NULL DEFAULT gen_random_uuid(),
task_type text NOT NULL,
status text DEFAULT 'PENDING'::text,
priority integer DEFAULT 5,
depends_on_task_id uuid,
tournament_id bigint,
season_id bigint,
round_id integer,
match_id bigint,
locked_at timestamp with time zone,
locked_by uuid,
error_message text,
created_at timestamp with time zone DEFAULT now(),
team_id bigint,
updated_at timestamp with time zone DEFAULT now(),
PRIMARY KEY (id)
);
CREATE TABLE public.team (
id integer NOT NULL,
name text NOT NULL,
image_url text,
UNIQUE (id),
UNIQUE (name),
PRIMARY KEY (id)
);
CREATE TABLE public.tournaments (
id bigint NOT NULL,
name text NOT NULL,
country_name text,
created_at timestamp with time zone DEFAULT now(),
image_url text,
PRIMARY KEY (id)
);
CREATE OR REPLACE FUNCTION public.complete_sync_task(p_task_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_next_sync_task(p_user_id uuid)
 RETURNS SETOF sync_tasks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.season TO authenticated;
GRANT SELECT ON public.tournaments,public.sync_tasks TO authenticated;
ALTER TABLE public.sync_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY sync_tasks_read_authenticated ON public.sync_tasks FOR SELECT TO authenticated USING(true);

