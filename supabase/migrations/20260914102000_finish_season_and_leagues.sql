-- A season is sportingly finished once every imported matchday is final.
-- It remains the tournament's active/current season until a newer season is activated.
-- Fantasy leagues are frozen immediately at season finish and stay readable as archives.

ALTER TABLE public.season
  ADD COLUMN IF NOT EXISTS finished_at timestamptz;

ALTER TABLE public.leagues
  ADD COLUMN IF NOT EXISTS finished_at timestamptz;

CREATE INDEX IF NOT EXISTS season_finished_lookup
  ON public.season (tournament_id, finished_at);

CREATE INDEX IF NOT EXISTS leagues_finished_lookup
  ON public.leagues (season_id, finished_at);

-- Shared server-side guard used by market writes and league mutations.
CREATE OR REPLACE FUNCTION public.assert_league_not_finished(p_league_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_league_finished timestamptz;
  v_season_finished timestamptz;
BEGIN
  SELECT l.finished_at, s.finished_at
  INTO v_league_finished, v_season_finished
  FROM public.leagues l
  LEFT JOIN public.season s ON s.id = l.season_id
  WHERE l.id = p_league_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown league' USING ERRCODE = '22023';
  END IF;

  IF v_league_finished IS NOT NULL OR v_season_finished IS NOT NULL THEN
    RAISE EXCEPTION 'Diese Liga ist beendet und schreibgeschützt.' USING ERRCODE = '55000';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_league_not_finished(bigint)
FROM PUBLIC, anon, authenticated;

-- Once a league has a finished_at timestamp, normal activity pings can never
-- reactivate it. Idle leagues still keep the existing reactivation behaviour.
CREATE OR REPLACE FUNCTION public.guard_finished_league_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.finished_at IS NOT NULL THEN
    NEW.finished_at := OLD.finished_at;
    NEW.is_active := false;
  ELSIF NEW.finished_at IS NOT NULL THEN
    NEW.is_active := false;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leagues_guard_finished_state ON public.leagues;
CREATE TRIGGER leagues_guard_finished_state
BEFORE UPDATE OF is_active, finished_at
ON public.leagues
FOR EACH ROW
EXECUTE FUNCTION public.guard_finished_league_state();

-- New fantasy leagues require a running, initialized season. Existing leagues
-- continue to keep their immutable season_id.
CREATE OR REPLACE FUNCTION public.guard_league_season()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
  v_season public.season;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.season_id IS DISTINCT FROM OLD.season_id THEN
    RAISE EXCEPTION 'Existing fantasy leagues keep their original season';
  END IF;

  SELECT * INTO v_season
  FROM public.season
  WHERE id = NEW.season_id
  FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown season';
  END IF;

  IF TG_OP = 'INSERT' AND (
    v_season.is_active IS NOT TRUE
    OR v_season.is_initialized IS NOT TRUE
    OR v_season.finished_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'New leagues require the active initialized unfinished season';
  END IF;

  NEW.tournament_id := v_season.tournament_id;
  RETURN NEW;
END;
$$;

-- Finished seasons can never be activated again. A finished currently-active
-- season is archived normally when a newer season is activated.
CREATE OR REPLACE FUNCTION public.activate_season(p_season_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
  v_target public.season;
  v_tournament bigint;
BEGIN
  SELECT tournament_id INTO STRICT v_tournament
  FROM public.season
  WHERE id = p_season_id;

  PERFORM 1 FROM public.tournaments WHERE id = v_tournament FOR UPDATE;
  SELECT * INTO STRICT v_target FROM public.season WHERE id = p_season_id FOR UPDATE;

  IF v_target.is_active THEN
    RETURN false;
  END IF;

  IF v_target.archived_at IS NOT NULL
     OR v_target.finished_at IS NOT NULL
     OR public.season_start_year(v_target.name) < 0 THEN
    RAISE EXCEPTION 'Archived, finished or unrecognized season cannot be activated';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.season
    WHERE tournament_id = v_tournament
      AND id <> p_season_id
      AND public.season_start_year(name) > public.season_start_year(v_target.name)
  ) THEN
    RAISE EXCEPTION 'Only the latest known season can be activated';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.season
    WHERE tournament_id = v_tournament
      AND is_active
      AND public.season_start_year(name) >= public.season_start_year(v_target.name)
  ) THEN
    RAISE EXCEPTION 'Automatic rollback or ambiguous same-year transition refused';
  END IF;

  UPDATE public.season
  SET is_active = false,
      archived_at = now()
  WHERE tournament_id = v_tournament
    AND is_active;

  UPDATE public.season
  SET is_active = true
  WHERE id = p_season_id;

  RETURN true;
END;
$$;

-- Do not allow manual activation requests for already finished seasons.
DROP POLICY IF EXISTS season_requests_own_insert ON public.season_activation_requests;
CREATE POLICY season_requests_own_insert
ON public.season_activation_requests
FOR INSERT TO authenticated
WITH CHECK (
  requested_by = (SELECT auth.uid())
  AND processed_at IS NULL
  AND error_message IS NULL
  AND EXISTS (
    SELECT 1
    FROM public.season s
    WHERE s.id = season_id
      AND s.archived_at IS NULL
      AND s.finished_at IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.season newer
        WHERE newer.tournament_id = s.tournament_id
          AND public.season_start_year(newer.name) > public.season_start_year(s.name)
      )
  )
);

-- Market writes from current and older clients are blocked once the league is
-- finished. Deactivation of existing offers is still allowed.
CREATE OR REPLACE FUNCTION public.guard_finished_transfer_market_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.is_active IS TRUE THEN
    PERFORM public.assert_league_not_finished(NEW.league_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS transfer_market_guard_finished_league ON public.transfer_market;
CREATE TRIGGER transfer_market_guard_finished_league
BEFORE INSERT OR UPDATE
ON public.transfer_market
FOR EACH ROW
EXECUTE FUNCTION public.guard_finished_transfer_market_write();

CREATE OR REPLACE FUNCTION public.guard_finished_transfer_bid_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_league_id bigint;
BEGIN
  SELECT tm.league_id INTO v_league_id
  FROM public.transfer_market tm
  WHERE tm.id = NEW.transfer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown transfer' USING ERRCODE = '22023';
  END IF;

  PERFORM public.assert_league_not_finished(v_league_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS transfer_bids_guard_finished_league ON public.transfer_bids;
CREATE TRIGGER transfer_bids_guard_finished_league
BEFORE INSERT OR UPDATE
ON public.transfer_bids
FOR EACH ROW
EXECUTE FUNCTION public.guard_finished_transfer_bid_write();

-- Quick sell is the one transfer operation that does not create/update a
-- transfer_market row, so guard it explicitly.
CREATE OR REPLACE FUNCTION public.quick_sell_player(p_league_id bigint, p_player_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_mw integer;
  v_sell_price integer;
  v_user_id uuid;
  v_season_id bigint;
BEGIN
  PERFORM public.assert_league_not_finished(p_league_id);
  v_user_id := auth.uid();

  IF NOT EXISTS (
    SELECT 1
    FROM public.league_players
    WHERE league_id = p_league_id
      AND player_id = p_player_id
      AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Spieler gehört dir nicht oder ist bereits auf dem Transfermarkt.';
  END IF;

  SELECT season_id INTO v_season_id
  FROM public.leagues
  WHERE id = p_league_id;

  SELECT marktwert INTO v_mw
  FROM public.spieler_analytics
  WHERE spieler_id = p_player_id
    AND season_id = v_season_id;

  IF v_mw IS NULL THEN
    v_mw := 0;
  END IF;

  v_sell_price := floor(v_mw * 0.95);

  UPDATE public.league_members
  SET budget = budget + v_sell_price
  WHERE league_id = p_league_id
    AND user_id = v_user_id;

  DELETE FROM public.league_players
  WHERE league_id = p_league_id
    AND player_id = p_player_id
    AND user_id = v_user_id;
END;
$$;

-- Users cannot join a league after its season has ended.
CREATE OR REPLACE FUNCTION public.join_league(p_league_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Nicht autorisiert. Bitte einloggen.';
  END IF;

  PERFORM public.assert_league_not_finished(p_league_id);

  IF EXISTS (
    SELECT 1
    FROM public.league_members
    WHERE league_id = p_league_id
      AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Du bist bereits Mitglied dieser Liga.';
  END IF;

  INSERT INTO public.league_members (league_id, user_id, role, budget)
  VALUES (p_league_id, v_user_id, 'player', 150000000);

  PERFORM public.assign_random_team(p_league_id, v_user_id);
  PERFORM public.catch_up_matchdays_for_new_user(p_league_id, v_user_id);
END;
$$;

-- Once finished, routine season maintenance must stop even though the season
-- stays is_active=true until its successor is activated.
CREATE OR REPLACE FUNCTION public.generate_routine_sync_tasks()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
BEGIN
  INSERT INTO public.sync_tasks (task_type, tournament_id, season_id, match_id, priority, status)
  SELECT
    'UPDATE_MATCH', s.tournament_id, sp.season_id, sp.id,
    CASE WHEN sp.datum >= now() - interval '6 hours' THEN 1 ELSE 7 END,
    'PENDING'
  FROM public.spiel sp
  JOIN public.season s ON sp.season_id = s.id
  WHERE sp.status != 'final'
    AND sp.datum <= now()
    AND s.is_active = true
    AND s.is_initialized = true
    AND s.finished_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.sync_tasks st
      WHERE st.task_type = 'UPDATE_MATCH'
        AND st.match_id = sp.id
        AND st.status IN ('PENDING', 'PROCESSING', 'WAITING')
    );

  INSERT INTO public.sync_tasks (task_type, tournament_id, season_id, priority, status)
  SELECT 'UPDATE_SCHEDULE', s.tournament_id, s.id, 5, 'PENDING'
  FROM public.season s
  WHERE s.is_active = true
    AND s.is_initialized = true
    AND s.finished_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.sync_tasks st
      WHERE st.task_type = 'UPDATE_SCHEDULE'
        AND st.season_id = s.id
        AND st.created_at > now() - interval '24 hours'
    );

  INSERT INTO public.sync_tasks (task_type, tournament_id, season_id, priority, status)
  SELECT 'SYNC_TRANSFERS', s.tournament_id, s.id, 8, 'PENDING'
  FROM public.season s
  WHERE s.is_active = true
    AND s.is_initialized = true
    AND s.finished_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.sync_tasks st
      WHERE st.task_type = 'SYNC_TRANSFERS'
        AND st.season_id = s.id
        AND st.created_at > now() - interval '12 hours'
    );

  INSERT INTO public.sync_tasks (task_type, tournament_id, season_id, priority, status)
  SELECT 'REPAIR_PLAYERS', s.tournament_id, s.id, 9, 'PENDING'
  FROM public.season s
  WHERE s.is_active = true
    AND s.is_initialized = true
    AND s.finished_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.sync_tasks st
      WHERE st.task_type = 'REPAIR_PLAYERS'
        AND st.season_id = s.id
        AND st.created_at > now() - interval '6 hours'
    );
END;
$$;

-- Old pending routine work is also never claimed after a season finishes.
CREATE OR REPLACE FUNCTION public.get_next_sync_task(p_user_id uuid)
RETURNS SETOF public.sync_tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
BEGIN
  IF NOT v_is_service AND (v_uid IS NULL OR p_user_id IS DISTINCT FROM v_uid) THEN
    RAISE EXCEPTION 'Cannot claim sync tasks for another user' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH next_task AS (
    SELECT t.id
    FROM public.sync_tasks t
    WHERE (
      t.status = 'PENDING'
      OR (t.status = 'PROCESSING' AND t.locked_at < now() - interval '10 minutes')
    )
    AND (
      t.depends_on_task_id IS NULL
      OR EXISTS (
        SELECT 1
        FROM public.sync_tasks parent
        WHERE parent.id = t.depends_on_task_id
          AND parent.status = 'COMPLETED'
      )
    )
    AND NOT (
      t.task_type IN ('UPDATE_MATCH', 'UPDATE_SCHEDULE', 'SYNC_TRANSFERS', 'REPAIR_PLAYERS')
      AND t.season_id IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM public.season s
        WHERE s.id = t.season_id
          AND s.finished_at IS NOT NULL
      )
    )
    ORDER BY t.priority DESC, t.created_at ASC, t.id
    FOR UPDATE OF t SKIP LOCKED
    LIMIT 1
  )
  UPDATE public.sync_tasks t
  SET status = 'PROCESSING',
      locked_at = now(),
      locked_by = p_user_id,
      updated_at = now(),
      error_message = null
  FROM next_task n
  WHERE t.id = n.id
  RETURNING t.*;
END;
$$;

-- Central, idempotent finalization. We intentionally do NOT clear season.is_active:
-- the finished season remains the tournament's current season until a successor
-- is discovered and activated. Its manager leagues, however, are frozen now.
CREATE OR REPLACE FUNCTION public.finish_season(p_season_id bigint, p_finished_at timestamptz DEFAULT now())
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_finished_at timestamptz := COALESCE(p_finished_at, now());
BEGIN
  PERFORM 1
  FROM public.season
  WHERE id = p_season_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown season' USING ERRCODE = '22023';
  END IF;

  UPDATE public.season
  SET finished_at = v_finished_at
  WHERE id = p_season_id
    AND finished_at IS NULL;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  UPDATE public.leagues
  SET finished_at = COALESCE(finished_at, v_finished_at),
      is_active = false
  WHERE season_id = p_season_id;

  UPDATE public.transfer_market tm
  SET is_active = false
  WHERE tm.is_active = true
    AND EXISTS (
      SELECT 1
      FROM public.leagues l
      WHERE l.id = tm.league_id
        AND l.season_id = p_season_id
    );

  UPDATE public.sync_tasks
  SET status = 'CANCELLED',
      locked_at = null,
      locked_by = null,
      error_message = 'Season finished',
      updated_at = now()
  WHERE season_id = p_season_id
    AND task_type IN ('UPDATE_MATCH', 'UPDATE_SCHEDULE', 'SYNC_TRANSFERS', 'REPAIR_PLAYERS')
    AND status IN ('PENDING', 'WAITING');

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.finish_season(bigint, timestamptz)
FROM PUBLIC, anon, authenticated;

-- The spiel trigger already calculates each matchday status. This trigger fires
-- after a matchday becomes final and closes the season only when EVERY imported
-- matchday of that season is final. Postponed earlier rounds therefore prevent a
-- premature season finish even if the nominal last round has already ended.
CREATE OR REPLACE FUNCTION public.finish_season_when_all_matchdays_final()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'final'
     AND OLD.status IS DISTINCT FROM 'final'
     AND EXISTS (
       SELECT 1
       FROM public.season s
       WHERE s.id = NEW.season_id
         AND s.is_initialized IS TRUE
         AND s.finished_at IS NULL
     )
     AND EXISTS (
       SELECT 1
       FROM public.spieltag st
       WHERE st.season_id = NEW.season_id
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.spieltag st
       WHERE st.season_id = NEW.season_id
         AND st.status IS DISTINCT FROM 'final'
     ) THEN
    PERFORM public.finish_season(NEW.season_id, now());
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS spieltag_finish_season ON public.spieltag;
CREATE TRIGGER spieltag_finish_season
AFTER UPDATE OF status
ON public.spieltag
FOR EACH ROW
EXECUTE FUNCTION public.finish_season_when_all_matchdays_final();

-- Backfill seasons that are already fully complete at migration time. Archived
-- seasons use their archive timestamp where available; running seasons are only
-- marked finished when every imported matchday is already final.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT s.id, COALESCE(s.archived_at, now()) AS finished_at
    FROM public.season s
    WHERE s.is_initialized IS TRUE
      AND s.finished_at IS NULL
      AND EXISTS (
        SELECT 1 FROM public.spieltag st WHERE st.season_id = s.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.spieltag st
        WHERE st.season_id = s.id
          AND st.status IS DISTINCT FROM 'final'
      )
  LOOP
    PERFORM public.finish_season(r.id, r.finished_at);
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_finished_league_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_finished_transfer_market_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_finished_transfer_bid_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_season_when_all_matchdays_final() FROM PUBLIC, anon, authenticated;
