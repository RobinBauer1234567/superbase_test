-- Read-only. Every result set must be reviewed before deploying the repair.
-- A fixture ID's presence/absence of ratings is not proof of source validity.
with participants as (
 select season_id,round,heimteam_id team_id,id from public.spiel
 union all select season_id,round,auswärtsteam_id,id from public.spiel
)
select season_id,round,team_id,array_agg(id order by id) match_ids
from participants group by season_id,round,team_id having count(*)>1
order by season_id,round,team_id;

select s.id,s.season_id,s.round from public.spiel s left join public.spieltag t
 on t.season_id=s.season_id and t.round=s.round
where t.season_id is null or s.heimteam_id is null or s.auswärtsteam_id is null
 or s.heimteam_id=s.auswärtsteam_id;

select season_id,player_id,array_agg(team_id) active_teams from public.season_players
where is_active group by season_id,player_id having count(*)>1;

select spiel_id,spieler_id,array_agg(id) rating_ids from public.matchrating
group by spiel_id,spieler_id having count(*)>1;

select j.jobname,j.active,j.schedule,j.username,r.status,r.return_message,r.start_time
from cron.job j left join lateral (
 select status,return_message,start_time from cron.job_run_details
 where jobid=j.jobid order by start_time desc limit 1
) r on true where j.jobname in ('daily-marktwert-update','generate-routine-tasks-job');
