-- Tournament metadata used by the global tournament picker.
-- UEFA coefficients are a 2026/27 five-year association snapshot.
-- Non-UEFA coefficients are deliberately manual comparison values and can be
-- replaced later without changing the UI/sorting model.

alter table public.tournaments
  add column if not exists gender text,
  add column if not exists tier integer,
  add column if not exists association_coefficient numeric(8,3),
  add column if not exists coefficient_source text;

update public.tournaments
set gender = 'M'
where gender is null;

update public.tournaments
set gender = 'F'
where lower(name) like '%women%'
   or lower(name) like '%frauen%'
   or lower(name) like '%feminino%'
   or lower(name) like '%feminina%'
   or lower(name) like '%féminine%'
   or name in ('NWSL', 'WE-League', 'Liga F Moeve');

update public.tournaments
set tier = case
  when name = '2. Bundesliga' then 2
  when name = '3. Liga' then 3
  when name = '2. Liga' and country_name = 'Austria' then 2
  when name = '2. SNL' then 2
  when name = 'Betclic 1. Liga' then 2
  when name = 'Betclic 2. Liga' then 3
  when name = 'Challenger Pro League' then 2
  when name = 'Championship' and country_name = 'England' then 2
  when name = 'League One' and country_name = 'England' then 3
  when name = 'League Two' and country_name = 'England' then 4
  when name = 'National League' and country_name = 'England' then 5
  when name = 'National League North' and country_name = 'England' then 6
  when name = 'Women''s Super League 2' then 2
  when name = 'LaLiga 2' then 2
  when name = 'Ligue 2' then 2
  when name = 'Serie B' and country_name = 'Italy' then 2
  when name = 'Liga Portugal 2' then 2
  when name = 'FNL' and country_name = 'Czechia' then 2
  when name = 'First Division' and country_name = 'Ireland' then 2
  when name = 'NB II' then 2
  when name = 'J2 League' then 2
  when name = 'J3 League' then 3
  when name = 'K League 2' then 2
  when name = 'K3 League' then 3
  when name = 'Saudi 1st Division' then 2
  when name = 'Thai League 2' then 2
  when name = 'USL Championship' then 2
  when name = 'USL League One' then 3
  when name = 'MLS Next Pro' then 3
  when name = 'Liga de Ascenso' then 2
  when name like 'Liga de Expansión MX%' then 2
  when name = 'División Intermedia' then 2
  when name = 'Birinci Liqa' then 2
  when name = 'Mozzart Bet Prva Liga' then 2
  when name = 'Challenge League' and country_name = 'Switzerland' then 2
  when name like 'NPL %' then 2
  when name = 'Brasileirão Série B' then 2
  when country_name = 'Brazil' and name <> 'Brasileirão Betano' and name <> 'Brasileirão Série B' then 10
  when lower(name) like '%primavera%' then 99
  else coalesce(tier, 1)
end;

update public.tournaments
set association_coefficient = case country_name
  -- UEFA five-year coefficients
  when 'England' then 103.352
  when 'Italy' then 88.303
  when 'Spain' then 83.243
  when 'Germany' then 81.545
  when 'France' then 69.153
  when 'Portugal' then 65.350
  when 'Belgium' then 59.050
  when 'Netherlands' then 52.562
  when 'Türkiye' then 49.875
  when 'Czechia' then 45.125
  when 'Poland' then 45.125
  when 'Greece' then 44.612
  when 'Denmark' then 36.181
  when 'Norway' then 34.212
  when 'Cyprus' then 33.193
  when 'Switzerland' then 29.075
  when 'Hungary' then 26.562
  when 'Sweden' then 25.625
  when 'Austria' then 25.250
  when 'Scotland' then 25.050
  when 'Croatia' then 24.531
  when 'Romania' then 24.500
  when 'Ukraine' then 24.087
  when 'Israel' then 22.625
  when 'Slovenia' then 22.468
  when 'Azerbaijan' then 21.187
  when 'Bulgaria' then 20.187
  when 'Slovakia' then 20.125
  when 'Serbia' then 17.500
  when 'Russia' then 17.332
  when 'Iceland' then 16.770
  when 'Ireland' then 16.093
  when 'Armenia' then 15.437
  when 'Kosovo' then 13.531
  when 'Bosnia & Herzegovina' then 13.468
  when 'Latvia' then 13.375
  when 'Finland' then 12.875
  when 'Kazakhstan' then 12.375
  when 'Liechtenstein' then 10.500
  when 'Moldova' then 10.250
  when 'Faroe Islands' then 9.625
  when 'North Macedonia' then 8.800
  when 'Albania' then 8.250
  when 'Belarus' then 8.208
  when 'Lithuania' then 7.875
  when 'Malta' then 7.625
  when 'Andorra' then 7.165
  when 'Estonia' then 7.041
  when 'Gibraltar' then 6.874
  when 'Northern Ireland' then 6.375
  when 'Georgia' then 6.250
  when 'Luxembourg' then 6.250
  when 'Montenegro' then 5.833
  when 'Wales' then 4.499
  when 'San Marino' then 2.998

  -- Manual cross-confederation comparison values
  when 'Brazil' then 72.000
  when 'Argentina' then 60.000
  when 'Saudi Arabia' then 52.000
  when 'USA' then 48.000
  when 'Mexico' then 45.000
  when 'Japan' then 42.000
  when 'South Korea' then 36.000
  when 'Morocco' then 34.000
  when 'Ecuador' then 32.000
  when 'Qatar' then 30.000
  when 'Paraguay' then 29.000
  when 'Chile' then 28.000
  when 'Australia' then 26.000
  when 'United Arab Emirates' then 25.000
  when 'South Africa' then 23.000
  when 'Costa Rica' then 22.000
  when 'Uzbekistan' then 20.000
  when 'Bolivia' then 19.000
  when 'India' then 17.000
  when 'Thailand' then 16.000
  when 'Vietnam' then 14.000
  when 'Malaysia' then 13.000
  when 'Guatemala' then 12.000
  when 'Singapore' then 11.000
  when 'Kyrgyzstan' then 10.000
  when 'Cambodia' then 8.000
  when 'Asia' then 0.000
  else coalesce(association_coefficient, 0.000)
end,
coefficient_source = case
  when country_name in (
    'England','Italy','Spain','Germany','France','Portugal','Belgium','Netherlands',
    'Türkiye','Czechia','Poland','Greece','Denmark','Norway','Cyprus','Switzerland',
    'Hungary','Sweden','Austria','Scotland','Croatia','Romania','Ukraine','Israel',
    'Slovenia','Azerbaijan','Bulgaria','Slovakia','Serbia','Russia','Iceland','Ireland',
    'Armenia','Kosovo','Bosnia & Herzegovina','Latvia','Finland','Kazakhstan',
    'Liechtenstein','Moldova','Faroe Islands','North Macedonia','Albania','Belarus',
    'Lithuania','Malta','Andorra','Estonia','Gibraltar','Northern Ireland','Georgia',
    'Luxembourg','Montenegro','Wales','San Marino'
  ) then 'uefa_5y_2026_27'
  else 'manual_global'
end;

alter table public.tournaments
  alter column gender set default 'M',
  alter column gender set not null,
  alter column tier set default 1,
  alter column tier set not null,
  alter column association_coefficient set default 0,
  alter column association_coefficient set not null,
  alter column coefficient_source set default 'manual_global',
  alter column coefficient_source set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tournaments_gender_check'
      and conrelid = 'public.tournaments'::regclass
  ) then
    alter table public.tournaments
      add constraint tournaments_gender_check check (gender in ('M', 'F'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tournaments_tier_check'
      and conrelid = 'public.tournaments'::regclass
  ) then
    alter table public.tournaments
      add constraint tournaments_tier_check check (tier >= 1);
  end if;
end
$$;

comment on column public.tournaments.gender is 'M or F; used for tournament picker filtering.';
comment on column public.tournaments.tier is 'League level within its country/gender, 1 = highest division.';
comment on column public.tournaments.association_coefficient is 'Country/association strength used for global tournament ordering.';
comment on column public.tournaments.coefficient_source is 'uefa_5y_2026_27 for UEFA snapshot, manual_global otherwise.';
