ALTER TABLE public.game_settings
ADD COLUMN IF NOT EXISTS average_rating_color_decay_base numeric NOT NULL DEFAULT 0.85;

UPDATE public.game_settings
SET average_rating_color_decay_base = 0.85
WHERE id = 1
  AND average_rating_color_decay_base IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'game_settings_average_rating_color_decay_base_check'
      AND conrelid = 'public.game_settings'::regclass
  ) THEN
    ALTER TABLE public.game_settings
    ADD CONSTRAINT game_settings_average_rating_color_decay_base_check
    CHECK (
      average_rating_color_decay_base > 0
      AND average_rating_color_decay_base <= 1
    );
  END IF;
END
$$;
