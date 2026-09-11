BEGIN;
CREATE FUNCTION pg_temp.assert(ok boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',message; END IF; END $$;
SELECT pg_temp.assert((SELECT tournament_id=17 AND season_id=101 FROM leagues WHERE id=1),'redundancy repaired, season retained');
SELECT generate_season_check_tasks();
SELECT generate_season_check_tasks();
SELECT pg_temp.assert((SELECT count(*)=3 FROM sync_tasks WHERE task_type='CHECK_SEASONS'),'daily queue idempotent and covers inactive tournaments');
-- Real client privilege boundary, including the exact ON CONFLICT used by discovery/scout.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000001';
INSERT INTO season(id,name,tournament_id,is_active) VALUES(101,'25/26',17,false) ON CONFLICT(id) DO NOTHING;
INSERT INTO season(id,name,tournament_id,is_active) VALUES(102,'26/27',17,false),(202,'26/27',8,false),(302,'26/27',25,false) ON CONFLICT(id) DO NOTHING;
DO $$ BEGIN
  BEGIN UPDATE season SET is_active=false WHERE id=101; RAISE EXCEPTION 'permission guard missing';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM activate_season(102); RAISE EXCEPTION 'privileged RPC exposed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO season_activation_requests(season_id,requested_by) VALUES(302,'00000000-0000-4000-8000-000000000002');
    RAISE EXCEPTION 'forged request allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.assert((SELECT is_active FROM season WHERE id=101),'scout preserves active flag');
SELECT process_season_lifecycle();
SELECT pg_temp.assert((SELECT is_active FROM season WHERE id=101),'incomplete discovery cannot activate');
-- Only successfully completed checks make auto-advancement eligible.
UPDATE sync_tasks SET status='COMPLETED',updated_at=now() WHERE task_type='CHECK_SEASONS';
SELECT process_season_lifecycle();
SELECT process_season_lifecycle();
SELECT pg_temp.assert((SELECT is_active AND NOT is_initialized FROM season WHERE id=102),'new season active and initializing');
SELECT pg_temp.assert((SELECT NOT is_active AND archived_at IS NOT NULL AND is_initialized FROM season WHERE id=101),'old season archived and initialized retained');
SELECT pg_temp.assert((SELECT count(*)=1 FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_TEAMS'),'initialization exactly once');
SELECT pg_temp.assert((SELECT count(*)=0 FROM season WHERE tournament_id=25 AND is_active),'inactive tournament does not automatically opt in');
SELECT pg_temp.assert((SELECT season_id=101 FROM leagues WHERE id=1),'fantasy league retains historical season');
SELECT pg_temp.assert((SELECT count(*)=1 FROM season_teams WHERE season_id=101)
 AND (SELECT count(*)=1 FROM season_players WHERE season_id=101)
 AND (SELECT count(*)=1 FROM spiel WHERE season_id=101)
 AND (SELECT count(*)=1 FROM spieltag WHERE season_id=101)
 AND (SELECT marktwert=1000000 FROM spieler_analytics WHERE season_id=101),'all historical data preserved');
DO $$ BEGIN
  BEGIN UPDATE season SET is_active=true WHERE id=101; RAISE EXCEPTION 'unique guard missing';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN UPDATE leagues SET season_id=102 WHERE id=1; RAISE EXCEPTION 'league moved';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM='league moved' THEN RAISE; END IF; END;
  BEGIN PERFORM activate_season(101); RAISE EXCEPTION 'rollback allowed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM='rollback allowed' THEN RAISE; END IF; END;
  BEGIN INSERT INTO leagues(id,name,admin_id,season_id) VALUES(2,'Bad','00000000-0000-4000-8000-000000000001',101);
    RAISE EXCEPTION 'historical creation allowed';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM='historical creation allowed' THEN RAISE; END IF; END;
END $$;
-- Existing secure worker RPC completion and the full fan-out/fan-in chain.
INSERT INTO season_teams VALUES(102,11),(102,12);
INSERT INTO season_players(season_id,player_id,team_id) VALUES(102,501,11),(102,502,12);
UPDATE sync_tasks SET status='PROCESSING',locked_by='00000000-0000-4000-8000-000000000001'
WHERE season_id=102 AND task_type='FETCH_TEAMS';
SET LOCAL ROLE authenticated;
SELECT complete_sync_task((SELECT id FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_TEAMS'));
RESET ROLE;
SELECT pg_temp.assert((SELECT count(*)=2 FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_TEAM_SQUAD'),'squad fan-out');
SELECT pg_temp.assert((SELECT status='WAITING_FOR_SQUADS' FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_ROUNDS'),'rounds wait');
UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_TEAM_SQUAD' AND team_id=11;
SELECT pg_temp.assert((SELECT status='WAITING_FOR_SQUADS' FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_ROUNDS'),'one squad cannot unlock rounds');
UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_TEAM_SQUAD' AND team_id=12;
SELECT pg_temp.assert((SELECT status='PENDING' FROM sync_tasks WHERE season_id=102 AND task_type='FETCH_ROUNDS'),'all squads unlock rounds');
INSERT INTO spieltag(round,status,season_id) VALUES(1,'nicht gestartet',102);
UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_ROUNDS';
INSERT INTO spiel(id,datum,season_id,round) VALUES(702,'2026-10-01',102,1);
UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_MATCHES';
SELECT pg_temp.assert((SELECT is_initialized FROM season WHERE id=102),'matches finish initialization');
-- Replayed completion cannot create duplicates even if an operator requeues a stage.
UPDATE sync_tasks SET status='PROCESSING' WHERE season_id=102 AND task_type='FETCH_TEAMS';
UPDATE sync_tasks SET status='COMPLETED' WHERE season_id=102 AND task_type='FETCH_TEAMS';
SELECT pg_temp.assert((SELECT count(*)=5 FROM sync_tasks WHERE season_id=102),'replayed completion idempotent');
INSERT INTO leagues(id,name,admin_id,season_id) VALUES(2,'New','00000000-0000-4000-8000-000000000001',102);
SELECT pg_temp.assert((SELECT tournament_id=17 FROM leagues WHERE id=2),'new league tournament derived');
SET LOCAL ROLE authenticated;
INSERT INTO season_activation_requests(season_id,requested_by) VALUES(302,'00000000-0000-4000-8000-000000000001');
RESET ROLE;
SELECT process_season_lifecycle();
SELECT pg_temp.assert((SELECT is_active FROM season WHERE id=302),'explicit initial activation request');
SELECT pg_temp.assert((SELECT processed_at IS NOT NULL AND error_message IS NULL FROM season_activation_requests WHERE season_id=302),'request result recorded');
SELECT pg_temp.assert((SELECT count(*)=2 FROM cron.job),'separate cron schedules registered');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND prosecdef AND proname IN
('activate_season','process_season_lifecycle','generate_season_check_tasks','handle_season_activation','check_and_unlock_dependencies','guard_league_season')),'no new security definer');
ROLLBACK;
