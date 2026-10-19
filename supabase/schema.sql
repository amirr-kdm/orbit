-- Claude Schedule — Friends feature
-- Run once in the Supabase SQL editor. Safe to re-run.

-- Profiles: one per user, with a short code friends type to add you
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  friend_code text not null unique default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  created_at timestamptz not null default now()
);

-- Friendships are stored in both directions (a→b and b→a)
create table if not exists public.friendships (
  user_id uuid not null references public.profiles(id) on delete cascade,
  friend_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);

-- One row per user per day: only a summary, never the full schedule
create table if not exists public.daily_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  day date not null,
  minutes int not null default 0,
  todos_done int not null default 0,
  todos_total int not null default 0,
  subjects jsonb not null default '[]',
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- What someone is studying right now (null when idle)
create table if not exists public.live_status (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  studying text,
  started_at timestamptz,
  updated_at timestamptz not null default now()
);

-- Is `other` a friend of the signed-in user?
create or replace function public.is_friend(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where user_id = auth.uid() and friend_id = other);
$$;

-- Add a friend by code (both directions). Returns the friend's name.
create or replace function public.add_friend(code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  them public.profiles;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into them from profiles where friend_code = upper(trim(code));
  if them.id is null then raise exception 'No one has the code %', upper(trim(code)); end if;
  if them.id = me then raise exception 'That is your own code'; end if;
  insert into friendships (user_id, friend_id) values (me, them.id), (them.id, me)
    on conflict do nothing;
  return them.name;
end;
$$;

-- Remove a friend (both directions)
create or replace function public.remove_friend(friend uuid)
returns void language sql security definer set search_path = public as $$
  delete from friendships
  where (user_id = auth.uid() and friend_id = friend)
     or (user_id = friend and friend_id = auth.uid());
$$;

revoke all on function public.add_friend(text) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
grant execute on function public.add_friend(text) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.is_friend(uuid) to authenticated;

-- Row Level Security: you see yourself and your friends; you only write your own rows
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.daily_stats enable row level security;
alter table public.live_status enable row level security;

drop policy if exists "profiles read" on public.profiles;
drop policy if exists "profiles insert" on public.profiles;
drop policy if exists "profiles update" on public.profiles;
drop policy if exists "profiles delete" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_friend(id));
create policy "profiles insert" on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy "profiles update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy "profiles delete" on public.profiles for delete to authenticated
  using (id = auth.uid());

drop policy if exists "friendships read" on public.friendships;
create policy "friendships read" on public.friendships for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "stats read" on public.daily_stats;
drop policy if exists "stats write" on public.daily_stats;
create policy "stats read" on public.daily_stats for select to authenticated
  using (user_id = auth.uid() or public.is_friend(user_id));
create policy "stats write" on public.daily_stats for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "live read" on public.live_status;
drop policy if exists "live write" on public.live_status;
create policy "live read" on public.live_status for select to authenticated
  using (user_id = auth.uid() or public.is_friend(user_id));
create policy "live write" on public.live_status for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on public.profiles, public.daily_stats, public.live_status to authenticated;
grant select on public.friendships to authenticated;
revoke all on public.profiles, public.friendships, public.daily_stats, public.live_status from anon;

-- Galaxy feature: level, profile planet and galaxy layout shown to friends
alter table public.profiles add column if not exists level int not null default 1 check (level between 1 and 10);
alter table public.profiles add column if not exists avatar text;
alter table public.profiles add column if not exists galaxy jsonb not null default '{"systems": []}';

-- Levels now go up to 50
alter table public.profiles drop constraint if exists profiles_level_check;
alter table public.profiles add constraint profiles_level_check check (level between 1 and 50);

-- Store: everyone's rocket balance, shown to friends and group members
alter table public.profiles add column if not exists rockets int not null default 0;
