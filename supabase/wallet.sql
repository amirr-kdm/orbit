-- Orbit — rockets live on the server (a wallet per member). Run after gifts.sql and challenges.sql. Safe to re-run.
--
-- Every rocket movement is a row in rocket_gifts (the ledger). A member's balance is the opening balance
-- moved over once from their app, plus every ledger row after that. Buying, refunds, Level Pass rewards,
-- weekly bonuses and group prizes all happen here, so editing the app's data file can't change rockets,
-- and two devices can't spend the same rockets twice. Owned store planets are kept here too.

alter table public.rocket_gifts add column if not exists ref text;   -- e.g. 'level:12', 'week:2026-10-10'
create unique index if not exists rocket_gifts_ref on public.rocket_gifts (user_id, ref) where ref is not null;

create table if not exists public.wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  opening int not null,
  started_at timestamptz not null default now(),
  levels_claimed int[] not null default '{}'   -- Level Pass levels taken before the wallet existed
);
alter table public.wallets enable row level security;
drop policy if exists "own wallet" on public.wallets;
create policy "own wallet" on public.wallets for select to authenticated using (user_id = auth.uid() or public.is_admin());
revoke insert, update, delete on public.wallets from anon, authenticated;
grant select on public.wallets to authenticated;

-- Store prices (the app's catalogue; the server charges these)
create table if not exists public.store_prices (planet_id text primary key, price int not null check (price > 0));
insert into public.store_prices (planet_id, price) values
('s2_bees', 110),
('s_lemondrop', 130),
('s2_beach', 150),
('s_comet', 160),
('s2_candy', 180),
('s_mint', 200),
('s2_farm', 220),
('s_launchpad', 240),
('s2_penguins', 260),
('s2_winter', 290),
('s_sakura', 310),
('s_moonbase', 330),
('s2_spooky', 350),
('s_neongrid', 380),
('s2_whale', 400),
('s_station', 420),
('s2_desert', 440),
('s2_jungle', 460),
('s_ufo', 490),
('s2_pirates', 520),
('s2_mars', 560),
('s_crystal', 580),
('s2_mine', 600),
('s_solarsail', 620),
('s2_zoo', 650),
('s_rally', 680),
('s2_tokyo', 710),
('s_dragonegg', 740),
('s2_observatory', 770),
('s_mothership', 800),
('s2_kingdom', 830),
('s_blackhole', 860),
('s2_robots', 880),
('s_captain', 900),
('s2_jurassic', 920),
('s_odyssey', 950),
('s_royal', 970),
('s3_meteor', 720),
('s3_satellite', 540),
('s3_impact', 960),
('s_aliens', 990),
('s4_spacecat', 1000),
('s4_ufocat', 1000),
('s4_claudecoder', 1000),
('s4_claudechute', 1000),
('s2_hub', 1000),
('s_infinity', 1000),
('s5_frost', 850),
('s5_coral', 870),
('s5_geode', 890),
('s5_maze', 910),
('s5_cloud', 880),
('s5_river', 900),
('s5_vortex', 950),
('s5_crater', 860),
('s5_circuit', 980),
('s5_mushroom', 920),
('s5_hills', 860),
('s5_glacier', 900),
('s5_blossom', 870),
('s5_cocoa', 880),
('s5_candy', 940),
('s5_blocks', 960),
('s5_lemon', 890),
('s5_cotton', 910),
('s5_slime', 930),
('s5_burger', 850),
('s5_hotdog', 860),
('s5_donut', 880),
('s5_taco', 870),
('s5_sushi', 900),
('s5_icecream', 920),
('s5_burgersaturn', 1000)
on conflict (planet_id) do update set price = excluded.price;
alter table public.store_prices enable row level security;
drop policy if exists "prices read" on public.store_prices;
create policy "prices read" on public.store_prices for select to authenticated using (true);
grant select on public.store_prices to authenticated;

-- Planets a member owns (store planets and Level Pass planets)
create table if not exists public.owned_planets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  planet_id text not null,
  price int not null default 0,
  bought_at timestamptz not null default now()
);
create index if not exists owned_planets_user on public.owned_planets (user_id);
alter table public.owned_planets enable row level security;
drop policy if exists "own planets" on public.owned_planets;
create policy "own planets" on public.owned_planets for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.owned_planets from anon, authenticated;
grant select on public.owned_planets to authenticated;

create table if not exists public.refunds (
  user_id uuid not null references public.profiles(id) on delete cascade,
  planet_id text not null,
  at timestamptz not null default now()
);
alter table public.refunds enable row level security;
revoke all on public.refunds from anon, authenticated;

-- Balance: opening + every ledger row since the wallet started (null = no wallet yet)
create or replace function public.wallet_balance(who uuid) returns int language sql stable security definer set search_path = public as $$
  select w.opening + coalesce((select sum(g.amount) from rocket_gifts g where g.user_id = who and g.created_at > w.started_at), 0)::int
  from wallets w where w.user_id = who;
$$;
revoke all on function public.wallet_balance(uuid) from public, anon, authenticated;

-- What the app shows: balance, refunds left, owned planets
create or replace function public.my_wallet()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'started', exists (select 1 from wallets where user_id = auth.uid()),
    'balance', public.wallet_balance(auth.uid()),
    'refunds_left', greatest(0, 3 - (select count(*) from refunds where user_id = auth.uid())),
    'levels', coalesce((select levels_claimed from wallets where user_id = auth.uid()), '{}'::int[])
              || coalesce((select array_agg(substr(ref, 7)::int) from rocket_gifts where user_id = auth.uid() and ref like 'level:%'), '{}'::int[]),
    'planets', coalesce((select json_agg(json_build_object('id', id, 'planet', planet_id, 'price', price, 'at', bought_at) order by bought_at)
                         from owned_planets where user_id = auth.uid()), '[]'));
$$;

-- Once per member: move the app's balance, owned planets and claimed levels to the server
create or replace function public.wallet_start(balance int, planets jsonb, levels int[], refunds_used int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p jsonb;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if exists (select 1 from wallets where user_id = me) then return; end if;
  insert into wallets (user_id, opening, levels_claimed) values (me, greatest(0, balance), coalesce(levels, '{}'));
  for p in select * from jsonb_array_elements(coalesce(planets, '[]')) loop
    insert into owned_planets (user_id, planet_id, price, bought_at)
      values (me, p->>'planetID', coalesce((p->>'price')::int, 0), coalesce((p->>'date')::timestamptz, now()));
  end loop;
  for i in 1..least(3, greatest(0, refunds_used)) loop insert into refunds (user_id, planet_id) values (me, 'before-wallet'); end loop;
  update profiles set rockets = greatest(0, balance) where id = me;
end;
$$;

-- Keep the balance friends see in step with the wallet
create or replace function public.wallet_sync_profile(who uuid) returns void language sql security definer set search_path = public as $$
  update profiles set rockets = coalesce(public.wallet_balance(who), rockets) where id = who;
$$;
revoke all on function public.wallet_sync_profile(uuid) from public, anon, authenticated;

create or replace function public.buy_planet(planet text)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cost int; bal int; pid uuid;
begin
  select price into cost from store_prices where planet_id = planet;
  if cost is null then raise exception 'That planet isn''t for sale'; end if;
  perform 1 from wallets where user_id = me for update;
  bal := public.wallet_balance(me);
  if bal is null then raise exception 'Your wallet isn''t ready yet — open the app online once'; end if;
  if bal < cost then raise exception 'Not enough rockets — you need %', cost; end if;
  insert into owned_planets (user_id, planet_id, price) values (me, planet, cost) returning id into pid;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, -cost, 'Bought a planet', 'buy:' || pid);
  perform public.wallet_sync_profile(me);
  return pid;
end;
$$;

create or replace function public.refund_planet(purchase uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x owned_planets;
begin
  perform 1 from wallets where user_id = me for update;
  if (select count(*) from refunds where user_id = me) >= 3 then raise exception 'No refund tickets left'; end if;
  select * into x from owned_planets where id = purchase and user_id = me;
  if x.id is null or x.price <= 0 then raise exception 'That can''t be refunded'; end if;
  delete from owned_planets where id = purchase;
  insert into refunds (user_id, planet_id) values (me, x.planet_id);
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, x.price, 'Refund', 'refund:' || purchase);
  perform public.wallet_sync_profile(me);
end;
$$;

-- Level Pass: 25 rockets per level (and a planet every 10 levels), once each, up to your level
create or replace function public.claim_level(lvl int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets;
begin
  select * into w from wallets where user_id = me for update;
  if w.user_id is null then raise exception 'Your wallet isn''t ready yet'; end if;
  if lvl < 1 or lvl > 60 or lvl > coalesce((select level from profiles where id = me), 1) then raise exception 'You haven''t reached that level yet'; end if;
  if lvl = any(w.levels_claimed) or exists (select 1 from rocket_gifts where user_id = me and ref = 'level:' || lvl) then return; end if;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, 25, 'Level ' || lvl || ' reward', 'level:' || lvl);
  if lvl % 10 = 0 then insert into owned_planets (user_id, planet_id, price) values (me, 'lv_t' || (lvl / 10), 0); end if;
  perform public.wallet_sync_profile(me);
end;
$$;

-- Weekly bonus for a finished week, from the study the server knows (daily_stats; timer study only)
create or replace function public.claim_week_bonus(week_start date)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; hours numeric; bonus int;
begin
  select * into w from wallets where user_id = me for update;
  if w.user_id is null then return 0; end if;
  -- finished weeks only, and only those after the wallet started (earlier ones are in the opening balance)
  if week_start + 7 > current_date or (week_start + 7)::timestamptz <= w.started_at then return 0; end if;
  if exists (select 1 from rocket_gifts where user_id = me and ref = 'week:' || week_start) then return 0; end if;
  select coalesce(sum(minutes), 0) / 60.0 into hours from daily_stats where user_id = me and day >= week_start and day < week_start + 7;
  bonus := case when hours > 30 then 400 when hours >= 30 then 300 when hours >= 25 then 240 when hours >= 20 then 200
                when hours >= 15 then 140 when hours >= 10 then 100 else 0 end;
  if bonus > 0 then
    insert into rocket_gifts (user_id, amount, reason, ref) values (me, bonus, 'Weekly bonus: ' || round(hours, 1) || 'h studied', 'week:' || week_start);
    perform public.wallet_sync_profile(me);
  end if;
  return bonus;
end;
$$;

-- Group prize: studied the most in a group in a finished week (ties included), 100 rockets, once per group per week
create or replace function public.claim_group_win(g uuid, week_start date)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets; mine int; best int;
begin
  select * into w from wallets where user_id = me for update;
  if w.user_id is null or not public.in_group(g) then return false; end if;
  if week_start + 7 > current_date or (week_start + 7)::timestamptz <= w.started_at then return false; end if;
  if (select count(*) from group_members where group_id = g) < 2 then return false; end if;
  if exists (select 1 from rocket_gifts where user_id = me and ref = 'group:' || g || '|' || week_start) then return false; end if;
  select coalesce(sum(minutes), 0) into mine from daily_stats where user_id = me and day >= week_start and day < week_start + 7;
  select coalesce(max(t), 0) into best from (select sum(s.minutes) t from daily_stats s join group_members m on m.user_id = s.user_id
     where m.group_id = g and m.user_id <> me and s.day >= week_start and s.day < week_start + 7 group by s.user_id) x;
  if mine = 0 or mine < best then return false; end if;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, 100, 'Studied the most in a group last week', 'group:' || g || '|' || week_start);
  perform public.wallet_sync_profile(me);
  return true;
end;
$$;

-- Challenges check the server balance once someone has a wallet
create or replace function public.check_balance(who uuid, need int)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if need > 0 and coalesce(public.wallet_balance(who), (select rockets from profiles where id = who), 0) < need then
    raise exception 'Not enough rockets — you need %', need;
  end if;
end;
$$;
revoke all on function public.check_balance(uuid, int) from public, anon, authenticated;

-- With a wallet, the app can no longer write its own rocket count
create or replace function public.keep_wallet_rockets() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from wallets where user_id = new.id) then new.rockets := public.wallet_balance(new.id); end if;
  return new;
end;
$$;
drop trigger if exists keep_wallet_rockets on public.profiles;
create trigger keep_wallet_rockets before update of rockets on public.profiles for each row execute function public.keep_wallet_rockets();

-- Admin: everyone's balance (to look over the moved-over numbers)
create or replace function public.admin_wallets()
returns table (id uuid, name text, opening int, balance int, started timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name), w.opening, public.wallet_balance(p.id), w.started_at
  from profiles p left join wallets w on w.user_id = p.id
  where public.is_admin() order by 4 desc nulls last;
$$;

revoke all on function public.my_wallet(), public.wallet_start(int, jsonb, int[], int), public.buy_planet(text), public.refund_planet(uuid),
  public.claim_level(int), public.claim_week_bonus(date), public.claim_group_win(uuid, date), public.admin_wallets() from public, anon;
grant execute on function public.my_wallet(), public.wallet_start(int, jsonb, int[], int), public.buy_planet(text), public.refund_planet(uuid),
  public.claim_level(int), public.claim_week_bonus(date), public.claim_group_win(uuid, date), public.admin_wallets() to authenticated;
