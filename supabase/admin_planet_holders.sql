-- Orbit — the admin can't give the same gift planet twice: it is refused if the member already owns it or has an unopened box with it.
create or replace function public.admin_planet_holders(planet text)
returns setof uuid language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  return query select user_id from owned_planets where planet_id = planet
               union select to_user from planet_gifts where planet_id = planet and opened_at is null;
end;
$$;
revoke all on function public.admin_planet_holders(text) from public, anon;
grant execute on function public.admin_planet_holders(text) to authenticated;

create or replace function public.admin_gift_planet(uid uuid, planet text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if planet is null or length(planet) = 0 then raise exception 'Pick a planet'; end if;
  if not exists (select 1 from profiles where id = uid and approved) then raise exception 'No such member'; end if;
  if exists (select 1 from owned_planets where user_id = uid and planet_id = planet)
     or exists (select 1 from planet_gifts where to_user = uid and planet_id = planet and opened_at is null) then
    raise exception 'They already have this planet';
  end if;
  insert into planet_gifts (from_user, to_user, planet_id, box, price) values (auth.uid(), uid, planet, 'balloon', 0);
end;
$$;
