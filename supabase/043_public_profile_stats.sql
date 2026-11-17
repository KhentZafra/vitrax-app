-- 043: stats, level and rank for the "visit profile" screen.
-- Run once in the Supabase SQL Editor after 042. Safe to re-run.
--
-- Only SHARED activities are counted, so nothing a person kept private leaks.
-- Level and rank come from badge tiers (bronze 1 ... elite 6, best tier per badge).
create or replace function public.public_profile_stats(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_km numeric := 0; n int := 0;
  ride_km numeric := 0; ride_n int := 0; run_km numeric := 0; run_n int := 0;
  joined int := 0; done int := 0;
  my_pts int := 0; pts_rank int := 1; pts_total int := 0;
  my_km_rank int := null; km_total int := 0;
begin
  if auth.uid() is null then return null; end if;

  select coalesce(sum(distance_km), 0), count(*),
         coalesce(sum(distance_km) filter (where type = 'ride'), 0), count(*) filter (where type = 'ride'),
         coalesce(sum(distance_km) filter (where type <> 'ride'), 0), count(*) filter (where type <> 'ride')
    into v_km, n, ride_km, ride_n, run_km, run_n
    from public.activities
   where user_id = p_user and coalesce(shared, false) and distance_km >= 0.2;

  select count(*), count(completed_at) into joined, done
    from public.challenge_participants where user_id = p_user;

  with best as (
    select user_id, badge_key,
           max(case tier when 'bronze' then 1 when 'silver' then 2 when 'gold' then 3
                         when 'platinum' then 4 when 'diamond' then 5 when 'elite' then 6 else 0 end) p
      from public.user_badges group by user_id, badge_key),
  pts as (select user_id, sum(p)::int as pts from best group by user_id)
  select coalesce((select pts from pts where user_id = p_user), 0),
         (select count(*) + 1 from pts where pts > coalesce((select pts from pts where user_id = p_user), 0)),
         (select count(*) from pts)
    into my_pts, pts_rank, pts_total;

  with k as (
    select user_id, sum(distance_km) as km from public.activities
     where coalesce(shared, false) and distance_km >= 0.2 group by user_id)
  select (select count(*) + 1 from k where k.km > v_km), (select count(*) from k)
    into my_km_rank, km_total;
  if n = 0 then my_km_rank := null; end if;

  return jsonb_build_object(
    'total_km', round(v_km, 1), 'activities', n,
    'ride_km', round(ride_km, 1), 'ride_count', ride_n,
    'run_km', round(run_km, 1), 'run_count', run_n,
    'challenges_joined', joined, 'challenges_completed', done,
    'badge_points', my_pts, 'points_rank', pts_rank, 'points_total', greatest(pts_total, 1),
    'km_rank', my_km_rank, 'km_total', km_total);
end $$;
grant execute on function public.public_profile_stats(uuid) to authenticated;
