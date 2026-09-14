ALTER TABLE public.game_settings
ADD COLUMN IF NOT EXISTS rating_color_decay_base numeric NOT NULL DEFAULT 0.8;

UPDATE public.game_settings
SET rating_color_decay_base = 0.8
WHERE id = 1
  AND rating_color_decay_base IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'game_settings_rating_color_decay_base_check'
      AND conrelid = 'public.game_settings'::regclass
  ) THEN
    ALTER TABLE public.game_settings
    ADD CONSTRAINT game_settings_rating_color_decay_base_check
    CHECK (
      rating_color_decay_base > 0
      AND rating_color_decay_base <= 1
    );
  END IF;
END
$$;
