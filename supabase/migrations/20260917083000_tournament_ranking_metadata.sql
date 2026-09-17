alter table public.tournaments
  add column if not exists gender text,
  add column if not exists tier integer,
  add column if not exists country_coefficient numeric(8,3);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tournaments_gender_check'
  ) then
    alter table public.tournaments
      add constraint tournaments_gender_check
      check (gender is null or gender in ('M', 'F'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'tournaments_tier_check'
  ) then
    alter table public.tournaments
      add constraint tournaments_tier_check
      check (tier is null or tier > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'tournaments_country_coefficient_check'
  ) then
    alter table public.tournaments
      add constraint tournaments_country_coefficient_check
      check (country_coefficient is null or country_coefficient >= 0);
  end if;
end $$;

-- UEFA five-year coefficients plus deliberately simple manual comparison
-- values for non-UEFA associations. The latter are product heuristics and can
-- later be replaced by a global league-strength model without schema changes.
update public.tournaments
set country_coefficient = case country_name
  when 'England' then 103.352
  when 'Italy' then 88.303
  when 'Spain' then 83.243
  when 'Germany' then 81.545
  when 'France' then 69.153
  when 'Portugal' then 65.350
  when 'Brazil' then 61.000
  when 'Belgium' then 59.050
  when 'Argentina' then 54.000
  when 'Netherlands' then 52.562
  when 'Türkiye' then 49.875
  when 'Saudi Arabia' then 49.000
  when 'USA' then 46.000
  when 'Czechia' then 45.125
  when 'Poland' then 45.125
  when 'Mexico' then 45.000
  when 'Greece' then 44.612
  when 'Japan' then 42.000
  when 'Denmark' then 36.181
  when 'South Korea' then 36.000
  when 'Norway' then 34.212
  when 'Morocco' then 34.000
  when 'Qatar' then 32.000
  when 'United Arab Emirates' then 31.000
  when 'Australia' then 30.000
  when 'Switzerland' then 29.075
  when 'Ecuador' then 29.000
  when 'Paraguay' then 28.000
  when 'Chile' then 27.000
  when 'Hungary' then 26.562
  when 'Sweden' then 25.625
  when 'Austria' then 25.250
  when 'Scotland' then 25.050
  when 'South Africa' then 25.000
  when 'Croatia' then 24.531
  when 'Romania' then 24.500
  when 'Costa Rica' then 24.000
  when 'Ukraine' then 22.587
  when 'Slovenia' then 22.468
  when 'Uzbekistan' then 22.000
  when 'Azerbaijan' then 21.187
  when 'India' then 21.000
  when 'Bulgaria' then 20.187
  when 'Slovakia' then 20.125
  when 'Bolivia' then 20.000
  when 'Thailand' then 19.000
  when 'Vietnam' then 18.000
  when 'Serbia' then 17.500
  when 'Malaysia' then 17.000
  when 'Ireland' then 16.093
  when 'Guatemala' then 16.000
  when 'Kosovo' then 13.531
  when 'Bosnia & Herzegovina' then 13.468
  when 'Latvia' then 13.375
  when 'Kazakhstan' then 12.375
  when 'Singapore' then 12.000
  when 'Cambodia' then 12.000
  when 'Kyrgyzstan' then 11.000
  when 'Moldova' then 10.250
  when 'Asia' then 10.000
  when 'Faroe Islands' then 9.625
  when 'Albania' then 8.250
  when 'Lithuania' then 7.875
  when 'Andorra' then 7.165
  when 'Estonia' then 7.041
  when 'Northern Ireland' then 6.375
  when 'Montenegro' then 5.600
  when 'Wales' then 5.400
  else coalesce(country_coefficient, 5.000)
end;

-- Existing data: explicitly identify women's competitions that are not always
-- recognizable from an English name. Future SofaScore metadata can overwrite
-- these values with the exact uniqueTournament.gender field.
update public.tournaments
set gender = case
  when id in (
    404, 1894, 10476, 10443, 9412, 14448, 1044, 10553, 1139,
    232, 20065, 10640, 18653, 13593, 13592, 10527, 23064, 1127, 1690
  ) then 'F'
  else coalesce(gender, 'M')
end;

-- Known league levels for the tournaments already discovered in production.
-- Unknown/special regional competitions remain nullable and are sorted after
-- explicit levels when richer SofaScore metadata is added later.
update public.tournaments
set tier = case id
  when 17 then 1 when 18 then 2 when 24 then 3 when 25 then 4
  when 173 then 5 when 176 then 6 when 1044 then 1 when 10553 then 2
  when 35 then 1 when 44 then 2 when 491 then 3 when 232 then 1
  when 34 then 1 when 182 then 2 when 1139 then 1
  when 23 then 1 when 53 then 2 when 10640 then 1 when 2292 then 1
  when 8 then 1 when 54 then 2 when 1127 then 1
  when 238 then 1 when 239 then 2 when 10527 then 1
  when 37 then 1 when 131 then 2
  when 38 then 1 when 9 then 2
  when 45 then 1 when 135 then 2
  when 172 then 1 when 205 then 2
  when 187 then 1 when 1339 then 2
  when 192 then 1 when 193 then 2 when 20065 then 1
  when 202 then 1 when 229 then 2 when 515 then 3
  when 36 then 1 when 206 then 2
  when 210 then 1 when 721 then 2
  when 215 then 1 when 216 then 2
  when 98 then 2
  when 196 then 1 when 402 then 2 when 2293 then 3 when 18653 then 1
  when 11621 then 1 when 11620 then 1 when 11611 then 2 when 11612 then 2
  when 13593 then 1 when 13592 then 1
  when 11653 then 1 when 1240 then 2
  when 11540 then 1 when 1254 then 2
  when 955 then 1 when 2120 then 2 when 23064 then 1
  when 777 then 2 when 10268 then 3
  when 1032 then 1 when 10511 then 2
  when 18641 then 3 when 1690 then 1 when 13363 then 2 when 13362 then 3
  when 136 then 1 when 1894 then 1
  when 1274 then 2 when 1268 then 2 when 10476 then 2 when 1258 then 2
  when 1275 then 2 when 10443 then 2 when 1270 then 2
  when 325 then 1 when 390 then 2 when 14448 then 1
  when 155 then 1
  when 937 then 1
  when 825 then 1
  when 971 then 1
  when 1900 then 1
  else tier
end;

comment on column public.tournaments.gender is
  'Competition gender from SofaScore where available: M or F.';
comment on column public.tournaments.tier is
  'League level within the domestic pyramid; 1 is the highest level.';
comment on column public.tournaments.country_coefficient is
  'Country sorting coefficient: UEFA five-year coefficient in Europe, manual comparison value elsewhere.';
