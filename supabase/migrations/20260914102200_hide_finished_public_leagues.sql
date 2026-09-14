-- Finished leagues are member archives, not joinable public leagues. Keep older
-- clients from making them public or active again.
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
    NEW.is_public := false;
  ELSIF NEW.finished_at IS NOT NULL THEN
    NEW.is_active := false;
    NEW.is_public := false;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leagues_guard_finished_state ON public.leagues;
CREATE TRIGGER leagues_guard_finished_state
BEFORE UPDATE OF is_active, finished_at, is_public
ON public.leagues
FOR EACH ROW
EXECUTE FUNCTION public.guard_finished_league_state();

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

-- Backfill the discoverability flag for leagues already finished by the prior
-- migration. The trigger also enforces is_active=false.
UPDATE public.leagues
SET is_public = false,
    is_active = false
WHERE finished_at IS NOT NULL;
