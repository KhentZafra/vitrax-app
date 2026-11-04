-- 041: an official challenge now notifies everyone in the Home bell (highlighted
-- announcement) as well as by phone push. Run once in the Supabase SQL Editor
-- after 040. Safe to re-run.

-- Allow the new notification type and kind.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.feed_notifications'::regclass and contype = 'c'
  loop
    execute format('alter table public.feed_notifications drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.feed_notifications
  add constraint feed_notifications_type_check
  check (type in ('like','comment','reply','reshare','route_like','route_retrace','badge','announcement'));
alter table public.feed_notifications
  add constraint feed_notifications_post_kind_check
  check (post_kind in ('activity','post','route','badge','challenge'));

-- The community-feed push must ignore announcements (they use the challenge push).
drop trigger if exists on_feed_notification_push on public.feed_notifications;
create trigger on_feed_notification_push after insert on public.feed_notifications
  for each row when (new.type <> 'announcement') execute function public.push_feed_notification();

-- One function does both the bell row and the push.
create or replace function public.push_official_challenge() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare recipients uuid[]; msg text;
begin
  if not coalesce(new.is_official, false) then return new; end if;
  msg := 'New challenge: "' || new.title || '"' ||
    case when coalesce(new.prize_amount, 0) > 0
      then ' - win ₱' || trim(to_char(new.prize_amount, 'FM999,999,990')) else '' end ||
    '. Join now!';
  select array_agg(id) into recipients from public.profiles
    where coalesce(is_suspended, false) = false and id <> new.creator_id;
  begin
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
    select id, new.creator_id, 'announcement', 'challenge', new.id, msg from unnest(recipients) as id;
  exception when others then null;
  end;
  begin
    perform public.push_challenge(recipients, 'New Vitrax challenge', msg, new.id);
  exception when others then null;
  end;
  return new;
end $$;
drop trigger if exists on_official_challenge_push on public.challenges;
create trigger on_official_challenge_push after insert on public.challenges
  for each row execute function public.push_official_challenge();
revoke execute on function public.push_official_challenge() from public, anon, authenticated;
