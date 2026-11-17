-- lock_down_functions.sql : clears the Security Advisor "SECURITY DEFINER function executable" warnings.
-- Keeps EXECUTE only where the app really needs it. Trigger / cron / internal helpers lose public access.
-- ROLLBACK at the bottom.

do $$
declare
  f record;
  keep_auth text[] := array[
    'admin_delete_user','admin_expire_stale_hazards','admin_flagged_users','admin_list_users',
    'confirm_prize_receipt','delete_my_account','dispute_prize','evaluate_my_badges',
    'my_badge_stats','public_profile_stats','resolve_prize_dispute','start_or_get_conversation',
    'is_admin','is_conversation_participant'];      -- called by the app or by RLS policies
  keep_anon text[] := array['public_profile_stats'];  -- public by design
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
    if f.proname = any(keep_auth) then execute format('grant execute on function %s to authenticated', f.sig); end if;
    if f.proname = any(keep_anon) then execute format('grant execute on function %s to anon', f.sig); end if;
  end loop;

  for f in
    select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'trim_route'
  loop
    execute format('alter function %s set search_path = public', f.sig);
  end loop;
end $$;

-- ROLLBACK (only if something breaks):
-- do $$ declare f record; begin
--   for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--            where n.nspname='public' and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e')
--   loop execute format('grant execute on function %s to anon, authenticated', f.sig); end loop;
-- end $$;
