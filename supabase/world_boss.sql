-- Orbit — Fight Club becomes a weekly World Boss for every Orbiter.
-- Run after bosses.sql (do NOT re-run bosses.sql: it starts by dropping the tables). Safe to re-run.
--
-- Each week (Saturday → Friday, Tehran time) one monster appears for everyone. Its health is
-- (approved members when it appears) × (hours per member, 5 by default; only the admin can change it,
-- and a change applies from the next monster). Every minute an Orbiter studies that week is a bullet.
-- Beat it before the week ends → 45 rockets per hour of its health, shared by damage done.
-- Nobody summons monsters any more.

alter table public.bosses add column if not exists world_week date;   -- set for the weekly World Boss
create unique index if not exists bosses_world_week on public.bosses (world_week) where world_week is not null;
alter table public.bosses drop constraint if exists bosses_hp_check;
alter table public.bosses add constraint bosses_hp_check check (hp between 30 and 1000000);

create table if not exists public.boss_settings (
  id int primary key default 1 check (id = 1),
  hours_per_member int not null default 5 check (hours_per_member between 1 and 100)
);
insert into public.boss_settings (id) values (1) on conflict do nothing;
alter table public.boss_settings enable row level security;
drop policy if exists "boss settings read" on public.boss_settings;
create policy "boss settings read" on public.boss_settings for select to authenticated using (true);
revoke insert, update, delete on public.boss_settings from anon, authenticated;
grant select on public.boss_settings to authenticated;

-- Everyone approved can see (and fight) a World Boss
create or replace function public.is_world_boss(b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from bosses where id = b and world_week is not null);
$$;
create or replace function public.can_see_boss(b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.fights_boss(b) or exists (select 1 from boss_invites where boss_id = b and user_id = auth.uid())
      or (public.is_world_boss(b) and public.is_approved());
$$;

-- This week's monster (made by the first app that asks). week_start = the Saturday the week begins.
create or replace function public.world_boss(week_start date)
returns setof public.bosses language plpgsql security definer set search_path = public as $$
declare n int; h int; begins timestamptz; ends timestamptz;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if extract(isodow from week_start) <> 6 or week_start > current_date + 1 or week_start < current_date - 7 then
    raise exception 'Not this week';
  end if;
  if not exists (select 1 from bosses where world_week = week_start) then
    select count(*) into n from profiles where approved;
    select hours_per_member into h from boss_settings where id = 1;
    begins := (week_start::timestamp) at time zone 'Asia/Tehran';
    ends := ((week_start + 7)::timestamp) at time zone 'Asia/Tehran';
    insert into bosses (creator, title, hp, deadline, monster, status, created_at, world_week)
      values (auth.uid(), 'World Boss · ' || to_char(week_start, 'Mon DD'), greatest(30, n * coalesce(h, 5) * 60), ends,
              (extract(week from week_start)::int % 5) + 1, 'alive', begins, week_start)
      on conflict do nothing;
  end if;
  return query select * from bosses where world_week = week_start;
end;
$$;

-- Bullets: anyone approved joins a World Boss fight by studying
create or replace function public.report_boss(b uuid, mins int)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; cap int;
begin
  select * into x from bosses where id = b;
  if x.id is null or x.status <> 'alive' then return; end if;
  if x.world_week is not null and public.is_approved() then
    insert into boss_fighters (boss_id, user_id) values (b, auth.uid()) on conflict do nothing;
  end if;
  cap := ceil(extract(epoch from (least(now(), x.deadline) - x.created_at)) / 60);
  update boss_fighters set minutes = greatest(minutes, least(mins, cap)) where boss_id = b and user_id = auth.uid();
end;
$$;

-- A World Boss pays 45 rockets per hour of its health (no size bonus); others as before
create or replace function public.pay_boss(b uuid)
returns void language plpgsql security definer set search_path = public as $$
declare x bosses; total int; pool int; f record;
begin
  select * into x from bosses where id = b;
  select coalesce(sum(damage), 0) into total from boss_fighters where boss_id = b;
  pool := case when x.world_week is not null then floor(x.hp / 60.0 * 45)::int else public.boss_pool(x.hp) end;
  for f in select user_id, damage from boss_fighters where boss_id = b and damage > 0 loop
    perform public.move_rockets(f.user_id, greatest(1, floor(pool::numeric * f.damage / greatest(1, total))::int),
      'Beat ' || x.title || ' — ' || f.damage || ' damage');
  end loop;
end;
$$;
revoke all on function public.pay_boss(uuid) from public, anon, authenticated;

create or replace function public.fire_boss(b uuid, shots int, hits int)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x bosses; mine boss_fighters; used int; dealt int; left_hp int;
begin
  select * into x from bosses where id = b for update;
  if x.id is not null and x.world_week is not null and public.is_approved() then
    insert into boss_fighters (boss_id, user_id) values (b, me) on conflict do nothing;
  end if;
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

create or replace function public.expire_boss(b uuid)
returns void language sql security definer set search_path = public as $$
  update bosses set status = 'escaped'
  where id = b and status = 'alive' and now() > deadline and (public.fights_boss(b) or (world_week is not null and public.is_approved()));
$$;

-- Nobody summons or deletes monsters any more (old ones run out as before)
create or replace function public.create_boss(title text, goal int, ends timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Monsters now come once a week for everyone — open Fight Club to fight this week''s World Boss';
end;
$$;
create or replace function public.delete_boss(b uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from bosses where id = b and creator = auth.uid() and world_week is null) then
    raise exception 'Only the one who summoned it can delete it';
  end if;
  delete from bosses where id = b;
end;
$$;

-- Names of World Boss fighters (they may not be your friends): just the username
create or replace function public.boss_names(ids uuid[])
returns table (id uuid, name text) language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name) from profiles p
  where public.is_approved() and p.id = any(ids)
    and exists (select 1 from boss_fighters f join bosses x on x.id = f.boss_id where f.user_id = p.id and x.world_week is not null);
$$;

-- Admin: hours of health per member for the next World Bosses
create or replace function public.admin_set_boss_hours(hours int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if hours < 1 or hours > 100 then raise exception 'Between 1 and 100 hours'; end if;
  update boss_settings set hours_per_member = hours where id = 1;
end;
$$;

revoke all on function public.world_boss(date), public.boss_names(uuid[]), public.admin_set_boss_hours(int),
  public.report_boss(uuid, int), public.fire_boss(uuid, int, int), public.expire_boss(uuid) from public, anon;
grant execute on function public.world_boss(date), public.boss_names(uuid[]), public.admin_set_boss_hours(int),
  public.is_world_boss(uuid), public.report_boss(uuid, int), public.fire_boss(uuid, int, int), public.expire_boss(uuid) to authenticated;
