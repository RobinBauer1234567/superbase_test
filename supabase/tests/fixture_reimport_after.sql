begin;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%',msg; end if; end $$;
select pg_temp.check((select count(*)=2 from private.fixture_reimports),'archive all conflicting games');
select pg_temp.check((select count(*)=2 from public.sync_tasks where status='PENDING' and task_type='UPDATE_MATCH'),'one replacement task per game');
select pg_temp.check((select count(*)=1 from public.sync_tasks where status='FAILED'),'old reservation cancelled');
select pg_temp.check((select count(*)=1 and min(id)=200 from public.spiel),'only conflicting games deleted');
select pg_temp.check((select count(*)=1 and min(id)=3 from public.matchrating),'conflicting ratings deleted');
select pg_temp.check((select anzahl_spiele=1 and gesamtstatistiken->>'gesamtpunkte'='7' from public.spieler_analytics where spieler_id=892949 and season_id=78229),'deleted ratings excluded from aggregates');
select pg_temp.check((select spiel_id is null and matchrating_id is null and points=0 and formation_index=0 and is_locked from public.user_matchday_players),'lineup retained and points reset');
select pg_temp.check((select total_points=0 and is_locked from public.user_matchday_points where round=1),'snapshot total reset and lock retained');
select pg_temp.check((select matchday_start is null and matchday_end is null from public.spieltag where round=1),'time window cleared');
select pg_temp.check(not has_table_privilege('authenticated','private.fixture_reimports','SELECT'),'archive private');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
select public.get_next_sync_task('00000000-0000-0000-0000-000000000001');
reset role;
select pg_temp.check((select count(*)=1 from public.sync_tasks where status='PROCESSING'),'inactive season repair can be claimed');
-- Reimport the first game into the confirmed original round.
insert into public.spiel(id,season_id,round,heimteam_id,auswärtsteam_id,datum,status)
values(14159939,78229,1,124,81,now(),'final');
insert into public.matchrating(id,spieler_id,spiel_id,punkte,statistics) values(4,892949,14159939,12,'{}');
select pg_temp.check((select spiel_id=14159939 and matchrating_id=4 and points=12 and formation_index=0 and is_locked from public.user_matchday_players),'snapshot reconnected to fresh rating');
select pg_temp.check((select total_points=12 from public.user_matchday_points where round=1),'fresh total restored');
-- The second source may still conflict: it must fail, never silently overwrite.
do $$ begin
  begin
    insert into public.spiel(id,season_id,round,heimteam_id,auswärtsteam_id,datum,status)
    values(14722090,78229,1,81,90,now(),'final');
    raise exception 'conflicting reimport accepted';
  exception when unique_violation then null; end;
end $$;
rollback;
