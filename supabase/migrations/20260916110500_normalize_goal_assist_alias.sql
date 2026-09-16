create or replace function public.normalize_matchrating_assists()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.statistics is null then
    return new;
  end if;

  if new.statistics ? 'goalAssist'
     and (
       not (new.statistics ? 'assists')
       or new.statistics->'assists' = 'null'::jsonb
     ) then
    new.statistics := jsonb_set(
      new.statistics,
      '{assists}',
      coalesce(new.statistics->'goalAssist', '0'::jsonb),
      true
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trigger_normalize_matchrating_assists on public.matchrating;
create trigger trigger_normalize_matchrating_assists
before insert or update of statistics on public.matchrating
for each row
execute function public.normalize_matchrating_assists();

-- Backfill the compatibility alias without re-running the expensive
-- aggregate trigger once per historic matchrating row.
alter table public.matchrating disable trigger trigger_update_gesamtstatistiken;

update public.matchrating
set statistics = jsonb_set(
  coalesce(statistics, '{}'::jsonb),
  '{assists}',
  coalesce(statistics->'goalAssist', '0'::jsonb),
  true
)
where statistics ? 'goalAssist'
  and (
    not (statistics ? 'assists')
    or statistics->'assists' is distinct from statistics->'goalAssist'
  );

alter table public.matchrating enable trigger trigger_update_gesamtstatistiken;

-- spieler_analytics already contains the aggregated SofaScore key goalAssist.
-- Add the alias used by the Flutter UI so historic totals are immediately correct.
update public.spieler_analytics
set gesamtstatistiken = jsonb_set(
  coalesce(gesamtstatistiken, '{}'::jsonb),
  '{assists}',
  coalesce(gesamtstatistiken->'goalAssist', '0'::jsonb),
  true
)
where gesamtstatistiken ? 'goalAssist'
  and (
    not (gesamtstatistiken ? 'assists')
    or gesamtstatistiken->'assists' is distinct from gesamtstatistiken->'goalAssist'
  );