-- 034_route_likes_feed_split.sql
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- 1) Sharing a route and posting to the community feed are now separate:
--      activities.shared          = visible in the Routes tab (shared route)
--      activities.shared_to_feed  = also posted on the Community feed
--    Existing shared activities that have a caption or photo were deliberate
--    feed posts, so they stay on the feed; plain shared routes do not.
-- 2) Likes on shared routes (route_likes) and a "Crowd Favorite" badge.

alter table public.activities add column if not exists shared_to_feed boolean not null default false;

update public.activities
   set shared_to_feed = true
 where shared = true and shared_to_feed = false
   and (coalesce(caption, '') <> '' or photo_url is not null);

create index if not exists activities_feed_created_idx
  on public.activities (created_at desc) where shared_to_feed;

-- ---------- route likes ----------
create table if not exists public.route_likes (
  route_id   uuid not null references public.activities(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (route_id, user_id)
);
create index if not exists route_likes_route_idx on public.route_likes (route_id);

alter table public.route_likes enable row level security;

drop policy if exists "Anyone signed in can see route likes" on public.route_likes;
create policy "Anyone signed in can see route likes" on public.route_likes
  for select to authenticated using (true);

-- You can like a shared route that is not your own.
drop policy if exists "Users can like routes as themselves" on public.route_likes;
create policy "Users can like routes as themselves" on public.route_likes
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.activities a
                where a.id = route_id and a.shared and a.user_id <> auth.uid())
  );

drop policy if exists "Users can remove their own route like" on public.route_likes;
create policy "Users can remove their own route like" on public.route_likes
  for delete to authenticated using (user_id = auth.uid());

-- ---------- badge: Crowd Favorite (likes on your shared routes) ----------
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
    'early_bird',  (select count(*) from public.activities a
                     where a.user_id = uid and a.distance_km >= 0.2
                       and extract(hour from (a.started_at at time zone 'Asia/Manila')) < 7),
    'endurance',   (select coalesce(floor(max(a.distance_km)), 0) from public.activities a where a.user_id = uid),
    'hazard_spotter', (select count(*) from public.hazards h where h.user_id = uid and h.shared),
    'trail_sharer', (select count(*) from public.activities a where a.user_id = uid and a.shared),
    'community_voice', (select count(*) from public.community_posts p where p.user_id = uid)
                     + (select count(*) from public.feed_comments c where c.user_id = uid),
    -- new in 034
    'route_likes', (select count(*) from public.route_likes l
                    join public.activities a on a.id = l.route_id
                    where a.user_id = uid and a.shared)
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
    "community_voice": [1, 10, 25, 50, 100, 250],
    "route_likes": [1, 5, 15, 30, 60, 100]
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
