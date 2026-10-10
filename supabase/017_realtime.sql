-- 017_realtime.sql
-- Makes chats, the feed and notifications update live. Adds the tables
-- to Supabase's realtime publication (safe to run more than once - a
-- table that is already in it is skipped).
-- Run once in Supabase SQL Editor.

do $$
declare t text;
begin
  foreach t in array array[
    'messages', 'feed_notifications', 'feed_comments',
    'community_posts', 'post_likes', 'activity_likes'
  ] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;   -- already added
      when undefined_table then null;    -- table does not exist here
    end;
  end loop;
end $$;
