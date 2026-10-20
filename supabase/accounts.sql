-- Orbit — Accounts (email + username + password), owner approval, cloud backup and the admin panel
-- Run once in the Supabase SQL editor after schema.sql and groups.sql. Safe to re-run.
-- Also turn OFF "Confirm email" in Authentication → Sign In / Providers → Email (sign-up needs no code).

-- Profile fields for accounts
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists approved boolean not null default false;
alter table public.profiles add column if not exists is_admin boolean not null default false;
alter table public.profiles add column if not exists requested_at timestamptz not null default now();
create unique index if not exists profiles_username_key on public.profiles (lower(username));

-- People already using Orbit before accounts existed keep working
update public.profiles set approved = true where approved = false and created_at < now() - interval '1 minute';

-- The owner (developer) is the only admin. Change this name if you self-host.
update public.profiles set is_admin = true, username = 'Amirreza' where name = 'Amirreza' and not exists (select 1 from public.profiles where is_admin);

-- Users may only write their own harmless fields; approval and admin can't be set from the app
revoke insert, update on public.profiles from authenticated;
grant insert (id, name, username) on public.profiles to authenticated;
alter table public.profiles add column if not exists streak int;  -- null until their app reports it
grant update (name, username, level, avatar, galaxy, rockets, streak) on public.profiles to authenticated;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and is_admin);
$$;

create or replace function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and approved);
$$;

-- The owner sees everyone (for the admin panel)
create or replace function public.can_see(other uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select other = auth.uid() or public.is_admin() or public.is_friend(other) or public.shares_group(other)
      or exists (select 1 from friend_requests
                 where (from_user = auth.uid() and to_user = other) or (from_user = other and to_user = auth.uid()));
$$;

-- Is a username free? (asked before / while signing up)
drop function if exists public.username_available(text);
create or replace function public.username_available(wanted text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles p where lower(p.username) = lower(trim(wanted)));
$$;

-- Only approved people share stats and live status
drop policy if exists "stats write" on public.daily_stats;
create policy "stats write" on public.daily_stats for all to authenticated
  using (user_id = auth.uid() and public.is_approved()) with check (user_id = auth.uid() and public.is_approved());
drop policy if exists "live write" on public.live_status;
create policy "live write" on public.live_status for all to authenticated
  using (user_id = auth.uid() and public.is_approved()) with check (user_id = auth.uid() and public.is_approved());

-- Cloud backup of each user's whole data file (only they can read it)
create table if not exists public.user_data (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  device text
);
alter table public.user_data enable row level security;
drop policy if exists "own data" on public.user_data;
create policy "own data" on public.user_data for all to authenticated
  using (user_id = auth.uid() and public.is_approved()) with check (user_id = auth.uid() and public.is_approved());
grant select, insert, update on public.user_data to authenticated;
revoke all on public.user_data from anon;

-- Social features need an approved account
create or replace function public.add_friend(code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  them public.profiles;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  select * into them from profiles where friend_code = upper(trim(code));
  if them.id is null then raise exception 'No one has the code %', upper(trim(code)); end if;
  if them.id = me then raise exception 'That is your own code'; end if;
  insert into friendships (user_id, friend_id) values (me, them.id), (them.id, me) on conflict do nothing;
  return them.name;
end;
$$;

create or replace function public.create_group(group_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  insert into groups (name, owner) values (trim(group_name), me) returning id into g;
  insert into group_members (group_id, user_id) values (g, me);
  return g;
end;
$$;

create or replace function public.join_group(group_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g public.groups;
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  select * into g from groups where code = upper(trim(group_code));
  if g.id is null then raise exception 'No group has the code %', upper(trim(group_code)); end if;
  insert into group_members (group_id, user_id) values (g.id, me) on conflict do nothing;
  return g.name;
end;
$$;

create or replace function public.send_friend_request(other uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
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

-- ---------- Admin (the owner) ----------

-- Everyone with an account: for the admin panel
create or replace function public.admin_users()
returns table (id uuid, name text, username text, email text, approved boolean, is_admin boolean,
               requested_at timestamptz, last_backup timestamptz, last_studied date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query
    select p.id, p.name, p.username, u.email::text, p.approved, p.is_admin, p.requested_at,
           (select d.updated_at from user_data d where d.user_id = p.id),
           (select max(s.day) from daily_stats s where s.user_id = p.id and s.minutes > 0)
    from profiles p left join auth.users u on u.id = p.id
    order by p.approved, p.requested_at desc;
end;
$$;

create or replace function public.approve_user(uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  update profiles set approved = true where id = uid;
end;
$$;

-- Turn down a sign-up: their profile is removed (they can't use the app)
create or replace function public.reject_user(uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if uid = auth.uid() then raise exception 'You can''t remove yourself'; end if;
  delete from profiles where id = uid;
end;
$$;

-- Give someone who forgot their password a new temporary one (passwords are never stored readably)
create or replace function public.admin_reset_password(uid uuid, new_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if char_length(new_password) < 6 then raise exception 'Password must be at least 6 characters'; end if;
  update auth.users set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf')), updated_at = now()
  where id = uid;
end;
$$;

revoke all on function public.admin_users(), public.approve_user(uuid), public.reject_user(uuid),
  public.admin_reset_password(uuid, text) from public, anon;
grant execute on function public.admin_users(), public.approve_user(uuid), public.reject_user(uuid),
  public.admin_reset_password(uuid, text), public.is_admin(), public.is_approved() to authenticated;
grant execute on function public.username_available(text) to anon, authenticated;
