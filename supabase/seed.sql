-- Stable reference/configuration data required by a fresh ManagerSpiel database.
-- User, league, sports, match, analytics, queue, and Storage object data are intentionally excluded.

insert into public.formation (formation, positionsliste)
values
  ('3-1-4-2', '["TW","IV","IV","IV","ZDM","RA","ZM","ZM","LA","ST","ST"]'::jsonb),
  ('3-2-4-1', '["TW","IV","IV","IV","ZDM","ZDM","RA","ZM","ZM","LA","ST"]'::jsonb),
  ('3-3-1-3', '["TW","IV","IV","IV","RV","ZM","LV","ZOM","RA","ST","LA"]'::jsonb),
  ('3-3-3-1', '["TW","IV","IV","IV","RV","ZM","LV","RA","ZOM","LA","ST"]'::jsonb),
  ('3-4-1-2', '["TW","IV","IV","IV","RV","ZDM","ZDM","LV","ZOM","ST","ST"]'::jsonb),
  ('3-4-2-1', '["TW","IV","IV","IV","RV","ZDM","ZDM","LV","ZOM","ZOM","ST"]'::jsonb),
  ('3-4-3', '["TW","IV","IV","IV","RA","ZM","ZM","LA","RA","ST","LA"]'::jsonb),
  ('3-5-1-1', '["TW","IV","IV","IV","RV","ZDM","ZDM","ZDM","LV","ZOM","ST"]'::jsonb),
  ('3-5-2', '["TW","IV","IV","IV","RA","ZM","ZM","ZM","LA","ST","ST"]'::jsonb),
  ('4-1-3-2', '["TW","RV","IV","IV","LV","ZDM","RA","ZOM","LA","ST","ST"]'::jsonb),
  ('4-1-4-1', '["TW","RV","IV","IV","LV","ZDM","RA","ZM","ZM","LA","ST"]'::jsonb),
  ('4-2-1-3', '["TW","RV","IV","IV","LV","ZDM","ZDM","ZOM","RA","ST","LA"]'::jsonb),
  ('4-2-2-2', '["TW","RV","IV","IV","LV","ZDM","ZDM","ZOM","ZOM","ST","ST"]'::jsonb),
  ('4-2-3-1', '["TW","RV","IV","IV","LV","ZDM","ZDM","RA","ZOM","LA","ST"]'::jsonb),
  ('4-3-1-2', '["TW","RV","IV","IV","LV","RV","ZM","LV","ZOM","ST","ST"]'::jsonb),
  ('4-3-2-1', '["TW","RV","IV","IV","LV","RV","ZM","LV","ZOM","ZOM","ST"]'::jsonb),
  ('4-3-3', '["TW","RV","IV","IV","LV","ZM","ZM","ZM","RA","ST","LA"]'::jsonb),
  ('4-4-1-1', '["TW","RV","IV","IV","LV","RV","ZDM","ZDM","LV","ZOM","ST"]'::jsonb),
  ('4-4-2', '["TW","RV","IV","IV","LV","RA","ZM","ZM","LA","ST","ST"]'::jsonb),
  ('4-5-1', '["TW","RV","IV","IV","LV","RA","ZM","ZM","ZM","LA","ST"]'::jsonb),
  ('5-3-2', '["TW","RV","IV","IV","IV","LV","ZM","ZM","ZM","ST","ST"]'::jsonb),
  ('5-4-1', '["TW","RV","IV","IV","IV","LV","RA","ZM","ZM","LA","ST"]'::jsonb)
on conflict (formation) do update
set positionsliste = excluded.positionsliste;

insert into public.game_settings (
  id,
  mw_multiplier,
  mw_exponent,
  mw_base_value,
  mw_daily_adjustment,
  tm_daily_players,
  updated_at
)
values (1, 100000, 1.25, 1000000, 0.03, 10, now())
on conflict (id) do update
set
  mw_multiplier = excluded.mw_multiplier,
  mw_exponent = excluded.mw_exponent,
  mw_base_value = excluded.mw_base_value,
  mw_daily_adjustment = excluded.mw_daily_adjustment,
  tm_daily_players = excluded.tm_daily_players,
  updated_at = excluded.updated_at;

insert into public.api_sync_lock (id)
values (1)
on conflict (id) do nothing;
