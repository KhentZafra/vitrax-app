-- VITRAX security audit (READ-ONLY: changes nothing).
-- Run each block in the Supabase SQL Editor and send me the results.

-- 1) Tables with Row Level Security OFF (should return no rows)
select schemaname, tablename
from pg_tables
where schemaname = 'public' and not rowsecurity
order by tablename;

-- 2) Every policy: who can do what on which table
select tablename, policyname, cmd, roles, qual as using_rule, with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- 3) Tables that have RLS ON but NO policies (nobody can use them, or a mistake)
select c.relname as table_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname);

-- 4) Functions callable by the public (anon) role
select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and has_function_privilege('anon', p.oid, 'execute')
order by p.proname;

-- 5) Storage buckets that are public
select id, name, public from storage.buckets order by name;
