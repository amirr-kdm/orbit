-- Orbit — Challenges v2. Run after challenges.sql, wallet.sql and gifts.sql. Safe to re-run.
--
-- * A challenge is public (anyone can join), private (needs an invite code) or for one group (its members only).
-- * Anyone allowed can join at any time until the end. A late joiner's study counts from the moment they joined.
-- * Admin: gift rockets to every member at once.
-- * New Orbiters start with 800 rockets (members who signed up on or after 2026-10-28).
-- Older apps keep working: create_challenge / join_challenge / report_challenge keep their signatures.

alter table public.challenges add column if not exists visibility text not null default 'public';
alter table public.challenges add column if not exists invite_code text;
alter table public.challenges drop constraint if exists challenges_visibility_check;
alter table public.challenges add constraint challenges_visibility_check check (visibility in ('public', 'private', 'group'));
create unique index if not exists challenges_invite_code on public.challenges (invite_code) where invite_code is not null;
update public.challenges set visibility = 'group' where group_id is not null and visibility = 'public';

-- Who can see a challenge: public ones (every member), its group, and anyone inside a private one
create or replace function public.can_see_challenge(c uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from challenges x where x.id = c and (
    x.creator = auth.uid() or x.friend = auth.uid()
    or (x.kind = 'group' and x.visibility = 'public' and x.group_id is null and public.is_approved())
    or (x.group_id is not null and public.in_group(x.group_id))
    or exists (select 1 from challenge_members m where m.challenge_id = x.id and m.user_id = auth.uid())));
$$;

-- Joining (shared): open until the end, pay the fee
create or replace function public.join_challenge_as_me(x challenges)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if x.status <> 'open' or now() >= x.ends_at then raise exception 'This challenge is over'; end if;
  if exists (select 1 from challenge_members where challenge_id = x.id and user_id = me) then return; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  perform public.check_balance(me, x.fee);
  insert into challenge_members (challenge_id, user_id) values (x.id, me);
  perform public.move_rockets(me, -x.fee, 'Entry fee: ' || x.title);
  perform public.wallet_sync_profile(me);
end;
$$;
revoke all on function public.join_challenge_as_me(challenges) from public, anon, authenticated;

create or replace function public.join_challenge(c uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); x challenges;
begin
  select * into x from challenges where id = c for update;
  if x.id is null or x.kind <> 'group' then raise exception 'Challenge not found'; end if;
  if not ((x.visibility = 'public' and x.group_id is null)
          or (x.group_id is not null and public.in_group(x.group_id))
          or exists (select 1 from challenge_members where challenge_id = c and user_id = me)) then
    raise exception 'This challenge needs an invite code';
  end if;
  perform public.join_challenge_as_me(x);
end;
$$;

create or replace function public.join_challenge_by_code(code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare x challenges;
begin
  select * into x from challenges where invite_code = upper(trim(code)) and kind = 'group' for update;
  if x.id is null then raise exception 'No challenge has that code'; end if;
  perform public.join_challenge_as_me(x);
  return x.id;
end;
$$;

-- A late joiner's minutes count from when they joined
create or replace function public.report_challenge(c uuid, minutes int)
returns void language plpgsql security definer set search_path = public as $$
declare x challenges; cap int; since timestamptz;
begin
  select * into x from challenges where id = c;
  if x.id is null or x.status <> 'open' or now() < x.starts_at or now() > x.ends_at + public.challenge_grace() then return; end if;
  select greatest(x.starts_at, joined_at) into since from challenge_members where challenge_id = c and user_id = auth.uid();
  if since is null then return; end if;
  cap := greatest(0, ceil(extract(epoch from (least(now(), x.ends_at) - since)) / 60));
  update challenge_members set minutes = greatest(challenge_members.minutes, least(report_challenge.minutes, cap))
    where challenge_id = c and user_id = auth.uid();
end;
$$;

create or replace function public.create_challenge_v2(title text, target_minutes int, fee int, starts_at timestamptz, ends_at timestamptz,
                                                      visibility text default 'public', grp uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c uuid; s timestamptz := greatest(starts_at, now()); code text;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if visibility not in ('public', 'private', 'group') then raise exception 'Unknown challenge type'; end if;
  if visibility = 'group' and (grp is null or not public.in_group(grp)) then raise exception 'You are not in that group'; end if;
  if target_minutes < public.challenge_min_minutes() then raise exception 'A challenge is at least 4 hours of study'; end if;
  if fee < public.challenge_min_fee(target_minutes) then
    raise exception 'The entry fee is at least % rockets for this goal', public.challenge_min_fee(target_minutes);
  end if;
  if ends_at <= s then raise exception 'The end must be after the start'; end if;
  perform public.check_balance(me, fee);
  if visibility = 'private' then
    loop
      code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
      exit when not exists (select 1 from challenges x where x.invite_code = code);
    end loop;
  end if;
  insert into challenges (kind, group_id, creator, title, target_minutes, fee, starts_at, ends_at, visibility, invite_code)
    values ('group', case when visibility = 'group' then grp end, me, trim(title), target_minutes, fee, s, ends_at, visibility, code)
    returning id into c;
  insert into challenge_members (challenge_id, user_id) values (c, me);
  perform public.move_rockets(me, -fee, 'Entry fee: ' || trim(title));
  perform public.wallet_sync_profile(me);
  return c;
end;
$$;

-- Names, planets and levels of the people in challenges I can see (they may not be my friends)
create or replace function public.challenge_people(ids uuid[])
returns table (id uuid, name text, avatar text, level int) language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name), p.avatar, p.level from profiles p
  where public.is_approved() and p.id = any(ids)
    and exists (select 1 from challenge_members m where m.user_id = p.id and public.can_see_challenge(m.challenge_id));
$$;

-- Admin: the same gift for every member at once
create or replace function public.admin_gift_all(amount int, reason text default null)
returns int language plpgsql security definer set search_path = public as $$
declare u record; n int := 0;
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if amount < 1 or amount > 100000 then raise exception 'Between 1 and 100000 rockets'; end if;
  for u in select id from profiles where approved loop
    insert into rocket_gifts (user_id, amount, reason) values (u.id, amount, nullif(trim(coalesce(reason, '')), ''));
    perform public.wallet_sync_profile(u.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- New Orbiters (signed up on or after 2026-10-28) start with at least 800 rockets, whatever their app says
create or replace function public.wallet_start(balance int, planets jsonb, levels int[], refunds_used int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p jsonb; start_rockets int;
begin
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if exists (select 1 from wallets where user_id = me) then return; end if;
  start_rockets := case when (select created_at from profiles where id = me) >= timestamptz '2026-10-28 00:00+00'
                        then greatest(balance, 800) else greatest(0, balance) end;
  insert into wallets (user_id, opening, levels_claimed) values (me, start_rockets, coalesce(levels, '{}'));
  for p in select * from jsonb_array_elements(coalesce(planets, '[]')) loop
    insert into owned_planets (user_id, planet_id, price, bought_at)
      values (me, p->>'planetID', coalesce((p->>'price')::int, 0), coalesce((p->>'date')::timestamptz, now()));
  end loop;
  for i in 1..least(3, greatest(0, refunds_used)) loop insert into refunds (user_id, planet_id) values (me, 'before-wallet'); end loop;
  update profiles set rockets = start_rockets where id = me;
end;
$$;

revoke all on function public.join_challenge(uuid), public.join_challenge_by_code(text), public.report_challenge(uuid, int),
  public.create_challenge_v2(text, int, int, timestamptz, timestamptz, text, uuid), public.challenge_people(uuid[]),
  public.admin_gift_all(int, text), public.wallet_start(int, jsonb, int[], int) from public, anon;
grant execute on function public.join_challenge(uuid), public.join_challenge_by_code(text), public.report_challenge(uuid, int),
  public.create_challenge_v2(text, int, int, timestamptz, timestamptz, text, uuid), public.challenge_people(uuid[]),
  public.admin_gift_all(int, text), public.wallet_start(int, jsonb, int[], int) to authenticated;
