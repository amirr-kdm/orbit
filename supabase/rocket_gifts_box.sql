-- Orbit — gift rockets to a friend in a gift box (same table and popup as planet gifts). Safe to re-run. Run after planet_gifts.sql.
alter table public.planet_gifts alter column planet_id drop not null;
alter table public.planet_gifts add column if not exists rockets int;

create or replace function public.send_rocket_gift(recipient uuid, amount int, box text default 'starry', note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); bal int; gid uuid; who text;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if recipient = me then raise exception 'You can''t gift rockets to yourself'; end if;
  if not public.is_friend(recipient) then raise exception 'You can only gift a friend'; end if;
  if amount < 10 or amount > 100000 then raise exception 'Between 10 and 100,000 rockets'; end if;
  perform 1 from wallets where user_id = me for update;
  bal := public.wallet_balance(me);
  if bal is null then raise exception 'Your wallet isn''t ready yet'; end if;
  if bal < amount then raise exception 'Not enough rockets - you need %', amount; end if;
  select coalesce(username, name) into who from profiles where id = recipient;
  insert into planet_gifts (from_user, to_user, planet_id, rockets, box, note, price)
    values (me, recipient, null, amount, left(coalesce(box, 'starry'), 20), left(note, 120), amount) returning id into gid;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, -amount, 'Gift for ' || who, 'giftrockets:' || gid);
  perform public.wallet_sync_profile(me);
  return gid;
end;
$$;

drop function if exists public.my_planet_gifts();
create or replace function public.my_planet_gifts()
returns table (id uuid, from_name text, planet_id text, rockets int, box text, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select g.id, coalesce(p.username, p.name), g.planet_id, g.rockets, g.box, g.note, g.created_at
  from planet_gifts g join profiles p on p.id = g.from_user
  where g.to_user = auth.uid() and g.opened_at is null
  order by g.created_at;
$$;

create or replace function public.open_planet_gift(gift uuid)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g planet_gifts; owned boolean;
begin
  select * into g from planet_gifts where id = gift and to_user = me for update;
  if g.id is null then raise exception 'Gift not found'; end if;
  if g.opened_at is not null then raise exception 'Already opened'; end if;
  if not exists (select 1 from wallets where user_id = me) then raise exception 'Your wallet isn''t ready yet'; end if;
  if g.planet_id is null then   -- a box of rockets
    insert into rocket_gifts (user_id, amount, reason, ref) values (me, g.rockets, 'Gift of rockets from a friend', 'giftbox:' || g.id);
    update planet_gifts set opened_at = now(), result = 'rocketbox' where id = g.id;
    perform public.wallet_sync_profile(me);
    return json_build_object('result', 'rocketbox', 'planet', null, 'amount', g.rockets);
  end if;
  owned := exists (select 1 from owned_planets where user_id = me and planet_id = g.planet_id);
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

revoke all on function public.send_rocket_gift(uuid, int, text, text), public.my_planet_gifts(), public.open_planet_gift(uuid) from public, anon;
grant execute on function public.send_rocket_gift(uuid, int, text, text), public.my_planet_gifts(), public.open_planet_gift(uuid) to authenticated;
