-- Fight Club's small leaderboard: who has won the most World Bosses (most damage on a defeated boss).
-- Safe to re-run.
create or replace function public.boss_slayers()
returns table (id uuid, name text, avatar text, wins int)
language sql stable security definer set search_path = public as $$
  select p.id, coalesce(p.username, p.name), p.avatar, count(*)::int
  from boss_fighters f
  join bosses x on x.id = f.boss_id and x.world_week is not null and x.status = 'defeated'
  join profiles p on p.id = f.user_id
  where public.is_approved() and p.approved and f.damage > 0
    and f.damage = (select max(m.damage) from boss_fighters m where m.boss_id = x.id)
  group by p.id, p.username, p.name, p.avatar
  order by 4 desc, 2
  limit 10;
$$;
revoke all on function public.boss_slayers() from public, anon;
grant execute on function public.boss_slayers() to authenticated;
