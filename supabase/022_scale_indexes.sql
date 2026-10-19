-- 022_scale_indexes.sql
-- Speeds up the paged feed and the nearby-hazard lookup as data grows.
-- Run once in the Supabase SQL Editor. Safe to re-run.

create index if not exists hazards_shared_lat_lng_idx
  on public.hazards (lat, lng) where shared;

create index if not exists activities_shared_created_idx
  on public.activities (created_at desc) where shared;

create index if not exists community_posts_created_idx
  on public.community_posts (created_at desc);

create index if not exists feed_comments_post_idx
  on public.feed_comments (post_kind, post_id);
