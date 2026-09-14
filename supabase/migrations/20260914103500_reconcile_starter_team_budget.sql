-- Reconcile the small unavoidable difference between the configured starter
-- squad target and the actually assigned squad against the manager's budget.
-- If the squad is cheaper than the target, the difference is credited. If it
-- is more expensive, the difference is deducted. Budgets are never allowed to
-- become negative.
CREATE OR REPLACE FUNCTION public.assign_random_team(
  p_league_id bigint,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
  v_num_players integer;
  v_target_val numeric;
  v_season_id bigint;
  v_available integer;
  v_attempt integer;
  v_slot integer;
  v_remaining_slots integer;
  v_desired numeric;
  v_candidate_id bigint;
  v_candidate_value numeric;
  v_selected_ids bigint[];
  v_total numeric;
  v_diff numeric;
  v_best_ids bigint[] := ARRAY[]::bigint[];
  v_best_total numeric := 0;
  v_best_diff numeric;
  v_shortlist integer;
  v_inserted integer;
  v_current_budget numeric;
  v_budget_adjustment numeric;
  v_tolerance constant numeric := 1000000;
BEGIN
  PERFORM public.assert_league_not_finished(p_league_id);

  SELECT
    l.num_starting_players,
    l.starting_team_value,
    l.season_id
  INTO
    v_num_players,
    v_target_val,
    v_season_id
  FROM public.leagues l
  WHERE l.id = p_league_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown league' USING ERRCODE = '22023';
  END IF;

  SELECT lm.budget
  INTO v_current_budget
  FROM public.league_members lm
  WHERE lm.league_id = p_league_id
    AND lm.user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'League membership required before starter team assignment'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(v_num_players, 0) <= 0 THEN
    RETURN;
  END IF;

  IF COALESCE(v_target_val, 0) <= 0 THEN
    RAISE EXCEPTION 'Der Ziel-Teamwert muss größer als 0 sein.' USING ERRCODE = '22023';
  END IF;

  SELECT count(*)
  INTO v_available
  FROM public.spieler_analytics sa
  WHERE sa.season_id = v_season_id
    AND sa.marktwert > 0
    AND EXISTS (
      SELECT 1
      FROM public.season_players sp
      WHERE sp.season_id = v_season_id
        AND sp.player_id = sa.spieler_id
        AND sp.is_active = true
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.league_players lp
      WHERE lp.league_id = p_league_id
        AND lp.player_id = sa.spieler_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.transfer_market tm
      WHERE tm.league_id = p_league_id
        AND tm.player_id = sa.spieler_id
        AND tm.is_active = true
    );

  IF v_available < v_num_players THEN
    RAISE EXCEPTION
      'Nicht genügend freie Spieler für die gewünschte Startzulosung (% benötigt, % verfügbar).',
      v_num_players,
      v_available
      USING ERRCODE = '22023';
  END IF;

  FOR v_attempt IN 1..80 LOOP
    v_selected_ids := ARRAY[]::bigint[];
    v_total := 0;

    FOR v_slot IN 1..v_num_players LOOP
      v_remaining_slots := v_num_players - v_slot + 1;
      v_desired := GREATEST(0, (v_target_val - v_total) / v_remaining_slots);
      v_shortlist := CASE WHEN v_remaining_slots = 1 THEN 1 ELSE 10 END;

      SELECT candidate.player_id, candidate.marktwert
      INTO v_candidate_id, v_candidate_value
      FROM (
        SELECT sa.spieler_id AS player_id, sa.marktwert
        FROM public.spieler_analytics sa
        WHERE sa.season_id = v_season_id
          AND sa.marktwert > 0
          AND EXISTS (
            SELECT 1
            FROM public.season_players sp
            WHERE sp.season_id = v_season_id
              AND sp.player_id = sa.spieler_id
              AND sp.is_active = true
          )
          AND NOT (sa.spieler_id = ANY(v_selected_ids))
          AND NOT EXISTS (
            SELECT 1
            FROM public.league_players lp
            WHERE lp.league_id = p_league_id
              AND lp.player_id = sa.spieler_id
          )
          AND NOT EXISTS (
            SELECT 1
            FROM public.transfer_market tm
            WHERE tm.league_id = p_league_id
              AND tm.player_id = sa.spieler_id
              AND tm.is_active = true
          )
        ORDER BY abs(sa.marktwert - v_desired), sa.spieler_id
        LIMIT v_shortlist
      ) candidate
      ORDER BY random()
      LIMIT 1;

      IF v_candidate_id IS NULL THEN
        EXIT;
      END IF;

      v_selected_ids := array_append(v_selected_ids, v_candidate_id);
      v_total := v_total + v_candidate_value;
    END LOOP;

    IF COALESCE(array_length(v_selected_ids, 1), 0) <> v_num_players THEN
      CONTINUE;
    END IF;

    v_diff := abs(v_total - v_target_val);
    IF v_best_diff IS NULL OR v_diff < v_best_diff THEN
      v_best_diff := v_diff;
      v_best_total := v_total;
      v_best_ids := v_selected_ids;
    END IF;

    EXIT WHEN v_best_diff <= 100000;
  END LOOP;

  IF COALESCE(array_length(v_best_ids, 1), 0) <> v_num_players THEN
    RAISE EXCEPTION 'Es konnte kein vollständiger Startkader zusammengestellt werden.'
      USING ERRCODE = '22023';
  END IF;

  IF v_best_diff > v_tolerance THEN
    RAISE EXCEPTION
      'Der gewählte Ziel-Teamwert von % Mio. € ist mit den aktuell freien Spielern nicht ausreichend genau erreichbar. Bestes Ergebnis: % Mio. €.',
      round(v_target_val / 1000000.0, 1),
      round(v_best_total / 1000000.0, 1)
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.league_players (
    league_id,
    user_id,
    player_id,
    purchase_price
  )
  SELECT
    p_league_id,
    p_user_id,
    player_id,
    0
  FROM unnest(v_best_ids) AS player_id
  ON CONFLICT (league_id, player_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted <> v_num_players THEN
    RAISE EXCEPTION
      'Startkader konnte nicht vollständig gespeichert werden (% von % Spielern).',
      v_inserted,
      v_num_players;
  END IF;

  -- Positive adjustment: actual squad is cheaper than the configured target.
  -- Negative adjustment: actual squad is more expensive than the target.
  v_budget_adjustment := v_target_val - v_best_total;

  UPDATE public.league_members lm
  SET budget = GREATEST(
    0::numeric,
    COALESCE(v_current_budget, 0) + v_budget_adjustment
  )
  WHERE lm.league_id = p_league_id
    AND lm.user_id = p_user_id;
END;
$$;

-- New members must start from the league's configured starting budget, not the
-- historical hard-coded EUR 150m value. assign_random_team then applies the
-- starter-squad value reconciliation above.
CREATE OR REPLACE FUNCTION public.join_league(p_league_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_starting_budget numeric;
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

  SELECT l.starting_budget
  INTO v_starting_budget
  FROM public.leagues l
  WHERE l.id = p_league_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown league' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.league_members (league_id, user_id, role, budget)
  VALUES (
    p_league_id,
    v_user_id,
    'player',
    COALESCE(v_starting_budget, 0)
  );

  PERFORM public.assign_random_team(p_league_id, v_user_id);
  PERFORM public.catch_up_matchdays_for_new_user(p_league_id, v_user_id);
END;
$$;
