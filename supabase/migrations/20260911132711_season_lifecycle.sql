-- Additive lifecycle migration for the inspected ManagerSpiel production schema.
-- Abort on ambiguous legacy state; never choose/delete an existing active row silently.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.season WHERE is_active GROUP BY tournament_id HAVING count(*) > 1)
     OR EXISTS (SELECT 1 FROM public.season WHERE tournament_id IS NULL) THEN
    RAISE EXCEPTION 'Resolve ambiguous season tournament/active state before migration';
  END IF;
END $$;
ALTER TABLE public.season ALTER COLUMN is_active SET DEFAULT false;
ALTER TABLE public.season ALTER COLUMN tournament_id SET NOT NULL;
ALTER TABLE public.season ADD COLUMN discovered_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.season ADD COLUMN archived_at timestamptz;
ALTER TABLE public.season ADD COLUMN initialization_started_at timestamptz;
UPDATE public.season s SET initialization_started_at = now()
WHERE s.is_initialized OR EXISTS (
  SELECT 1 FROM public.sync_tasks t WHERE t.season_id=s.id AND t.task_type='FETCH_TEAMS');
CREATE UNIQUE INDEX season_one_active_per_tournament ON public.season(tournament_id) WHERE is_active;
CREATE UNIQUE INDEX season_id_tournament_unique ON public.season(id,tournament_id);
CREATE INDEX season_tournament_lookup ON public.season(tournament_id);

CREATE FUNCTION public.season_start_year(p_name text) RETURNS integer
LANGUAGE sql IMMUTABLE STRICT SECURITY INVOKER SET search_path = '' AS $$
  SELECT CASE WHEN trim(p_name) ~ '^([0-9]{4}|[0-9]{2})([/\-][0-9]{2,4})?$'
    THEN CASE WHEN length(substring(trim(p_name) from '^([0-9]+)'))=2 THEN 2000 ELSE 0 END
      + substring(trim(p_name) from '^([0-9]+)')::integer ELSE -1 END
$$;

-- Stable historical links: only repair the redundant tournament, never the season.
UPDATE public.leagues l SET tournament_id=s.tournament_id
FROM public.season s WHERE s.id=l.season_id AND l.tournament_id IS DISTINCT FROM s.tournament_id;
ALTER TABLE public.leagues ADD CONSTRAINT leagues_season_tournament_fkey
FOREIGN KEY (season_id,tournament_id) REFERENCES public.season(id,tournament_id);
CREATE FUNCTION public.guard_league_season() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_season public.season;
BEGIN
  IF TG_OP='UPDATE' AND NEW.season_id IS DISTINCT FROM OLD.season_id THEN
    RAISE EXCEPTION 'Existing fantasy leagues keep their original season';
  END IF;
  SELECT * INTO v_season FROM public.season WHERE id=NEW.season_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown season'; END IF;
  IF TG_OP='INSERT' AND (v_season.is_active IS NOT TRUE OR v_season.is_initialized IS NOT TRUE) THEN
    RAISE EXCEPTION 'New leagues require the active initialized season';
  END IF;
  NEW.tournament_id := v_season.tournament_id;
  RETURN NEW;
END $$;
CREATE TRIGGER leagues_preserve_season BEFORE INSERT OR UPDATE OF season_id,tournament_id
ON public.leagues FOR EACH ROW EXECUTE FUNCTION public.guard_league_season();

-- Do not re-enqueue any initialization stage on replay, including completed tasks.
CREATE UNIQUE INDEX sync_initialization_stage_once ON public.sync_tasks(season_id,task_type,coalesce(team_id,0))
WHERE task_type IN ('FETCH_TEAMS','FETCH_TEAM_SQUAD','FETCH_ROUNDS','FETCH_MATCHES');
CREATE UNIQUE INDEX sync_one_open_season_check ON public.sync_tasks(tournament_id)
WHERE task_type='CHECK_SEASONS' AND status IN ('PENDING','PROCESSING','WAITING');
CREATE INDEX sync_season_check_history ON public.sync_tasks(tournament_id,created_at DESC)
WHERE task_type='CHECK_SEASONS';

DROP TRIGGER IF EXISTS on_season_activated ON public.season;
CREATE OR REPLACE FUNCTION public.handle_season_activation() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF NEW.is_active IS TRUE AND NEW.is_initialized IS NOT TRUE AND NEW.initialization_started_at IS NULL THEN
    INSERT INTO public.sync_tasks(task_type,tournament_id,season_id,priority,status)
    VALUES ('FETCH_TEAMS',NEW.tournament_id,NEW.id,10,'PENDING') ON CONFLICT DO NOTHING;
    NEW.initialization_started_at := now();
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER on_season_activated BEFORE INSERT OR UPDATE OF is_active ON public.season
FOR EACH ROW EXECUTE FUNCTION public.handle_season_activation();

CREATE OR REPLACE FUNCTION public.check_and_unlock_dependencies() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF NEW.status='COMPLETED' AND OLD.status IS DISTINCT FROM 'COMPLETED' THEN
    -- Serialize fan-in completions across workers; the last squad reliably unlocks rounds.
    IF NEW.task_type IN ('FETCH_TEAMS','FETCH_TEAM_SQUAD','FETCH_ROUNDS','FETCH_MATCHES') THEN
      PERFORM 1 FROM public.season WHERE id=NEW.season_id FOR UPDATE;
    END IF;
    UPDATE public.sync_tasks SET status='PENDING'
    WHERE depends_on_task_id=NEW.id AND status='WAITING';
    IF NEW.task_type='FETCH_TEAMS' THEN
      IF NOT EXISTS (SELECT 1 FROM public.season_teams WHERE season_id=NEW.season_id) THEN
        RAISE EXCEPTION 'Cannot initialize an empty season: no teams imported';
      END IF;
      INSERT INTO public.sync_tasks(task_type,tournament_id,season_id,priority,status)
      VALUES ('FETCH_ROUNDS',NEW.tournament_id,NEW.season_id,10,'WAITING_FOR_SQUADS') ON CONFLICT DO NOTHING;
      INSERT INTO public.sync_tasks(task_type,tournament_id,season_id,team_id,priority,status)
      SELECT 'FETCH_TEAM_SQUAD',NEW.tournament_id,NEW.season_id,team_id,10,'PENDING'
      FROM public.season_teams WHERE season_id=NEW.season_id ON CONFLICT DO NOTHING;
    ELSIF NEW.task_type='FETCH_TEAM_SQUAD' THEN
      IF NOT EXISTS (SELECT 1 FROM public.season_players WHERE season_id=NEW.season_id AND team_id=NEW.team_id) THEN
        RAISE EXCEPTION 'Cannot complete an empty squad';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.sync_tasks WHERE season_id=NEW.season_id
        AND task_type='FETCH_TEAM_SQUAD' AND status IS DISTINCT FROM 'COMPLETED') THEN
        UPDATE public.sync_tasks SET status='PENDING' WHERE season_id=NEW.season_id
          AND task_type='FETCH_ROUNDS' AND status='WAITING_FOR_SQUADS';
      END IF;
    ELSIF NEW.task_type='FETCH_ROUNDS' THEN
      IF NOT EXISTS (SELECT 1 FROM public.spieltag WHERE season_id=NEW.season_id) THEN
        RAISE EXCEPTION 'Cannot initialize an empty schedule: no rounds imported';
      END IF;
      INSERT INTO public.sync_tasks(task_type,tournament_id,season_id,priority,status)
      VALUES ('FETCH_MATCHES',NEW.tournament_id,NEW.season_id,10,'PENDING') ON CONFLICT DO NOTHING;
    ELSIF NEW.task_type='FETCH_MATCHES' THEN
      IF NOT EXISTS (SELECT 1 FROM public.spiel WHERE season_id=NEW.season_id) THEN
        RAISE EXCEPTION 'Cannot finish initialization: no matches imported';
      END IF;
      UPDATE public.season SET is_initialized=true WHERE id=NEW.season_id;
    END IF;
  ELSIF NEW.status='FAILED' AND OLD.status IS DISTINCT FROM 'FAILED' THEN
    UPDATE public.sync_tasks SET status='FAILED',error_message='Predecessor failed'
    WHERE depends_on_task_id=NEW.id AND status='WAITING';
  END IF;
  RETURN NEW;
END $$;

-- Only the cron/service role can perform the transaction. No elevated RPC for clients.
CREATE FUNCTION public.activate_season(p_season_id bigint) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_target public.season; v_tournament bigint;
BEGIN
  SELECT tournament_id INTO STRICT v_tournament FROM public.season WHERE id=p_season_id;
  PERFORM 1 FROM public.tournaments WHERE id=v_tournament FOR UPDATE;
  SELECT * INTO STRICT v_target FROM public.season WHERE id=p_season_id FOR UPDATE;
  IF v_target.is_active THEN RETURN false; END IF;
  IF v_target.archived_at IS NOT NULL OR public.season_start_year(v_target.name)<0 THEN
    RAISE EXCEPTION 'Archived or unrecognized season cannot be activated';
  END IF;
  IF EXISTS (SELECT 1 FROM public.season WHERE tournament_id=v_tournament AND id<>p_season_id
    AND public.season_start_year(name)>public.season_start_year(v_target.name)) THEN
    RAISE EXCEPTION 'Only the latest known season can be activated';
  END IF;
  IF EXISTS (SELECT 1 FROM public.season WHERE tournament_id=v_tournament AND is_active
    AND public.season_start_year(name)>=public.season_start_year(v_target.name)) THEN
    RAISE EXCEPTION 'Automatic rollback or ambiguous same-year transition refused';
  END IF;
  UPDATE public.season SET is_active=false,archived_at=now()
    WHERE tournament_id=v_tournament AND is_active;
  UPDATE public.season SET is_active=true WHERE id=p_season_id;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.activate_season(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.activate_season(bigint) TO service_role;

CREATE TABLE public.season_activation_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id bigint NOT NULL REFERENCES public.season(id),
  requested_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  error_message text
);
ALTER TABLE public.season_activation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.season_activation_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.season_activation_requests TO authenticated;
GRANT ALL ON public.season_activation_requests TO service_role;
CREATE POLICY season_requests_own_read ON public.season_activation_requests FOR SELECT TO authenticated
USING (requested_by=(SELECT auth.uid()));
CREATE POLICY season_requests_own_insert ON public.season_activation_requests FOR INSERT TO authenticated
WITH CHECK (requested_by=(SELECT auth.uid()) AND processed_at IS NULL AND error_message IS NULL
  AND EXISTS (SELECT 1 FROM public.season s WHERE s.id=season_id AND s.archived_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.season newer WHERE newer.tournament_id=s.tournament_id
      AND public.season_start_year(newer.name)>public.season_start_year(s.name))));
CREATE UNIQUE INDEX season_request_one_pending ON public.season_activation_requests(season_id) WHERE processed_at IS NULL;
CREATE INDEX season_requests_owner ON public.season_activation_requests(requested_by);

-- Shared reference data remains readable. Clients may discover inactive rows, but
-- cannot deactivate/activate/delete seasons or write the initialization markers.
ALTER TABLE public.season ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.season FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.season TO anon,authenticated;
GRANT INSERT(id,name,tournament_id,is_active) ON public.season TO authenticated;
GRANT UPDATE(last_schedule_update) ON public.season TO authenticated;
GRANT ALL ON public.season TO service_role;
CREATE POLICY season_read ON public.season FOR SELECT TO anon,authenticated USING (true);
CREATE POLICY season_discover ON public.season FOR INSERT TO authenticated
WITH CHECK (is_active=false AND archived_at IS NULL AND initialization_started_at IS NULL AND is_initialized=false);
CREATE POLICY season_schedule_update ON public.season FOR UPDATE TO authenticated
USING (is_active=true) WITH CHECK (is_active=true);

CREATE FUNCTION public.generate_season_check_tasks() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(809112026);
  INSERT INTO public.sync_tasks(task_type,tournament_id,priority,status)
  SELECT 'CHECK_SEASONS',t.id,2,'PENDING' FROM public.tournaments t
  WHERE NOT EXISTS (SELECT 1 FROM public.sync_tasks q WHERE q.task_type='CHECK_SEASONS'
    AND q.tournament_id=t.id AND (q.status IN ('PENDING','PROCESSING','WAITING') OR q.created_at>now()-interval '23 hours'))
  ON CONFLICT DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.generate_season_check_tasks() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.generate_season_check_tasks() TO service_role;

CREATE FUNCTION public.process_season_lifecycle() RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE r record; candidate bigint;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(809112027);
  FOR r IN SELECT * FROM public.season_activation_requests WHERE processed_at IS NULL ORDER BY created_at,id FOR UPDATE LOOP
    BEGIN
      PERFORM public.activate_season(r.season_id);
      UPDATE public.season_activation_requests SET processed_at=now() WHERE id=r.id;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.season_activation_requests SET processed_at=now(),error_message=SQLERRM WHERE id=r.id;
    END;
  END LOOP;
  -- Only previously opted-in tournaments advance automatically, after a successful check.
  FOR r IN SELECT * FROM public.season WHERE is_active ORDER BY tournament_id LOOP
    SELECT s.id INTO candidate FROM public.season s
    WHERE s.tournament_id=r.tournament_id AND s.archived_at IS NULL
      AND public.season_start_year(s.name)>public.season_start_year(r.name)
      AND public.season_start_year(r.name)>=0
      AND EXISTS (SELECT 1 FROM public.sync_tasks q WHERE q.task_type='CHECK_SEASONS'
        AND q.tournament_id=s.tournament_id AND q.status='COMPLETED' AND q.updated_at>=s.discovered_at)
    ORDER BY public.season_start_year(s.name) DESC,s.id DESC LIMIT 1;
    IF candidate IS NOT NULL THEN PERFORM public.activate_season(candidate); END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.process_season_lifecycle() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.process_season_lifecycle() TO service_role;

-- pg_cron uses the scheduling role (postgres); no credential or privileged client RPC.
SELECT cron.schedule('daily-season-check','15 4 * * *','SELECT public.generate_season_check_tasks();');
SELECT cron.schedule('process-season-lifecycle','* * * * *','SELECT public.process_season_lifecycle();');
-- generate_routine_sync_tasks is deliberately unchanged.
