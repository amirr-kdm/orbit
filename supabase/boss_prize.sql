-- Orbit — World Boss: the admin sets the prize (still shared by damage); only the top fighter counts as having won the boss.
-- Safe to re-run. Run after world_boss.sql. The prize of a boss is fixed when it appears, so a change
-- applies from the next week's boss (this week's stays as it is, like the hours per member).

alter table public.boss_settings add column if not exists prize int not null default 1000;
alter table public.boss_settings drop constraint if exists boss_settings_prize_check;
alter table public.boss_settings add constraint boss_settings_prize_check check (prize between 1 and 100000);
-- the prize this boss was created with (null = a boss from before this setting: 1000)
alter table public.bosses add column if not exists prize int;

-- This week's monster: same as before, and it remembers the current prize setting
create or replace function public.world_boss(week_start date)
returns setof public.bosses language plpgsql security definer set search_path = public as $$
declare n int; h int; pz int; begins timestamptz; ends timestamptz;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if extract(isodow from week_start) <> 6 or week_start > (now() at time zone 'Asia/Tehran')::date + 1 or week_start < (now() at time zone 'Asia/Tehran')::date - 7 then
    raise exception 'Not this week';
  end if;
  if not exists (select 1 from bosses where world_week = week_start) then
    select count(*) into n from profiles where approved;
    select hours_per_member, prize into h, pz from boss_settings where id = 1;
    begins := (week_start::timestamp) at time zone 'Asia/Tehran';
    ends := ((week_start + 7)::timestamp) at time zone 'Asia/Tehran';
    insert into bosses (creator, title, hp, deadline, monster, status, created_at, world_week, prize)
      values (auth.uid(), 'World Boss · ' || to_char(week_start, 'Mon DD'), greatest(30, n * coalesce(h, 5) * 60), ends,
              1 + floor(random() * 7)::int, 'alive', begins, week_start, coalesce(pz, 1000))
      on conflict do nothing;
  end if;
  return query select * from bosses where world_week = week_start;
end;
$$;

-- The prize is shared by damage done (a World Boss pays its own prize setting; older monsters pay by their health)
create or replace function public.pay_boss(b uuid)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; total int; pool int; f record;
begin
  select * into x from bosses where id = b;
  select coalesce(sum(damage), 0) into total from boss_fighters where boss_id = b;
  pool := case when x.world_week is not null then coalesce(x.prize, 1000) else public.boss_pool(x.hp) end;
  for f in select user_id, damage from boss_fighters where boss_id = b and damage > 0 loop
    perform public.move_rockets(f.user_id, greatest(1, floor(pool::numeric * f.damage / greatest(1, total))::int),
      'Beat ' || x.title || ' — ' || f.damage || ' damage');
  end loop;
end;
$$;
revoke all on function public.pay_boss(uuid) from public, anon, authenticated;

-- The profile's "World Bosses won" count: only the fighter with the most damage (a tie counts for each) wins a boss
create or replace function public.orbiter_profile(uid uuid)
returns table (id uuid, name text, avatar text, level int, streak int, slain int, joined timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name), p.avatar, p.level, p.streak,
         (select count(*) from boss_fighters f join bosses x on x.id = f.boss_id
           where f.user_id = p.id and f.damage > 0 and x.world_week is not null and x.status = 'defeated'
             and f.damage = (select max(m.damage) from boss_fighters m where m.boss_id = x.id))::int,
         p.created_at
  from profiles p
  where public.is_approved() and p.id = uid and p.approved;
$$;
revoke all on function public.orbiter_profile(uuid) from public, anon;
grant execute on function public.orbiter_profile(uuid) to authenticated;

-- Admin: the prize of the next World Bosses
create or replace function public.admin_set_boss_prize(amount int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if amount < 1 or amount > 100000 then raise exception 'Between 1 and 100,000 rockets'; end if;
  update boss_settings set prize = amount where id = 1;
end;
$$;
revoke all on function public.world_boss(date), public.admin_set_boss_prize(int) from public, anon;
grant execute on function public.world_boss(date), public.admin_set_boss_prize(int) to authenticated;
