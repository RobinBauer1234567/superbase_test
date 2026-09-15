-- Performance RPC for the Top-Team screen.
-- Filtering, sorting and limiting are performed in PostgreSQL so the Flutter
-- client does not need to download the entire season player/analytics dataset.

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
  from public.season_players sp
  join public.spieler s
    on s.id = sp.player_id
  join public.team t
    on t.id = sp.team_id
  left join public.spieler_analytics sa
    on sa.spieler_id = sp.player_id
   and sa.season_id = sp.season_id
  where sp.season_id = p_season_id
    and (p_team_id is null or sp.team_id = p_team_id)
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

-- Supporting indexes for the most common season-scoped reads. These are safe to
-- create repeatedly and are intentionally narrow to keep write overhead modest.
create index if not exists idx_spiel_season_datum
  on public.spiel (season_id, datum);

create index if not exists idx_spieltag_season_round
  on public.spieltag (season_id, round);

create index if not exists idx_season_players_season_player
  on public.season_players (season_id, player_id);

create index if not exists idx_season_players_season_team
  on public.season_players (season_id, team_id);

create index if not exists idx_spieler_analytics_season_player
  on public.spieler_analytics (season_id, spieler_id);