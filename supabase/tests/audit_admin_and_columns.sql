-- audit_admin_and_columns.sql  (read-only, changes nothing)
-- Run it, then copy the whole result and paste it back to Claude.

select 'is_admin() definition' as item,
       pg_get_functiondef('public.is_admin()'::regprocedure) as detail
union all
select 'profiles columns',
       string_agg(column_name || ' ' || data_type, E'\n' order by ordinal_position)
from information_schema.columns
where table_schema = 'public' and table_name = 'profiles'
union all
select 'challenge_participants columns',
       string_agg(column_name || ' ' || data_type, E'\n' order by ordinal_position)
from information_schema.columns
where table_schema = 'public' and table_name = 'challenge_participants'
union all
select 'tables WITHOUT row security',
       coalesce(string_agg(c.relname, ', '), 'none')
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
union all
select 'tables with security but NO rules (fully locked)',
       coalesce(string_agg(c.relname, ', '), 'none')
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
  and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
union all
select 'unique / primary keys on vote tables',
       coalesce(string_agg(conrelid::regclass || ': ' || pg_get_constraintdef(oid), E'\n'), 'none')
from pg_constraint
where contype in ('u', 'p')
  and conrelid in ('public.hazard_verifications'::regclass,
                   'public.hazard_clear_confirmations'::regclass,
                   'public.activity_likes'::regclass,
                   'public.post_likes'::regclass)
union all
select 'storage rules',
       coalesce(string_agg(policyname || ' | ' || cmd || ' | roles=' || roles::text
                           || ' | using=' || coalesce(qual, '-')
                           || ' | check=' || coalesce(with_check, '-'), E'\n'), 'none')
from pg_policies
where schemaname = 'storage';
