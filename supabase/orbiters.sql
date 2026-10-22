-- Orbit — All Orbiters: a weekly leaderboard of every member, and friend requests to anyone.
-- Run after accounts.sql and groups.sql. Safe to re-run.
-- Only the username, planet avatar, level and the week's study minutes are shared here —
-- never what someone studies, their subjects or what they're studying right now (that stays for friends).

create or replace function public.orbiters_board(week_start date)
returns table (id uuid, name text, avatar text, level int, minutes int)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name), p.avatar, p.level,
         coalesce((select sum(s.minutes) from daily_stats s
                   where s.user_id = p.id and s.day >= week_start and s.day < week_start + 7), 0)::int
  from profiles p
  where public.is_approved() and p.approved
  order by 5 desc, 2;
$$;
revoke all on function public.orbiters_board(date) from public, anon;
grant execute on function public.orbiters_board(date) to authenticated;

-- Ask any Orbit member to be friends. If they already asked you, you become friends.
create or replace function public.send_friend_request(other uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if not public.is_approved() then raise exception 'Your account is waiting for approval'; end if;
  if other = me then raise exception 'That is you'; end if;
  if not exists (select 1 from profiles where id = other and approved) then raise exception 'No such member'; end if;
  if public.is_friend(other) then return 'friends'; end if;
  if exists (select 1 from friend_requests where from_user = other and to_user = me) then
    insert into friendships (user_id, friend_id) values (me, other), (other, me) on conflict do nothing;
    delete from friend_requests where (from_user = other and to_user = me) or (from_user = me and to_user = other);
    return 'friends';
  end if;
  insert into friend_requests (from_user, to_user) values (me, other) on conflict do nothing;
  return 'sent';
end;
$$;
