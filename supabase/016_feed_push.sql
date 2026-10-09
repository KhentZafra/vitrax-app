-- 016_feed_push.sql
-- Sends a phone push whenever a row is added to feed_notifications
-- (like / comment / reply / reshare on your post).
--
-- BEFORE RUNNING: replace YOUR_WEBHOOK_SECRET below with the new random
-- secret you also set as the FEED_PUSH_WEBHOOK_SECRET function secret
-- (do not commit the real value to GitHub).

create extension if not exists pg_net with schema extensions;

create or replace function public.push_feed_notification() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform net.http_post(
    url := 'https://vodintxkapxjjmtezahi.supabase.co/functions/v1/send-feed-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', 'YOUR_WEBHOOK_SECRET'
    ),
    body := jsonb_build_object(
      'user_id', new.user_id,
      'actor_id', new.actor_id,
      'type', new.type,
      'post_kind', new.post_kind,
      'post_id', new.post_id,
      'body', new.body
    )
  );
  return new;
exception when others then
  -- Never block a like/comment just because the push could not be sent.
  return new;
end $$;

drop trigger if exists on_feed_notification_push on public.feed_notifications;
create trigger on_feed_notification_push after insert on public.feed_notifications
  for each row execute function public.push_feed_notification();
