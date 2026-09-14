-- Final archive hardening:
--   * restore user-owned players that are still listed when the season ends
--   * block lineup changes once the league/season is finished

CREATE OR REPLACE FUNCTION public.finish_season(
  p_season_id bigint,
  p_finished_at timestamptz DEFAULT now()
)
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

  -- A user listing temporarily removes that player from league_players. At the
  -- season boundary the market is cancelled, so return every still-listed user
  -- player to the seller before freezing the league. min_bid_price is the
  -- listing-time market value and is the best available historical price here.
  INSERT INTO public.league_players (
    league_id,
    user_id,
    player_id,
    purchase_price
  )
  SELECT
    tm.league_id,
    tm.seller_id,
    tm.player_id,
    COALESCE(tm.min_bid_price, 0)
  FROM public.transfer_market tm
  JOIN public.leagues l ON l.id = tm.league_id
  WHERE l.season_id = p_season_id
    AND tm.is_active IS TRUE
    AND tm.seller_id IS NOT NULL
  ON CONFLICT (league_id, player_id) DO NOTHING;

  UPDATE public.leagues
  SET finished_at = COALESCE(finished_at, v_finished_at),
      is_active = false,
      is_public = false
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

-- Current Flutter client lineup RPC. A finished league is an immutable archive.
CREATE OR REPLACE FUNCTION public.save_lineup(
  p_league_id bigint,
  p_season_id bigint,
  p_round integer,
  p_formation text,
  p_updates jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_point_id bigint;
  v_item jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  PERFORM public.assert_league_not_finished(p_league_id);

  IF NOT EXISTS (
    SELECT 1
    FROM public.leagues l
    WHERE l.id = p_league_id
      AND l.season_id = p_season_id
  ) THEN
    RAISE EXCEPTION 'Season does not belong to league' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.league_members lm
    WHERE lm.league_id = p_league_id
      AND lm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'League membership required' USING ERRCODE = '42501';
  END IF;

  SELECT id INTO v_point_id
  FROM public.user_matchday_points
  WHERE user_id = v_user_id
    AND league_id = p_league_id
    AND season_id = p_season_id
    AND round = p_round;

  IF v_point_id IS NULL THEN
    INSERT INTO public.user_matchday_points (
      user_id,
      league_id,
      season_id,
      round,
      formation
    )
    VALUES (
      v_user_id,
      p_league_id,
      p_season_id,
      p_round,
      p_formation
    )
    RETURNING id INTO v_point_id;
  ELSE
    UPDATE public.user_matchday_points
    SET formation = p_formation
    WHERE id = v_point_id;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM public.user_matchday_players
      WHERE matchday_point_id = v_point_id
        AND player_id = (v_item->>'player_id')::int
    ) THEN
      UPDATE public.user_matchday_players
      SET formation_index = (v_item->>'index')::int
      WHERE matchday_point_id = v_point_id
        AND player_id = (v_item->>'player_id')::int
        AND is_locked = false;
    ELSE
      INSERT INTO public.user_matchday_players (
        matchday_point_id,
        player_id,
        formation_index,
        is_locked
      )
      VALUES (
        v_point_id,
        (v_item->>'player_id')::int,
        (v_item->>'index')::int,
        false
      );
    END IF;
  END LOOP;

  UPDATE public.user_matchday_points
  SET total_points = (
    SELECT COALESCE(SUM(points), 0)
    FROM public.user_matchday_players
    WHERE matchday_point_id = v_point_id
      AND formation_index <= 10
  )
  WHERE id = v_point_id;
END;
$$;

-- Legacy overload: retain compatibility while applying the same archive guard.
CREATE OR REPLACE FUNCTION public.save_lineup(
  p_league_id bigint,
  p_updates jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_item jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  PERFORM public.assert_league_not_finished(p_league_id);

  -- This overload is kept for older clients. Only mutate the caller's own rows.
  -- Some deployments no longer store formation_index in league_players; in that
  -- case older clients already cannot use this obsolete path.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    BEGIN
      EXECUTE
        'UPDATE public.league_players '
        'SET formation_index = $1 '
        'WHERE league_id = $2 AND user_id = $3 AND player_id = $4'
      USING
        (v_item->>'index')::int,
        p_league_id,
        v_user_id,
        (v_item->>'player_id')::int;
    EXCEPTION
      WHEN undefined_column THEN
        RAISE EXCEPTION 'Legacy lineup storage is no longer supported'
          USING ERRCODE = '0A000';
    END;
  END LOOP;
END;
$$;
