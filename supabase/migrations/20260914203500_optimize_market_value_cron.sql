-- Replace the per-player loop with one set-based analytics refresh per season.
-- This keeps the daily cron fast enough now that player projections use cross-season history.
CREATE OR REPLACE FUNCTION public.update_all_spieler_analytics(p_season_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  WITH active_players AS (
    SELECT DISTINCT ON (sp.player_id)
      sp.player_id,
      sp.team_id
    FROM public.season_players sp
    WHERE sp.season_id = p_season_id
      AND sp.is_active = true
    ORDER BY sp.player_id, sp.team_id
  ),
  career_average AS (
    SELECT
      mr.spieler_id AS player_id,
      AVG(mr.punkte) AS punkteschnitt
    FROM public.matchrating mr
    JOIN public.spiel s ON s.id = mr.spiel_id
    JOIN active_players ap ON ap.player_id = mr.spieler_id
    WHERE lower(s.status) = 'final'
    GROUP BY mr.spieler_id
  ),
  ranked_recent_appearances AS (
    SELECT
      mr.spieler_id AS player_id,
      mr.punkte,
      mr.formationsindex,
      ROW_NUMBER() OVER (
        PARTITION BY mr.spieler_id
        ORDER BY s.datum DESC NULLS LAST, s.id DESC
      ) AS rn
    FROM public.matchrating mr
    JOIN public.spiel s ON s.id = mr.spiel_id
    JOIN active_players ap ON ap.player_id = mr.spieler_id
    WHERE lower(s.status) = 'final'
  ),
  recent_form AS (
    SELECT
      rra.player_id,
      AVG(rra.punkte) AS form,
      AVG(CASE WHEN rra.formationsindex <= 10 THEN 1.0 ELSE 0.0 END) AS historical_startelf_quote
    FROM ranked_recent_appearances rra
    WHERE rra.rn <= 5
    GROUP BY rra.player_id
  ),
  ranked_current_team_games AS (
    SELECT
      ap.player_id,
      s.id AS spiel_id,
      ROW_NUMBER() OVER (
        PARTITION BY ap.player_id
        ORDER BY s.datum DESC NULLS LAST, s.id DESC
      ) AS rn
    FROM active_players ap
    JOIN public.spiel s
      ON s.season_id = p_season_id
     AND lower(s.status) = 'final'
     AND (s.heimteam_id = ap.team_id OR s."auswärtsteam_id" = ap.team_id)
  ),
  current_startelf AS (
    SELECT
      rcg.player_id,
      COUNT(*)::integer AS current_team_games,
      COUNT(mr.id) FILTER (WHERE mr.formationsindex <= 10)::numeric
        / NULLIF(COUNT(*), 0) AS startelf_quote
    FROM ranked_current_team_games rcg
    LEFT JOIN public.matchrating mr
      ON mr.spiel_id = rcg.spiel_id
     AND mr.spieler_id = rcg.player_id
    WHERE rcg.rn <= 5
    GROUP BY rcg.player_id
  ),
  computed AS (
    SELECT
      ap.player_id,
      COALESCE(ca.punkteschnitt, 0) AS punkteschnitt,
      COALESCE(rf.form, 0) AS form,
      CASE
        WHEN COALESCE(cs.current_team_games, 0) > 0
          THEN COALESCE(cs.startelf_quote, 0)
        ELSE COALESCE(rf.historical_startelf_quote, 0)
      END AS startelf_quote,
      COALESCE(ta.matchup_faktor, 1.0) AS matchup_faktor
    FROM active_players ap
    LEFT JOIN career_average ca ON ca.player_id = ap.player_id
    LEFT JOIN recent_form rf ON rf.player_id = ap.player_id
    LEFT JOIN current_startelf cs ON cs.player_id = ap.player_id
    LEFT JOIN public.team_analytics ta ON ta.team_id = ap.team_id
  )
  UPDATE public.spieler_analytics sa
  SET punkteschnitt = ROUND(c.punkteschnitt, 2),
      form = ROUND(c.form, 2),
      startelf_quote = ROUND(c.startelf_quote, 2),
      expected_points = GREATEST(
        0,
        ROUND(
          ((c.punkteschnitt * 0.4) + (c.form * 0.6))
          * c.matchup_faktor
          * c.startelf_quote,
          2
        )
      ),
      last_updated_at = now()
  FROM computed c
  WHERE sa.spieler_id = c.player_id
    AND sa.season_id = p_season_id;
END;
$$;
