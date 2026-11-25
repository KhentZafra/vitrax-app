-- 050_delete_own_post.sql
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- Lets a person delete their OWN community post from the app (1.0.4).
-- UNDO: drop policy "Users delete own posts" on public.community_posts;

drop policy if exists "Users delete own posts" on public.community_posts;
create policy "Users delete own posts" on public.community_posts
  for delete to authenticated using (user_id = auth.uid());
