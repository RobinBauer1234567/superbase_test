-- Keep the matchrating analytics trigger safe when called from RPCs that run
-- with an empty search_path (for example process_match_lineups).
--
-- The previous function referenced matchrating and spiel without a schema.
-- When process_match_lineups inserted into public.matchrating, this trigger
-- inherited search_path = '' and failed with 42P01: relation "matchrating"
-- does not exist.

CREATE OR REPLACE FUNCTION public.update_gesamtstatistiken()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
  v_mr_id bigint;
  player_id bigint;
  _season_id bigint;
  _stats_sum jsonb := '{}'::jsonb;
  aggregated_stats jsonb;
  total_punkte numeric := 0;
  total_matches bigint := 0;
BEGIN
  v_mr_id := coalesce(
    (case when new is not null then (new.id)::bigint end),
    (case when old is not null then (old.id)::bigint end)
  );

  if v_mr_id is null then return null; end if;

  select mr.spieler_id::bigint, sp.season_id::bigint
  into player_id, _season_id
  from public.matchrating mr
  join public.spiel sp on sp.id = mr.spiel_id
  where mr.id = v_mr_id
  limit 1;

  if player_id is null or _season_id is null then return null; end if;

  select coalesce(jsonb_object_agg(key, val_sum), '{}'::jsonb)
  into _stats_sum
  from (
    select e.key,
      sum(
        case jsonb_typeof(e.val)
          when 'number' then (e.val)::text::numeric
          when 'object' then coalesce(
            nullif(regexp_replace(e.val->>'original','[^0-9\.-]+','','g'),'')::numeric,
            nullif(regexp_replace(e.val->>'alternative','[^0-9\.-]+','','g'),'')::numeric,
            nullif(regexp_replace(e.val->>'value','[^0-9\.-]+','','g'),'')::numeric,
            0
          )
          when 'string' then coalesce(
            nullif(regexp_replace(e.val::text,'[^0-9\.-]+','','g'), '')::numeric,
            0
          )
          else 0
        end
      ) as val_sum
    from public.matchrating mr
    join public.spiel sp on sp.id = mr.spiel_id
    cross join lateral jsonb_each(coalesce(mr.statistics, '{}'::jsonb)) as e(key, val)
    where mr.spieler_id = player_id
      and sp.season_id = _season_id
    group by e.key
  ) sub;

  select coalesce(sum(mr.punkte)::numeric, 0), coalesce(count(*)::bigint, 0)
  into total_punkte, total_matches
  from public.matchrating mr
  join public.spiel sp on sp.id = mr.spiel_id
  where mr.spieler_id = player_id
    and sp.season_id = _season_id;

  if total_matches = 0 then
    update public.spieler_analytics
    set gesamtstatistiken = '{}'::jsonb,
        anzahl_spiele = 0
    where spieler_id = player_id
      and season_id = _season_id;
    return null;
  end if;

  aggregated_stats := coalesce(_stats_sum, '{}'::jsonb)
    || jsonb_build_object('gesamtpunkte', total_punkte);

  insert into public.spieler_analytics (
    spieler_id,
    season_id,
    gesamtstatistiken,
    anzahl_spiele,
    marktwert,
    calculated_marktwert
  )
  values (
    player_id,
    _season_id,
    aggregated_stats,
    total_matches,
    1000000,
    1000000
  )
  on conflict (spieler_id, season_id)
  do update set
    gesamtstatistiken = excluded.gesamtstatistiken,
    anzahl_spiele = excluded.anzahl_spiele;

  return null;
END;
$function$;
