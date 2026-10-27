-- 032_push_notifications_v2.sql
-- Smarter phone notifications:
--   * Chat: the first message of a new conversation says "Someone messaged
--     you"; later messages show the sender's name and the message.
--   * Challenges: someone left your challenge, someone passed you in the
--     standings, someone finished, and the "challenge ended" message now
--     tells each person their final place.
-- Needs 031_push_triggers.sql to have been run already (it reuses the secret
-- already stored in push_chat_message(); nothing to paste here).
-- Safe to run more than once.

-- ---------------------------------------------------------------- chat
do $outer$
declare
  src text;
  sec text;
begin
  select prosrc into src from pg_proc where oid = 'public.push_chat_message()'::regprocedure;
  sec := substring(src from $re$'x-webhook-secret',\s*'([^']*)'$re$);
  if sec is null or sec = '' or sec like 'YOUR\_%' then
    raise exception 'push_chat_message() has no real secret yet; re-run the chat part of 031 first';
  end if;

  execute format($f$
    create or replace function public.push_chat_message() returns trigger
    language plpgsql security definer set search_path = public, extensions as $body$
    declare first_msg boolean;
    begin
      select count(*) = 1 into first_msg from public.messages where conversation_id = new.conversation_id;
      perform net.http_post(
        url := 'https://vodintxkapxjjmtezahi.supabase.co/functions/v1/send-chat-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', %L),
        body := jsonb_build_object('conversation_id', new.conversation_id, 'sender_id', new.sender_id, 'body', new.body, 'is_first', coalesce(first_msg, false))
      );
      return new;
    exception when others then
      return new;
    end $body$;
  $f$, sec);
end $outer$;

-- ----------------------------------------------------------- challenges
-- The app already saves each person's challenge progress here (and reads it
-- for the standings), but the column was never created in the database.
alter table public.challenge_participants
  add column if not exists progress_value double precision not null default 0;

create or replace function public.display_name_of(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), ''), 'Someone')
  from public.profiles where id = p_user
$$;
revoke execute on function public.display_name_of(uuid) from public, anon, authenticated;

-- Someone left your challenge.
create or replace function public.push_challenge_left() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record;
begin
  select id, creator_id, title into c from public.challenges where id = old.challenge_id;
  if c.id is null or c.creator_id = old.user_id then return old; end if;
  if not exists (select 1 from public.profiles where id = old.user_id) then return old; end if;  -- account deleted
  perform public.push_challenge(array[c.creator_id], 'Vitrax Challenges',
    public.display_name_of(old.user_id) || ' left your challenge "' || c.title || '".', c.id);
  return old;
exception when others then
  return old;
end $$;

drop trigger if exists on_challenge_left_push on public.challenge_participants;
create trigger on_challenge_left_push after delete on public.challenge_participants
  for each row execute function public.push_challenge_left();

-- Someone passed you in the standings, or finished the challenge.
create or replace function public.push_standing_change() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record; who text; passed uuid[]; others uuid[];
begin
  select id, creator_id, title, type into c from public.challenges where id = new.challenge_id;
  if c.id is null then return new; end if;
  who := public.display_name_of(new.user_id);

  if c.type = 'route' then
    -- A faster time than before: tell everyone who is now slower.
    if new.duration_seconds is not null
       and new.duration_seconds is distinct from old.duration_seconds
       and new.duration_seconds < coalesce(old.duration_seconds, 2147483647) then
      select array_agg(user_id) into passed from public.challenge_participants
        where challenge_id = new.challenge_id and user_id <> new.user_id
          and duration_seconds is not null
          and duration_seconds > new.duration_seconds
          and duration_seconds <= coalesce(old.duration_seconds, 2147483647);
      perform public.push_challenge(passed, 'Challenge standings',
        who || ' beat your time in "' || c.title || '".', c.id);
    end if;
    return new;
  end if;

  -- Regular challenge: finished the goal.
  if new.completed_at is not null and old.completed_at is null then
    select array_agg(user_id) into others from public.challenge_participants
      where challenge_id = new.challenge_id and user_id <> new.user_id;
    perform public.push_challenge(others, 'Challenge standings',
      who || ' finished "' || c.title || '".', c.id);
    return new;
  end if;

  -- Regular challenge: overtook people on progress.
  if coalesce(new.progress_value, 0) > coalesce(old.progress_value, 0) then
    select array_agg(user_id) into passed from public.challenge_participants
      where challenge_id = new.challenge_id and user_id <> new.user_id
        and completed_at is null
        and coalesce(progress_value, 0) < coalesce(new.progress_value, 0)
        and coalesce(progress_value, 0) >= coalesce(old.progress_value, 0);
    perform public.push_challenge(passed, 'Challenge standings',
      who || ' passed you in "' || c.title || '".', c.id);
  end if;
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists on_standing_change_push on public.challenge_participants;
create trigger on_standing_change_push after update of duration_seconds, progress_value, completed_at
  on public.challenge_participants
  for each row execute function public.push_standing_change();

-- Reminders: starting soon, and an ended message that includes the final place.
create or replace function public.send_challenge_reminders() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare c record; recipients uuid[]; r record;
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
    select id, creator_id, title, type from public.challenges
    where end_notified_at is null
      and end_date::timestamptz <= now()
      and end_date::timestamptz > now() - interval '3 days'
  loop
    for r in
      select user_id,
             rank() over (order by case when c.type = 'route' then duration_seconds::numeric end asc nulls last,
                                   completed_at asc nulls last,
                                   progress_value desc nulls last) as place,
             count(*) over () as total
      from public.challenge_participants where challenge_id = c.id
    loop
      perform public.push_challenge(array[r.user_id], 'Challenge ended',
        'You placed #' || r.place || ' of ' || r.total || ' in "' || c.title || '".', c.id);
    end loop;
    update public.challenges set end_notified_at = now() where id = c.id;
  end loop;
end $$;

revoke execute on function public.push_challenge_left()      from public, anon, authenticated;
revoke execute on function public.push_standing_change()     from public, anon, authenticated;
revoke execute on function public.send_challenge_reminders() from public, anon, authenticated;
