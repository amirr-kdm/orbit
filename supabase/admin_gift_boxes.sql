-- Orbit — gifts from the admin (planets, rockets, rockets for everyone) now arrive as gift boxes too. Safe to re-run.
-- Nothing reaches the member's balance or shelf until they open the box. Taking rockets back (a negative amount) stays direct.
alter table public.planet_gifts drop constraint if exists planet_gifts_price_check;
alter table public.planet_gifts add constraint planet_gifts_price_check check (price >= 0);

create or replace function public.admin_gift_planet(uid uuid, planet text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if planet is null or length(planet) = 0 then raise exception 'Pick a planet'; end if;
  if not exists (select 1 from profiles where id = uid and approved) then raise exception 'No such member'; end if;
  insert into planet_gifts (from_user, to_user, planet_id, box, price) values (auth.uid(), uid, planet, 'balloon', 0);
end;
$$;

create or replace function public.admin_gift_rockets(uid uuid, amount int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if amount = 0 then return; end if;
  if amount < 0 then
    insert into rocket_gifts (user_id, amount) values (uid, amount);   -- taking back: direct
    perform public.wallet_sync_profile(uid);
  else
    insert into planet_gifts (from_user, to_user, planet_id, rockets, box, price) values (auth.uid(), uid, null, amount, 'starry', amount);
  end if;
end;
$$;

create or replace function public.admin_gift_all(amount int, reason text default null)
returns int language plpgsql security definer set search_path = public as $$
declare u record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if amount < 1 or amount > 100000 then raise exception 'Between 1 and 100000 rockets'; end if;
  for u in select id from profiles where approved loop
    insert into planet_gifts (from_user, to_user, planet_id, rockets, box, note, price)
      values (auth.uid(), u.id, null, amount, 'treasure', left(nullif(trim(coalesce(reason, '')), ''), 120), amount);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Opening: an admin's planet is always added (it has no price to turn into rockets)
create or replace function public.open_planet_gift(gift uuid)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g planet_gifts; owned boolean;
begin
  select * into g from planet_gifts where id = gift and to_user = me for update;
  if g.id is null then raise exception 'Gift not found'; end if;
  if g.opened_at is not null then raise exception 'Already opened'; end if;
  if not exists (select 1 from wallets where user_id = me) then raise exception 'Your wallet isn''t ready yet'; end if;
  if g.planet_id is null then
    insert into rocket_gifts (user_id, amount, reason, ref) values (me, g.rockets, 'Gift of rockets', 'giftbox:' || g.id);
    update planet_gifts set opened_at = now(), result = 'rocketbox' where id = g.id;
    perform public.wallet_sync_profile(me);
    return json_build_object('result', 'rocketbox', 'planet', null, 'amount', g.rockets);
  end if;
  owned := g.price > 0 and exists (select 1 from owned_planets where user_id = me and planet_id = g.planet_id);
  if owned then
    insert into rocket_gifts (user_id, amount, reason, ref) values (me, g.price, 'Gift: you already had this planet', 'giftback:' || g.id);
    update planet_gifts set opened_at = now(), result = 'rockets' where id = g.id;
    perform public.wallet_sync_profile(me);
    return json_build_object('result', 'rockets', 'planet', g.planet_id, 'amount', g.price);
  end if;
  insert into owned_planets (user_id, planet_id, price) values (me, g.planet_id, 0);
  update planet_gifts set opened_at = now(), result = 'planet' where id = g.id;
  return json_build_object('result', 'planet', 'planet', g.planet_id, 'amount', 0);
end;
$$;
