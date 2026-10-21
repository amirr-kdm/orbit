-- Orbit — Fight Club (experiment): a space monster for a group goal.
-- Run after challenges.sql. Remove with the "drop" block at the bottom.
--
-- Someone sets a goal (e.g. "Finish chapter 5"), how long it takes (= the monster's health in minutes) and a deadline.
-- Every minute a member studies after the monster appears is one bullet. Firing a bullet does 1 damage.
-- Beat it before the deadline → a reward pool (bigger for bigger monsters) is split by damage done.
-- If the deadline passes first, the monster escapes and no one is paid.

create table if not exists public.bosses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  creator uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  hp int not null check (hp between 30 and 6000),          -- minutes of study needed
  deadline timestamptz not null,
  monster int not null default 1 check (monster between 1 and 5),
  status text not null default 'alive' check (status in ('alive', 'defeated', 'escaped')),
  created_at timestamptz not null default now()
);

create table if not exists public.boss_fighters (
  boss_id uuid not null references public.bosses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  minutes int not null default 0,    -- bullets earned (minutes studied since the monster appeared)
  damage int not null default 0,     -- bullets fired
  primary key (boss_id, user_id)
);

alter table public.bosses enable row level security;
alter table public.boss_fighters enable row level security;
drop policy if exists "bosses read" on public.bosses;
create policy "bosses read" on public.bosses for select to authenticated using (public.in_group(group_id));
drop policy if exists "boss fighters read" on public.boss_fighters;
create policy "boss fighters read" on public.boss_fighters for select to authenticated
  using (exists (select 1 from bosses b where b.id = boss_id and public.in_group(b.group_id)));
revoke insert, update, delete on public.bosses, public.boss_fighters from anon, authenticated;
grant select on public.bosses, public.boss_fighters to authenticated;

-- Monster level from the goal size: up to 5h, 10h, 20h, 40h, more
create or replace function public.boss_level(hp int) returns int language sql immutable as $$
  select case when hp <= 300 then 1 when hp <= 600 then 2 when hp <= 1200 then 3 when hp <= 2400 then 4 else 5 end
$$;

-- Reward pool: 30 rockets per hour of the goal, +15% per monster level above 1
create or replace function public.boss_pool(hp int) returns int language sql immutable as $$
  select floor(hp / 60.0 * 30 * (1 + 0.15 * (public.boss_level(hp) - 1)))::int
$$;

create or replace function public.create_boss(g uuid, title text, goal int, ends timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b uuid;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if not public.in_group(g) then raise exception 'You are not in that group'; end if;
  if ends <= now() + interval '10 minutes' then raise exception 'Give it a later deadline'; end if;
  insert into bosses (group_id, creator, title, hp, deadline, monster)
    values (g, me, trim(create_boss.title), goal, ends, public.boss_level(goal)) returning id into b;
  insert into boss_fighters (boss_id, user_id) values (b, me);
  return b;
end;
$$;

-- Each app reports the minutes its user studied since the monster appeared (= bullets earned)
create or replace function public.report_boss(b uuid, mins int)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; cap int;
begin
  select * into x from bosses where id = b;
  if x.id is null or x.status <> 'alive' or not public.in_group(x.group_id) then return; end if;
  cap := ceil(extract(epoch from (least(now(), x.deadline) - x.created_at)) / 60);
  insert into boss_fighters (boss_id, user_id, minutes) values (b, auth.uid(), least(mins, cap))
    on conflict (boss_id, user_id) do update set minutes = greatest(boss_fighters.minutes, least(excluded.minutes, cap));
end;
$$;

create or replace function public.pay_boss(b uuid)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; total int; pool int; f record;
begin
  select * into x from bosses where id = b;
  select coalesce(sum(damage), 0) into total from boss_fighters where boss_id = b;
  pool := public.boss_pool(x.hp);
  for f in select user_id, damage from boss_fighters where boss_id = b and damage > 0 loop
    perform public.move_rockets(f.user_id, greatest(1, floor(pool::numeric * f.damage / greatest(1, total))::int),
      'Beat the monster “' || x.title || '” — ' || f.damage || ' damage');
  end loop;
end;
$$;
revoke all on function public.pay_boss(uuid) from public, anon, authenticated;

-- Fire bullets; returns the monster's health left
create or replace function public.fire_boss(b uuid, shots int)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x bosses; mine boss_fighters; dealt int; left_hp int;
begin
  select * into x from bosses where id = b for update;
  if x.id is null or not public.in_group(x.group_id) then raise exception 'Monster not found'; end if;
  if x.status <> 'alive' then raise exception 'This fight is over'; end if;
  if now() > x.deadline then update bosses set status = 'escaped' where id = b; raise exception 'Too late — the monster escaped'; end if;
  select * into mine from boss_fighters where boss_id = b and user_id = me for update;
  if mine.user_id is null then raise exception 'Study first to earn bullets'; end if;
  left_hp := x.hp - (select coalesce(sum(damage), 0) from boss_fighters where boss_id = b);
  dealt := greatest(0, least(shots, mine.minutes - mine.damage, left_hp));
  if dealt = 0 then return left_hp; end if;
  update boss_fighters set damage = damage + dealt where boss_id = b and user_id = me;
  left_hp := left_hp - dealt;
  if left_hp <= 0 then
    update bosses set status = 'defeated' where id = b;
    perform public.pay_boss(b);
  end if;
  return left_hp;
end;
$$;

-- After the deadline an alive monster escapes (anyone in the group may trigger this)
create or replace function public.expire_boss(b uuid)
returns void language sql security definer set search_path = public as $$
  update bosses set status = 'escaped' where id = b and status = 'alive' and now() > deadline and public.in_group(group_id);
$$;

revoke all on function public.create_boss(uuid, text, int, timestamptz), public.report_boss(uuid, int),
  public.fire_boss(uuid, int), public.expire_boss(uuid) from public, anon;
grant execute on function public.create_boss(uuid, text, int, timestamptz), public.report_boss(uuid, int),
  public.fire_boss(uuid, int), public.expire_boss(uuid) to authenticated;

-- To remove the experiment:
-- drop function if exists public.create_boss(uuid, text, int, timestamptz), public.report_boss(uuid, int), public.fire_boss(uuid, int),
--   public.expire_boss(uuid), public.pay_boss(uuid), public.boss_pool(int), public.boss_level(int);
-- drop table if exists public.boss_fighters, public.bosses;
