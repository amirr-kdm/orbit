-- Rocket gifts from the owner. Each user's app adds unclaimed gifts to its balance once.
create table if not exists public.rocket_gifts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount int not null check (amount between -100000 and 100000 and amount <> 0),
  created_at timestamptz not null default now()
);
alter table public.rocket_gifts enable row level security;
drop policy if exists "own gifts" on public.rocket_gifts;
create policy "own gifts" on public.rocket_gifts for select using (user_id = auth.uid());
revoke insert, update, delete on public.rocket_gifts from anon, authenticated;
grant select on public.rocket_gifts to authenticated;

create or replace function public.admin_gift_rockets(uid uuid, amount int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  insert into rocket_gifts (user_id, amount) values (uid, amount);
end;
$$;
revoke all on function public.admin_gift_rockets(uuid, int) from public, anon;
grant execute on function public.admin_gift_rockets(uuid, int) to authenticated;
