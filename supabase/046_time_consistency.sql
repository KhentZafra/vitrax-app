-- 046: makes the database's time rules agree with how the app saves times.
--
-- The app saves started_at / reported_at as the phone's clock reading marked
-- as UTC (a ride at 2:14 PM is stored as 14:14 UTC). That is 8 hours ahead of
-- the real moment. This file does NOT change any stored data. It changes the
-- rules that compare those columns with "now":
--   * Early Bird and streak badges: read the stored value as the clock reading
--     it is (at time zone 'UTC') instead of converting it to Manila again.
--   * Hazard rules (hide stale hazards, flagged-user counts, report rate
--     limits): compare against the Manila clock reading instead of real UTC.
-- It patches the LIVE function definitions, so it also covers any edits made
-- after the numbered files. Safe to re-run: a second run finds nothing to change.
--
-- Preview which functions it will touch (run this alone first):
--   select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and (p.prosrc like '%started_at at time zone ''Asia/Manila''%'
--        or p.prosrc like '%reported_at > now()%' or p.prosrc like '%reported_at < now()%');
--
-- Undo: swap the replacements in the block below the other way round
-- ('UTC' back to 'Asia/Manila', manila_clock_now() back to now()).

create or replace function public.manila_clock_now() returns timestamptz
language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Manila') at time zone 'UTC'
$$;

do $$
declare
  r record;
  def text;
  n int := 0;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
       and (p.prosrc like '%started_at at time zone ''Asia/Manila''%'
         or p.prosrc like '%reported_at > now()%'
         or p.prosrc like '%reported_at < now()%')
  loop
    def := pg_get_functiondef(r.oid);
    def := replace(def, 'started_at at time zone ''Asia/Manila''', 'started_at at time zone ''UTC''');
    def := replace(def, 'reported_at > now()', 'reported_at > public.manila_clock_now()');
    def := replace(def, 'reported_at < now()', 'reported_at < public.manila_clock_now()');
    execute def;
    n := n + 1;
    raise notice 'patched %', r.proname;
  end loop;
  raise notice 'patched % function(s)', n;
end $$;
