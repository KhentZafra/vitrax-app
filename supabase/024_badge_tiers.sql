-- 024_badge_tiers.sql
-- Six badge tiers instead of four:
--   Bronze -> Silver -> Gold -> Platinum -> Diamond -> Elite
-- Run once in the Supabase SQL Editor (after 023). Safe to re-run.
--
-- Badges are derived from your real activity, so this clears the stored
-- badge rows and lets the server award them again at the new thresholds the
-- next time each user opens the app or finishes something. (Do this before
-- the pilot so nobody keeps a tier earned under the old numbers.)

alter table public.user_badges drop constraint if exists user_badges_tier_check;
delete from public.user_badges;
alter table public.user_badges
  add constraint user_badges_tier_check
  check (tier in ('bronze','silver','gold','platinum','diamond','elite'));

create or replace function public.evaluate_my_badges()
returns table (badge_key text, tier text, earned_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  stats jsonb;
  defs constant jsonb := '{
    "first_steps": [1, 10, 25, 50, 100, 250],
    "distance": [10, 50, 150, 300, 600, 1000],
    "challenger": [1, 3, 5, 10, 20, 40],
    "streak": [3, 7, 14, 30, 60, 100],
    "route_pioneer": [1, 5, 15, 30, 60, 100],
    "safety_warden": [1, 5, 15, 30, 60, 100],
    "early_bird": [1, 5, 15, 30, 60, 100],
    "endurance": [10, 25, 50, 100, 150, 200],
    "hazard_spotter": [1, 10, 25, 50, 100, 250],
    "trail_sharer": [1, 5, 15, 30, 60, 100],
    "community_voice": [1, 10, 25, 50, 100, 250]
  }';
  tiers constant text[] := array['bronze','silver','gold','platinum','diamond','elite'];
  k text; v numeric; i int; got timestamptz;
begin
  if uid is null then return; end if;
  stats := public.badge_stats(uid);
  for k in select jsonb_object_keys(defs) loop
    v := coalesce((stats->>k)::numeric, 0);
    for i in 1 .. 6 loop
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
