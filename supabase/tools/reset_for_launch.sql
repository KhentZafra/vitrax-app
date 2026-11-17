-- reset_for_launch.sql  -- ONE-TIME, IRREVERSIBLE. Wipes all test data.
-- Keeps: table structure, functions, policies, and the ADMIN account(s).
-- Run in Supabase SQL Editor. Do STEP 1 first, read it, then STEP 2.

-- ================= STEP 1: PREVIEW (safe, changes nothing) =================
-- Shows every public table and how many rows it will lose, plus who is kept.
select relname as table_name, n_live_tup as approx_rows
from pg_stat_user_tables where schemaname = 'public' order by relname;

select id, email, is_admin from public.profiles where is_admin = true;   -- KEPT
select count(*) as users_to_delete
from auth.users where id not in (select id from public.profiles where is_admin);

-- ================= STEP 2: WIPE (select from here down and Run) ============
do $$
declare
  -- tables to leave untouched (add any lookup/config table here)
  keep text[] := array['profiles'];
  t text;
  admins int;
begin
  select count(*) into admins from public.profiles where is_admin;
  if admins = 0 then
    raise exception 'No admin profile found - aborting so you do not lock yourself out.';
  end if;

  -- empty every other public table (no row triggers fire, so no pushes are sent)
  for t in
    select tablename from pg_tables
    where schemaname = 'public' and tablename <> all (keep)
  loop
    execute format('truncate table public.%I restart identity cascade', t);
  end loop;

  -- delete every non-admin account (their profile rows go with them)
  delete from auth.users
  where id not in (select id from public.profiles where is_admin);

end $$;

-- Verify
select (select count(*) from auth.users)      as users_left,
       (select count(*) from public.profiles) as profiles_left;
