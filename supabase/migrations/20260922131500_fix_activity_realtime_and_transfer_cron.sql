-- Restores the activity feed subscription without publishing other league data.
-- League activities remain protected by the existing league-membership SELECT RLS policy.
DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'league_activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.league_activities;
  END IF;
END
$migration$;

-- pg_cron executes these jobs as the database login postgres. auth.uid() and
-- auth.jwt() are NULL in that trusted session, unlike a service_role API call.
-- Only the original login role (session_user), NOT current_user (which becomes
-- postgres inside SECURITY DEFINER), can distinguish the cron session from
-- a PostgREST request from authenticated/anon clients.
DO $migration$
DECLARE
  function_sql text;
  old_guard text := 'IF auth.uid() IS NULL AND COALESCE(auth.jwt()->>''role'', '''') <> ''service_role'' THEN';
  cron_guard text := 'IF session_user <> ''postgres'' AND auth.uid() IS NULL AND COALESCE(auth.jwt()->>''role'', '''') <> ''service_role'' THEN';
BEGIN
  SELECT pg_get_functiondef('public.process_expired_transfers()'::regprocedure)
  INTO function_sql;
  IF position(cron_guard IN function_sql) = 0 THEN
    IF position(old_guard IN function_sql) = 0 THEN
      RAISE EXCEPTION 'Unexpected process_expired_transfers authorization guard; review before migrating';
    END IF;
    EXECUTE replace(function_sql, old_guard, cron_guard);
  END IF;
END
$migration$;

DO $migration$
DECLARE
  function_sql text;
  old_guard text := 'if not v_is_service and (';
  cron_guard text := 'if session_user <> ''postgres'' and not v_is_service and (';
BEGIN
  SELECT pg_get_functiondef('public.generate_daily_transfers(bigint,bigint,integer)'::regprocedure)
  INTO function_sql;
  IF position(cron_guard IN function_sql) = 0 THEN
    IF position(old_guard IN function_sql) = 0 THEN
      RAISE EXCEPTION 'Unexpected generate_daily_transfers authorization guard; review before migrating';
    END IF;
    EXECUTE replace(function_sql, old_guard, cron_guard);
  END IF;
END
$migration$;

-- The scheduled orchestrator is an internal maintenance entry point, not
-- an RPC for mobile/browser users. Cron runs it as postgres unaffected by this.
REVOKE EXECUTE ON FUNCTION public.process_random_system_transfers()
  FROM PUBLIC, anon, authenticated;
