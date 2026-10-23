-- 027: Stop logged-out (anon) visitors from calling database functions.
-- The app and admin page only call functions after login, so nothing changes
-- for normal use. Triggers and edge functions are not affected.

revoke execute on all functions in schema public from public, anon;
grant  execute on all functions in schema public to authenticated, service_role;

-- Functions created in the future follow the same rule.
alter default privileges in schema public revoke execute on functions from public, anon;
alter default privileges in schema public grant  execute on functions to authenticated, service_role;

-- Verify: should now return NO rows.
select p.proname
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
