-- 014_feed_comments_reshare.sql
-- Adds (1) comments + replies on feed posts and (2) reshare-to-community
-- with credit to the original poster.
-- Run once in Supabase Dashboard -> SQL Editor -> New query -> Run.

-- ---------- Comments (threaded) ----------
create table if not exists public.feed_comments (
  id uuid primary key default gen_random_uuid(),
  -- 'activity' = a shared activity (activities.id)
  -- 'post'     = a standalone post (community_posts.id)
  post_kind text not null check (post_kind in ('activity', 'post')),
  post_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- Set when this comment is a reply to a specific other comment.
  parent_id uuid references public.feed_comments(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists feed_comments_post_idx on public.feed_comments (post_kind, post_id, created_at);
create index if not exists feed_comments_parent_idx on public.feed_comments (parent_id);

alter table public.feed_comments enable row level security;

drop policy if exists "feed_comments_select" on public.feed_comments;
create policy "feed_comments_select" on public.feed_comments
  for select to authenticated using (true);

drop policy if exists "feed_comments_insert" on public.feed_comments;
create policy "feed_comments_insert" on public.feed_comments
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "feed_comments_delete" on public.feed_comments;
create policy "feed_comments_delete" on public.feed_comments
  for delete to authenticated using (auth.uid() = user_id);

-- ---------- Reshare to community ----------
-- A reshare is a normal community_posts row that also remembers who
-- originally posted it. A reshared activity may have no photo/video,
-- so media must be allowed to be empty.
alter table public.community_posts alter column media_url drop not null;
alter table public.community_posts alter column media_type drop not null;

alter table public.community_posts add column if not exists original_kind text;
alter table public.community_posts add column if not exists original_id uuid;
alter table public.community_posts add column if not exists original_user_id uuid;
alter table public.community_posts add column if not exists original_caption text;
