-- Orbit — Level Pass rewards grow with the level. Run after wallet.sql. Safe to re-run.
--   levels 1–9: 25 rockets · from level 10: 75 · from level 20: 125 · then +50 with every further ten levels
--   (30 → 175, 40 → 225, 50 → 275, 60 → 325). Levels already claimed keep what they paid.
create or replace function public.level_reward(lvl int) returns int language sql immutable as $$
  select case when lvl < 10 then 25 else 75 + 50 * (lvl / 10 - 1) end
$$;

create or replace function public.claim_level(lvl int)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); w wallets;
begin
  select * into w from wallets where user_id = me for update;
  if w.user_id is null then raise exception 'Your wallet isn''t ready yet'; end if;
  if lvl < 1 or lvl > 60 or lvl > coalesce((select level from profiles where id = me), 1) then raise exception 'You haven''t reached that level yet'; end if;
  if lvl = any(w.levels_claimed) or exists (select 1 from rocket_gifts where user_id = me and ref = 'level:' || lvl) then return; end if;
  insert into rocket_gifts (user_id, amount, reason, ref) values (me, public.level_reward(lvl), 'Level ' || lvl || ' reward', 'level:' || lvl);
  if lvl % 10 = 0 then insert into owned_planets (user_id, planet_id, price) values (me, 'lv_t' || (lvl / 10), 0); end if;
  perform public.wallet_sync_profile(me);
end;
$$;
revoke all on function public.level_reward(int), public.claim_level(int) from public, anon;
grant execute on function public.level_reward(int), public.claim_level(int) to authenticated;
