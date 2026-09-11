-- Legacy state before migration: active season, full historical rows, redundant league mismatch.
INSERT INTO auth.users VALUES ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
INSERT INTO tournaments(id,name) VALUES (17,'Test League'),(8,'Other League'),(25,'Not opted in');
INSERT INTO season(id,name,tournament_id,is_active,is_initialized) VALUES
(101,'25/26',17,true,true),(201,'25/26',8,true,true),(301,'25/26',25,false,false);
INSERT INTO leagues(id,name,admin_id,season_id,tournament_id) VALUES
(1,'Historical fantasy','00000000-0000-4000-8000-000000000001',101,8);
INSERT INTO season_teams VALUES(101,11);
INSERT INTO season_players(season_id,player_id,team_id) VALUES(101,501,11);
INSERT INTO spiel(id,datum,season_id,round) VALUES(701,'2025-10-01',101,1);
INSERT INTO spieltag(round,status,season_id) VALUES(1,'final',101);
INSERT INTO spieler_analytics(spieler_id,season_id,marktwert) VALUES(501,101,1000000);
CREATE FUNCTION public.check_and_unlock_dependencies() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
CREATE TRIGGER on_sync_task_status_change AFTER UPDATE OF status ON public.sync_tasks
FOR EACH ROW EXECUTE FUNCTION public.check_and_unlock_dependencies();
