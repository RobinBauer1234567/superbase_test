-- Keep tournament ranking metadata complete for leagues discovered after the
-- initial 20260917093000_tournament_ranking_metadata.sql backfill.
--
-- UEFA values are the five-year association coefficient snapshot used by the
-- app for 2026/27. Non-UEFA values are deliberately coarse manual comparison
-- values so that global leagues can be interleaved instead of being pushed to
-- the end of the list.

create or replace function public.apply_tournament_ranking_metadata()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_name text := lower(trim(coalesce(new.name, '')));
  v_country text := trim(coalesce(new.country_name, ''));
begin
  -- Normalize a few country labels that can occur in external feeds.
  v_country := case v_country
    when 'Turkey' then 'Türkiye'
    when 'Turkiye' then 'Türkiye'
    when 'Czech Republic' then 'Czechia'
    when 'Republic of Ireland' then 'Ireland'
    when 'Bosnia and Herzegovina' then 'Bosnia & Herzegovina'
    when 'United States' then 'USA'
    when 'United States of America' then 'USA'
    when 'Korea Republic' then 'South Korea'
    else v_country
  end;
  new.country_name := nullif(v_country, '');

  -- Preserve explicit SofaScore metadata when available, but repair obvious
  -- female competitions even when the column arrived with its default 'M'.
  if new.gender is null
     or v_name like '%women%'
     or v_name like '%women''s%'
     or v_name like '%frauen%'
     or v_name like '%feminino%'
     or v_name like '%feminina%'
     or v_name like '%féminine%'
     or v_name like '%femenin%'
     or v_name in ('nwsl', 'liga f moeve', 'we-league') then
    if v_name like '%women%'
       or v_name like '%women''s%'
       or v_name like '%frauen%'
       or v_name like '%feminino%'
       or v_name like '%feminina%'
       or v_name like '%féminine%'
       or v_name like '%femenin%'
       or v_name in ('nwsl', 'liga f moeve', 'we-league') then
      new.gender := 'F';
    else
      new.gender := 'M';
    end if;
  end if;

  -- Preserve an explicitly supplied tier unless this is one of the currently
  -- known competitions for which the domestic league level is unambiguous.
  new.tier := case
    -- England
    when v_country = 'England' and v_name = 'premier league' then 1
    when v_country = 'England' and v_name = 'championship' then 2
    when v_country = 'England' and v_name = 'league one' then 3
    when v_country = 'England' and v_name = 'league two' then 4
    when v_country = 'England' and v_name = 'national league' then 5
    when v_country = 'England' and v_name like 'national league north%' then 6
    when v_country = 'England' and v_name like 'national league south%' then 6
    when v_country = 'England' and v_name = 'women''s super league 2' then 2

    -- Major European pyramids
    when v_country = 'Germany' and v_name = '2. bundesliga' then 2
    when v_country = 'Germany' and v_name = '3. liga' then 3
    when v_country = 'Italy' and v_name = 'serie b' then 2
    when v_country = 'Spain' and v_name = 'laliga 2' then 2
    when v_country = 'France' and v_name = 'ligue 2' then 2
    when v_country = 'Portugal' and v_name = 'liga portugal 2' then 2
    when v_country = 'Belgium' and v_name = 'challenger pro league' then 2
    when v_country = 'Netherlands' and v_name = 'eerste divisie' then 2
    when v_country = 'Austria' and v_name = '2. liga' then 2
    when v_country = 'Switzerland' and v_name = 'challenge league' then 2
    when v_country = 'Scotland' and v_name = 'scottish championship' then 2

    -- Central / Eastern Europe
    when v_country = 'Poland' and v_name = 'betclic 1. liga' then 2
    when v_country = 'Poland' and v_name = 'betclic 2. liga' then 3
    when v_country = 'Czechia' and v_name = 'fnl' then 2
    when v_country = 'Hungary' and v_name = 'nb ii' then 2
    when v_country = 'Serbia' and v_name = 'mozzart bet prva liga' then 2
    when v_country = 'Slovenia' and v_name = '2. snl' then 2
    when v_country = 'Azerbaijan' and v_name = 'birinci liqa' then 2
    when v_country = 'Ireland' and v_name = 'first division' then 2

    -- Asia / Oceania
    when v_country = 'Japan' and v_name = 'j2 league' then 2
    when v_country = 'Japan' and v_name = 'j3 league' then 3
    when v_country = 'South Korea' and v_name = 'k league 2' then 2
    when v_country = 'South Korea' and v_name = 'k3 league' then 3
    when v_country = 'Saudi Arabia' and v_name = 'saudi 1st division' then 2
    when v_country = 'Thailand' and v_name = 'thai league 2' then 2
    when v_country = 'Australia' and v_name like 'npl %' then 2

    -- Americas
    when v_country = 'Brazil' and v_name = 'brasileirão série b' then 2
    when v_country = 'Brazil' and (
      v_name like 'baianão%'
      or v_name = 'carioca'
      or v_name = 'gaúcho'
      or v_name like 'mineiro%'
      or v_name = 'paranaense'
      or v_name like 'paulista%'
    ) then 10
    when v_country = 'Chile' and v_name = 'liga de ascenso' then 2
    when v_country = 'Paraguay' and v_name = 'división intermedia' then 2
    when v_country = 'Mexico' and v_name like 'liga de expansión mx%' then 2
    when v_country = 'USA' and v_name = 'usl championship' then 2
    when v_country = 'USA' and v_name = 'usl league one' then 3
    when v_country = 'USA' and v_name = 'mls next pro' then 3

    when v_name like '%primavera%' then 99
    else greatest(coalesce(new.tier, 1), 1)
  end;

  new.association_coefficient := case v_country
    -- UEFA five-year association coefficients
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
    when 'Brazil' then 62.000
    when 'Argentina' then 52.000
    when 'Saudi Arabia' then 33.000
    when 'USA' then 30.000
    when 'Mexico' then 29.000
    when 'Japan' then 28.000
    when 'South Korea' then 24.000
    when 'Morocco' then 23.000
    when 'Ecuador' then 22.000
    when 'Paraguay' then 21.000
    when 'Chile' then 20.000
    when 'Qatar' then 19.000
    when 'Australia' then 18.000
    when 'United Arab Emirates' then 17.000
    when 'South Africa' then 16.000
    when 'Costa Rica' then 15.000
    when 'Uzbekistan' then 14.000
    when 'Bolivia' then 13.000
    when 'India' then 11.000
    when 'Thailand' then 10.000
    when 'Vietnam' then 9.000
    when 'Malaysia' then 8.000
    when 'Guatemala' then 8.000
    when 'Singapore' then 6.000
    when 'Kyrgyzstan' then 6.000
    when 'Cambodia' then 5.000
    else 0.000
  end;

  new.coefficient_source := case
    when v_country in (
      'England','Italy','Spain','Germany','France','Portugal','Belgium',
      'Netherlands','Türkiye','Czechia','Poland','Greece','Denmark','Norway',
      'Cyprus','Switzerland','Hungary','Sweden','Austria','Scotland','Croatia',
      'Romania','Ukraine','Israel','Slovenia','Azerbaijan','Bulgaria','Slovakia',
      'Serbia','Russia','Iceland','Ireland','Armenia','Kosovo',
      'Bosnia & Herzegovina','Latvia','Finland','Kazakhstan','Liechtenstein',
      'Moldova','Faroe Islands','North Macedonia','Albania','Belarus','Lithuania',
      'Malta','Andorra','Estonia','Gibraltar','Northern Ireland','Georgia',
      'Luxembourg','Montenegro','Wales','San Marino'
    ) then 'uefa_5y_2026_27'
    when new.association_coefficient > 0 then 'manual_global'
    else 'manual_global'
  end;

  return new;
end;
$$;

-- The function is an implementation detail of the table trigger, not a public
-- RPC endpoint.
revoke all on function public.apply_tournament_ranking_metadata() from public;
revoke all on function public.apply_tournament_ranking_metadata() from anon;
revoke all on function public.apply_tournament_ranking_metadata() from authenticated;

drop trigger if exists trg_apply_tournament_ranking_metadata on public.tournaments;
create trigger trg_apply_tournament_ranking_metadata
before insert or update of name, country_name, gender, tier
on public.tournaments
for each row
execute function public.apply_tournament_ranking_metadata();

-- Re-run the classifier once so older installations receive the same calibrated
-- manual values as the app fallback map. This is idempotent for the current
-- 136 discovered leagues.
update public.tournaments
set name = name;

create index if not exists idx_tournaments_global_picker
  on public.tournaments (association_coefficient desc, country_name, gender, tier);
