-- User-authorized repair: remove every fixture participating in a team/round
-- conflict and queue its complete reimport. This migration has not been deployed.
create schema if not exists private;
revoke all on schema private from public,anon;
lock table public.spiel, public.matchrating, public.user_matchday_players,
  public.user_matchday_points, public.sync_tasks in share row exclusive mode;

-- Retain a private recovery record, never expose it through the client API.
create table private.fixture_reimports (
  match_id integer primary key,
  task_id uuid not null unique,
  fixture jsonb not null,
  ratings jsonb not null,
  snapshots jsonb not null,
  removed_at timestamptz not null default now()
);
alter table private.fixture_reimports enable row level security;
revoke all on private.fixture_reimports from public,anon,authenticated;
grant select on private.fixture_reimports to service_role;

create temporary table conflicting_fixture_ids on commit drop as
with appearances as (
  select id,season_id,round,heimteam_id as team_id from public.spiel
  union all select id,season_id,round,auswärtsteam_id from public.spiel
), conflicts as (
  select season_id,round,team_id from appearances
  group by season_id,round,team_id having count(*) > 1
)
select distinct a.id from appearances a join conflicts c
  using(season_id,round,team_id);

insert into private.fixture_reimports(match_id,task_id,fixture,ratings,snapshots)
select s.id,gen_random_uuid(),to_jsonb(s),
  coalesce((select jsonb_agg(to_jsonb(m)) from public.matchrating m where m.spiel_id=s.id),'[]'),
  coalesce((select jsonb_agg(to_jsonb(u)) from public.user_matchday_players u
    where u.spiel_id=s.id or u.matchrating_id in
      (select id from public.matchrating where spiel_id=s.id)),'[]')
from public.spiel s join conflicting_fixture_ids c on c.id=s.id;

-- Supersede old reservations so an old worker cannot complete the new task.
update public.sync_tasks set status='FAILED',locked_by=null,locked_at=null,
  error_message='Superseded by fixture conflict reimport',updated_at=now()
where match_id in (select id from conflicting_fixture_ids)
  and status not in ('COMPLETED','FAILED');
insert into public.sync_tasks(id,task_type,season_id,tournament_id,round_id,match_id,priority,status)
select r.task_id,'UPDATE_MATCH',s.season_id,se.tournament_id,s.round,s.id,0,'PENDING'
from private.fixture_reimports r join public.spiel s on s.id=r.match_id
join public.season se on se.id=s.season_id;

-- Preserve ownership, lineup positions and locks; invalidate only imported data.
update public.user_matchday_players u set spiel_id=null,matchrating_id=null,points=0
where u.spiel_id in(select id from conflicting_fixture_ids)
   or u.matchrating_id in(select id from public.matchrating where spiel_id in(select id from conflicting_fixture_ids));
update public.user_matchday_points p set total_points=(
  select coalesce(sum(u.points),0) from public.user_matchday_players u
  where u.matchday_point_id=p.id and u.formation_index<=10
) where p.id in (
  select (j->>'matchday_point_id')::bigint from private.fixture_reimports r,
  lateral jsonb_array_elements(r.snapshots) j
);
CREATE OR REPLACE FUNCTION public.update_gesamtstatistiken()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  player_id bigint;
  _season_id bigint;
  _stats_sum jsonb := '{}'::jsonb;
  aggregated_stats jsonb;
  total_punkte numeric := 0;
  total_matches bigint := 0;
begin
  player_id := case when TG_OP = 'DELETE' then OLD.spieler_id else NEW.spieler_id end;
  select sp.season_id into _season_id from public.spiel sp
  where sp.id = case when TG_OP = 'DELETE' then OLD.spiel_id else NEW.spiel_id end;

  if player_id is null or _season_id is null then return null; end if;

  select coalesce(jsonb_object_agg(key, val_sum), '{}'::jsonb)
  into _stats_sum
  from (
    select e.key,
      sum(
        case jsonb_typeof(e.val)
          when 'number' then (e.val)::text::numeric
          when 'object' then coalesce(
            nullif(regexp_replace(e.val->>'original','[^0-9\.-]+','','g'),'')::numeric,
            nullif(regexp_replace(e.val->>'alternative','[^0-9\.-]+','','g'),'')::numeric,
            nullif(regexp_replace(e.val->>'value','[^0-9\.-]+','','g'),'')::numeric,
            0
          )
          when 'string' then coalesce(nullif(regexp_replace(e.val::text,'[^0-9\.-]+','','g'), '')::numeric, 0)
          else 0
        end
      ) as val_sum
    from matchrating mr
    join spiel sp on sp.id = mr.spiel_id
    cross join lateral jsonb_each(coalesce(mr.statistics, '{}'::jsonb)) as e(key, val)
    where mr.spieler_id = player_id and sp.season_id = _season_id
    group by e.key
  ) sub;

  select coalesce(sum(mr.punkte)::numeric, 0), coalesce(count(*)::bigint, 0)
  into total_punkte, total_matches
  from matchrating mr
  join spiel sp on sp.id = mr.spiel_id
  where mr.spieler_id = player_id and sp.season_id = _season_id;

  if total_matches = 0 then
    update public.spieler_analytics
    set gesamtstatistiken = '{}'::jsonb, anzahl_spiele = 0
    where spieler_id = player_id and season_id = _season_id;
    return null;
  end if;

  aggregated_stats := coalesce(_stats_sum, '{}'::jsonb)
    || jsonb_build_object('gesamtpunkte', total_punkte);

  -- HIER IST DER FIX: marktwert & calculated_marktwert (1000000) wurden zum INSERT hinzugefügt!
  INSERT INTO public.spieler_analytics (spieler_id, season_id, gesamtstatistiken, anzahl_spiele, marktwert, calculated_marktwert)
  VALUES (player_id, _season_id, aggregated_stats, total_matches, 1000000, 1000000)
  ON CONFLICT (spieler_id, season_id) 
  DO UPDATE SET 
    gesamtstatistiken = aggregated_stats,
    anzahl_spiele = total_matches;

  return null;
end;
$function$;

-- The corrected aggregate trigger now also recomputes statistics on DELETE.
delete from public.matchrating where spiel_id in(select id from conflicting_fixture_ids);
delete from public.api_debug_dump where spiel_id in(select id from conflicting_fixture_ids);
delete from public.spiel where id in(select id from conflicting_fixture_ids);
update public.spieltag d set
  matchday_start=(select min(s.datum)-interval '48 hours' from public.spiel s where s.season_id=d.season_id and s.round=d.round),
  matchday_end=(select max(s.datum)+interval '24 hours' from public.spiel s where s.season_id=d.season_id and s.round=d.round),
  status='nicht gestartet'
where (d.season_id,d.round) in (
  select (fixture->>'season_id')::bigint,(fixture->>'round')::int from private.fixture_reimports
);

-- Reconnect preserved snapshots only when the refreshed source still belongs to
-- the same season/round. The normal points trigger runs after this trigger.
create function private.restore_reimport_snapshot() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  update public.user_matchday_players u set spiel_id=new.spiel_id
  from public.user_matchday_points p,public.spiel s,private.fixture_reimports r
  where r.match_id=new.spiel_id and s.id=new.spiel_id
    and p.id=u.matchday_point_id and p.season_id=s.season_id and p.round=s.round
    and u.player_id=new.spieler_id and u.spiel_id is null
    and exists(select 1 from jsonb_array_elements(r.snapshots) j where (j->>'id')::bigint=u.id);
  return new;
end $$;
revoke all on function private.restore_reimport_snapshot() from public,anon,authenticated;
create trigger a_restore_reimport_snapshot after insert or update of punkte on public.matchrating
for each row execute function private.restore_reimport_snapshot();

create table private.match_team_slots (
  season_id bigint not null,
  round integer not null,
  team_id integer not null references public.team(id),
  match_id integer not null references public.spiel(id) on delete cascade,
  primary key(season_id,round,team_id),
  unique(match_id,team_id),
  foreign key(round,season_id) references public.spieltag(round,season_id)
);
-- All remaining fixtures must satisfy the invariant; nothing is silently skipped.
insert into private.match_team_slots(season_id,round,team_id,match_id)
select season_id,round,heimteam_id,id from public.spiel
union all select season_id,round,auswärtsteam_id,id from public.spiel;

create function private.sync_match_team_slots()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from private.match_team_slots where match_id=new.id;
  insert into private.match_team_slots(season_id,round,team_id,match_id)
  values(new.season_id,new.round,new.heimteam_id,new.id),
        (new.season_id,new.round,new.auswärtsteam_id,new.id);
  return new;
end $$;
revoke all on private.match_team_slots from public,anon,authenticated;
revoke all on function private.sync_match_team_slots() from public,anon,authenticated;
create trigger enforce_match_team_slots after insert or update of id,season_id,round,heimteam_id,auswärtsteam_id
on public.spiel for each row execute function private.sync_match_team_slots();

create function private.initialize_snapshot_internal(p_league_id bigint,p_user_id uuid,p_season_id bigint,p_round integer)
returns void language plpgsql security definer set search_path = '' as $$
declare v_header bigint; v_previous bigint; v_formation text; v_player record;
  v_games integer[]; v_game integer; v_rating bigint; v_points numeric; v_status text; v_index integer;
begin
  -- Serialize the full operation, including callers creating the first header.
  perform 1 from public.league_members m join public.leagues l on l.id=m.league_id
    where m.league_id=p_league_id and m.user_id=p_user_id and l.season_id=p_season_id
    for update of m;
  if not found then raise exception 'League membership or season mismatch' using errcode='42501'; end if;
  if not exists(select 1 from public.spieltag where season_id=p_season_id and round=p_round) then
    raise exception 'Unknown matchday for this season' using errcode='23503';
  end if;
  if exists(select 1 from public.user_matchday_points where league_id=p_league_id
    and user_id=p_user_id and season_id=p_season_id and round=p_round) then return; end if;
  select id,formation into v_previous,v_formation from public.user_matchday_points
    where league_id=p_league_id and user_id=p_user_id and season_id=p_season_id and round<p_round
    order by round desc limit 1;
  insert into public.user_matchday_points(user_id,league_id,season_id,round,formation,total_points,is_locked)
    values(p_user_id,p_league_id,p_season_id,p_round,coalesce(v_formation,'4-4-2'),0,false)
    returning id into v_header;
  for v_player in select player_id from public.league_players
      where league_id=p_league_id and user_id=p_user_id loop
    -- A recorded appearance is authoritative for historical team transfers.
    select array_agg(distinct s.id) into v_games from public.matchrating mr
      join public.spiel s on s.id=mr.spiel_id
      where mr.spieler_id=v_player.player_id and s.season_id=p_season_id and s.round=p_round;
    if coalesce(cardinality(v_games),0)=0 then
      select array_agg(distinct s.id) into v_games from public.season_players sp
        join public.spiel s on s.season_id=sp.season_id and s.round=p_round
          and (s.heimteam_id=sp.team_id or s.auswärtsteam_id=sp.team_id)
        where sp.player_id=v_player.player_id and sp.season_id=p_season_id and sp.is_active;
    end if;
    if cardinality(v_games)>1 then
      raise exception 'Ambiguous fixtures for player %, season %, round %',v_player.player_id,p_season_id,p_round
        using errcode='23514';
    end if;
    v_game:=v_games[1];
    select status into v_status from public.spiel where id=v_game;
    select id,punkte into v_rating,v_points from public.matchrating
      where spiel_id=v_game and spieler_id=v_player.player_id;
    -- Detect bad rating data instead of selecting one of several records.
    if (select count(*) from public.matchrating where spiel_id=v_game and spieler_id=v_player.player_id)>1 then
      raise exception 'Duplicate match ratings for player %',v_player.player_id using errcode='23514';
    end if;
    select formation_index into v_index from public.user_matchday_players
      where matchday_point_id=v_previous and player_id=v_player.player_id;
    insert into public.user_matchday_players(matchday_point_id,player_id,formation_index,is_locked,spiel_id,matchrating_id,points)
      values(v_header,v_player.player_id,coalesce(v_index,99),
        coalesce(v_status not in ('nicht gestartet','notstarted'),false),v_game,v_rating,coalesce(v_points,0));
  end loop;
  update public.user_matchday_points set total_points=(select coalesce(sum(points),0)
    from public.user_matchday_players where matchday_point_id=v_header and formation_index<=10),
    is_locked=exists(select 1 from public.user_matchday_players where matchday_point_id=v_header and is_locked)
    where id=v_header;
end $$;
revoke all on function private.initialize_snapshot_internal(bigint,uuid,bigint,integer) from public,anon,authenticated;
grant execute on function private.initialize_snapshot_internal(bigint,uuid,bigint,integer) to service_role;
create function private.initialize_matchday_snapshot(p_league_id bigint,p_user_id uuid,p_season_id bigint,p_round integer)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role'
     and (auth.uid() is null or auth.uid() is distinct from p_user_id) then
    raise exception 'Cannot initialize another user lineup' using errcode='42501';
  end if;
  perform private.initialize_snapshot_internal(p_league_id,p_user_id,p_season_id,p_round);
end $$;
create or replace function public.initialize_matchday_snapshot(p_league_id bigint,p_user_id uuid,p_season_id bigint,p_round integer)
returns void language sql security invoker set search_path = '' as $$
  select private.initialize_matchday_snapshot(p_league_id,p_user_id,p_season_id,p_round)
$$;
grant usage on schema private to authenticated,service_role;
revoke all on function private.initialize_matchday_snapshot(bigint,uuid,bigint,integer) from public,anon;
grant execute on function private.initialize_matchday_snapshot(bigint,uuid,bigint,integer) to authenticated,service_role;
revoke all on function public.initialize_matchday_snapshot(bigint,uuid,bigint,integer) from public,anon;
grant execute on function public.initialize_matchday_snapshot(bigint,uuid,bigint,integer) to authenticated,service_role;

-- Historical team memberships must not multiply the starting-player pool.
CREATE OR REPLACE FUNCTION public.assign_random_team(p_league_id bigint, p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_num_players int;
    v_target_val numeric;
    v_min_val numeric;
    v_max_val numeric;
    v_player_ids bigint[];
    v_total_val numeric;
    v_season_id int;
    v_retry int := 0;
BEGIN
    SELECT num_starting_players, starting_team_value, season_id
    INTO v_num_players, v_target_val, v_season_id
    FROM leagues WHERE id = p_league_id;

    IF v_num_players <= 0 THEN RETURN; END IF;

    v_min_val := GREATEST(0, v_target_val - 1000000);
    v_max_val := v_target_val + 1000000;

    LOOP
        EXIT WHEN v_retry >= 50;
        v_retry := v_retry + 1;

        SELECT ARRAY_agg(pid), SUM(mkw)
        INTO v_player_ids, v_total_val
        FROM (
            SELECT s.id as pid, COALESCE(sa.marktwert, 0) as mkw
            FROM public.spieler s
            -- NEU: Saison-Filter im JOIN
            JOIN public.spieler_analytics sa ON sa.spieler_id = s.id AND sa.season_id = v_season_id
            WHERE EXISTS (SELECT 1 FROM public.season_players sp
              WHERE sp.player_id = s.id AND sp.season_id = v_season_id AND sp.is_active)
            AND sa.marktwert > 0
            AND s.id NOT IN (
                SELECT player_id FROM public.league_players WHERE league_id = p_league_id
            )
            ORDER BY random()
            LIMIT v_num_players
        ) sub;

        IF array_length(v_player_ids, 1) = v_num_players
           AND v_total_val >= v_min_val
           AND v_total_val <= v_max_val THEN
            EXIT;
        END IF;
    END LOOP;

    IF v_player_ids IS NOT NULL THEN
        INSERT INTO public.league_players (league_id, user_id, player_id, purchase_price)
        SELECT p_league_id, p_user_id, unnest(v_player_ids), 0
        ON CONFLICT (league_id, player_id) DO NOTHING;
    END IF;
END;
$function$;


-- Trusted kickoff trigger initializes all affected managers, not just the worker.
CREATE OR REPLACE FUNCTION public.lock_matchday_players()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    r RECORD;
    v_point_id bigint;
BEGIN
    -- NEUE LOGIK: Lock greift, sobald das Spiel startet ODER direkt beendet/final ist
    IF NEW.status IN ('läuft', 'beendet', 'final') AND OLD.status NOT IN ('läuft', 'beendet', 'final') THEN

        -- Finde alle Ligen und User, die Spieler aus diesem Spiel besitzen
        FOR r IN (
            SELECT
                lp.user_id,
                lp.league_id,
                lp.player_id
            FROM public.league_players lp
            JOIN public.leagues l ON l.id=lp.league_id AND l.season_id=NEW.season_id
            JOIN public.season_players sp
               -- FIX: sp.is_active = true hinzugefügt
               ON lp.player_id = sp.player_id
              AND sp.season_id = NEW.season_id
              AND sp.is_active = true
            WHERE sp.team_id IN (NEW.heimteam_id, NEW.auswärtsteam_id) AND lp.user_id IS NOT NULL
            ORDER BY lp.league_id,lp.user_id,lp.player_id
        )
        LOOP
            -- 1. Prüfen, ob der User für diesen Spieltag schon einen Points-Eintrag hat
            SELECT id INTO v_point_id
            FROM public.user_matchday_points
            WHERE user_id = r.user_id
              AND league_id = r.league_id
              AND season_id = NEW.season_id
              AND round = NEW.round;

            -- Falls nicht: Initialisiere den Spieltag
            IF NOT FOUND THEN
                PERFORM private.initialize_snapshot_internal(r.league_id, r.user_id, NEW.season_id, NEW.round);

                -- Danach die neu erstellte ID abfragen
                SELECT id INTO v_point_id
                FROM public.user_matchday_points
                WHERE user_id = r.user_id
                  AND league_id = r.league_id
                  AND season_id = NEW.season_id
                  AND round = NEW.round;
            END IF;

            -- 2. Den gesamten Spieltag für den User sperren (Formation darf nicht mehr geändert werden)
            UPDATE public.user_matchday_points
            SET is_locked = true
            WHERE id = v_point_id AND is_locked = false;

            -- 3. Den spezifischen Spieler in diesem Snapshot sperren und das laufende Spiel zuweisen
            UPDATE public.user_matchday_players
            SET is_locked = true,
                spiel_id = NEW.id
            WHERE matchday_point_id = v_point_id
              AND player_id = r.player_id;

        END LOOP;
    END IF;

    RETURN NEW;
END;
$function$;
