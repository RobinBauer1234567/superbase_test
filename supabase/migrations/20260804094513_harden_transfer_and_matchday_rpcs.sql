-- Route all fantasy-market and matchday mutations through authenticated,
-- server-validated RPCs. Direct reads remain unchanged.
revoke insert, update, delete on table public.transfer_bids from anon, authenticated;
revoke insert, update, delete on table public.transfer_market from anon, authenticated;
revoke insert, update, delete on table public.league_players from anon, authenticated;
revoke insert, update, delete on table public.user_matchday_points from anon, authenticated;
revoke insert, update, delete on table public.user_matchday_players from anon, authenticated;

create or replace function public.place_transfer_bid(
  p_transfer_id bigint,
  p_amount integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_transfer record;
  v_budget numeric;
  v_squad_limit integer;
  v_roster_size integer;
  v_highest_bid integer;
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Das Gebot muss größer als 0 sein.';
  end if;

  select tm.*, l.squad_limit
  into v_transfer
  from public.transfer_market tm
  join public.leagues l on l.id = tm.league_id
  where tm.id = p_transfer_id
    and tm.is_active is true
    and l.is_active is true
  for update of tm;

  if not found then
    raise exception 'Aktiver Transfer nicht gefunden.';
  end if;

  if v_transfer.expires_at <= now() then
    raise exception 'Der Transfer ist bereits abgelaufen.';
  end if;

  if v_transfer.seller_id = v_user_id then
    raise exception 'Du kannst nicht auf deinen eigenen Spieler bieten.';
  end if;

  if p_amount < v_transfer.min_bid_price then
    raise exception 'Das Gebot liegt unter dem Mindestgebot.';
  end if;

  if v_transfer.buy_now_price is not null
     and p_amount >= v_transfer.buy_now_price then
    raise exception 'Nutze für diesen Betrag den Sofortkauf.';
  end if;

  select lm.budget
  into v_budget
  from public.league_members lm
  where lm.league_id = v_transfer.league_id
    and lm.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Du bist kein Mitglied dieser Liga.';
  end if;

  if v_budget < p_amount then
    raise exception 'Nicht genug Budget.';
  end if;

  select count(*)
  into v_roster_size
  from public.league_players lp
  where lp.league_id = v_transfer.league_id
    and lp.user_id = v_user_id;

  v_squad_limit := v_transfer.squad_limit;
  if v_squad_limit is not null
     and v_squad_limit > 0
     and v_roster_size >= v_squad_limit then
    raise exception 'Dein Kaderlimit ist erreicht.';
  end if;

  if exists (
    select 1
    from public.league_players lp
    where lp.league_id = v_transfer.league_id
      and lp.player_id = v_transfer.player_id
  ) then
    raise exception 'Der Spieler gehört bereits zu einem Kader dieser Liga.';
  end if;

  select max(tb.amount)
  into v_highest_bid
  from public.transfer_bids tb
  where tb.transfer_id = p_transfer_id;

  if v_highest_bid is not null and p_amount <= v_highest_bid then
    raise exception 'Das Gebot muss das aktuelle Höchstgebot übersteigen.';
  end if;

  delete from public.transfer_bids tb
  where tb.transfer_id = p_transfer_id
    and tb.bidder_id = v_user_id;

  insert into public.transfer_bids (transfer_id, bidder_id, amount)
  values (p_transfer_id, v_user_id, p_amount);
end;
$function$;

create or replace function public.withdraw_transfer_bid(p_transfer_id bigint)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  perform 1
  from public.transfer_market tm
  where tm.id = p_transfer_id
    and tm.is_active is true
    and tm.expires_at > now()
  for update;

  if not found then
    raise exception 'Aktiver Transfer nicht gefunden oder bereits abgelaufen.';
  end if;

  delete from public.transfer_bids tb
  where tb.transfer_id = p_transfer_id
    and tb.bidder_id = v_user_id;

  if not found then
    raise exception 'Kein eigenes Gebot für diesen Transfer gefunden.';
  end if;
end;
$function$;

create or replace function public.list_player_for_sale(
  p_league_id bigint,
  p_player_id bigint,
  p_buy_now_price integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_market_value integer;
  v_season_id bigint;
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  select l.season_id
  into v_season_id
  from public.leagues l
  where l.id = p_league_id
    and l.is_active is true;

  if not found or v_season_id is null then
    raise exception 'Aktive Liga mit Saison nicht gefunden.';
  end if;

  perform 1
  from public.league_members lm
  where lm.league_id = p_league_id
    and lm.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Du bist kein Mitglied dieser Liga.';
  end if;

  perform 1
  from public.league_players lp
  where lp.league_id = p_league_id
    and lp.player_id = p_player_id
    and lp.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Der Spieler gehört nicht zu deinem Kader.';
  end if;

  if exists (
    select 1
    from public.transfer_market tm
    where tm.league_id = p_league_id
      and tm.player_id = p_player_id
      and tm.is_active is true
  ) then
    raise exception 'Der Spieler ist bereits auf dem Transfermarkt.';
  end if;

  select sa.marktwert
  into v_market_value
  from public.spieler_analytics sa
  where sa.spieler_id = p_player_id
    and sa.season_id = v_season_id;

  if v_market_value is null or v_market_value <= 0 then
    raise exception 'Für diesen Spieler ist kein gültiger Marktwert vorhanden.';
  end if;

  if p_buy_now_price is null or p_buy_now_price < v_market_value then
    raise exception 'Der Sofortkaufpreis darf nicht unter dem Marktwert liegen.';
  end if;

  insert into public.transfer_market (
    league_id,
    player_id,
    seller_id,
    listed_at,
    expires_at,
    buy_now_price,
    min_bid_price,
    is_active
  )
  values (
    p_league_id,
    p_player_id,
    v_user_id,
    now(),
    now() + interval '24 hours',
    p_buy_now_price,
    v_market_value,
    true
  );

  delete from public.league_players lp
  where lp.league_id = p_league_id
    and lp.player_id = p_player_id
    and lp.user_id = v_user_id;

  if not found then
    raise exception 'Der Spieler konnte nicht aus deinem Kader entfernt werden.';
  end if;
end;
$function$;

create or replace function public.quick_sell_player(
  p_league_id bigint,
  p_player_id bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_market_value integer;
  v_sell_price integer;
  v_season_id bigint;
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  select l.season_id
  into v_season_id
  from public.leagues l
  where l.id = p_league_id
    and l.is_active is true;

  if not found or v_season_id is null then
    raise exception 'Aktive Liga mit Saison nicht gefunden.';
  end if;

  perform 1
  from public.league_members lm
  where lm.league_id = p_league_id
    and lm.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Du bist kein Mitglied dieser Liga.';
  end if;

  perform 1
  from public.league_players lp
  where lp.league_id = p_league_id
    and lp.player_id = p_player_id
    and lp.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Der Spieler gehört nicht zu deinem Kader.';
  end if;

  if exists (
    select 1
    from public.transfer_market tm
    where tm.league_id = p_league_id
      and tm.player_id = p_player_id
      and tm.is_active is true
  ) then
    raise exception 'Der Spieler ist bereits auf dem Transfermarkt.';
  end if;

  select sa.marktwert
  into v_market_value
  from public.spieler_analytics sa
  where sa.spieler_id = p_player_id
    and sa.season_id = v_season_id;

  if v_market_value is null or v_market_value <= 0 then
    raise exception 'Für diesen Spieler ist kein gültiger Marktwert vorhanden.';
  end if;

  v_sell_price := floor(v_market_value * 0.95);

  update public.league_members lm
  set budget = lm.budget + v_sell_price
  where lm.league_id = p_league_id
    and lm.user_id = v_user_id;

  if not found then
    raise exception 'Das Budget konnte nicht aktualisiert werden.';
  end if;

  delete from public.league_players lp
  where lp.league_id = p_league_id
    and lp.player_id = p_player_id
    and lp.user_id = v_user_id;

  if not found then
    raise exception 'Der Spieler konnte nicht verkauft werden.';
  end if;
end;
$function$;

create or replace function public.buy_player_now(p_transfer_id bigint)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_transfer record;
  v_buyer_budget numeric;
  v_roster_size integer;
  v_player record;
  v_seller_name text := 'System';
  v_seller_avatar text;
  v_buyer_name text;
  v_buyer_avatar text;
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  select tm.*, l.squad_limit, l.season_id
  into v_transfer
  from public.transfer_market tm
  join public.leagues l on l.id = tm.league_id
  where tm.id = p_transfer_id
    and tm.is_active is true
    and l.is_active is true
  for update of tm;

  if not found then
    raise exception 'Aktiver Transfer nicht gefunden.';
  end if;

  if v_transfer.expires_at <= now() then
    raise exception 'Der Transfer ist bereits abgelaufen.';
  end if;

  if v_transfer.buy_now_price is null or v_transfer.buy_now_price <= 0 then
    raise exception 'Für diesen Transfer ist kein Sofortkauf möglich.';
  end if;

  if v_transfer.seller_id = v_user_id then
    raise exception 'Du kannst deinen eigenen Spieler nicht kaufen.';
  end if;

  select lm.budget
  into v_buyer_budget
  from public.league_members lm
  where lm.league_id = v_transfer.league_id
    and lm.user_id = v_user_id
  for update;

  if not found then
    raise exception 'Du bist kein Mitglied dieser Liga.';
  end if;

  if v_buyer_budget < v_transfer.buy_now_price then
    raise exception 'Nicht genug Budget.';
  end if;

  select count(*)
  into v_roster_size
  from public.league_players lp
  where lp.league_id = v_transfer.league_id
    and lp.user_id = v_user_id;

  if v_transfer.squad_limit is not null
     and v_transfer.squad_limit > 0
     and v_roster_size >= v_transfer.squad_limit then
    raise exception 'Dein Kaderlimit ist erreicht.';
  end if;

  if exists (
    select 1
    from public.league_players lp
    where lp.league_id = v_transfer.league_id
      and lp.player_id = v_transfer.player_id
  ) then
    raise exception 'Der Spieler gehört bereits zu einem Kader dieser Liga.';
  end if;

  if v_transfer.seller_id is not null then
    perform 1
    from public.league_members lm
    where lm.league_id = v_transfer.league_id
      and lm.user_id = v_transfer.seller_id
    for update;

    if not found then
      raise exception 'Der Verkäufer ist kein Mitglied dieser Liga mehr.';
    end if;
  end if;

  update public.league_members lm
  set budget = lm.budget - v_transfer.buy_now_price
  where lm.league_id = v_transfer.league_id
    and lm.user_id = v_user_id
    and lm.budget >= v_transfer.buy_now_price;

  if not found then
    raise exception 'Nicht genug Budget.';
  end if;

  if v_transfer.seller_id is not null then
    update public.league_members lm
    set budget = lm.budget + v_transfer.buy_now_price
    where lm.league_id = v_transfer.league_id
      and lm.user_id = v_transfer.seller_id;

    select p.username, p.avatar_url
    into v_seller_name, v_seller_avatar
    from public.profiles p
    where p.user_id = v_transfer.seller_id;
  end if;

  insert into public.league_players (league_id, user_id, player_id, purchase_price)
  values (
    v_transfer.league_id,
    v_user_id,
    v_transfer.player_id,
    v_transfer.buy_now_price
  );

  select p.username, p.avatar_url
  into v_buyer_name, v_buyer_avatar
  from public.profiles p
  where p.user_id = v_user_id;

  select
    s.name,
    s.position,
    s.profilbild_url,
    t.image_url as team_image_url,
    sa.marktwert,
    sa.punkteschnitt
  into v_player
  from public.spieler s
  left join public.season_players sp
    on sp.player_id = s.id
   and sp.season_id = v_transfer.season_id
   and sp.is_active is true
  left join public.team t on t.id = sp.team_id
  left join public.spieler_analytics sa
    on sa.spieler_id = s.id
   and sa.season_id = v_transfer.season_id
  where s.id = v_transfer.player_id
  limit 1;

  insert into public.league_activities (league_id, type, content)
  values (
    v_transfer.league_id,
    'TRANSFER',
    jsonb_build_object(
      'transfer_type', 'SOFORTKAUF',
      'transfer_id', v_transfer.id,
      'player_id', v_transfer.player_id,
      'position', v_player.position,
      'player_name', v_player.name,
      'profilbild_url', v_player.profilbild_url,
      'team_image_url', v_player.team_image_url,
      'marktwert', v_player.marktwert,
      'score', round(coalesce(v_player.punkteschnitt, 0)),
      'buyer_name', v_buyer_name,
      'buyer_avatar_url', v_buyer_avatar,
      'seller_name', v_seller_name,
      'seller_avatar_url', v_seller_avatar,
      'price', v_transfer.buy_now_price,
      'is_system_buy', v_transfer.seller_id is null
    )
  );

  update public.transfer_market tm
  set is_active = false
  where tm.id = v_transfer.id
    and tm.is_active is true;

  delete from public.transfer_bids tb
  where tb.transfer_id = v_transfer.id;
end;
$function$;

create or replace function public.process_expired_transfers()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_transfer record;
  v_bid record;
  v_budget numeric;
  v_player record;
  v_seller_name text;
  v_seller_avatar text;
  v_buyer_name text;
  v_buyer_avatar text;
  v_final_price bigint;
  v_transfer_type text;
  v_winner_found boolean;
  v_failed_bid boolean;
  v_roster_size integer;
begin
  perform set_config('my.skip_trigger', 'true', true);

  for v_transfer in
    select tm.*, l.season_id, l.squad_limit
    from public.transfer_market tm
    join public.leagues l on l.id = tm.league_id
    where tm.is_active is true
      and tm.expires_at <= now()
    for update of tm skip locked
  loop
    v_seller_name := 'System';
    v_seller_avatar := null;
    v_buyer_name := 'System';
    v_buyer_avatar := null;
    v_final_price := v_transfer.min_bid_price;
    v_transfer_type := 'KEINE GEBOTE';
    v_winner_found := false;
    v_failed_bid := false;

    if v_transfer.seller_id is not null then
      select p.username, p.avatar_url
      into v_seller_name, v_seller_avatar
      from public.profiles p
      where p.user_id = v_transfer.seller_id;
    end if;

    select
      s.name,
      s.position,
      s.profilbild_url,
      t.image_url as team_image_url,
      sa.marktwert,
      sa.punkteschnitt
    into v_player
    from public.spieler s
    left join public.season_players sp
      on sp.player_id = s.id
     and sp.season_id = v_transfer.season_id
     and sp.is_active is true
    left join public.team t on t.id = sp.team_id
    left join public.spieler_analytics sa
      on sa.spieler_id = s.id
     and sa.season_id = v_transfer.season_id
    where s.id = v_transfer.player_id
    limit 1;

    for v_bid in
      select tb.*
      from public.transfer_bids tb
      where tb.transfer_id = v_transfer.id
      order by tb.amount desc, tb.created_at asc, tb.id asc
      for update
    loop
      v_transfer_type := 'AUKTION';

      if v_bid.bidder_id = v_transfer.seller_id then
        v_failed_bid := true;
        continue;
      end if;

      select lm.budget
      into v_budget
      from public.league_members lm
      where lm.league_id = v_transfer.league_id
        and lm.user_id = v_bid.bidder_id
      for update;

      if not found or v_budget < v_bid.amount then
        v_failed_bid := true;
        continue;
      end if;

      select count(*)
      into v_roster_size
      from public.league_players lp
      where lp.league_id = v_transfer.league_id
        and lp.user_id = v_bid.bidder_id;

      if v_transfer.squad_limit is not null
         and v_transfer.squad_limit > 0
         and v_roster_size >= v_transfer.squad_limit then
        v_failed_bid := true;
        continue;
      end if;

      if exists (
        select 1
        from public.league_players lp
        where lp.league_id = v_transfer.league_id
          and lp.player_id = v_transfer.player_id
      ) then
        v_failed_bid := true;
        continue;
      end if;

      update public.league_members lm
      set budget = lm.budget - v_bid.amount
      where lm.league_id = v_transfer.league_id
        and lm.user_id = v_bid.bidder_id
        and lm.budget >= v_bid.amount;

      if not found then
        v_failed_bid := true;
        continue;
      end if;

      if v_transfer.seller_id is not null then
        update public.league_members lm
        set budget = lm.budget + v_bid.amount
        where lm.league_id = v_transfer.league_id
          and lm.user_id = v_transfer.seller_id;
      end if;

      insert into public.league_players (league_id, user_id, player_id, purchase_price)
      values (
        v_transfer.league_id,
        v_bid.bidder_id,
        v_transfer.player_id,
        v_bid.amount
      );

      select p.username, p.avatar_url
      into v_buyer_name, v_buyer_avatar
      from public.profiles p
      where p.user_id = v_bid.bidder_id;

      v_final_price := v_bid.amount;
      v_winner_found := true;
      exit;
    end loop;

    if not v_winner_found
       and v_transfer.seller_id is not null then
      update public.league_members lm
      set budget = lm.budget + v_transfer.min_bid_price
      where lm.league_id = v_transfer.league_id
        and lm.user_id = v_transfer.seller_id;
    end if;

    insert into public.league_activities (league_id, type, content)
    values (
      v_transfer.league_id,
      'TRANSFER',
      jsonb_build_object(
        'transfer_type', v_transfer_type,
        'transfer_id', v_transfer.id,
        'player_id', v_transfer.player_id,
        'position', v_player.position,
        'player_name', v_player.name,
        'profilbild_url', v_player.profilbild_url,
        'team_image_url', v_player.team_image_url,
        'marktwert', v_player.marktwert,
        'score', round(coalesce(v_player.punkteschnitt, 0)),
        'buyer_name', v_buyer_name,
        'buyer_avatar_url', v_buyer_avatar,
        'seller_name', v_seller_name,
        'seller_avatar_url', v_seller_avatar,
        'price', v_final_price,
        'is_system_buy', not v_winner_found,
        'failed_highest_bid', v_failed_bid
      )
    );

    update public.transfer_market tm
    set is_active = false
    where tm.id = v_transfer.id;

    delete from public.transfer_bids tb
    where tb.transfer_id = v_transfer.id;
  end loop;
end;
$function$;

create or replace function public.initialize_matchday_snapshot(
  p_league_id bigint,
  p_user_id uuid,
  p_season_id bigint,
  p_round integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor_id uuid := auth.uid();
  v_previous_point_id bigint;
  v_previous_formation text;
  v_new_point_id bigint;
  v_league_season_id bigint;
begin
  if p_user_id is null then
    raise exception 'Benutzer-ID fehlt.';
  end if;

  -- Trigger and service-role calls may initialize snapshots for league members.
  -- Direct client calls may only initialize the caller's own snapshot.
  if pg_trigger_depth() = 0
     and coalesce(auth.role(), '') <> 'service_role'
     and (v_actor_id is null or v_actor_id <> p_user_id) then
    raise exception 'Du darfst nur deinen eigenen Spieltag initialisieren.';
  end if;

  select l.season_id
  into v_league_season_id
  from public.leagues l
  where l.id = p_league_id
    and l.is_active is true;

  if not found or v_league_season_id is distinct from p_season_id then
    raise exception 'Liga und Saison passen nicht zusammen.';
  end if;

  if not exists (
    select 1
    from public.league_members lm
    where lm.league_id = p_league_id
      and lm.user_id = p_user_id
  ) then
    raise exception 'Der Benutzer ist kein Mitglied dieser Liga.';
  end if;

  if not exists (
    select 1
    from public.spieltag st
    where st.season_id = p_season_id
      and st.round = p_round
  ) then
    raise exception 'Spieltag nicht gefunden.';
  end if;

  if exists (
    select 1
    from public.user_matchday_points ump
    where ump.user_id = p_user_id
      and ump.league_id = p_league_id
      and ump.season_id = p_season_id
      and ump.round = p_round
  ) then
    return;
  end if;

  select ump.id, ump.formation
  into v_previous_point_id, v_previous_formation
  from public.user_matchday_points ump
  where ump.user_id = p_user_id
    and ump.league_id = p_league_id
    and ump.season_id = p_season_id
    and ump.round < p_round
  order by ump.round desc
  limit 1;

  v_previous_formation := coalesce(v_previous_formation, '4-4-2');

  insert into public.user_matchday_points (
    user_id,
    league_id,
    season_id,
    round,
    formation,
    total_points,
    is_locked
  )
  values (
    p_user_id,
    p_league_id,
    p_season_id,
    p_round,
    v_previous_formation,
    0,
    false
  )
  on conflict (user_id, league_id, season_id, round) do nothing
  returning id into v_new_point_id;

  if v_new_point_id is null then
    return;
  end if;

  insert into public.user_matchday_players (
    matchday_point_id,
    player_id,
    formation_index,
    is_locked,
    spiel_id,
    matchrating_id,
    points
  )
  select
    v_new_point_id,
    lp.player_id,
    coalesce(previous_player.formation_index, 99),
    coalesce(game.status, 'nicht gestartet') <> 'nicht gestartet',
    game.id,
    rating.id,
    coalesce(rating.punkte, 0)
  from public.league_players lp
  left join public.user_matchday_players previous_player
    on previous_player.player_id = lp.player_id
   and previous_player.matchday_point_id = v_previous_point_id
  left join lateral (
    select sp.team_id
    from public.season_players sp
    where sp.player_id = lp.player_id
      and sp.season_id = p_season_id
      and sp.is_active is true
    order by sp.team_id
    limit 1
  ) active_team on true
  left join lateral (
    select s.id, s.status
    from public.spiel s
    where s.season_id = p_season_id
      and s.round = p_round
      and active_team.team_id in (s.heimteam_id, s.auswärtsteam_id)
    order by s.id
    limit 1
  ) game on true
  left join public.matchrating rating
    on rating.spiel_id = game.id
   and rating.spieler_id = lp.player_id
  where lp.user_id = p_user_id
    and lp.league_id = p_league_id;

  update public.user_matchday_points ump
  set total_points = (
    select coalesce(sum(player.points), 0)
    from public.user_matchday_players player
    where player.matchday_point_id = v_new_point_id
      and player.formation_index between 0 and 10
  )
  where ump.id = v_new_point_id;
end;
$function$;

create or replace function public.save_lineup(
  p_league_id bigint,
  p_season_id bigint,
  p_round integer,
  p_formation text,
  p_updates jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_point_id bigint;
  v_is_locked boolean;
  v_league_season_id bigint;
  v_item jsonb;
  v_player_id bigint;
  v_index integer;
  v_seen_players bigint[] := '{}';
  v_seen_starter_indexes integer[] := '{}';
  v_updated_rows integer;
begin
  if v_user_id is null then
    raise exception 'Nicht autorisiert. Bitte einloggen.';
  end if;

  select l.season_id
  into v_league_season_id
  from public.leagues l
  where l.id = p_league_id
    and l.is_active is true;

  if not found or v_league_season_id is distinct from p_season_id then
    raise exception 'Liga und Saison passen nicht zusammen.';
  end if;

  if not exists (
    select 1
    from public.league_members lm
    where lm.league_id = p_league_id
      and lm.user_id = v_user_id
  ) then
    raise exception 'Du bist kein Mitglied dieser Liga.';
  end if;

  if not exists (
    select 1
    from public.formation f
    where f.formation = p_formation
  ) then
    raise exception 'Ungültige Formation.';
  end if;

  if jsonb_typeof(p_updates) is distinct from 'array' then
    raise exception 'Die Aufstellungsdaten müssen ein JSON-Array sein.';
  end if;

  select ump.id, ump.is_locked
  into v_point_id, v_is_locked
  from public.user_matchday_points ump
  where ump.user_id = v_user_id
    and ump.league_id = p_league_id
    and ump.season_id = p_season_id
    and ump.round = p_round
  for update;

  if not found then
    perform public.initialize_matchday_snapshot(
      p_league_id,
      v_user_id,
      p_season_id,
      p_round
    );

    select ump.id, ump.is_locked
    into v_point_id, v_is_locked
    from public.user_matchday_points ump
    where ump.user_id = v_user_id
      and ump.league_id = p_league_id
      and ump.season_id = p_season_id
      and ump.round = p_round
    for update;
  end if;

  if v_point_id is null then
    raise exception 'Spieltag konnte nicht initialisiert werden.';
  end if;

  if v_is_locked is true then
    raise exception 'Die Aufstellung dieses Spieltags ist bereits gesperrt.';
  end if;

  for v_item in select value from jsonb_array_elements(p_updates)
  loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ? 'player_id')
       or not (v_item ? 'index') then
      raise exception 'Jeder Aufstellungseintrag benötigt player_id und index.';
    end if;

    begin
      v_player_id := (v_item ->> 'player_id')::bigint;
      v_index := (v_item ->> 'index')::integer;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'player_id und index müssen ganze Zahlen sein.';
    end;

    if v_index <> 99 and (v_index < 0 or v_index > 10) then
      raise exception 'Der Aufstellungsindex muss zwischen 0 und 10 oder 99 sein.';
    end if;

    if v_player_id = any(v_seen_players) then
      raise exception 'Ein Spieler darf nur einmal in der Aufstellung vorkommen.';
    end if;
    v_seen_players := array_append(v_seen_players, v_player_id);

    if v_index between 0 and 10 then
      if v_index = any(v_seen_starter_indexes) then
        raise exception 'Jeder Startelfplatz darf nur einmal belegt sein.';
      end if;
      v_seen_starter_indexes := array_append(v_seen_starter_indexes, v_index);
    end if;

    if not exists (
      select 1
      from public.league_players lp
      where lp.league_id = p_league_id
        and lp.user_id = v_user_id
        and lp.player_id = v_player_id
    ) then
      raise exception 'Spieler % gehört nicht zu deinem Kader.', v_player_id;
    end if;

    update public.user_matchday_players player
    set formation_index = v_index
    where player.matchday_point_id = v_point_id
      and player.player_id = v_player_id
      and player.is_locked is false;

    get diagnostics v_updated_rows = row_count;

    if v_updated_rows = 0 then
      if exists (
        select 1
        from public.user_matchday_players player
        where player.matchday_point_id = v_point_id
          and player.player_id = v_player_id
          and player.is_locked is true
      ) then
        raise exception 'Spieler % ist für diesen Spieltag bereits gesperrt.', v_player_id;
      end if;

      insert into public.user_matchday_players (
        matchday_point_id,
        player_id,
        formation_index,
        is_locked
      )
      values (v_point_id, v_player_id, v_index, false);
    end if;
  end loop;

  update public.user_matchday_points ump
  set
    formation = p_formation,
    total_points = (
      select coalesce(sum(player.points), 0)
      from public.user_matchday_players player
      where player.matchday_point_id = v_point_id
        and player.formation_index between 0 and 10
    )
  where ump.id = v_point_id
    and ump.is_locked is false;

  if not found then
    raise exception 'Die Aufstellung wurde zwischenzeitlich gesperrt.';
  end if;
end;
$function$;

revoke all on function public.place_transfer_bid(bigint, integer) from public, anon;
revoke all on function public.withdraw_transfer_bid(bigint) from public, anon;
revoke all on function public.list_player_for_sale(bigint, bigint, integer) from public, anon;
revoke all on function public.quick_sell_player(bigint, bigint) from public, anon;
revoke all on function public.buy_player_now(bigint) from public, anon;
revoke all on function public.initialize_matchday_snapshot(bigint, uuid, bigint, integer) from public, anon;
revoke all on function public.save_lineup(bigint, bigint, integer, text, jsonb) from public, anon;
revoke all on function public.process_expired_transfers() from public, anon, authenticated;

grant execute on function public.place_transfer_bid(bigint, integer) to authenticated, service_role;
grant execute on function public.withdraw_transfer_bid(bigint) to authenticated, service_role;
grant execute on function public.list_player_for_sale(bigint, bigint, integer) to authenticated, service_role;
grant execute on function public.quick_sell_player(bigint, bigint) to authenticated, service_role;
grant execute on function public.buy_player_now(bigint) to authenticated, service_role;
grant execute on function public.initialize_matchday_snapshot(bigint, uuid, bigint, integer) to authenticated, service_role;
grant execute on function public.save_lineup(bigint, bigint, integer, text, jsonb) to authenticated, service_role;
grant execute on function public.process_expired_transfers() to service_role;
