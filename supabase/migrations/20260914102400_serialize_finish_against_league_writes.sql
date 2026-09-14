-- Serialize every guarded fantasy mutation against finish_season via a shared
-- lock on the season row. The finish transaction holds FOR UPDATE on that row.
-- Therefore a mutation is entirely before the finish or rejected after it.
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
  JOIN public.season s ON s.id = l.season_id
  WHERE l.id = p_league_id
  FOR SHARE OF s;

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

-- Lock the season before the transfer row. This lock order is compatible with
-- finish_season and prevents an instant purchase from crossing the finish
-- boundary while still avoiding a season/transfer-row deadlock.
CREATE OR REPLACE FUNCTION public.buy_player_now(p_transfer_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  t_row record;
  v_league_id bigint;
  buyer_budget bigint;
  current_user_id uuid := auth.uid();
  v_player record;
  v_season_id bigint;
  v_seller_name text := 'System';
  v_seller_avatar text := null;
  v_buyer_name text;
  v_buyer_avatar text;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT league_id INTO v_league_id
  FROM public.transfer_market
  WHERE id = p_transfer_id
    AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer nicht gefunden.';
  END IF;

  PERFORM public.assert_league_not_finished(v_league_id);

  SELECT * INTO t_row
  FROM public.transfer_market
  WHERE id = p_transfer_id
    AND is_active = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer nicht gefunden.';
  END IF;

  -- The listing cannot move between leagues, but defend the lock assumption.
  IF t_row.league_id IS DISTINCT FROM v_league_id THEN
    RAISE EXCEPTION 'Transfer league changed unexpectedly';
  END IF;

  SELECT budget INTO buyer_budget
  FROM public.league_members
  WHERE user_id = current_user_id
    AND league_id = t_row.league_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'League membership required' USING ERRCODE = '42501';
  END IF;

  IF buyer_budget < t_row.buy_now_price THEN
    RAISE EXCEPTION 'Nicht genug Budget.';
  END IF;

  UPDATE public.league_members
  SET budget = budget - t_row.buy_now_price
  WHERE user_id = current_user_id
    AND league_id = t_row.league_id;

  IF t_row.seller_id IS NOT NULL THEN
    UPDATE public.league_members
    SET budget = budget + t_row.buy_now_price
    WHERE user_id = t_row.seller_id
      AND league_id = t_row.league_id;

    SELECT username, avatar_url
    INTO v_seller_name, v_seller_avatar
    FROM public.profiles
    WHERE user_id = t_row.seller_id;
  END IF;

  SELECT username, avatar_url
  INTO v_buyer_name, v_buyer_avatar
  FROM public.profiles
  WHERE user_id = current_user_id;

  SELECT season_id INTO v_season_id
  FROM public.leagues
  WHERE id = t_row.league_id;

  SELECT
    s.name,
    s.position,
    s.profilbild_url,
    t.image_url AS team_image_url,
    sa.marktwert,
    sa.punkteschnitt
  INTO v_player
  FROM public.spieler s
  LEFT JOIN public.season_players sp
    ON sp.player_id = s.id
   AND sp.season_id = v_season_id
   AND sp.is_active = true
  LEFT JOIN public.team t ON sp.team_id = t.id
  LEFT JOIN public.spieler_analytics sa
    ON sa.spieler_id = s.id
   AND sa.season_id = v_season_id
  WHERE s.id = t_row.player_id;

  PERFORM set_config('my.skip_trigger', 'true', true);

  INSERT INTO public.league_players (
    league_id,
    user_id,
    player_id,
    purchase_price
  )
  VALUES (
    t_row.league_id,
    current_user_id,
    t_row.player_id,
    t_row.buy_now_price
  );

  INSERT INTO public.league_activities (league_id, type, content)
  VALUES (
    t_row.league_id,
    'TRANSFER',
    jsonb_build_object(
      'transfer_type', 'SOFORTKAUF',
      'transfer_id', t_row.id,
      'player_id', t_row.player_id,
      'position', v_player.position,
      'player_name', v_player.name,
      'profilbild_url', v_player.profilbild_url,
      'team_image_url', v_player.team_image_url,
      'marktwert', v_player.marktwert,
      'score', ROUND(COALESCE(v_player.punkteschnitt, 0)),
      'buyer_name', v_buyer_name,
      'buyer_avatar_url', v_buyer_avatar,
      'seller_name', v_seller_name,
      'seller_avatar_url', v_seller_avatar,
      'price', t_row.buy_now_price,
      'is_system_buy', (t_row.seller_id IS NULL)
    )
  );

  UPDATE public.transfer_market
  SET is_active = false
  WHERE id = t_row.id;
END;
$$;

-- Expired auctions use the same season-first lock order. Candidate IDs are read
-- without row locks; after the season guard succeeds, the transfer is claimed
-- with FOR UPDATE SKIP LOCKED so concurrent processors stay safe.
CREATE OR REPLACE FUNCTION public.process_expired_transfers()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  candidate record;
  t_rec record;
  bid_rec record;
  v_winner_budget numeric;
  v_player record;
  v_season_id bigint;
  v_seller_name text;
  v_seller_avatar text;
  v_buyer_name text;
  v_buyer_avatar text;
  v_is_system_buy boolean;
  v_final_price bigint;
  v_failed_bid boolean;
  v_transfer_type text;
  v_winner_found boolean;
BEGIN
  IF auth.uid() IS NULL AND COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  PERFORM set_config('my.skip_trigger', 'true', true);

  FOR candidate IN
    SELECT tm.id, tm.league_id
    FROM public.transfer_market tm
    JOIN public.leagues l ON l.id = tm.league_id
    JOIN public.season s ON s.id = l.season_id
    WHERE tm.is_active = true
      AND tm.expires_at <= now()
      AND l.finished_at IS NULL
      AND s.finished_at IS NULL
    ORDER BY tm.id
  LOOP
    -- Takes a shared lock on the season until this transaction ends.
    PERFORM public.assert_league_not_finished(candidate.league_id);

    SELECT * INTO t_rec
    FROM public.transfer_market
    WHERE id = candidate.id
      AND is_active = true
      AND expires_at <= now()
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    IF t_rec.league_id IS DISTINCT FROM candidate.league_id THEN
      CONTINUE;
    END IF;

    v_seller_name := 'System';
    v_seller_avatar := null;
    v_buyer_name := 'System';
    v_buyer_avatar := null;
    v_is_system_buy := true;
    v_failed_bid := false;
    v_transfer_type := 'AUKTION';
    v_winner_found := false;

    SELECT season_id INTO v_season_id
    FROM public.leagues
    WHERE id = t_rec.league_id;

    SELECT
      s.name,
      s.position,
      s.profilbild_url,
      t.image_url AS team_image_url,
      sa.marktwert,
      sa.punkteschnitt
    INTO v_player
    FROM public.spieler s
    LEFT JOIN public.season_players sp
      ON sp.player_id = s.id
     AND sp.season_id = v_season_id
     AND sp.is_active = true
    LEFT JOIN public.team t ON sp.team_id = t.id
    LEFT JOIN public.spieler_analytics sa
      ON sa.spieler_id = s.id
     AND sa.season_id = v_season_id
    WHERE s.id = t_rec.player_id;

    IF t_rec.seller_id IS NOT NULL THEN
      SELECT username, avatar_url
      INTO v_seller_name, v_seller_avatar
      FROM public.profiles
      WHERE user_id = t_rec.seller_id;
    END IF;

    FOR bid_rec IN
      SELECT *
      FROM public.transfer_bids
      WHERE transfer_id = t_rec.id
      ORDER BY amount DESC
    LOOP
      SELECT budget INTO v_winner_budget
      FROM public.league_members
      WHERE league_id = t_rec.league_id
        AND user_id = bid_rec.bidder_id
      FOR UPDATE;

      IF v_winner_budget >= bid_rec.amount THEN
        v_winner_found := true;
        v_final_price := bid_rec.amount;
        v_is_system_buy := false;

        SELECT username, avatar_url
        INTO v_buyer_name, v_buyer_avatar
        FROM public.profiles
        WHERE user_id = bid_rec.bidder_id;

        UPDATE public.league_members
        SET budget = budget - bid_rec.amount
        WHERE league_id = t_rec.league_id
          AND user_id = bid_rec.bidder_id;

        IF t_rec.seller_id IS NOT NULL THEN
          UPDATE public.league_members
          SET budget = budget + bid_rec.amount
          WHERE league_id = t_rec.league_id
            AND user_id = t_rec.seller_id;
        END IF;

        INSERT INTO public.league_players (
          league_id,
          user_id,
          player_id,
          purchase_price
        )
        VALUES (
          t_rec.league_id,
          bid_rec.bidder_id,
          t_rec.player_id,
          bid_rec.amount
        );
        EXIT;
      ELSE
        v_failed_bid := true;
      END IF;
    END LOOP;

    IF NOT v_winner_found THEN
      IF EXISTS (
        SELECT 1 FROM public.transfer_bids WHERE transfer_id = t_rec.id
      ) THEN
        v_transfer_type := 'AUKTION';
      ELSE
        v_transfer_type := 'KEINE GEBOTE';
      END IF;

      v_final_price := t_rec.min_bid_price;

      IF t_rec.seller_id IS NOT NULL THEN
        UPDATE public.league_members
        SET budget = budget + t_rec.min_bid_price
        WHERE league_id = t_rec.league_id
          AND user_id = t_rec.seller_id;
      END IF;
    END IF;

    INSERT INTO public.league_activities (league_id, type, content)
    VALUES (
      t_rec.league_id,
      'TRANSFER',
      jsonb_build_object(
        'transfer_type', v_transfer_type,
        'transfer_id', t_rec.id,
        'player_id', t_rec.player_id,
        'position', v_player.position,
        'player_name', v_player.name,
        'profilbild_url', v_player.profilbild_url,
        'team_image_url', v_player.team_image_url,
        'marktwert', v_player.marktwert,
        'score', round(coalesce(v_player.punkteschnitt, 0)),
        'buyer_name', v_buyer_name,
        'buyer_avatar_url', v_buyer_avatar,
        'seller_name', v_seller_name,
        'seller_avatar_url', v_seller_avatar,
        'price', v_final_price,
        'is_system_buy', v_is_system_buy,
        'failed_highest_bid', v_failed_bid
      )
    );

    UPDATE public.transfer_market
    SET is_active = false
    WHERE id = t_rec.id;
  END LOOP;
END;
$$;
