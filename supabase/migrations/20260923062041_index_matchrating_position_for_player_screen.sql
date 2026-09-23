-- Speed up the PlayerScreen radar comparison query:
-- SELECT spieler_id, statistics, punkte FROM matchrating
-- WHERE match_position = $1 LIMIT 1000.
-- Existing player/match-specific indexes do not cover match_position.
CREATE INDEX IF NOT EXISTS idx_matchrating_match_position
  ON public.matchrating (match_position);

ANALYZE public.matchrating;
