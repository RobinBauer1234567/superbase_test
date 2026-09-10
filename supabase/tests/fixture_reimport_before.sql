insert into auth.users(id,email) values('00000000-0000-0000-0000-000000000001','test@example.test');
insert into public.tournaments(id,name) values(17,'Test');
insert into public.season(id,name,tournament_id,is_active) values(78229,'Test',17,false);
insert into public.team(id,name) values(81,'A'),(124,'B'),(85,'C'),(90,'D');
insert into public.spieltag(round,season_id,status) values(1,78229,'final'),(2,78229,'final');
insert into public.spiel(id,season_id,round,heimteam_id,auswärtsteam_id,datum,status)
values(14159939,78229,1,124,81,now(),'final'),(14722090,78229,1,81,90,now(),'final'),
      (200,78229,2,124,85,now(),'final');
insert into public.spieler(id,name,position) values(892949,'Reported player','ST');
insert into public.season_players(season_id,player_id,team_id) values(78229,892949,81);
insert into public.matchrating(id,spieler_id,spiel_id,punkte,statistics)
values(1,892949,14159939,20,'{}'),(2,892949,14722090,30,'{}'),(3,892949,200,7,'{}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select public.create_league_and_add_admin('Repair league',10000000,78229,true,20,0,0);
update public.user_matchday_points set total_points=20,is_locked=true where round=1;
insert into public.user_matchday_players(matchday_point_id,player_id,formation_index,points,spiel_id,matchrating_id,is_locked)
select id,892949,0,20,14159939,1,true from public.user_matchday_points where round=1;
insert into public.sync_tasks(task_type,season_id,tournament_id,match_id,status,locked_at,locked_by)
values('UPDATE_MATCH',78229,17,14159939,'PROCESSING',now(),'00000000-0000-0000-0000-000000000001');
