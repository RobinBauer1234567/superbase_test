-- A real-world club departure applies across competitions. The old implementation
-- only deactivated the membership inside p_season_id, which could leave the same
-- player active for the former club in another current competition. We only
-- propagate the departure; activation for the destination still requires that
-- competition's own squad/transfer sync so cup eligibility is not invented.
CREATE OR REPLACE FUNCTION public.process_transfer_event(
  p_transfer_id bigint,
  p_player_id bigint,
  p_from_team_id bigint,
  p_to_team_id bigint,
  p_season_id integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_service boolean := coalesce(auth.jwt()->>'role', '') = 'service_role';
  v_team_exists boolean;
  v_player_exists boolean;
BEGIN
  IF NOT v_is_service AND (
    v_uid IS NULL OR NOT EXISTS (
      SELECT 1
      FROM public.sync_tasks st
      WHERE st.locked_by = v_uid
        AND st.status = 'PROCESSING'
        AND st.locked_at > now() - interval '10 minutes'
        AND st.task_type = 'SYNC_TRANSFERS'
        AND st.season_id = p_season_id
    )
  ) THEN
    RAISE EXCEPTION 'An owned SYNC_TRANSFERS task is required'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(p_transfer_id);

  IF EXISTS (
    SELECT 1
    FROM public.processed_transfers pt
    WHERE pt.transfer_id = p_transfer_id
  ) THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.spieler s
    WHERE s.id = p_player_id
  )
  INTO v_player_exists;

  IF NOT v_player_exists THEN
    INSERT INTO public.processed_transfers (transfer_id)
    VALUES (p_transfer_id)
    ON CONFLICT (transfer_id) DO NOTHING;
    RETURN false;
  END IF;

  IF p_from_team_id IS NOT NULL THEN
    UPDATE public.season_players sp
    SET is_active = false
    FROM public.season s
    WHERE sp.player_id = p_player_id
      AND sp.team_id = p_from_team_id
      AND sp.is_active = true
      AND s.id = sp.season_id
      AND s.is_active IS TRUE
      AND s.finished_at IS NULL
      AND s.archived_at IS NULL;
  END IF;

  IF p_to_team_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.team t
      WHERE t.id = p_to_team_id
    )
    INTO v_team_exists;

    IF v_team_exists THEN
      INSERT INTO public.season_players (
        season_id,
        player_id,
        team_id,
        is_active
      )
      VALUES (
        p_season_id,
        p_player_id,
        p_to_team_id,
        true
      )
      ON CONFLICT ON CONSTRAINT season_players_unique_combo
      DO UPDATE SET is_active = true;
    END IF;
  END IF;

  INSERT INTO public.processed_transfers (transfer_id)
  VALUES (p_transfer_id)
  ON CONFLICT (transfer_id) DO NOTHING;

  RETURN true;
END;
$$;
