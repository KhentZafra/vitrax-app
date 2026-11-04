-- 042: nicer phone notification for official challenges (plain text: title, prize,
-- goal and end date). Run once in the Supabase SQL Editor after 041.
create or replace function public.push_official_challenge() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  recipients uuid[]; msg text; ptitle text; pbody text;
  goal text; prize text; ends text;
begin
  if not coalesce(new.is_official, false) then return new; end if;

  goal := regexp_replace(trim(to_char(new.target_value, 'FM999,999,990.99')), '\.$', '') ||
    case new.type when 'distance' then ' km' when 'activity_count' then ' activities'
                  when 'duration' then ' minutes' else '' end;
  ends := to_char(new.end_date::timestamptz at time zone 'Asia/Manila', 'Mon FMDD');
  prize := case when coalesce(new.prize_amount, 0) > 0
    then 'Win ₱' || trim(to_char(new.prize_amount, 'FM999,999,990')) || ' by reaching ' else 'Reach ' end;

  -- In-app bell card.
  msg := 'New challenge: "' || new.title || '"' ||
    case when coalesce(new.prize_amount, 0) > 0
      then ' - win ₱' || trim(to_char(new.prize_amount, 'FM999,999,990')) else '' end ||
    '. Join now!';
  -- Phone notification.
  ptitle := 'New challenge: ' || left(new.title, 50);
  pbody  := prize || goal || '. Ends ' || ends || '.';

  select array_agg(id) into recipients from public.profiles
    where coalesce(is_suspended, false) = false and id <> new.creator_id;
  begin
    insert into public.feed_notifications (user_id, actor_id, type, post_kind, post_id, body)
    select id, new.creator_id, 'announcement', 'challenge', new.id, msg from unnest(recipients) as id;
  exception when others then null;
  end;
  begin
    perform public.push_challenge(recipients, ptitle, pbody, new.id);
  exception when others then null;
  end;
  return new;
end $$;
revoke execute on function public.push_official_challenge() from public, anon, authenticated;
