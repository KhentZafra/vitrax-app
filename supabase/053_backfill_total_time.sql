-- 053_backfill_total_time.sql
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- Fills in the "total time" (all runs that added up to the goal) for people
-- who finished a challenge BEFORE the server started tracking it, e.g. the
-- current runners challenge. Does not change who finished or when.

do $$
declare r record; f record; secs integer;
begin
  perform set_config('vitrax.server_eval', '1', true);
  for r in
    select cp.challenge_id, cp.user_id, c.target_value
      from public.challenge_participants cp
      join public.challenges c on c.id = cp.challenge_id
     where cp.completed_at is not null and cp.total_seconds = 0 and c.type::text <> 'route'
  loop
    select x.* into f from public.challenge_counted(r.challenge_id, r.user_id) x
     where x.running >= r.target_value order by x.s_at, x.id limit 1;
    if f.id is not null then
      select coalesce(sum(x.duration_seconds), 0)::int into secs
        from public.challenge_counted(r.challenge_id, r.user_id) x
       where (x.s_at, x.id) <= (f.s_at, f.id);
      update public.challenge_participants set total_seconds = secs
       where challenge_id = r.challenge_id and user_id = r.user_id;
    end if;
  end loop;
  perform set_config('vitrax.server_eval', '0', true);
end $$;
