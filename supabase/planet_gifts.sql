-- Orbit — gift a store planet to a friend. Safe to re-run.
-- You pay the planet's price when you send it. The friend gets a gift box; when they open it, the server checks
-- whether they already own that planet: if not, it joins their shelf; if they do, they get its price in rockets instead.

create table if not exists public.planet_gifts (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  planet_id text not null,
  box text not null default 'starry',
  note text,
  price int not null check (price > 0),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  result text                      /* 'planet' or 'rockets', once opened */
);
create index if not exists planet_gifts_to on public.planet_gifts (to_user, opened_at);
alter table public.planet_gifts enable row level security;
drop policy if exists "my gifts" on public.planet_gifts;
create policy "my gifts" on public.planet_gifts for select to authenticated using (from_user = auth.uid() or to_user = auth.uid());
revoke insert, update, delete on public.planet_gifts from anon, authenticated;
grant select on public.planet_gifts to authenticated;

-- Send: friends only, store planets only, you must be able to pay
create or replace function public.send_planet_gift(recipient uuid, planet text, box text default 'starry', note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cost int; bal int; gid uuid; who text;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if recipient = me then raise exception 'You can''t gift a planet to yourself'; end if;
  if not public.is_friend(recipient) then raise exception 'You can only gift a friend'; end if;
  select price into cost from store_prices where planet_id = planet;
  if cost is null then raise exception 'That planet can''t be gifted'; end if;
  perform 1 from wallets where user_id = me for update;
  bal := public.wallet_balance(me);
  if bal is null then raise exception 'Your wallet isn''t ready yet — open the app online once'; end if;
  if bal < cost then raise exception 'Not enough rockets — you need %', cost; end if;
  select coalesce(username, name) into who from profiles where id = recipient;
  insert into planet_gifts (from_user, to_user, planet_id, box, note, price)
    values (me, recipient, planet, left(coalesce(box, 'starry'), 20), left(note, 120), cost) returning id into gid;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, -cost, 'Gift for ' || who, 'giftplanet:' || gid);
  perform public.wallet_sync_profile(me);
  return gid;
end;
$$;

-- Gift boxes waiting for me
create or replace function public.my_planet_gifts()
returns table (id uuid, from_name text, planet_id text, box text, note text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select g.id, coalesce(p.username, p.name), g.planet_id, g.box, g.note, g.created_at
  from planet_gifts g join profiles p on p.id = g.from_user
  where g.to_user = auth.uid() and g.opened_at is null
  order by g.created_at;
$$;

-- Open one: the planet, or its price in rockets if I already own it
create or replace function public.open_planet_gift(gift uuid)
returns json language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g planet_gifts; owned boolean;
begin
  select * into g from planet_gifts where id = gift and to_user = me for update;
  if g.id is null then raise exception 'Gift not found'; end if;
  if g.opened_at is not null then raise exception 'Already opened'; end if;
  if not exists (select 1 from wallets where user_id = me) then raise exception 'Your wallet isn''t ready yet — open the app online once'; end if;
  owned := exists (select 1 from owned_planets where user_id = me and planet_id = g.planet_id);
  if owned then
    insert into rocket_gifts (user_id, amount, reason, ref) values (me, g.price, 'Gift: you already had this planet', 'giftback:' || g.id);
    update planet_gifts set opened_at = now(), result = 'rockets' where id = g.id;
    perform public.wallet_sync_profile(me);
    return json_build_object('result', 'rockets', 'planet', g.planet_id, 'amount', g.price);
  end if;
  insert into owned_planets (user_id, planet_id, price) values (me, g.planet_id, 0);   /* price 0: a gift can't be refunded */
  update planet_gifts set opened_at = now(), result = 'planet' where id = g.id;
  return json_build_object('result', 'planet', 'planet', g.planet_id, 'amount', 0);
end;
$$;

revoke all on function public.send_planet_gift(uuid, text, text, text), public.my_planet_gifts(), public.open_planet_gift(uuid) from public, anon;
grant execute on function public.send_planet_gift(uuid, text, text, text), public.my_planet_gifts(), public.open_planet_gift(uuid) to authenticated;
