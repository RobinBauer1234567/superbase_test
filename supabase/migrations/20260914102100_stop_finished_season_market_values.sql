-- Market values are season-scoped. Update every currently running initialized
-- season, and never mutate analytics after that season has finished.
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
  SELECT * INTO v_settings
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

    UPDATE public.spieler_analytics
    SET calculated_marktwert = ROUND(
          v_settings.mw_multiplier
          * power(COALESCE(expected_points, 0), v_settings.mw_exponent)
          + v_settings.mw_base_value
        ),
        marktwert = ROUND(
          marktwert + (
            (
              v_settings.mw_multiplier
              * power(COALESCE(expected_points, 0), v_settings.mw_exponent)
              + v_settings.mw_base_value
            ) - marktwert
          ) * v_settings.mw_daily_adjustment
        ),
        last_updated_at = now()
    WHERE season_id = v_season.id;
  END LOOP;
END;
$$;
