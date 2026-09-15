-- A player can have multiple season_players rows after a transfer. Select exactly
-- one current membership per player before joining analytics so rankings do not
-- contain duplicate player rows.

create or replace function public.get_top_players(
  p_season_id bigint,
  p_team_id bigint default null,
  p_position text default null,
  p_limit integer default 50
)
returns table (
  id bigint,
  name text,
  profilbild_url text,
  "position" text,
  team_image_url text,
  marktwert bigint,
  total_punkte bigint
)
language sql
stable
security invoker
set search_path = public
as $$
  with membership as (
    select distinct on (sp.player_id)
      sp.player_id,
      sp.team_id
    from public.season_players sp
    where sp.season_id = p_season_id
    order by sp.player_id, sp.is_active desc nulls last, sp.team_id
  )
  select
    s.id::bigint,
    s.name::text,
    s.profilbild_url::text,
    s.position::text,
    t.image_url::text as team_image_url,
    sa.marktwert::bigint,
    coalesce(
      case
        when jsonb_typeof(sa.gesamtstatistiken) = 'object'
          and (sa.gesamtstatistiken ->> 'gesamtpunkte') ~ '^-?[0-9]+([.][0-9]+)?$'
        then round((sa.gesamtstatistiken ->> 'gesamtpunkte')::numeric)::bigint
        else 0
      end,
      0
    ) as total_punkte
  from membership m
  join public.spieler s
    on s.id = m.player_id
  join public.team t
    on t.id = m.team_id
  left join public.spieler_analytics sa
    on sa.spieler_id = m.player_id
   and sa.season_id = p_season_id
  where (p_team_id is null or m.team_id = p_team_id)
    and (
      p_position is null
      or btrim(p_position) = ''
      or lower(coalesce(s.position::text, '')) like '%' || lower(btrim(p_position)) || '%'
    )
    and sa.gesamtstatistiken is not null
  order by total_punkte desc, s.id
  limit greatest(1, least(coalesce(p_limit, 50), 200));
$$;

revoke all on function public.get_top_players(bigint, bigint, text, integer) from public;
revoke all on function public.get_top_players(bigint, bigint, text, integer) from anon;
grant execute on function public.get_top_players(bigint, bigint, text, integer) to authenticated;
