-- 023_more_badges.sql
-- Adds 5 more badges (11 in total). Run once in the Supabase SQL Editor. Safe to re-run.
-- Replaces badge_stats and evaluate_my_badges from 020_badges.sql; nothing already earned is lost.
--
-- New badges (Bronze / Silver / Gold / Elite):
--   early_bird       real activities started before 7 AM Manila time     1 / 5 / 15 / 30
--   endurance        longest single activity, in km                      10 / 25 / 50 / 100
--   hazard_spotter   hazards you reported that are shared                1 / 10 / 25 / 50
--   trail_sharer     activities you shared with the community            1 / 5 / 15 / 30
--   community_voice  community posts plus comments you wrote             1 / 10 / 25 / 50

create or replace function public.badge_stats(uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'first_steps', (select count(*) from public.activities a where a.user_id = uid and a.distance_km >= 0.2),
    'distance',    (select coalesce(floor(sum(a.distance_km)), 0) from public.activities a where a.user_id = uid),
    'challenger',  (select count(*) from public.challenge_participants p where p.user_id = uid and p.completed_at is not null),
    'streak',      (select coalesce(max(n), 0) from (
                      select count(*) n from (
                        select d, d - (row_number() over (order by d))::int as grp from (
                          select distinct (a.started_at at time zone 'Asia/Manila')::date d
                          from public.activities a where a.user_id = uid and a.distance_km >= 0.2
                        ) days
                      ) g group by grp) runs),
    'route_pioneer', (select count(distinct v.hazard_id) from public.hazard_verifications v
                      join public.hazards h on h.id = v.hazard_id where h.user_id = uid),
    'safety_warden', (select count(*) from public.hazard_clear_confirmations c where c.user_id = uid),
    -- new in 023
    'early_bird',  (select count(*) from public.activities a
                     where a.user_id = uid and a.distance_km >= 0.2
                       and extract(hour from (a.started_at at time zone 'Asia/Manila')) < 7),
    'endurance',   (select coalesce(floor(max(a.distance_km)), 0) from public.activities a where a.user_id = uid),
    'hazard_spotter', (select count(*) from public.hazards h where h.user_id = uid and h.shared),
    'trail_sharer', (select count(*) from public.activities a where a.user_id = uid and a.shared),
    'community_voice', (select count(*) from public.community_posts p where p.user_id = uid)
                     + (select count(*) from public.feed_comments c where c.user_id = uid)
  )
$$;
revoke all on function public.badge_stats(uuid) from public;

create or replace function public.evaluate_my_badges()
returns table (badge_key text, tier text, earned_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  stats jsonb;
  defs constant jsonb := '{
    "first_steps":     [1, 10, 25, 50],
    "distance":        [10, 50, 150, 500],
    "challenger":      [1, 3, 5, 10],
    "streak":          [3, 7, 14, 30],
    "route_pioneer":   [1, 5, 15, 30],
    "safety_warden":   [1, 5, 15, 30],
    "early_bird":      [1, 5, 15, 30],
    "endurance":       [10, 25, 50, 100],
    "hazard_spotter":  [1, 10, 25, 50],
    "trail_sharer":    [1, 5, 15, 30],
    "community_voice": [1, 10, 25, 50]
  }';
  tiers constant text[] := array['bronze','silver','gold','elite'];
  k text; v numeric; i int; got timestamptz;
begin
  if uid is null then return; end if;
  stats := public.badge_stats(uid);
  for k in select jsonb_object_keys(defs) loop
    v := coalesce((stats->>k)::numeric, 0);
    for i in 1 .. 4 loop
      if v >= (defs->k->>(i-1))::numeric then
        insert into public.user_badges (user_id, badge_key, tier, value)
        values (uid, k, tiers[i], v)
        on conflict do nothing
        returning user_badges.earned_at into got;
        if got is not null then
          badge_key := k; tier := tiers[i]; earned_at := got;
          return next;
          got := null;
        end if;
      end if;
    end loop;
  end loop;
end $$;
revoke all on function public.evaluate_my_badges() from public;
grant execute on function public.evaluate_my_badges() to authenticated;
