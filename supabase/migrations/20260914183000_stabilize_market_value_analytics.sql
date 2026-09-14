-- Keep finished-season market values immutable while allowing their historical
-- match data to remain available as input for current player projections.
CREATE OR REPLACE FUNCTION public.protect_finished_season_market_values()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.season s
    WHERE s.id = NEW.season_id
      AND s.finished_at IS NOT NULL
  ) THEN
    NEW.marktwert := OLD.marktwert;
    NEW.calculated_marktwert := OLD.calculated_marktwert;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_finished_season_market_values
ON public.spieler_analytics;

CREATE TRIGGER trg_protect_finished_season_market_values
BEFORE UPDATE OF marktwert, calculated_marktwert
ON public.spieler_analytics
FOR EACH ROW
EXECUTE FUNCTION public.protect_finished_season_market_values();

-- Refresh each active player only once per competition-season. Inactive former
-- club memberships remain historical data and must not cause duplicate work.
CREATE OR REPLACE FUNCTION public.update_all_spieler_analytics(p_season_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_player record;
BEGIN
  FOR v_player IN
    SELECT DISTINCT sp.player_id
    FROM public.season_players sp
    WHERE sp.season_id = p_season_id
      AND sp.is_active = true
  LOOP
    PERFORM public.update_spieler_analytics_prognose(
      v_player.player_id,
      p_season_id
    );
  END LOOP;
END;
$$;

-- Historical baseline:
--   * point average = every final matchrating stored for this player, across seasons
--   * form = last five final appearances across season boundaries
--   * starting XI quote = current team's last five final games when available;
--     before the current season has final games, fall back to the player's recent
--     historical starting-XI rate.
-- This keeps the beginning of a new season from over-weighting only one or two games.
CREATE OR REPLACE FUNCTION public.update_spieler_analytics_prognose(
  p_spieler_id bigint,
  p_season_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_team_id bigint;
  v_matchup_faktor numeric := 1.0;
  v_punkteschnitt numeric := 0;
  v_form numeric := 0;
  v_startelf_quote numeric := 0;
  v_historical_startelf_quote numeric := 0;
  v_current_team_games integer := 0;
  v_expected_points numeric := 0;
BEGIN
  SELECT sp.team_id
  INTO v_team_id
  FROM public.season_players sp
  WHERE sp.player_id = p_spieler_id
    AND sp.season_id = p_season_id
    AND sp.is_active = true
  ORDER BY sp.team_id
  LIMIT 1;

  IF v_team_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(
    (
      SELECT ta.matchup_faktor
      FROM public.team_analytics ta
      WHERE ta.team_id = v_team_id
      LIMIT 1
    ),
    1.0
  )
  INTO v_matchup_faktor;

  -- Long-term level: use every finalized performance currently stored for the player,
  -- regardless of which season/competition it came from.
  SELECT COALESCE(AVG(mr.punkte), 0)
  INTO v_punkteschnitt
  FROM public.matchrating mr
  JOIN public.spiel s ON s.id = mr.spiel_id
  WHERE mr.spieler_id = p_spieler_id
    AND lower(s.status) = 'final';

  -- Recent form crosses season boundaries. At the start of a new season this means
  -- the remaining slots naturally come from the previous season(s).
  WITH recent_appearances AS (
    SELECT mr.punkte, mr.formationsindex
    FROM public.matchrating mr
    JOIN public.spiel s ON s.id = mr.spiel_id
    WHERE mr.spieler_id = p_spieler_id
      AND lower(s.status) = 'final'
    ORDER BY s.datum DESC NULLS LAST, s.id DESC
    LIMIT 5
  )
  SELECT
    COALESCE(AVG(ra.punkte), 0),
    COALESCE(
      AVG(CASE WHEN ra.formationsindex <= 10 THEN 1.0 ELSE 0.0 END),
      0
    )
  INTO v_form, v_historical_startelf_quote
  FROM recent_appearances ra;

  -- Prefer the current club/competition for the starting-XI probability because a
  -- transfer or role change should be visible quickly. If the new season has no
  -- final team games yet, use the recent historical start rate instead of 0.
  WITH last_current_team_games AS (
    SELECT s.id
    FROM public.spiel s
    WHERE s.season_id = p_season_id
      AND lower(s.status) = 'final'
      AND (s.heimteam_id = v_team_id OR s."auswärtsteam_id" = v_team_id)
    ORDER BY s.datum DESC NULLS LAST, s.id DESC
    LIMIT 5
  )
  SELECT
    COUNT(*)::integer,
    COALESCE(
      COUNT(mr.id) FILTER (WHERE mr.formationsindex <= 10)::numeric
      / NULLIF(COUNT(*), 0),
      0
    )
  INTO v_current_team_games, v_startelf_quote
  FROM last_current_team_games g
  LEFT JOIN public.matchrating mr
    ON mr.spiel_id = g.id
   AND mr.spieler_id = p_spieler_id;

  IF v_current_team_games = 0 THEN
    v_startelf_quote := v_historical_startelf_quote;
  END IF;

  v_expected_points :=
    ((v_punkteschnitt * 0.4) + (v_form * 0.6))
    * v_matchup_faktor
    * v_startelf_quote;

  v_expected_points := GREATEST(0, ROUND(COALESCE(v_expected_points, 0), 2));

  UPDATE public.spieler_analytics sa
  SET punkteschnitt = ROUND(v_punkteschnitt, 2),
      form = ROUND(v_form, 2),
      startelf_quote = ROUND(v_startelf_quote, 2),
      expected_points = v_expected_points,
      last_updated_at = now()
  WHERE sa.spieler_id = p_spieler_id
    AND sa.season_id = p_season_id;
END;
$$;

-- Only unfinished, initialized, active seasons receive the once-per-day market move.
-- Within such a season, only players that are currently active for a club are changed.
CREATE OR REPLACE FUNCTION public.daily_marktwert_update()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_season record;
  v_settings public.game_settings%ROWTYPE;
BEGIN
  SELECT *
  INTO v_settings
  FROM public.game_settings
  WHERE id = 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fehler: game_settings (id=1) wurde nicht gefunden. Update abgebrochen!';
  END IF;

  FOR v_season IN
    SELECT s.id
    FROM public.season s
    WHERE s.is_active IS TRUE
      AND s.is_initialized IS TRUE
      AND s.finished_at IS NULL
    ORDER BY s.id
  LOOP
    PERFORM public.update_all_matchup_faktors(v_season.id);
    PERFORM public.update_all_spieler_analytics(v_season.id);

    UPDATE public.spieler_analytics sa
    SET calculated_marktwert = ROUND(
          v_settings.mw_multiplier
          * power(COALESCE(sa.expected_points, 0), v_settings.mw_exponent)
          + v_settings.mw_base_value
        ),
        marktwert = ROUND(
          sa.marktwert + (
            (
              v_settings.mw_multiplier
              * power(COALESCE(sa.expected_points, 0), v_settings.mw_exponent)
              + v_settings.mw_base_value
            ) - sa.marktwert
          ) * v_settings.mw_daily_adjustment
        ),
        last_updated_at = now()
    WHERE sa.season_id = v_season.id
      AND EXISTS (
        SELECT 1
        FROM public.season_players sp
        WHERE sp.season_id = v_season.id
          AND sp.player_id = sa.spieler_id
          AND sp.is_active = true
      );
  END LOOP;
END;
$$;

-- The legacy overload has no season argument. Keep it service-compatible, but never
-- let it rewrite market values that belong to a finished season.
CREATE OR REPLACE FUNCTION public.init_player_from_sofascore(
  p_player_id bigint,
  p_formation text,
  p_lineup_index integer,
  p_api_position text,
  p_ratings numeric[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_final_position text;
  v_avg_points numeric := 0;
  v_calc_mw bigint;
  v_rating numeric;
  v_points_sum numeric := 0;
  v_points_count int := 0;
  v_settings record;
BEGIN
  SELECT * INTO v_settings FROM public.game_settings WHERE id = 1;
  IF v_settings IS NULL THEN
    v_calc_mw := 1000000;
  ELSE
    v_calc_mw := v_settings.mw_base_value;
  END IF;

  IF p_formation IS NOT NULL AND p_lineup_index IS NOT NULL AND p_lineup_index <= 10 THEN
    v_final_position := public.get_position_from_formation(p_formation, p_lineup_index);
  END IF;

  IF v_final_position IS NULL OR v_final_position IN ('N/A', 'SUB', 'N/V') THEN
    v_final_position := CASE
      WHEN p_api_position = 'G' THEN 'TW'
      WHEN p_api_position = 'D' THEN 'IV'
      WHEN p_api_position = 'M' THEN 'ZM'
      WHEN p_api_position = 'F' THEN 'ST'
      ELSE 'SUB'
    END;
  END IF;

  IF array_length(p_ratings, 1) > 0 THEN
    FOREACH v_rating IN ARRAY p_ratings LOOP
      IF v_rating IS NOT NULL THEN
        v_points_sum := v_points_sum + ROUND((v_rating - 6.0) * 100);
        v_points_count := v_points_count + 1;
      END IF;
    END LOOP;

    IF v_points_count > 0 THEN
      v_avg_points := v_points_sum / v_points_count;
      IF v_avg_points > 0 AND v_settings IS NOT NULL THEN
        v_calc_mw := ROUND(
          v_settings.mw_multiplier
          * power(v_avg_points, v_settings.mw_exponent)
          + v_settings.mw_base_value
        );
      END IF;
    END IF;
  END IF;

  UPDATE public.spieler
  SET position = CASE
    WHEN position IS NULL OR position IN ('', 'SUB', 'N/A', 'N/V') THEN v_final_position
    WHEN v_final_position NOT IN ('SUB', 'N/A', 'N/V')
      AND position NOT LIKE '%' || v_final_position || '%'
      THEN position || ', ' || v_final_position
    ELSE position
  END
  WHERE id = p_player_id;

  UPDATE public.spieler_analytics sa
  SET marktwert = v_calc_mw,
      calculated_marktwert = v_calc_mw,
      last_updated_at = now()
  FROM public.season se
  WHERE sa.spieler_id = p_player_id
    AND se.id = sa.season_id
    AND se.finished_at IS NULL;
END;
$$;

-- Current clients use this season-aware overload. A finished season is immutable;
-- a late repair may still finish elsewhere, but it cannot rewrite this market value.
CREATE OR REPLACE FUNCTION public.init_player_from_sofascore(
  p_player_id bigint,
  p_season_id bigint,
  p_formation text,
  p_lineup_index integer,
  p_api_position text,
  p_ratings numeric[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_final_position text;
  v_avg_points numeric := 0;
  v_calc_mw bigint;
  v_rating numeric;
  v_points_sum numeric := 0;
  v_points_count int := 0;
  v_settings record;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.season s
    WHERE s.id = p_season_id
      AND s.finished_at IS NOT NULL
  ) THEN
    RETURN;
  END IF;

  SELECT * INTO v_settings FROM public.game_settings WHERE id = 1;
  IF v_settings IS NULL THEN
    v_calc_mw := 1000000;
  ELSE
    v_calc_mw := v_settings.mw_base_value;
  END IF;

  IF p_formation IS NOT NULL AND p_lineup_index IS NOT NULL AND p_lineup_index <= 10 THEN
    v_final_position := public.get_position_from_formation(p_formation, p_lineup_index);
  END IF;

  IF v_final_position IS NULL OR v_final_position IN ('N/A', 'SUB', 'N/V') THEN
    v_final_position := CASE
      WHEN p_api_position = 'G' THEN 'TW'
      WHEN p_api_position = 'D' THEN 'IV'
      WHEN p_api_position = 'M' THEN 'ZM'
      WHEN p_api_position = 'F' THEN 'ST'
      ELSE 'SUB'
    END;
  END IF;

  IF array_length(p_ratings, 1) > 0 THEN
    FOREACH v_rating IN ARRAY p_ratings LOOP
      IF v_rating IS NOT NULL THEN
        v_points_sum := v_points_sum + ROUND((v_rating - 6.0) * 100);
        v_points_count := v_points_count + 1;
      END IF;
    END LOOP;

    IF v_points_count > 0 THEN
      v_avg_points := v_points_sum / v_points_count;
      IF v_avg_points > 0 AND v_settings IS NOT NULL THEN
        v_calc_mw := ROUND(
          v_settings.mw_multiplier
          * power(v_avg_points, v_settings.mw_exponent)
          + v_settings.mw_base_value
        );
      END IF;
    END IF;
  END IF;

  UPDATE public.spieler
  SET position = CASE
    WHEN position IS NULL OR position IN ('', 'SUB', 'N/A', 'N/V') THEN v_final_position
    WHEN v_final_position NOT IN ('SUB', 'N/A', 'N/V')
      AND position NOT LIKE '%' || v_final_position || '%'
      THEN position || ', ' || v_final_position
    ELSE position
  END
  WHERE id = p_player_id;

  INSERT INTO public.spieler_analytics (
    spieler_id,
    season_id,
    marktwert,
    calculated_marktwert,
    last_updated_at
  )
  VALUES (
    p_player_id,
    p_season_id,
    v_calc_mw,
    v_calc_mw,
    now()
  )
  ON CONFLICT (spieler_id, season_id)
  DO UPDATE SET
    marktwert = CASE
      WHEN public.spieler_analytics.marktwert = 1000000
        THEN EXCLUDED.marktwert
      ELSE public.spieler_analytics.marktwert
    END,
    calculated_marktwert = EXCLUDED.calculated_marktwert,
    last_updated_at = now();
END;
$$;

-- Keep player analytics current when match lineup/rating data is refreshed. This does
-- not move the market value; the 3% market move remains exclusively in the daily job.
CREATE OR REPLACE FUNCTION public.process_match_lineups(
  p_spiel_id bigint,
  p_season_id bigint,
  p_raw_json jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
  INSERT INTO public.api_debug_dump (spiel_id, raw_json)
  VALUES (p_spiel_id, p_raw_json);

  SELECT s.heimteam_id, s."auswärtsteam_id"
  INTO v_home_id, v_away_id
  FROM public.spiel s
  WHERE s.id = p_spiel_id;

  v_home_formation := p_raw_json->'home'->>'formation';
  v_away_formation := p_raw_json->'away'->>'formation';

  IF v_home_formation IS NOT NULL AND v_home_formation <> 'N/A' THEN
    INSERT INTO public.formation (formation, positionsliste)
    VALUES (v_home_formation, public.calculate_formation_array(v_home_formation))
    ON CONFLICT (formation) DO NOTHING;
  END IF;

  IF v_away_formation IS NOT NULL AND v_away_formation <> 'N/A' THEN
    INSERT INTO public.formation (formation, positionsliste)
    VALUES (v_away_formation, public.calculate_formation_array(v_away_formation))
    ON CONFLICT (formation) DO NOTHING;
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
      FROM jsonb_array_elements(p_raw_json->v_team_type->'players')
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
          THEN COALESCE(public.spieler.position, EXCLUDED.position)
        WHEN public.spieler.position IS NULL
          OR public.spieler.position IN ('', 'SUB', 'N/A', 'N/V')
          THEN EXCLUDED.position
        WHEN EXCLUDED.position = ANY(
          string_to_array(replace(public.spieler.position, ' ', ''), ',')
        )
          THEN public.spieler.position
        ELSE public.spieler.position || ', ' || EXCLUDED.position
      END;

      UPDATE public.season_players
      SET is_active = false
      WHERE season_id = p_season_id
        AND player_id = v_player_id
        AND team_id != v_team_id
        AND is_active = true;

      INSERT INTO public.season_players (
        season_id,
        player_id,
        team_id,
        is_active
      )
      VALUES (p_season_id, v_player_id, v_team_id, true)
      ON CONFLICT ON CONSTRAINT season_players_unique_combo
      DO UPDATE SET is_active = true;

      v_match_rating_id := (p_spiel_id::text || v_player_id::text)::bigint;

      INSERT INTO public.matchrating (
        id,
        spiel_id,
        spieler_id,
        punkte,
        statistics,
        neuepunkte,
        formationsindex,
        match_position
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
          match_position = EXCLUDED.match_position;

      PERFORM public.update_spieler_analytics_prognose(
        v_player_id,
        p_season_id
      );

      v_idx := v_idx + 1;
    END LOOP;
  END LOOP;
END;
$$;
