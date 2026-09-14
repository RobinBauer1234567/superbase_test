-- Keep the manager-game season catalogue intentionally small:
--   * retain every initialized season as historical archive
--   * retain exactly the newest discovered season, even before initialization
--   * remove older seasons that were never initialized and have no dependent data
--
-- SofaScore uses both four-digit (2026/27) and two-digit (26/27) labels.
-- Two-digit labels from 70..99 are historical 19xx seasons; 00..69 are 20xx.
CREATE OR REPLACE FUNCTION public.season_start_year(p_name text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path TO ''
AS $$
  WITH parsed AS (
    SELECT
      trim(p_name) AS label,
      substring(trim(p_name) FROM '^([0-9]+)') AS raw_year
  )
  SELECT CASE
    WHEN label !~ '^([0-9]{4}|[0-9]{2})([/\-][0-9]{2,4})?$' THEN -1
    WHEN length(raw_year) = 4 THEN raw_year::integer
    WHEN raw_year::integer >= 70 THEN 1900 + raw_year::integer
    ELSE 2000 + raw_year::integer
  END
  FROM parsed
$$;

CREATE OR REPLACE FUNCTION public.prune_stale_uninitialized_seasons(
  p_tournament_id bigint DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  WITH ranked AS (
    SELECT
      s.id,
      s.tournament_id,
      row_number() OVER (
        PARTITION BY s.tournament_id
        ORDER BY public.season_start_year(s.name) DESC, s.id DESC
      ) AS season_rank
    FROM public.season s
    WHERE p_tournament_id IS NULL OR s.tournament_id = p_tournament_id
  ), stale AS (
    SELECT s.id
    FROM public.season s
    JOIN ranked r ON r.id = s.id
    WHERE r.season_rank > 1
      AND COALESCE(s.is_initialized, false) = false
      AND s.initialization_started_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.leagues x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.season_activation_requests x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.season_players x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.season_teams x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.spiel x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.spieltag x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.spieler_analytics x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.sync_tasks x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.user_matchday_points x WHERE x.season_id = s.id)
      AND NOT EXISTS (SELECT 1 FROM public.marktwert_historie x WHERE x.season_id = s.id)
  )
  DELETE FROM public.season s
  USING stale x
  WHERE s.id = x.id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_latest_uninitialized_season()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.tournament_id IS DISTINCT FROM NEW.tournament_id THEN
    PERFORM public.prune_stale_uninitialized_seasons(OLD.tournament_id);
  END IF;

  PERFORM public.prune_stale_uninitialized_seasons(NEW.tournament_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS season_prune_stale_uninitialized ON public.season;
CREATE TRIGGER season_prune_stale_uninitialized
AFTER INSERT OR UPDATE OF name, tournament_id, is_initialized, initialization_started_at
ON public.season
FOR EACH ROW
EXECUTE FUNCTION public.enforce_latest_uninitialized_season();

-- One-time cleanup of the historical discovery flood. Initialized archive seasons
-- are deliberately not touched.
SELECT public.prune_stale_uninitialized_seasons(NULL);

REVOKE ALL ON FUNCTION public.prune_stale_uninitialized_seasons(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_latest_uninitialized_season() FROM PUBLIC, anon, authenticated;
