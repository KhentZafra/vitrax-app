-- 033_multi_activity.sql
-- People can now choose Cyclist, Runner, or both when registering. The value
-- is saved in profiles.primary_activity as 'Cyclist', 'Runner' or
-- 'Cyclist,Runner'. If an older rule limited the column to one word, remove
-- it. Safe to run more than once.
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%primary_activity%'
  loop
    execute format('alter table public.profiles drop constraint %I', r.conname);
  end loop;
end $$;
