-- 035_general_notifications.sql
-- Run once in the Supabase SQL Editor (after 034). Safe to re-run.
--
-- Turns the bell on Home into a general notification centre. Besides the
-- community notifications it already had (likes, comments, replies, reshares),
-- it now also shows:
--   route_like     someone liked a route you shared
--   route_retrace  someone retraced a route you shared
--   badge          you earned a badge
-- Rows are created by triggers, like the existing ones.

-- Which shared route an activity was a retrace of.
alter table public.activities add column if not exists retraced_from uuid references public.activities(id) on delete set null;
create index if not exists activities_retraced_from_idx on public.activities (retraced_from) where retraced_from is not null;

-- Allow the new notification types and kinds: drop the old CHECK rules
-- (the table only has these two) and add the wider ones below.
alter table public.feed_notifications drop constraint if exists feed_notifications_type_check;
alter table public.feed_notifications drop constraint if exists feed_notifications_post_kind_check;
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.feed_notifications'::regclass and contype = 'c'
  loop
    execute format('alter table public.feed_notifications drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.feed_notifications
  add constraint feed_notifications_type_check
  check (type in ('like','comment','reply','reshare','route_like','route_retrace','badge'));
alter table public.feed_notifications
  add constraint feed_notifications_post_kind_check
  check (post_kind in ('activity','post','route','badge'));

-- One notification per person per route for likes and retraces.
create unique index if not exists feed_notifications_route_like_uniq
  on public.feed_notifications (user_id, actor_id, post_id) where type = 'route_like';
create unique index if not exists feed_notifications_route_retrace_uniq
  on public.feed_notifications (user_id, actor_id, post_id) where type = 'route_retrace';

-- ---------- Someone liked your shared route ----------
create or replace function public.notify_route_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select user_id into owner from public.activities where id = new.route_id;
  if owner is not null and owner <> new.user_id then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id)
    values (owner, new.user_id, 'route_like', 'route', new.route_id)
    on conflict (user_id, actor_id, post_id) where type = 'route_like' do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_route_like_notify on public.route_likes;
create trigger on_route_like_notify after insert on public.route_likes
  for each row execute function public.notify_route_like();

-- ---------- Someone retraced your shared route ----------
create or replace function public.notify_route_retrace() returns trigger
language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  if new.retraced_from is null then return new; end if;
  select user_id into owner from public.activities where id = new.retraced_from and shared;
  if owner is not null and owner <> new.user_id then
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id)
    values (owner, new.user_id, 'route_retrace', 'route', new.retraced_from)
    on conflict (user_id, actor_id, post_id) where type = 'route_retrace' do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_route_retrace_notify on public.activities;
create trigger on_route_retrace_notify after insert on public.activities
  for each row execute function public.notify_route_retrace();

-- ---------- You earned a badge ----------
-- actor = yourself; body = "<badge key>:<tier>", the app turns it into a title.
create or replace function public.notify_badge_earned() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
  values (new.user_id, new.user_id, 'badge', 'badge', gen_random_uuid(), new.badge_key || ':' || new.tier);
  return new;
end $$;

drop trigger if exists on_badge_earned_notify on public.user_badges;
create trigger on_badge_earned_notify after insert on public.user_badges
  for each row execute function public.notify_badge_earned();

revoke execute on function public.notify_route_like() from public, anon, authenticated;
revoke execute on function public.notify_route_retrace() from public, anon, authenticated;
revoke execute on function public.notify_badge_earned() from public, anon, authenticated;
