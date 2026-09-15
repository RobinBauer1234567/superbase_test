-- Reduce UPDATE_MATCH task churn, prevent immediate retry storms, and speed up lineup RPC writes.

-- 1) Cover the hot paths used by process_match_lineups and its triggers.
CREATE INDEX IF NOT EXISTS idx_matchrating_spieler_spiel
  ON public.matchrating (spieler_id, spiel_id);

CREATE INDEX IF NOT EXISTS idx_matchrating_spiel_spieler
  ON public.matchrating (spiel_id, spieler_id);

CREATE INDEX IF NOT EXISTS idx_user_matchday_players_player_spiel
  ON public.user_matchday_players (player_id, spiel_id);

CREATE INDEX IF NOT EXISTS idx_user_matchday_players_matchday_formation
  ON public.user_matchday_players (matchday_point_id, formation_index);

CREATE INDEX IF NOT EXISTS idx_spiel_season_status_datum
  ON public.spiel (season_id, status, datum);

-- At most one open UPDATE_MATCH task may exist per match.
CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_tasks_open_update_match
  ON public.sync_tasks (match_id)
  WHERE task_type = 'UPDATE_MATCH'
    AND status IN ('PENDING', 'PROCESSING', 'WAITING');

-- 2) Poll live matches frequently, but cool down provisional/post-match polling.
-- Priority values are intentionally high for live matches because get_next_sync_task
-- orders priority DESC.
CREATE OR REPLACE FUNCTION public.generate_routine_sync_tasks()
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.sync_tasks (task_type, tournament_id, season_id, match_id, priority, status)
  SELECT
    'UPDATE_MATCH',
    s.tournament_id,
    sp.season_id,
    sp.id,
    CASE
      WHEN sp.datum >= now() - interval '3 hours' THEN 10
      WHEN sp.datum >= now() - interval '6 hours' THEN 7
      WHEN sp.datum >= now() - interval '24 hours' THEN 3
      ELSE 1
    END,
    'PENDING'
  FROM public.spiel sp
  JOIN public.season s ON sp.season_id = s.id
  WHERE lower(coalesce(sp.status, '')) <> 'final'
    AND sp.datum <= now()
    AND s.is_active = true
    AND s.is_initialized = true
    AND s.finished_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.sync_tasks st
      WHERE st.task_type = 'UPDATE_MATCH'
        AND st.match_id = sp.id
        AND (
          st.status IN ('PENDING', 'PROCESSING', 'WAITING')
          OR st.created_at > now() - CASE
            WHEN sp.datum >= now() - interval '3 hours' THEN interval '2 minutes'
            WHEN sp.datum >= now() - interval '6 hours' THEN interval '10 minutes'
            WHEN sp.datum >= now() - interval '24 hours' THEN interval '1 hour'
            WHEN sp.datum >= now() - interval '30 hours' THEN interval '1 hour'
            ELSE interval '6 hours'
          END
        )
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
$function$;

-- 3) Failed tasks are not reclaimed immediately. This prevents a timeout from
-- being hammered every 15-30 seconds by the client worker.
CREATE OR REPLACE FUNCTION public.get_next_sync_task(p_user_id uuid)
RETURNS SETOF public.sync_tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
      (
        t.status = 'PENDING'
        AND (t.error_message IS NULL OR t.updated_at <= now() - interval '2 minutes')
      )
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
$function$;

-- 4) Avoid expensive analytics triggers when SofaScore returns exactly the same
-- lineup/rating payload again. Also stop writing full raw payloads into api_debug_dump.
CREATE OR REPLACE FUNCTION public.process_match_lineups(
    p_spiel_id bigint,
    p_season_id bigint,
    p_raw_json jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_home_formation text;
    v_away_formation text;
    v_home_id int;
    v_away_id int;
    v_team_type text;
    v_team_id int;
    v_formation text;
    v_idx int;
    player_item jsonb;
    v_player_id int;
    v_player_name text;
    v_api_pos text;
    v_calc_pos text;
    v_rating numeric;
    v_stats jsonb;
    v_fantasy_points int;
    v_match_rating_id bigint;
BEGIN
    SELECT heimteam_id, auswärtsteam_id
      INTO v_home_id, v_away_id
    FROM public.spiel
    WHERE id = p_spiel_id;

    v_home_formation := p_raw_json->'home'->>'formation';
    v_away_formation := p_raw_json->'away'->>'formation';

    IF v_home_formation IS NOT NULL AND v_home_formation <> 'N/A' THEN
        INSERT INTO public.formation (formation, positionsliste)
        VALUES (v_home_formation, public.calculate_formation_array(v_home_formation))
        ON CONFLICT DO NOTHING;
    END IF;

    IF v_away_formation IS NOT NULL AND v_away_formation <> 'N/A' THEN
        INSERT INTO public.formation (formation, positionsliste)
        VALUES (v_away_formation, public.calculate_formation_array(v_away_formation))
        ON CONFLICT DO NOTHING;
    END IF;

    UPDATE public.spiel
    SET hometeam_formation = v_home_formation,
        awayteam_formation = v_away_formation,
        last_updated_at = now()
    WHERE id = p_spiel_id;

    FOREACH v_team_type IN ARRAY ARRAY['home', 'away'] LOOP
        IF v_team_type = 'home' THEN
            v_team_id := v_home_id;
            v_formation := v_home_formation;
        ELSE
            v_team_id := v_away_id;
            v_formation := v_away_formation;
        END IF;

        v_idx := 0;

        FOR player_item IN
            SELECT *
            FROM jsonb_array_elements(
              coalesce(p_raw_json->v_team_type->'players', '[]'::jsonb)
            )
        LOOP
            v_player_id := (player_item->'player'->>'id')::int;
            v_player_name := player_item->'player'->>'name';
            v_api_pos := player_item->'player'->>'position';
            v_stats := player_item->'statistics';
            v_rating := (v_stats->>'rating')::numeric;

            v_calc_pos := public.get_position_from_formation(v_formation, v_idx);
            IF v_calc_pos = 'N/A' OR v_calc_pos IS NULL THEN
                 v_calc_pos := CASE
                   WHEN v_api_pos = 'G' THEN 'TW'
                   WHEN v_api_pos = 'D' THEN 'IV'
                   WHEN v_api_pos = 'M' THEN 'ZM'
                   WHEN v_api_pos = 'F' THEN 'ST'
                   ELSE 'SUB'
                 END;
            END IF;

            v_fantasy_points := public.calculate_fantasy_points(v_api_pos, v_stats);

            INSERT INTO public.spieler (id, name, position)
            VALUES (v_player_id, v_player_name, v_calc_pos)
            ON CONFLICT (id) DO UPDATE
            SET position = CASE
                WHEN EXCLUDED.position IN ('SUB', 'N/A', 'N/V')
                  THEN COALESCE(spieler.position, EXCLUDED.position)
                WHEN spieler.position IS NULL OR spieler.position IN ('', 'SUB', 'N/A', 'N/V')
                  THEN EXCLUDED.position
                WHEN EXCLUDED.position = ANY(string_to_array(replace(spieler.position, ' ', ''), ','))
                  THEN spieler.position
                ELSE spieler.position || ', ' || EXCLUDED.position
            END;

            UPDATE public.season_players
            SET is_active = false
            WHERE season_id = p_season_id
              AND player_id = v_player_id
              AND team_id <> v_team_id
              AND is_active = true;

            INSERT INTO public.season_players (season_id, player_id, team_id, is_active)
            VALUES (p_season_id, v_player_id, v_team_id, true)
            ON CONFLICT (season_id, player_id, team_id)
            DO UPDATE SET is_active = true;

            v_match_rating_id := (p_spiel_id::text || v_player_id::text)::bigint;

            INSERT INTO public.matchrating (
              id, spiel_id, spieler_id, punkte, statistics, neuepunkte,
              formationsindex, match_position
            )
            VALUES (
              v_match_rating_id,
              p_spiel_id,
              v_player_id,
              ROUND((COALESCE(v_rating, 6.0) - 6) * 100),
              v_stats,
              v_fantasy_points,
              v_idx,
              v_calc_pos
            )
            ON CONFLICT (id) DO UPDATE
            SET punkte = EXCLUDED.punkte,
                statistics = EXCLUDED.statistics,
                neuepunkte = EXCLUDED.neuepunkte,
                formationsindex = EXCLUDED.formationsindex,
                match_position = EXCLUDED.match_position
            WHERE (matchrating.punkte,
                   matchrating.statistics,
                   matchrating.neuepunkte,
                   matchrating.formationsindex,
                   matchrating.match_position)
              IS DISTINCT FROM
                  (EXCLUDED.punkte,
                   EXCLUDED.statistics,
                   EXCLUDED.neuepunkte,
                   EXCLUDED.formationsindex,
                   EXCLUDED.match_position);

            v_idx := v_idx + 1;
        END LOOP;
    END LOOP;
END;
$function$;

-- Function-specific safety margin only; authenticated remains at 8s globally.
ALTER FUNCTION public.process_match_lineups(bigint, bigint, jsonb)
  SET statement_timeout TO '15s';