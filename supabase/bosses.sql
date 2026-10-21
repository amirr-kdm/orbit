-- Orbit — Fight Club (experiment): a space monster for a study goal.
-- Run after challenges.sql. Remove with the "drop" block at the bottom.
--
-- Anyone can summon a monster on their own: a goal, how long it takes (= the monster's health in minutes) and a deadline.
-- Invite friends one by one, or a whole study group at once (everyone in it gets the invite). Invitees accept or decline.
-- Every minute a fighter studies after the monster appears is one bullet; firing a bullet does 1 damage.
-- Beat it before the deadline → a reward pool (bigger for bigger monsters) is split by damage done.
-- If the deadline passes first, the monster escapes and no one is paid.

drop table if exists public.boss_invites, public.boss_fighters, public.bosses cascade;

create table public.bosses (
  id uuid primary key default gen_random_uuid(),
  creator uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  hp int not null check (hp between 30 and 6000),          -- minutes of study needed
  deadline timestamptz not null,
  monster int not null default 1 check (monster between 1 and 5),
  status text not null default 'alive' check (status in ('alive', 'defeated', 'escaped')),
  created_at timestamptz not null default now()
);

create table public.boss_fighters (
  boss_id uuid not null references public.bosses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  minutes int not null default 0,    -- bullets earned (minutes studied since the monster appeared)
  damage int not null default 0,     -- bullets fired
  primary key (boss_id, user_id)
);

create table public.boss_invites (
  boss_id uuid not null references public.bosses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  from_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (boss_id, user_id)
);

create or replace function public.fights_boss(b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from boss_fighters where boss_id = b and user_id = auth.uid());
$$;
create or replace function public.can_see_boss(b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.fights_boss(b) or exists (select 1 from boss_invites where boss_id = b and user_id = auth.uid());
$$;

alter table public.bosses enable row level security;
alter table public.boss_fighters enable row level security;
alter table public.boss_invites enable row level security;
create policy "bosses read" on public.bosses for select to authenticated using (public.can_see_boss(id));
create policy "boss fighters read" on public.boss_fighters for select to authenticated using (public.can_see_boss(boss_id));
create policy "boss invites read" on public.boss_invites for select to authenticated using (user_id = auth.uid() or public.fights_boss(boss_id));
revoke insert, update, delete on public.bosses, public.boss_fighters, public.boss_invites from anon, authenticated;
grant select on public.bosses, public.boss_fighters, public.boss_invites to authenticated;

-- Monster level from the goal size: up to 5h, 10h, 20h, 40h, more
create or replace function public.boss_level(hp int) returns int language sql immutable as $$
  select case when hp <= 300 then 1 when hp <= 600 then 2 when hp <= 1200 then 3 when hp <= 2400 then 4 else 5 end
$$;

-- Reward pool: 45 rockets per hour of the goal, +15% per monster level above 1
create or replace function public.boss_pool(hp int) returns int language sql immutable as $$
  select floor(hp / 60.0 * 45 * (1 + 0.15 * (public.boss_level(hp) - 1)))::int
$$;

-- Summon a monster on your own (invite others afterwards)
drop function if exists public.create_boss(uuid, text, int, timestamptz);
create or replace function public.create_boss(title text, goal int, ends timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b uuid;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if ends <= now() + interval '10 minutes' then raise exception 'Give it a later deadline'; end if;
  insert into bosses (creator, title, hp, deadline, monster)
    values (me, trim(create_boss.title), goal, ends, public.boss_level(goal)) returning id into b;
  insert into boss_fighters (boss_id, user_id) values (b, me);
  return b;
end;
$$;

-- Invite one friend (or anyone you share a group with)
create or replace function public.invite_boss(b uuid, who uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.fights_boss(b) then raise exception 'Only fighters can invite'; end if;
  if (select status from bosses where id = b) <> 'alive' then raise exception 'This fight is over'; end if;
  if not (public.is_friend(who) or public.shares_group(who)) then raise exception 'You can only invite friends and group members'; end if;
  if exists (select 1 from boss_fighters where boss_id = b and user_id = who) then return; end if;
  insert into boss_invites (boss_id, user_id, from_user) values (b, who, auth.uid()) on conflict do nothing;
end;
$$;

-- Invite a whole study group: everyone in it gets the invite. Returns how many were invited.
create or replace function public.invite_boss_group(b uuid, g uuid)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.fights_boss(b) then raise exception 'Only fighters can invite'; end if;
  if not public.in_group(g) then raise exception 'You are not in that group'; end if;
  if (select status from bosses where id = b) <> 'alive' then raise exception 'This fight is over'; end if;
  insert into boss_invites (boss_id, user_id, from_user)
    select b, m.user_id, auth.uid() from group_members m
    where m.group_id = g and m.user_id <> auth.uid()
      and not exists (select 1 from boss_fighters f where f.boss_id = b and f.user_id = m.user_id)
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.answer_boss_invite(b uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from boss_invites where boss_id = b and user_id = auth.uid()) then raise exception 'No invite'; end if;
  delete from boss_invites where boss_id = b and user_id = auth.uid();
  if accept then
    if (select status from bosses where id = b) <> 'alive' then raise exception 'This fight is already over'; end if;
    insert into boss_fighters (boss_id, user_id) values (b, auth.uid()) on conflict do nothing;
  end if;
end;
$$;

-- Each fighter's app reports the minutes they studied since the monster appeared (= bullets earned)
drop function if exists public.report_boss(uuid, int);
create or replace function public.report_boss(b uuid, mins int)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; cap int;
begin
  select * into x from bosses where id = b;
  if x.id is null or x.status <> 'alive' then return; end if;
  cap := ceil(extract(epoch from (least(now(), x.deadline) - x.created_at)) / 60);
  update boss_fighters set minutes = greatest(minutes, least(mins, cap)) where boss_id = b and user_id = auth.uid();
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

-- Fire: `shots` bullets used, `hits` of them landed (aiming happens in the app; a miss still costs a bullet).
-- Returns the monster's health left.
alter table public.boss_fighters add column if not exists spent int not null default 0;
drop function if exists public.fire_boss(uuid, int);
create or replace function public.fire_boss(b uuid, shots int, hits int)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x bosses; mine boss_fighters; used int; dealt int; left_hp int;
begin
  select * into x from bosses where id = b for update;
  if x.id is null or not public.fights_boss(b) then raise exception 'Join the fight first'; end if;
  if x.status <> 'alive' then raise exception 'This fight is over'; end if;
  if now() > x.deadline then update bosses set status = 'escaped' where id = b; raise exception 'Too late — the monster escaped'; end if;
  select * into mine from boss_fighters where boss_id = b and user_id = me for update;
  left_hp := x.hp - (select coalesce(sum(damage), 0) from boss_fighters where boss_id = b);
  used := greatest(0, least(shots, mine.minutes - mine.spent));
  dealt := greatest(0, least(hits, used, left_hp));
  if used = 0 then return left_hp; end if;
  update boss_fighters set spent = spent + used, damage = damage + dealt where boss_id = b and user_id = me;
  left_hp := left_hp - dealt;
  if left_hp <= 0 then
    update bosses set status = 'defeated' where id = b;
    delete from boss_invites where boss_id = b;
    perform public.pay_boss(b);
  end if;
  return left_hp;
end;
$$;

-- After the deadline an alive monster escapes (any fighter may trigger this)
create or replace function public.expire_boss(b uuid)
returns void language sql security definer set search_path = public as $$
  update bosses set status = 'escaped' where id = b and status = 'alive' and now() > deadline and public.fights_boss(b);
$$;

revoke all on function public.create_boss(text, int, timestamptz), public.invite_boss(uuid, uuid), public.invite_boss_group(uuid, uuid),
  public.answer_boss_invite(uuid, boolean), public.report_boss(uuid, int), public.fire_boss(uuid, int, int), public.expire_boss(uuid) from public, anon;
grant execute on function public.create_boss(text, int, timestamptz), public.invite_boss(uuid, uuid), public.invite_boss_group(uuid, uuid),
  public.answer_boss_invite(uuid, boolean), public.report_boss(uuid, int), public.fire_boss(uuid, int, int), public.expire_boss(uuid),
  public.fights_boss(uuid), public.can_see_boss(uuid) to authenticated;

-- The one who summoned a monster can delete it (no rockets are involved until it's beaten)
create or replace function public.delete_boss(b uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from bosses where id = b and creator = auth.uid()) then raise exception 'Only the one who summoned it can delete it'; end if;
  delete from bosses where id = b;
end;
$$;
revoke all on function public.delete_boss(uuid) from public, anon;
grant execute on function public.delete_boss(uuid) to authenticated;

-- To remove the experiment:
-- drop function if exists public.create_boss(text, int, timestamptz), public.invite_boss(uuid, uuid), public.invite_boss_group(uuid, uuid),
--   public.answer_boss_invite(uuid, boolean), public.report_boss(uuid, int), public.fire_boss(uuid, int, int), public.expire_boss(uuid),
--   public.pay_boss(uuid), public.delete_boss(uuid), public.boss_pool(int), public.boss_level(int), public.fights_boss(uuid), public.can_see_boss(uuid);
-- drop table if exists public.boss_invites, public.boss_fighters, public.bosses;
