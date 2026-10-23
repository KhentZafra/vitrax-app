-- 025_hazard_rate_limit.sql
-- Stops one account from flooding the map with fake or spam hazards:
-- at most 10 hazard reports per hour and 30 per day per user.
-- Admins and server-side jobs are not limited. Run once in the Supabase
-- SQL Editor. Safe to re-run.

create or replace function public.limit_hazard_rate() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  per_hour int;
  per_day int;
begin
  -- server jobs (no signed-in user) and admins are exempt
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;

  select count(*) into per_hour from public.hazards
   where user_id = new.user_id and reported_at > now() - interval '1 hour';
  if per_hour >= 10 then
    raise exception 'hazard_rate_limit: too many hazard reports in the last hour'
      using errcode = 'P0001';
  end if;

  select count(*) into per_day from public.hazards
   where user_id = new.user_id and reported_at > now() - interval '1 day';
  if per_day >= 30 then
    raise exception 'hazard_rate_limit: too many hazard reports today'
      using errcode = 'P0001';
  end if;

  return new;
end $$;

drop trigger if exists limit_hazard_rate on public.hazards;
create trigger limit_hazard_rate before insert on public.hazards
  for each row execute function public.limit_hazard_rate();

-- makes the "last hour" lookup fast
create index if not exists hazards_user_reported_idx
  on public.hazards (user_id, reported_at desc);
