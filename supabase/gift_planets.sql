-- Orbit — planets that can't be bought, only given by the admin (Flag Planet). Safe to re-run.

-- Flag Planet is no longer for sale: no price means buy_planet refuses it
delete from public.store_prices where planet_id = 's6_flagplanet';

-- Admin: give a planet to a member (it lands on their "Your Store Planets" shelf, price 0 so it can't be refunded)
create or replace function public.admin_gift_planet(uid uuid, planet text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if planet is null or length(planet) = 0 then raise exception 'Pick a planet'; end if;
  if not exists (select 1 from profiles where id = uid and approved) then raise exception 'No such member'; end if;
  insert into owned_planets (user_id, planet_id, price) values (uid, planet, 0);
end;
$$;
revoke all on function public.admin_gift_planet(uuid, text) from public, anon;
grant execute on function public.admin_gift_planet(uuid, text) to authenticated;
