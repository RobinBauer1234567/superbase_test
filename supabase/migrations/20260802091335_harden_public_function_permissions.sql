-- Public functions are exposed as PostgREST RPC endpoints when a client role
-- has EXECUTE. Start from no client access and explicitly allow only the RPCs
-- used by the authenticated Flutter application.
revoke execute on all functions in schema public
from public, anon, authenticated;

-- Do not expose newly created functions automatically. Every future RPC must
-- receive an explicit grant in the migration that introduces it.
alter default privileges in schema public
revoke execute on functions from public, anon, authenticated;

-- Read/update checks used by the authenticated sync flow.
grant execute on function public.check_schedule_update_needed(bigint)
to authenticated;
grant execute on function public.mark_schedule_updated(bigint)
to authenticated;
grant execute on function public.get_pending_updates(bigint)
to authenticated;
grant execute on function public.request_sync_permission()
to authenticated;

-- Sports-data imports currently initiated by an authenticated Flutter client.
-- These remain temporarily available until the sync is moved to a trusted
-- backend worker in a later migration.
grant execute on function public.init_player_from_sofascore(
  bigint,
  bigint,
  text,
  integer,
  text,
  numeric[]
) to authenticated;
grant execute on function public.process_match_lineups(bigint, bigint, jsonb)
to authenticated;

-- User-facing league and transfer operations.
grant execute on function public.create_league_and_add_admin(
  text,
  numeric,
  bigint,
  boolean,
  integer,
  integer,
  numeric
) to authenticated;
grant execute on function public.join_league(bigint)
to authenticated;
grant execute on function public.get_league_ranking(bigint)
to authenticated;
grant execute on function public.buy_player_now(bigint)
to authenticated;
grant execute on function public.list_player_for_sale(bigint, bigint, integer)
to authenticated;
grant execute on function public.quick_sell_player(bigint, bigint)
to authenticated;

-- Rankings and matchday lineups.
grant execute on function public.get_ranking_overall(bigint)
to authenticated;
grant execute on function public.get_ranking_matchday(bigint, integer)
to authenticated;
grant execute on function public.initialize_matchday_snapshot(
  bigint,
  uuid,
  bigint,
  integer
) to authenticated;
grant execute on function public.save_lineup(
  bigint,
  bigint,
  integer,
  text,
  jsonb
) to authenticated;
