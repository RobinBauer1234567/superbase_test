begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'ASSERTION FAILED: %',message; end if; end $$;
grant execute on function pg_temp.assert_true(boolean,text) to authenticated;
insert into auth.users(id,email) values
 ('00000000-0000-0000-0000-000000000001','one@example.test'),
 ('00000000-0000-0000-0000-000000000002','two@example.test');
insert into public.tournaments(id,name) values(17,'Test');
insert into public.season(id,name,tournament_id,is_active) values
 (78229,'Active 1',17,true),(78230,'Active 2',17,true),(99999,'Inactive',17,false);
insert into public.team(id,name) values(81,'Team A'),(124,'Team B'),(85,'Team C'),(90,'Team D');
insert into public.season_teams values(78229,81),(78229,124),(78230,85),(78230,90);
insert into public.spieltag(round,season_id,status) values(1,78229,'final'),(2,78229,'nicht gestartet'),(1,78230,'nicht gestartet');
insert into public.spiel(id,season_id,round,heimteam_id,auswärtsteam_id,datum,status)
 values(14159939,78229,1,124,81,now()-interval '1 day','final'),(200,78230,1,85,90,now(),'nicht gestartet');
do $$ begin
  begin
    insert into public.spiel(id,season_id,round,heimteam_id,auswärtsteam_id,datum,status)
    values(14722090,78229,1,90,124,now(),'final');
    raise exception 'Duplicate fixture accepted';
  exception when unique_violation then null; end;
end $$;
select pg_temp.assert_true((select count(*)=2 from private.match_team_slots where match_id=14159939),'two team slots');
insert into public.spieler(id,name,position) values(892949,'Reported player','ST'),(892950,'Second player','TW');
insert into public.season_players(season_id,player_id,team_id) values(78229,892949,81),(78229,892950,124);
insert into public.spieler_analytics(spieler_id,season_id,marktwert)
 values(892949,78229,2000000),(892950,78229,2000000),(892949,78230,2000000),(892949,99999,2000000)
 on conflict(spieler_id,season_id) do update set marktwert=excluded.marktwert;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select public.create_league_and_add_admin('Empty league',10000000,78229,true,20,0,0);
select public.create_league_and_add_admin('Starter league',10000000,78229,true,20,2,4000000);
reset role;
select pg_temp.assert_true((select count(*)=2 from public.league_players where league_id=(select id from public.leagues where name='Starter league')),'starting players assigned');
select pg_temp.assert_true((select count(*)=2 from public.user_matchday_players where matchday_point_id in
 (select id from public.user_matchday_points where league_id=(select id from public.leagues where name='Starter league'))),'one snapshot row per starter');
set local role authenticated;
do $$ declare lid bigint; begin
 select id into lid from public.leagues where name='Starter league';
 perform public.initialize_matchday_snapshot(lid,auth.uid(),78229,1);
 perform public.initialize_matchday_snapshot(lid,auth.uid(),78229,1);
 begin
  perform public.initialize_matchday_snapshot(lid,'00000000-0000-0000-0000-000000000002',78229,1);
  raise exception 'Foreign snapshot accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.initialize_matchday_snapshot(lid,auth.uid(),78230,1);
  raise exception 'Wrong season accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select public.join_league((select id from public.leagues where name='Empty league'));
do $$ begin
 begin
  insert into public.sync_tasks(task_type) values('FETCH_TEAMS');
  raise exception 'Direct queue insertion accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.sync_tasks(id,task_type,season_id,tournament_id)
 values('10000000-0000-0000-0000-000000000001','UPDATE_MATCH',78229,17);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select pg_temp.assert_true((select count(*)=1 from public.get_next_sync_task(auth.uid())),'user A claims task');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
select pg_temp.assert_true((select count(*)=0 from public.get_next_sync_task(auth.uid())),'user B cannot claim same task');
do $$ begin
 begin
  perform public.complete_sync_task('10000000-0000-0000-0000-000000000001');
  raise exception 'Foreign completion accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.get_next_sync_task('00000000-0000-0000-0000-000000000001');
  raise exception 'Foreign claim accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.sync_tasks set locked_at=now()-interval '11 minutes' where id='10000000-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.assert_true((select count(*)=1 from public.get_next_sync_task(auth.uid())),'expired claim recovered');
select public.fail_sync_task('10000000-0000-0000-0000-000000000001','HTTP 503');
select pg_temp.assert_true((select count(*)=0 from public.get_next_sync_task(auth.uid())),'retry backoff honored');
reset role;
update public.sync_tasks set next_attempt_at=now()-interval '1 minute',attempts=4 where id='10000000-0000-0000-0000-000000000001';
set local role authenticated;
select count(*) from public.get_next_sync_task(auth.uid());
select public.fail_sync_task('10000000-0000-0000-0000-000000000001','HTTP 503');
reset role;
select pg_temp.assert_true((select status='FAILED' from public.sync_tasks where id='10000000-0000-0000-0000-000000000001'),'bounded retries');

-- Exercise the production dependency trigger through all initialization steps.
delete from public.sync_tasks;
insert into public.sync_tasks(task_type,season_id,tournament_id) values('FETCH_TEAMS',78229,17);
set local role authenticated;
do $$ declare task public.sync_tasks; n integer:=0; begin
 loop
  select * into task from public.get_next_sync_task(auth.uid());
  exit when task.id is null;
  n:=n+1;
  if n>10 then raise exception 'Dependency loop'; end if;
  perform public.complete_sync_task(task.id);
 end loop;
 perform pg_temp.assert_true(n=5,'teams, two squads, rounds and matches');
end $$;
reset role;
select pg_temp.assert_true((select is_initialized from public.season where id=78229),'initialization complete');

-- Import permissions: both allowed work and forbidden writes are exercised.
set local role authenticated;
do $$ begin
 begin
  insert into public.spieltag(round,season_id,status) values(3,78229,'nicht gestartet');
  raise exception 'Import without a task accepted';
 exception when insufficient_privilege then null; end;
 begin
  perform public.init_player_from_sofascore(892949,78229,'4-4-2',1,'F',array[7.0]);
  raise exception 'Player RPC without a task accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.sync_tasks(id,task_type,season_id,tournament_id,status,locked_at,locked_by)
 values('10000000-0000-0000-0000-000000000021','FETCH_TEAM_SQUAD',78229,17,'PROCESSING',now(),'00000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.init_player_from_sofascore(892949,78229,'4-4-2',1,'F',array[7.0]);
update public.season_players set is_active=true where player_id=892949 and season_id=78229;
reset role;
insert into public.sync_tasks(id,task_type,season_id,tournament_id,match_id,status,locked_at,locked_by)
 values('10000000-0000-0000-0000-000000000022','UPDATE_MATCH',78229,17,14159939,'PROCESSING',now(),'00000000-0000-0000-0000-000000000002');
set local role authenticated;
select public.process_match_lineups(14159939,78229,'{"home":{"players":[]},"away":{"players":[]}}');
-- Kickoff must initialize/lock the other manager's missing snapshot internally.
reset role;
delete from public.user_matchday_points where league_id=(select id from public.leagues where name='Starter league');
set local role authenticated;
update public.spiel set status='nicht gestartet' where id=14159939;
update public.spiel set status='läuft' where id=14159939;
update public.spiel set status='final' where id=14159939;
select pg_temp.assert_true((select is_locked from public.user_matchday_points where league_id=(select id from public.leagues where name='Starter league')),'kickoff locks another manager lineup through trusted trigger');
do $$ begin
 begin
  perform public.process_match_lineups(200,78230,'{}');
  raise exception 'Unrelated match import accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;

-- Existing backend role RPC access remains usable.
set local role service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','service_role',true);
select public.renew_sync_task('10000000-0000-0000-0000-000000000022');
select public.complete_sync_task('10000000-0000-0000-0000-000000000022');
reset role;
select set_config('request.jwt.claim.role','',true);

-- Actual calculation functions run here, not replacements.
select set_config('request.jwt.claim.sub','',true);
select public.daily_marktwert_update();
select pg_temp.assert_true((select count(*)=2 from private.market_value_runs where status='succeeded'),'both active seasons updated');
select pg_temp.assert_true((select marktwert<>2000000 from public.spieler_analytics where spieler_id=892949 and season_id=78229),'active value changed');
select pg_temp.assert_true((select marktwert=2000000 from public.spieler_analytics where spieler_id=892949 and season_id=99999),'inactive season unchanged');
create temporary table previous_values as select * from public.spieler_analytics;
select public.daily_marktwert_update();
select pg_temp.assert_true(not exists(select 1 from public.spieler_analytics a join previous_values b using(spieler_id,season_id) where a.marktwert is distinct from b.marktwert),'daily retry is idempotent');

-- Force a per-season failure and verify the next season still commits.
delete from private.market_value_runs;
create function pg_temp.fail_one_season() returns trigger language plpgsql as $$
begin if new.season_id=78229 then raise exception 'Injected test failure'; end if; return new; end $$;
create trigger fail_one_season before update on public.spieler_analytics for each row execute function pg_temp.fail_one_season();
select public.daily_marktwert_update();
select pg_temp.assert_true((select status='failed' from private.market_value_runs where season_id=78229),'failure logged');
select pg_temp.assert_true((select status='succeeded' from private.market_value_runs where season_id=78230),'other season succeeds');
rollback;
