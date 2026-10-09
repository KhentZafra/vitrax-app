-- 015_feed_notifications.sql
-- In-app notifications for activity on posts you shared in the feed:
-- likes, comments, replies to your comment, and reshares of your post.
-- Rows are created by triggers (SECURITY DEFINER), so the app never
-- inserts them itself. Run once in Supabase SQL Editor.

create table if not exists public.feed_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,   -- who gets notified
  actor_id uuid not null references public.profiles(id) on delete cascade,  -- who did it
  type text not null check (type in ('like', 'comment', 'reply', 'reshare')),
  post_kind text not null check (post_kind in ('activity', 'post')),
  post_id uuid not null,
  body text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists feed_notifications_user_idx on public.feed_notifications (user_id, created_at desc);
-- A person liking the same post twice (like, unlike, like) notifies once.
create unique index if not exists feed_notifications_like_uniq
  on public.feed_notifications (user_id, actor_id, post_kind, post_id) where type = 'like';

alter table public.feed_notifications enable row level security;

drop policy if exists "feed_notifications_select" on public.feed_notifications;
create policy "feed_notifications_select" on public.feed_notifications
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "feed_notifications_update" on public.feed_notifications;
create policy "feed_notifications_update" on public.feed_notifications
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "feed_notifications_delete" on public.feed_notifications;
create policy "feed_notifications_delete" on public.feed_notifications
  for delete to authenticated using (auth.uid() = user_id);

-- ---------- Likes ----------
create or replace function public.notify_activity_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select user_id into owner from public.activities where id = new.activity_id;
  if owner is not null and owner <> new.user_id then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id)
    values (owner, new.user_id, 'like', 'activity', new.activity_id)
    on conflict (user_id, actor_id, post_kind, post_id) where type = 'like' do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_activity_like_notify on public.activity_likes;
create trigger on_activity_like_notify after insert on public.activity_likes
  for each row execute function public.notify_activity_like();

create or replace function public.notify_post_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select user_id into owner from public.community_posts where id = new.post_id;
  if owner is not null and owner <> new.user_id then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id)
    values (owner, new.user_id, 'like', 'post', new.post_id)
    on conflict (user_id, actor_id, post_kind, post_id) where type = 'like' do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_post_like_notify on public.post_likes;
create trigger on_post_like_notify after insert on public.post_likes
  for each row execute function public.notify_post_like();

-- ---------- Comments and replies ----------
create or replace function public.notify_feed_comment() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid; parent_author uuid;
begin
  if new.post_kind = 'activity' then
    select user_id into owner from public.activities where id = new.post_id;
  else
    select user_id into owner from public.community_posts where id = new.post_id;
  end if;

  if new.parent_id is not null then
    select user_id into parent_author from public.feed_comments where id = new.parent_id;
    if parent_author is not null and parent_author <> new.user_id then
      insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
      values (parent_author, new.user_id, 'reply', new.post_kind, new.post_id, left(new.body, 200));
    end if;
  end if;

  -- Post owner hears about it too, unless they are the actor or were
  -- already notified above as the author of the replied-to comment.
  if owner is not null and owner <> new.user_id and owner is distinct from parent_author then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
    values (owner, new.user_id, 'comment', new.post_kind, new.post_id, left(new.body, 200));
  end if;
  return new;
end $$;

drop trigger if exists on_feed_comment_notify on public.feed_comments;
create trigger on_feed_comment_notify after insert on public.feed_comments
  for each row execute function public.notify_feed_comment();

-- ---------- Reshares ----------
create or replace function public.notify_feed_reshare() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.original_user_id is not null and new.original_user_id <> new.user_id then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
    values (new.original_user_id, new.user_id, 'reshare', coalesce(new.original_kind, 'post'), coalesce(new.original_id, new.id), left(new.caption, 200));
  end if;
  return new;
end $$;

drop trigger if exists on_feed_reshare_notify on public.community_posts;
create trigger on_feed_reshare_notify after insert on public.community_posts
  for each row execute function public.notify_feed_reshare();
