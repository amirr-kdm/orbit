-- The Level Pass goes up to level 60, but profiles.level was limited to 50: syncing the profile (and claiming
-- Level Pass rewards, which check the profile's level) failed for anyone above level 50. Raise the limit to 60.
alter table public.profiles drop constraint if exists profiles_level_check;
alter table public.profiles add constraint profiles_level_check check (level >= 1 and level <= 60);
