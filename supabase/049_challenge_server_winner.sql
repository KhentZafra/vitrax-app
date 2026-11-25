-- 049_challenge_server_winner.sql
-- Run once in the Supabase SQL Editor (after 048). Safe to re-run.
--
-- WHY: until now the PHONE decided when a challenge was complete (only when the
-- person opened the challenge page, and it counted unshared runs too). That made
-- the finish time depend on lag and on when the page was opened.
--
-- NOW the SERVER decides:
--   * only SHARED activities count (the published rule)
--   * the finish time is the real moment the finishing activity ended
--     (a phone can claim at most 15 minutes earlier than its upload time)
--   * the first finisher starts a 30 minute wait; when it is over the challenge
--     closes automatically, the earliest real finish wins, everyone is notified
--     and the winner gets the "Challenge Winner" badge
--   * only challenges with a prize close automatically; challenges that already
--     exist keep the old behaviour (auto_close = false)
--
-- Timing constants (change here if you want different numbers):
--   challenge_lag_allowance()  15 minutes
--   challenge_grace()          30 minutes
--
-- UNDO (stop the automatic closing only):
--   select cron.unschedule(jobid) from cron.job where jobname = 'challenge-autoclose';

-- ------------------------------------------------------------------ columns
alter table public.challenges add column if not exists closed_at timestamptz;
alter table public.challenges add column if not exists winner_user_id uuid references auth.users(id) on delete set null;

do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'challenges' and column_name = 'auto_close') then
    alter table public.challenges add column auto_close boolean not null default true;
    -- challenges that already exist keep the old behaviour
    update public.challenges set auto_close = false;
  end if;
end $$;

alter table public.challenge_participants add column if not exists total_seconds integer not null default 0;
alter table public.challenge_participants add column if not exists completed_recorded_at timestamptz;

create or replace function public.challenge_lag_allowance() returns interval
language sql immutable as $$ select interval '15 minutes' $$;

create or replace function public.challenge_grace() returns interval
language sql immutable as $$ select interval '30 minutes' $$;

-- ------------------------------------------- the runs that count, in order
-- Shared runs/rides of one person that started inside the challenge window and
-- match its activity filter, with a running total of the goal metric.
-- started_at stores the phone's clock reading labelled UTC, so it is converted
-- back to the real moment (Bohol time).
create or replace function public.challenge_counted(p_challenge uuid, p_user uuid)
returns table (id uuid, created_at timestamptz, duration_seconds integer, metric numeric,
               s_at timestamptz, e_at timestamptz, running numeric)
language sql stable security definer set search_path = public as $$
  with c as (select * from public.challenges where id = p_challenge),
  acts as (
    select a.id, a.created_at, a.duration_seconds::int as duration_seconds,
           case c.type::text
             when 'distance' then a.distance_km::numeric
             when 'duration' then a.duration_seconds / 60.0
             else 1::numeric
           end as metric,
           ((a.started_at at time zone 'UTC') at time zone 'Asia/Manila') as s_at
      from public.activities a, c
     where a.user_id = p_user and a.shared
       and (   c.activity_filter::text = 'any'
            or (c.activity_filter::text = 'run'  and a.type::text in ('run', 'walk'))
            or (c.activity_filter::text = 'ride' and a.type::text = 'ride'))
  ),
  win as (
    select acts.*, acts.s_at + make_interval(secs => acts.duration_seconds) as e_at
      from acts, c
     where acts.s_at >= c.start_date and acts.s_at <= c.end_date
  )
  select win.id, win.created_at, win.duration_seconds, win.metric, win.s_at, win.e_at,
         sum(win.metric) over (order by win.s_at, win.id) as running
    from win
$$;
revoke all on function public.challenge_counted(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------- evaluate one person in one challenge
create or replace function public.eval_challenge_for(p_challenge uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  c public.challenges%rowtype;
  cp public.challenge_participants%rowtype;
  total numeric; secs integer; f record; fin timestamptz;
begin
  select * into c from public.challenges where id = p_challenge;
  if not found or c.type::text = 'route' or c.closed_at is not null then return; end if;

  select * into cp from public.challenge_participants
   where challenge_id = p_challenge and user_id = p_user;
  if not found then return; end if;

  select coalesce(sum(x.metric), 0), coalesce(sum(x.duration_seconds), 0)::int
    into total, secs
    from public.challenge_counted(p_challenge, p_user) x;

  select x.* into f from public.challenge_counted(p_challenge, p_user) x
   where x.running >= c.target_value order by x.s_at, x.id limit 1;

  perform set_config('vitrax.server_eval', '1', true);

  if f.id is not null and cp.completed_at is null then
    -- real finish moment, but never earlier than 15 minutes before the upload
    fin := least(now(), greatest(f.e_at, f.created_at - public.challenge_lag_allowance()));
    select coalesce(sum(x.duration_seconds), 0)::int into secs
      from public.challenge_counted(p_challenge, p_user) x
     where (x.s_at, x.id) <= (f.s_at, f.id);
    update public.challenge_participants
       set progress_value = total, total_seconds = secs,
           completed_at = fin, completed_recorded_at = now()
     where challenge_id = p_challenge and user_id = p_user;
  else
    update public.challenge_participants
       set progress_value = total,
           total_seconds = case when completed_at is null then secs else total_seconds end
     where challenge_id = p_challenge and user_id = p_user;
  end if;

  perform set_config('vitrax.server_eval', '0', true);
end $$;
revoke all on function public.eval_challenge_for(uuid, uuid) from public, anon, authenticated;

-- ---------------------- phones can no longer write progress/completion themselves
create or replace function public.guard_participant_progress() returns trigger
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if coalesce(current_setting('vitrax.server_eval', true), '0') = '1' then return new; end if;
  select type::text into t from public.challenges where id = new.challenge_id;
  if t is distinct from 'route' then
    new.completed_at := old.completed_at;
    new.progress_value := old.progress_value;
    new.total_seconds := old.total_seconds;
    new.completed_recorded_at := old.completed_recorded_at;
  end if;
  return new;
end $$;

drop trigger if exists guard_participant_progress on public.challenge_participants;
create trigger guard_participant_progress before update on public.challenge_participants
  for each row execute function public.guard_participant_progress();

-- ------------------------------- re-check whenever a run is shared / someone joins
create or replace function public.eval_on_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if not new.shared then return new; end if;
  for r in
    select cp.challenge_id
      from public.challenge_participants cp
      join public.challenges c on c.id = cp.challenge_id
     where cp.user_id = new.user_id and c.closed_at is null and c.type::text <> 'route'
       and now() <= c.end_date + interval '1 day'
  loop
    perform public.eval_challenge_for(r.challenge_id, new.user_id);
  end loop;
  return new;
exception when others then
  return new; -- never block saving an activity
end $$;

drop trigger if exists eval_on_activity on public.activities;
create trigger eval_on_activity after insert or update of shared, distance_km, duration_seconds
  on public.activities for each row execute function public.eval_on_activity();

create or replace function public.eval_on_join() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.eval_challenge_for(new.challenge_id, new.user_id);
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists eval_on_join on public.challenge_participants;
create trigger eval_on_join after insert on public.challenge_participants
  for each row execute function public.eval_on_join();

-- ------------------------------------------------- close, announce, award badge
create or replace function public.close_due_challenges() returns integer
language plpgsql security definer set search_path = public as $$
declare c record; w record; n integer := 0; others uuid[];
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
      perform public.push_challenge(others, 'Challenge closed',
        public.display_name_of(w.user_id) || ' won "' || c.title || '". Congratulations!', c.id);
      perform public.push_challenge(array[w.user_id], 'You won!',
        'You won "' || c.title || '". Open it to add your GCash QR for the prize.', c.id);
    exception when others then
      null; -- a failed push must never undo the close
    end;

    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.close_due_challenges() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.unschedule(jobid) from cron.job where jobname = 'challenge-autoclose';
select cron.schedule('challenge-autoclose', '* * * * *', 'select public.close_due_challenges()');

-- ----------------------------------------------- "Challenge Winner" badge (champion)
do $$
declare def text; r record;
begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('badge_stats', 'evaluate_my_badges') loop
    def := pg_get_functiondef(r.oid);
    if r.proname = 'badge_stats' and position('''champion''' in def) = 0 then
      if position('-- new in 034' in def) = 0 then raise exception 'badge_stats not in the expected form'; end if;
      def := replace(def, '-- new in 034',
        E'''champion'', (select count(*) from public.challenges c where c.winner_user_id = uid),\n    -- new in 034');
      execute def;
    elsif r.proname = 'evaluate_my_badges' and position('"champion"' in def) = 0 then
      if position('"route_likes": [1, 5, 15, 30, 60, 100]' in def) = 0 then raise exception 'evaluate_my_badges not in the expected form'; end if;
      def := replace(def, '"route_likes": [1, 5, 15, 30, 60, 100]',
        '"route_likes": [1, 5, 15, 30, 60, 100],' || E'\n    "champion": [1, 3, 5, 10, 20, 40]');
      execute def;
    end if;
  end loop;
end $$;

-- ------------------------------------------ one-time catch-up for running challenges
do $$
declare r record;
begin
  for r in
    select cp.challenge_id, cp.user_id
      from public.challenge_participants cp
      join public.challenges c on c.id = cp.challenge_id
     where c.closed_at is null and c.type::text <> 'route' and c.end_date > now()
  loop
    begin
      perform public.eval_challenge_for(r.challenge_id, r.user_id);
    exception when others then null;
    end;
  end loop;
end $$;
