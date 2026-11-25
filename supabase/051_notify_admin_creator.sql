-- 051_notify_admin_creator.sql
-- Run once in the Supabase SQL Editor (after 049). Safe to re-run.
-- Tells the challenge creator and every admin:
--   1) EARLY: the moment the first person finishes a prize challenge
--      ("X reached the target, the challenge closes in 30 minutes unless
--       someone finished earlier"), and
--   2) when the challenge closes and the winner is decided (so you can pay).
-- UNDO: drop trigger if exists notify_first_finisher on public.challenge_participants;
--       and re-run the close_due_challenges() function from 049.

-- ---------- 1) first finisher heads-up
create or replace function public.notify_first_finisher() returns trigger
language plpgsql security definer set search_path = public as $$
declare c record; staff uuid[];
begin
  if new.completed_at is null or old.completed_at is not null then return new; end if;
  select id, title, creator_id, prize_amount, auto_close, type::text as t into c
    from public.challenges where id = new.challenge_id;
  if c.id is null or not coalesce(c.auto_close, false) or coalesce(c.prize_amount, 0) <= 0 or c.t = 'route' then
    return new;
  end if;
  -- only for the very first finisher
  if exists (select 1 from public.challenge_participants p
              where p.challenge_id = new.challenge_id and p.user_id <> new.user_id and p.completed_at is not null) then
    return new;
  end if;
  select coalesce(array_agg(distinct u), '{}') into staff
    from (select c.creator_id as u
          union select id from public.profiles where is_admin) s
   where u is not null;
  perform public.push_challenge(staff, 'Challenge: first finisher',
    public.display_name_of(new.user_id) || ' reached the target in "' || c.title ||
    '". It closes in 30 minutes unless someone finished earlier.', c.id);
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists notify_first_finisher on public.challenge_participants;
create trigger notify_first_finisher after update of completed_at on public.challenge_participants
  for each row execute function public.notify_first_finisher();

-- ---------- 2) winner decided: also tell the creator and the admins
create or replace function public.close_due_challenges() returns integer
language plpgsql security definer set search_path = public as $$
declare c record; w record; n integer := 0; others uuid[]; staff uuid[];
begin
  for c in
    select ch.*
      from public.challenges ch
     where ch.closed_at is null and ch.auto_close
       and coalesce(ch.prize_amount, 0) > 0 and ch.type::text <> 'route'
       and (select min(p.completed_recorded_at) from public.challenge_participants p
             where p.challenge_id = ch.id and p.completed_at is not null)
           <= now() - public.challenge_grace()
  loop
    select p.user_id into w
      from public.challenge_participants p
     where p.challenge_id = c.id and p.completed_at is not null
     order by p.completed_at asc, p.completed_recorded_at asc nulls last
     limit 1;
    if w.user_id is null then continue; end if;

    update public.challenges
       set closed_at = now(), winner_user_id = w.user_id, end_date = least(end_date, now())
     where id = c.id;

    insert into public.user_badges (user_id, badge_key, tier, value)
    values (w.user_id, 'champion', 'bronze',
            (select count(*) from public.challenges where winner_user_id = w.user_id))
    on conflict do nothing;

    begin
      select coalesce(array_agg(p.user_id), '{}') into others
        from public.challenge_participants p
       where p.challenge_id = c.id and p.user_id <> w.user_id;
      select coalesce(array_agg(distinct u), '{}') into staff
        from (select c.creator_id as u union select id from public.profiles where is_admin) s
       where u is not null and u <> w.user_id;
      -- the creator and admins hear it with the payment reminder; everyone else the plain result
      others := array(select unnest(others) except select unnest(staff));
      perform public.push_challenge(others, 'Challenge closed',
        public.display_name_of(w.user_id) || ' won "' || c.title || '". Congratulations!', c.id);
      perform public.push_challenge(staff, 'Winner decided',
        public.display_name_of(w.user_id) || ' won "' || c.title || '". The prize is ready to be paid.', c.id);
      perform public.push_challenge(array[w.user_id], 'You won!',
        'You won "' || c.title || '". Open it to add your GCash QR for the prize.', c.id);
    exception when others then
      null;
    end;

    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.close_due_challenges() from public, anon, authenticated;
