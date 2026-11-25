-- 052_finish_run_duration.sql
-- Run once in the Supabase SQL Editor (after 049 and 051). Safe to re-run.
-- Stores the duration of the ONE run that finished the challenge
-- (e.g. 10.0 km in 1h 00m), so the standings and winner card can show it.

alter table public.challenge_participants add column if not exists finish_seconds integer not null default 0;

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
    fin := least(now(), greatest(f.e_at, f.created_at - public.challenge_lag_allowance()));
    select coalesce(sum(x.duration_seconds), 0)::int into secs
      from public.challenge_counted(p_challenge, p_user) x
     where (x.s_at, x.id) <= (f.s_at, f.id);
    update public.challenge_participants
       set progress_value = total, total_seconds = secs, finish_seconds = f.duration_seconds,
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
    new.finish_seconds := old.finish_seconds;
    new.completed_recorded_at := old.completed_recorded_at;
  end if;
  return new;
end $$;

-- fill it in for people who already finished
do $$
declare r record; f record;
begin
  perform set_config('vitrax.server_eval', '1', true);
  for r in
    select cp.challenge_id, cp.user_id, c.target_value
      from public.challenge_participants cp
      join public.challenges c on c.id = cp.challenge_id
     where cp.completed_at is not null and cp.finish_seconds = 0 and c.type::text <> 'route'
  loop
    select x.* into f from public.challenge_counted(r.challenge_id, r.user_id) x
     where x.running >= r.target_value order by x.s_at, x.id limit 1;
    if f.id is not null then
      update public.challenge_participants set finish_seconds = f.duration_seconds
       where challenge_id = r.challenge_id and user_id = r.user_id;
    end if;
  end loop;
  perform set_config('vitrax.server_eval', '0', true);
end $$;
