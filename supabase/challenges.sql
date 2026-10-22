-- Orbit — Group challenges and promises to a friend
-- Run after groups.sql, accounts.sql and gifts.sql. Safe to re-run.
--
-- Rockets move through rocket_gifts (each app adds rows it hasn't counted yet to its balance),
-- so paying in is a negative row and payouts are positive rows. All rules run here, on the server.
--
-- Group challenge: everyone (creator included) pays the entry fee to join.
--   At least 4 hours of study; the fee is at least 50 rockets per hour of the goal (4h → 200, 5h → 250 …).
--   Fewer than 2 people joined → everyone is refunded, nobody wins.
--   All finish  → everyone gets their fee back plus a bonus: as much again, at most 100 rockets per hour of the goal.
--   Some fail   → those who failed lose their fee; it's shared between those who finished
--                 (who also get their own fee back).
--   Before the start anyone can leave for a full refund; after it, no one can.
--   Only the creator can cancel — everyone is refunded, even after the start.
-- Promise: one person stakes rockets on studying X minutes by a deadline.
--   Done → the stake comes back.  Not done → the stake goes to the friend.

alter table public.rocket_gifts add column if not exists reason text;

create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'group' check (kind in ('group', 'promise')),
  group_id uuid references public.groups(id) on delete cascade,
  creator uuid not null references public.profiles(id) on delete cascade,
  friend uuid references public.profiles(id) on delete cascade,  -- promises: who gets the stake
  title text not null check (char_length(title) between 1 and 60),
  target_minutes int not null check (target_minutes between 1 and 10080),
  fee int not null check (fee between 0 and 100000),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'settled', 'cancelled')),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.challenge_members (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  minutes int not null default 0,
  joined_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

-- How long after the end apps still have to report their last study minutes
create or replace function public.challenge_grace() returns interval language sql immutable as $$ select interval '1 hour' $$;

create or replace function public.can_see_challenge(c uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from challenges x where x.id = c and (
    x.creator = auth.uid() or x.friend = auth.uid()
    or (x.kind = 'group' and x.group_id is null and public.is_approved())   -- open to every Orbit member
    or (x.group_id is not null and public.in_group(x.group_id))
    or exists (select 1 from challenge_members m where m.challenge_id = x.id and m.user_id = auth.uid())));
$$;

alter table public.challenges enable row level security;
alter table public.challenge_members enable row level security;
drop policy if exists "challenges read" on public.challenges;
create policy "challenges read" on public.challenges for select to authenticated using (public.can_see_challenge(id));
drop policy if exists "challenge members read" on public.challenge_members;
create policy "challenge members read" on public.challenge_members for select to authenticated using (public.can_see_challenge(challenge_id));
revoke insert, update, delete on public.challenges, public.challenge_members from anon, authenticated;
grant select on public.challenges, public.challenge_members to authenticated;

-- Pay (negative) or receive (positive) rockets with a reason the app shows
create or replace function public.move_rockets(who uuid, amount int, why text)
returns void language sql security definer set search_path = public as $$
  insert into rocket_gifts (user_id, amount, reason) select who, amount, why where amount <> 0;
$$;
revoke all on function public.move_rockets(uuid, int, text) from public, anon, authenticated;

-- Can I afford it? (the balance each app reports to the server)
create or replace function public.check_balance(who uuid, need int)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if need > 0 and coalesce((select rockets from profiles where id = who), 0) < need then
    raise exception 'Not enough rockets — you need %', need;
  end if;
end;
$$;
revoke all on function public.check_balance(uuid, int) from public, anon, authenticated;

-- Rules for group challenges (shared by the app's form and the checks below)
create or replace function public.challenge_min_minutes() returns int language sql immutable as $$ select 240 $$;
create or replace function public.challenge_min_fee(target_minutes int) returns int language sql immutable as $$
  select ceil(target_minutes / 60.0 * 50)::int
$$;
create or replace function public.challenge_max_bonus(target_minutes int) returns int language sql immutable as $$
  select floor(target_minutes / 60.0 * 100)::int
$$;

create or replace function public.create_challenge(g uuid, title text, target_minutes int, fee int, starts_at timestamptz, ends_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c uuid; s timestamptz := greatest(starts_at, now());
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  -- challenges are open to every Orbit member: no group (older apps still send one; it's ignored)
  if target_minutes < public.challenge_min_minutes() then raise exception 'A challenge is at least 4 hours of study'; end if;
  if fee < public.challenge_min_fee(target_minutes) then
    raise exception 'The entry fee is at least % rockets for this goal', public.challenge_min_fee(target_minutes);
  end if;
  if ends_at <= s then raise exception 'The end must be after the start'; end if;
  perform public.check_balance(me, fee);
  insert into challenges (kind, group_id, creator, title, target_minutes, fee, starts_at, ends_at)
    values ('group', null, me, trim(title), target_minutes, fee, s, ends_at) returning id into c;
  insert into challenge_members (challenge_id, user_id) values (c, me);
  perform public.move_rockets(me, -fee, 'Entry fee: ' || trim(title));
  return c;
end;
$$;

create or replace function public.create_promise(to_friend uuid, target_minutes int, stake int, ends_at timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c uuid; who text;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if not public.is_friend(to_friend) then raise exception 'You can only promise a friend'; end if;
  if stake < 1 then raise exception 'Put at least 1 rocket at stake'; end if;
  if ends_at <= now() then raise exception 'The deadline must be in the future'; end if;
  perform public.check_balance(me, stake);
  select coalesce(username, name) into who from profiles where id = to_friend;
  insert into challenges (kind, creator, friend, title, target_minutes, fee, starts_at, ends_at)
    values ('promise', me, to_friend, 'Promise to ' || who, target_minutes, stake, now(), ends_at) returning id into c;
  insert into challenge_members (challenge_id, user_id) values (c, me);
  perform public.move_rockets(me, -stake, 'Stake: promise to ' || who);
  return c;
end;
$$;

create or replace function public.join_challenge(c uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x challenges;
begin
  select * into x from challenges where id = c for update;
  if x.id is null or x.kind <> 'group' or not (x.group_id is null or public.in_group(x.group_id)) then raise exception 'Challenge not found'; end if;
  if x.status <> 'open' or now() >= x.starts_at then raise exception 'This challenge has already started'; end if;
  if exists (select 1 from challenge_members where challenge_id = c and user_id = me) then return; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  perform public.check_balance(me, x.fee);
  insert into challenge_members (challenge_id, user_id) values (c, me);
  perform public.move_rockets(me, -x.fee, 'Entry fee: ' || x.title);
end;
$$;

-- Leave before the start: full refund (the creator cancels instead)
create or replace function public.leave_challenge(c uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x challenges;
begin
  select * into x from challenges where id = c for update;
  if x.id is null then raise exception 'Challenge not found'; end if;
  if x.creator = me then raise exception 'You created it — cancel it instead'; end if;
  if x.status <> 'open' or now() >= x.starts_at then raise exception 'It has started — you can no longer leave'; end if;
  delete from challenge_members where challenge_id = c and user_id = me;
  if found then perform public.move_rockets(me, x.fee, 'Refund: left ' || x.title); end if;
end;
$$;

-- Creator only, any time before it's settled: everyone gets their rockets back
create or replace function public.cancel_challenge(c uuid)
returns void language plpgsql security definer set search_path = public as $$
declare x challenges; m record;
begin
  select * into x from challenges where id = c for update;
  if x.id is null or x.creator <> auth.uid() then raise exception 'Only the creator can cancel it'; end if;
  if x.status <> 'open' then raise exception 'It is already finished'; end if;
  for m in select user_id from challenge_members where challenge_id = c loop
    perform public.move_rockets(m.user_id, x.fee, 'Refund: ' || x.title || ' was cancelled');
  end loop;
  update challenges set status = 'cancelled' where id = c;
end;
$$;

-- Each member's app reports the minutes it studied inside the challenge window
create or replace function public.report_challenge(c uuid, minutes int)
returns void language plpgsql security definer set search_path = public as $$
declare x challenges; cap int;
begin
  select * into x from challenges where id = c;
  if x.id is null or x.status <> 'open' or now() < x.starts_at or now() > x.ends_at + public.challenge_grace() then return; end if;
  cap := ceil(extract(epoch from (least(now(), x.ends_at) - x.starts_at)) / 60);
  update challenge_members set minutes = greatest(challenge_members.minutes, least(report_challenge.minutes, cap))
    where challenge_id = c and user_id = auth.uid();
end;
$$;

-- Pay out once the end + grace period has passed. Anyone who can see it may trigger this; it runs once.
create or replace function public.settle_challenge(c uuid)
returns void language plpgsql security definer set search_path = public as $$
declare x challenges; m record; winners int; losers int; pot int; share int; bonus int;
begin
  select * into x from challenges where id = c for update;
  if x.id is null or not public.can_see_challenge(c) then raise exception 'Challenge not found'; end if;
  if x.status <> 'open' or now() < x.ends_at + public.challenge_grace() then return; end if;
  -- a group challenge needs at least 2 people: otherwise everyone just gets their fee back
  if x.kind = 'group' and (select count(*) from challenge_members where challenge_id = c) < 2 then
    for m in select user_id from challenge_members where challenge_id = c loop
      perform public.move_rockets(m.user_id, x.fee, 'Refund: ' || x.title || ' needed at least 2 people');
    end loop;
    update challenges set status = 'settled' where id = c;
    return;
  end if;
  select count(*) filter (where minutes >= x.target_minutes), count(*) filter (where minutes < x.target_minutes)
    into winners, losers from challenge_members where challenge_id = c;
  if x.kind = 'promise' then
    for m in select user_id, minutes from challenge_members where challenge_id = c loop
      if m.minutes >= x.target_minutes then
        perform public.move_rockets(m.user_id, x.fee, 'Promise kept: stake returned');
      elsif x.friend is not null then
        perform public.move_rockets(x.friend, x.fee, 'A friend missed their promise — their stake is yours');
      end if;
    end loop;
  elsif losers = 0 then
    bonus := least(x.fee, public.challenge_max_bonus(x.target_minutes));
    for m in select user_id from challenge_members where challenge_id = c loop
      perform public.move_rockets(m.user_id, x.fee + bonus, 'Everyone finished ' || x.title || ' — fee back + ' || bonus || ' bonus!');
    end loop;
  elsif winners > 0 then
    pot := losers * x.fee;
    share := pot / winners;
    for m in select user_id from challenge_members where challenge_id = c and minutes >= x.target_minutes loop
      perform public.move_rockets(m.user_id, x.fee + share, 'You finished ' || x.title || ' — fee back + ' || share || ' won');
    end loop;
  end if;
  update challenges set status = 'settled' where id = c;
end;
$$;

revoke all on function public.create_challenge(uuid, text, int, int, timestamptz, timestamptz), public.create_promise(uuid, int, int, timestamptz),
  public.join_challenge(uuid), public.leave_challenge(uuid), public.cancel_challenge(uuid),
  public.report_challenge(uuid, int), public.settle_challenge(uuid) from public, anon;
grant execute on function public.create_challenge(uuid, text, int, int, timestamptz, timestamptz), public.create_promise(uuid, int, int, timestamptz),
  public.join_challenge(uuid), public.leave_challenge(uuid), public.cancel_challenge(uuid),
  public.report_challenge(uuid, int), public.settle_challenge(uuid) to authenticated;

grant execute on function public.challenge_min_minutes(), public.challenge_min_fee(int), public.challenge_max_bonus(int) to authenticated;

-- Names of the people in open-to-all challenges (they may not be your friends): just the username
create or replace function public.challenge_names(ids uuid[])
returns table (id uuid, name text) language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name) from profiles p
  where public.is_approved() and p.id = any(ids)
    and exists (select 1 from challenge_members m join challenges x on x.id = m.challenge_id
                where m.user_id = p.id and x.kind = 'group' and x.group_id is null);
$$;
revoke all on function public.challenge_names(uuid[]) from public, anon;
grant execute on function public.challenge_names(uuid[]) to authenticated;
