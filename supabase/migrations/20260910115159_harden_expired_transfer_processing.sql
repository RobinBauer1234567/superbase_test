create or replace function public.process_expired_transfers()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t_rec record;
  bid_rec record;
  v_winner_budget numeric;
  v_player record;
  v_season_id bigint;
  v_seller_name text;
  v_seller_avatar text;
  v_buyer_name text;
  v_buyer_avatar text;
  v_is_system_buy boolean;
  v_final_price bigint;
  v_failed_bid boolean;
  v_transfer_type text;
  v_winner_found boolean;
begin
  if auth.uid() is null and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  perform set_config('my.skip_trigger', 'true', true);

  for t_rec in
    select *
    from public.transfer_market
    where is_active = true and expires_at <= now()
    for update skip locked
  loop
    v_seller_name := 'System';
    v_seller_avatar := null;
    v_buyer_name := 'System';
    v_buyer_avatar := null;
    v_is_system_buy := true;
    v_failed_bid := false;
    v_transfer_type := 'AUKTION';
    v_winner_found := false;

    select season_id into v_season_id
    from public.leagues
    where id = t_rec.league_id;

    select s.name, s.position, s.profilbild_url,
           t.image_url as team_image_url,
           sa.marktwert, sa.punkteschnitt
    into v_player
    from public.spieler s
    left join public.season_players sp
      on sp.player_id = s.id
     and sp.season_id = v_season_id
     and sp.is_active = true
    left join public.team t on sp.team_id = t.id
    left join public.spieler_analytics sa
      on sa.spieler_id = s.id and sa.season_id = v_season_id
    where s.id = t_rec.player_id;

    if t_rec.seller_id is not null then
      select username, avatar_url into v_seller_name, v_seller_avatar
      from public.profiles
      where user_id = t_rec.seller_id;
    end if;

    for bid_rec in
      select * from public.transfer_bids
      where transfer_id = t_rec.id
      order by amount desc
    loop
      select budget into v_winner_budget
      from public.league_members
      where league_id = t_rec.league_id and user_id = bid_rec.bidder_id
      for update;

      if v_winner_budget >= bid_rec.amount then
        v_winner_found := true;
        v_final_price := bid_rec.amount;
        v_is_system_buy := false;

        select username, avatar_url into v_buyer_name, v_buyer_avatar
        from public.profiles
        where user_id = bid_rec.bidder_id;

        update public.league_members
        set budget = budget - bid_rec.amount
        where league_id = t_rec.league_id and user_id = bid_rec.bidder_id;

        if t_rec.seller_id is not null then
          update public.league_members
          set budget = budget + bid_rec.amount
          where league_id = t_rec.league_id and user_id = t_rec.seller_id;
        end if;

        insert into public.league_players (league_id, user_id, player_id, purchase_price)
        values (t_rec.league_id, bid_rec.bidder_id, t_rec.player_id, bid_rec.amount);
        exit;
      else
        v_failed_bid := true;
      end if;
    end loop;

    if not v_winner_found then
      if exists (select 1 from public.transfer_bids where transfer_id = t_rec.id) then
        v_transfer_type := 'AUKTION';
      else
        v_transfer_type := 'KEINE GEBOTE';
      end if;
      v_final_price := t_rec.min_bid_price;
      if t_rec.seller_id is not null then
        update public.league_members
        set budget = budget + t_rec.min_bid_price
        where league_id = t_rec.league_id and user_id = t_rec.seller_id;
      end if;
    end if;

    insert into public.league_activities (league_id, type, content)
    values (
      t_rec.league_id,
      'TRANSFER',
      jsonb_build_object(
        'transfer_type', v_transfer_type,
        'transfer_id', t_rec.id,
        'player_id', t_rec.player_id,
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
        'is_system_buy', v_is_system_buy,
        'failed_highest_bid', v_failed_bid
      )
    );

    update public.transfer_market set is_active = false where id = t_rec.id;
  end loop;
end;
$$;

revoke execute on function public.process_expired_transfers() from public, anon;
grant execute on function public.process_expired_transfers() to authenticated, service_role;
