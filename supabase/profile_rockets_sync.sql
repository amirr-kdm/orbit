-- profiles.rockets is a copy of the real balance (wallet_balance) that the leaderboard, friends list and
-- check_balance read. Challenge payouts, boss prizes and gifts only wrote to rocket_gifts, so the copy went stale
-- (e.g. faezebg: real balance 1141, copy 41, so she could not join challenges). Safe to run more than once.

-- 1) Every new ledger row refreshes the owner's copy, whoever inserted it
create or replace function public.rocket_gifts_sync_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.wallet_sync_profile(new.user_id);
  return null;
end;
$$;
revoke all on function public.rocket_gifts_sync_profile() from public, anon, authenticated;

drop trigger if exists rocket_gifts_sync_profile on public.rocket_gifts;
create trigger rocket_gifts_sync_profile
  after insert on public.rocket_gifts
  for each row execute function public.rocket_gifts_sync_profile();

-- 2) Fix everyone whose copy is already stale
update public.profiles p
set rockets = public.wallet_balance(p.id)
where public.wallet_balance(p.id) is not null
  and p.rockets is distinct from public.wallet_balance(p.id);
