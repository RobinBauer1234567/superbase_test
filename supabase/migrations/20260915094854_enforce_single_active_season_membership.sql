-- season_players keeps historical club memberships for transferred players.
-- Only one membership may be current (is_active = true) for a player/season.
-- Serialize competing sync writes and automatically deactivate the old club
-- before activating the new one, while preserving the historical row.
CREATE OR REPLACE FUNCTION public.enforce_single_active_season_membership()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
  IF NEW.is_active IS TRUE THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended(NEW.season_id::text || ':' || NEW.player_id::text, 0)
    );

    UPDATE public.season_players
    SET is_active = false
    WHERE season_id = NEW.season_id
      AND player_id = NEW.player_id
      AND team_id <> NEW.team_id
      AND is_active = true;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_season_players_single_active
ON public.season_players;

CREATE TRIGGER trg_season_players_single_active
BEFORE INSERT OR UPDATE OF season_id, player_id, team_id, is_active
ON public.season_players
FOR EACH ROW
WHEN (NEW.is_active IS TRUE)
EXECUTE FUNCTION public.enforce_single_active_season_membership();
