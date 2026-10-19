-- Orbit — Groups and friend requests
-- Run once in the Supabase SQL editor after schema.sql. Safe to re-run.

-- A study group: anyone with its code can join
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  code text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  owner uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- A pending friend request (accepting turns it into a friendship)
create table if not exists public.friend_requests (
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);

-- Am I a member of group g?
create or replace function public.in_group(g uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = g and user_id = auth.uid());
$$;

-- Are we in a group together?
create or replace function public.shares_group(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members a join group_members b on a.group_id = b.group_id
    where a.user_id = auth.uid() and b.user_id = other);
$$;

-- Who can I see: myself, friends, people in my groups, and anyone with a pending request with me
create or replace function public.can_see(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select other = auth.uid() or public.is_friend(other) or public.shares_group(other)
      or exists (select 1 from friend_requests
                 where (from_user = auth.uid() and to_user = other) or (from_user = other and to_user = auth.uid()));
$$;

-- Create a group (you become its first member). Returns its id.
create or replace function public.create_group(group_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  insert into groups (name, owner) values (trim(group_name), me) returning id into g;
  insert into group_members (group_id, user_id) values (g, me);
  return g;
end;
$$;

-- Join a group by its code. Returns the group's name.
create or replace function public.join_group(group_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g public.groups;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into g from groups where code = upper(trim(group_code));
  if g.id is null then raise exception 'No group has the code %', upper(trim(group_code)); end if;
  insert into group_members (group_id, user_id) values (g.id, me) on conflict do nothing;
  return g.name;
end;
$$;

-- Leave a group; the last one out deletes it, and the owner role passes to the longest member
create or replace function public.leave_group(g uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  next_owner uuid;
begin
  delete from group_members where group_id = g and user_id = me;
  select user_id into next_owner from group_members where group_id = g order by joined_at limit 1;
  if next_owner is null then
    delete from groups where id = g;
  else
    update groups set owner = next_owner where id = g and owner = me;
  end if;
end;
$$;

-- Ask someone in one of your groups to be friends. If they already asked you, you become friends.
create or replace function public.send_friend_request(other uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if other = me then raise exception 'That is you'; end if;
  if public.is_friend(other) then return 'friends'; end if;
  if exists (select 1 from friend_requests where from_user = other and to_user = me) then
    insert into friendships (user_id, friend_id) values (me, other), (other, me) on conflict do nothing;
    delete from friend_requests where (from_user = other and to_user = me) or (from_user = me and to_user = other);
    return 'friends';
  end if;
  if not public.shares_group(other) then raise exception 'You can only ask people in your groups'; end if;
  insert into friend_requests (from_user, to_user) values (me, other) on conflict do nothing;
  return 'sent';
end;
$$;

-- Accept or decline a request someone sent you
create or replace function public.respond_friend_request(other uuid, accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if not exists (select 1 from friend_requests where from_user = other and to_user = me) then return; end if;
  if accept then
    insert into friendships (user_id, friend_id) values (me, other), (other, me) on conflict do nothing;
  end if;
  delete from friend_requests where (from_user = other and to_user = me) or (from_user = me and to_user = other);
end;
$$;

-- Withdraw a request you sent
create or replace function public.cancel_friend_request(other uuid)
returns void language sql security definer set search_path = public as $$
  delete from friend_requests where from_user = auth.uid() and to_user = other;
$$;

revoke all on function public.create_group(text), public.join_group(text), public.leave_group(uuid),
  public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean), public.cancel_friend_request(uuid)
  from public, anon;
grant execute on function public.create_group(text), public.join_group(text), public.leave_group(uuid),
  public.send_friend_request(uuid), public.respond_friend_request(uuid, boolean), public.cancel_friend_request(uuid),
  public.in_group(uuid), public.shares_group(uuid), public.can_see(uuid) to authenticated;

-- Row Level Security
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.friend_requests enable row level security;

drop policy if exists "groups read" on public.groups;
create policy "groups read" on public.groups for select to authenticated using (public.in_group(id));
drop policy if exists "groups rename" on public.groups;
create policy "groups rename" on public.groups for update to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());

drop policy if exists "members read" on public.group_members;
create policy "members read" on public.group_members for select to authenticated using (public.in_group(group_id));

drop policy if exists "requests read" on public.friend_requests;
create policy "requests read" on public.friend_requests for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid());

grant select on public.groups, public.group_members, public.friend_requests to authenticated;
grant update (name) on public.groups to authenticated;
revoke all on public.groups, public.group_members, public.friend_requests from anon;

-- Group members can see each other's profile, daily totals and live status
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated using (public.can_see(id));
drop policy if exists "stats read" on public.daily_stats;
create policy "stats read" on public.daily_stats for select to authenticated using (public.can_see(user_id));
drop policy if exists "live read" on public.live_status;
create policy "live read" on public.live_status for select to authenticated using (public.can_see(user_id));
