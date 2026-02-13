-- Fix for league creation failing with:
-- column "purchase_price" of relation "league_players" does not exist (42703)
--
-- Run this in Supabase SQL Editor.

begin;

-- 1) Ensure the expected column exists.
alter table public.league_players
  add column if not exists purchase_price integer;

-- 2) Backfill existing rows (optional but recommended for consistent queries).
update public.league_players
set purchase_price = 0
where purchase_price is null;

-- 3) Enforce a sane default for new rows.
alter table public.league_players
  alter column purchase_price set default 0;

commit;

-- Optional diagnostic: check if your RPC references this column.
-- select pg_get_functiondef(p.oid)
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public' and p.proname in ('create_league_and_add_admin', 'join_league');
