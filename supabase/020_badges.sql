-- 020_badges.sql
-- Earned badges for VITRAX. Run once in Supabase SQL Editor. Safe to re-run.
--
-- Badges are awarded by the SERVER (function evaluate_my_badges), never by
-- the app, so nobody can give themselves a badge. The app just asks
-- "did I earn anything new?" after a ride, a challenge, a hazard action, or
-- when it opens, and shows a celebration for what comes back.

create table if not exists public.user_badges (
  user_id    uuid not null references auth.users(id) on delete cascade,
  badge_key  text not null,
  tier       text not null check (tier in ('bronze','silver','gold','elite')),
  value      numeric,
  earned_at  timestamptz not null default now(),
  primary key (user_id, badge_key, tier)
);

alter table public.user_badges enable row level security;
drop policy if exists "own badges select" on public.user_badges;
create policy "own badges select" on public.user_badges
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "badges readable by everyone" on public.user_badges;
create policy "badges readable by everyone" on public.user_badges
  for select to authenticated using (true);
-- no insert/update/delete policies: only the functions below can write.

drop policy if exists admin_delete_user_badges on public.user_badges;
create policy admin_delete_user_badges on public.user_badges
  for delete to authenticated using (public.is_admin());

-- ------------------------------------------------------------ the numbers
create or replace function public.badge_stats(uid uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    -- real rides only (ignores accidental 0-distance saves)
    'first_steps', (select count(*) from public.activities a where a.user_id = uid and a.distance_km >= 0.2),
    'distance',    (select coalesce(floor(sum(a.distance_km)), 0) from public.activities a where a.user_id = uid),
    'challenger',  (select count(*) from public.challenge_participants p where p.user_id = uid and p.completed_at is not null),
    -- longest run of consecutive days (Philippine time) with a real activity
    'streak',      (select coalesce(max(n), 0) from (
                      select count(*) n from (
                        select d, d - (row_number() over (order by d))::int as grp from (
                          select distinct (a.started_at at time zone 'Asia/Manila')::date d
                          from public.activities a where a.user_id = uid and a.distance_km >= 0.2
                        ) days
                      ) g group by grp) runs),
    -- hazards YOU reported that someone else confirmed are real
    'route_pioneer', (select count(distinct v.hazard_id) from public.hazard_verifications v
                      join public.hazards h on h.id = v.hazard_id where h.user_id = uid),
    -- times YOU helped confirm a hazard was cleared
    'safety_warden', (select count(*) from public.hazard_clear_confirmations c where c.user_id = uid)
  )
$$;
revoke all on function public.badge_stats(uuid) from public;

create or replace function public.my_badge_stats() returns jsonb
language sql stable security definer set search_path = public as $$
  select public.badge_stats(auth.uid())
$$;
revoke all on function public.my_badge_stats() from public;
grant execute on function public.my_badge_stats() to authenticated;

-- ------------------------------------------------------- award what's due
create or replace function public.evaluate_my_badges()
returns table (badge_key text, tier text, earned_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  stats jsonb;
  defs constant jsonb := '{
    "first_steps":   [1, 10, 25, 50],
    "distance":      [10, 50, 150, 500],
    "challenger":    [1, 3, 5, 10],
    "streak":        [3, 7, 14, 30],
    "route_pioneer": [1, 5, 15, 30],
    "safety_warden": [1, 5, 15, 30]
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
