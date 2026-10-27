-- 031_push_triggers.sql
-- Phone push notifications that arrive even when the app is closed or the
-- phone is locked: new chat messages, challenge activity and challenge
-- reminders. (Feed pushes already come from 016_feed_push.sql.)
--
-- BEFORE RUNNING (in the SQL Editor only, do NOT save the real values into
-- this file or commit them to GitHub):
--   1. Replace YOUR_CHAT_SECRET with the value of the CHAT_PUSH_WEBHOOK_SECRET
--      function secret.
--   2. Create a new function secret CHALLENGE_PUSH_WEBHOOK_SECRET with any
--      long random value, deploy the send-challenge-push function, then
--      replace YOUR_CHALLENGE_SECRET below with that same value.
-- Safe to run more than once.

create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------- chat
-- Remove any older trigger that already calls send-chat-push (avoids double
-- notifications), then create the one below.
do $$
declare r record;
begin
  for r in
    select t.tgname
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.messages'::regclass
      and not t.tgisinternal
      and p.prosrc ilike '%send-chat-push%'
  loop
    execute format('drop trigger %I on public.messages', r.tgname);
  end loop;
end $$;

create or replace function public.push_chat_message() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform net.http_post(
    url := 'https://vodintxkapxjjmtezahi.supabase.co/functions/v1/send-chat-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', 'YOUR_CHAT_SECRET'),
    body := jsonb_build_object('conversation_id', new.conversation_id, 'sender_id', new.sender_id, 'body', new.body)
  );
  return new;
exception when others then
  return new;  -- never block sending a message because the push failed
end $$;

drop trigger if exists on_message_push on public.messages;
create trigger on_message_push after insert on public.messages
  for each row execute function public.push_chat_message();

-- ----------------------------------------------------------- challenges
alter table public.challenges add column if not exists start_reminded_at timestamptz;
alter table public.challenges add column if not exists end_notified_at   timestamptz;

create or replace function public.push_challenge(p_user_ids uuid[], p_title text, p_body text, p_challenge_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_user_ids is null or coalesce(array_length(p_user_ids, 1), 0) = 0 then
    return;
  end if;
  perform net.http_post(
    url := 'https://vodintxkapxjjmtezahi.supabase.co/functions/v1/send-challenge-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', 'YOUR_CHALLENGE_SECRET'),
    body := jsonb_build_object('user_ids', to_jsonb(p_user_ids), 'title', p_title, 'body', p_body, 'challenge_id', p_challenge_id)
  );
exception when others then
  null;
end $$;

-- Someone joined your challenge.
create or replace function public.push_challenge_joined() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record; joiner text;
begin
  select id, creator_id, title into c from public.challenges where id = new.challenge_id;
  if c.id is null or c.creator_id = new.user_id then
    return new;
  end if;
  select coalesce(nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''), 'Someone')
    into joiner from public.profiles where id = new.user_id;
  perform public.push_challenge(array[c.creator_id], 'Vitrax Challenges',
    joiner || ' joined your challenge "' || c.title || '".', c.id);
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists on_challenge_joined_push on public.challenge_participants;
create trigger on_challenge_joined_push after insert on public.challenge_participants
  for each row execute function public.push_challenge_joined();

-- Your prize was marked as paid.
create or replace function public.push_prize_paid() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record;
begin
  select id, title, prize_amount into c from public.challenges where id = new.challenge_id;
  if c.id is null then
    return new;
  end if;
  perform public.push_challenge(array[new.winner_user_id], 'Vitrax Challenges',
    'Your prize for "' || c.title || '" was marked as paid. Check your GCash.', c.id);
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists on_prize_paid_push on public.challenge_prize_payments;
create trigger on_prize_paid_push after insert on public.challenge_prize_payments
  for each row execute function public.push_prize_paid();

-- Reminders: a challenge starts within 24 hours, and a challenge has ended.
create or replace function public.send_challenge_reminders() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c record; recipients uuid[];
begin
  for c in
    select id, creator_id, title from public.challenges
    where start_reminded_at is null
      and start_date::timestamptz > now()
      and start_date::timestamptz <= now() + interval '24 hours'
  loop
    select array_agg(distinct u) into recipients from (
      select user_id as u from public.challenge_participants where challenge_id = c.id
      union select c.creator_id
    ) s;
    perform public.push_challenge(recipients, 'Challenge starting soon', '"' || c.title || '" starts within 24 hours.', c.id);
    update public.challenges set start_reminded_at = now() where id = c.id;
  end loop;

  for c in
    select id, creator_id, title from public.challenges
    where end_notified_at is null
      and end_date::timestamptz <= now()
      and end_date::timestamptz > now() - interval '3 days'
  loop
    select array_agg(distinct u) into recipients from (
      select user_id as u from public.challenge_participants where challenge_id = c.id
      union select c.creator_id
    ) s;
    perform public.push_challenge(recipients, 'Challenge ended', '"' || c.title || '" has ended. Open it to see the results.', c.id);
    update public.challenges set end_notified_at = now() where id = c.id;
  end loop;
end $$;

-- Only the database itself may call these helpers.
revoke execute on function public.push_chat_message()        from public, anon, authenticated;
revoke execute on function public.push_challenge(uuid[], text, text, uuid) from public, anon, authenticated;
revoke execute on function public.push_challenge_joined()    from public, anon, authenticated;
revoke execute on function public.push_prize_paid()          from public, anon, authenticated;
revoke execute on function public.send_challenge_reminders() from public, anon, authenticated;

-- Check for reminders every 15 minutes.
select cron.unschedule(jobid) from cron.job where jobname = 'challenge-reminders';
select cron.schedule('challenge-reminders', '*/15 * * * *', 'select public.send_challenge_reminders()');
