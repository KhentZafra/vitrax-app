-- 019_admin_safety.sql
-- Safety + accountability layer for VITRAX. Run once in Supabase SQL Editor
-- (after 018_admin.sql). Safe to run again.
--
--  1. Audit log of admin actions
--  2. Hazard moderation (status, auto-expire stale hazards, spam flags)
--  3. Location privacy (hide first/last metres of routes other people see)
--  4. Repeat-offender flags + warnings
--  5. "Delete my account" (user) - shares one purge routine with admin delete

-- =====================================================================
-- 4a. warnings + privacy columns on profiles
-- =====================================================================
alter table public.profiles add column if not exists warning_count int not null default 0;
alter table public.profiles add column if not exists privacy_zone_m int not null default 200;
alter table public.profiles drop constraint if exists profiles_privacy_zone_chk;
alter table public.profiles add constraint profiles_privacy_zone_chk
  check (privacy_zone_m between 0 and 1000);

-- warning_count is admin-only, like is_admin / is_suspended
create or replace function public.guard_profile_admin_cols() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.is_admin := false;
      new.is_suspended := false;
      new.warning_count := 0;
    elsif new.is_admin is distinct from old.is_admin
       or new.is_suspended is distinct from old.is_suspended
       or new.warning_count is distinct from old.warning_count then
      raise exception 'Not allowed';
    end if;
  end if;
  return new;
end $$;

-- =====================================================================
-- 1. AUDIT LOG
-- =====================================================================
create table if not exists public.admin_audit_log (
  id          bigint generated always as identity primary key,
  admin_id    uuid,
  admin_email text,
  action      text not null,
  target_table text,
  target_id   text,
  details     jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists admin_audit_log_created_idx on public.admin_audit_log (created_at desc);

alter table public.admin_audit_log enable row level security;
drop policy if exists admin_select_audit on public.admin_audit_log;
create policy admin_select_audit on public.admin_audit_log
  for select to authenticated using (public.is_admin());
-- no insert/update/delete policies: nobody (not even admins) can edit or
-- erase history from the website. Rows are written only by the triggers below.

create or replace function public.write_audit(p_action text, p_table text, p_target text, p_details jsonb)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  insert into public.admin_audit_log (admin_id, admin_email, action, target_table, target_id, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), p_action, p_table, p_target, p_details);
end $$;
revoke all on function public.write_audit(text, text, text, jsonb) from public;

-- generic trigger: records deletes/inserts made by an ADMIN on other people's data
create or replace function public.audit_admin_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb; owner text;
begin
  if auth.uid() is null or not public.is_admin() then
    return coalesce(new, old);
  end if;
  r := to_jsonb(coalesce(old, new));
  owner := r->>'user_id';
  -- ignore an admin managing their own content
  if tg_op = 'DELETE' and owner is not null and owner = auth.uid()::text then
    return old;
  end if;
  perform public.write_audit(
    lower(tg_op) || ' ' || tg_table_name, tg_table_name, r->>'id',
    jsonb_build_object('owner', owner, 'row', r - 'route' - 'public_route'));
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['activities','community_posts','feed_comments','hazards',
                           'challenges','chat_reports','challenge_prize_payments'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop trigger if exists audit_admin_row on public.%I', t);
    execute format(
      'create trigger audit_admin_row after insert or delete on public.%I
         for each row execute function public.audit_admin_row()', t);
  end loop;
end $$;

-- profile changes made by an admin (suspend, admin rights, warnings)
create or replace function public.audit_admin_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or not public.is_admin() or new.id = auth.uid() then
    return new;
  end if;
  if new.is_suspended is distinct from old.is_suspended then
    perform public.write_audit(case when new.is_suspended then 'suspend user' else 'unsuspend user' end,
      'profiles', new.id::text, jsonb_build_object('email', new.email));
  end if;
  if new.is_admin is distinct from old.is_admin then
    perform public.write_audit(case when new.is_admin then 'grant admin' else 'revoke admin' end,
      'profiles', new.id::text, jsonb_build_object('email', new.email));
  end if;
  if new.warning_count is distinct from old.warning_count then
    perform public.write_audit('warn user', 'profiles', new.id::text,
      jsonb_build_object('email', new.email, 'warnings', new.warning_count));
  end if;
  return new;
end $$;
drop trigger if exists audit_admin_profile on public.profiles;
create trigger audit_admin_profile after update on public.profiles
  for each row execute function public.audit_admin_profile();

-- =====================================================================
-- 2. HAZARD MODERATION
-- =====================================================================
alter table public.hazards add column if not exists status text not null default 'active';
alter table public.hazards add column if not exists expired_at timestamptz;

-- keep a record of hazards that vanish, so spam reporters can be spotted
-- even after the hazard row is gone.
create table if not exists public.hazard_removals (
  id bigint generated always as identity primary key,
  hazard_id uuid,
  user_id uuid,
  hazard_type text,
  removed_by_admin boolean not null default false,
  removed_at timestamptz not null default now()
);
alter table public.hazard_removals enable row level security;
drop policy if exists admin_select_hazard_removals on public.hazard_removals;
create policy admin_select_hazard_removals on public.hazard_removals
  for select to authenticated using (public.is_admin());

create or replace function public.log_hazard_removal() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.hazard_removals (hazard_id, user_id, hazard_type, removed_by_admin)
  values (old.id, old.user_id, old.type::text, coalesce(auth.uid() is not null and public.is_admin(), false));
  return old;
end $$;
drop trigger if exists log_hazard_removal on public.hazards;
create trigger log_hazard_removal before delete on public.hazards
  for each row execute function public.log_hazard_removal();

-- hides shared hazards that nobody has verified for p_hours (default 72h)
create or replace function public.expire_stale_hazards(p_hours int default 72) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.hazards h
     set shared = false, status = 'expired', expired_at = now()
   where h.shared = true
     and h.reported_at < now() - make_interval(hours => p_hours)
     and not exists (select 1 from public.hazard_verifications v where v.hazard_id = h.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.expire_stale_hazards(int) from public;

create or replace function public.admin_expire_stale_hazards(p_hours int default 72) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Not allowed'; end if;
  n := public.expire_stale_hazards(p_hours);
  perform public.write_audit('expire stale hazards', 'hazards', null,
    jsonb_build_object('hours', p_hours, 'hidden', n));
  return n;
end $$;
revoke all on function public.admin_expire_stale_hazards(int) from public;
grant execute on function public.admin_expire_stale_hazards(int) to authenticated;

-- admin can hide / restore a hazard without deleting it
drop policy if exists admin_update_hazards on public.hazards;
create policy admin_update_hazards on public.hazards
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.audit_hazard_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.is_admin()
     and (new.status is distinct from old.status or new.shared is distinct from old.shared) then
    perform public.write_audit('hazard ' || new.status || (case when new.shared then ' (visible)' else ' (hidden)' end),
      'hazards', new.id::text, jsonb_build_object('type', new.type, 'owner', new.user_id));
  end if;
  return new;
end $$;
drop trigger if exists audit_hazard_status on public.hazards;
create trigger audit_hazard_status after update on public.hazards
  for each row execute function public.audit_hazard_status();

-- hourly auto-expire, if pg_cron is available on this project
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule('vitrax-expire-hazards')
    where exists (select 1 from cron.job where jobname = 'vitrax-expire-hazards');
  perform cron.schedule('vitrax-expire-hazards', '0 * * * *', 'select public.expire_stale_hazards(72)');
exception when others then
  raise notice 'pg_cron not enabled - use the "Hide stale hazards" button on the admin site instead (%).', sqlerrm;
end $$;

-- =====================================================================
-- 4b. REPEAT OFFENDERS / SPAM  (admin only)
-- =====================================================================
create or replace function public.admin_flagged_users()
returns table (user_id uuid, reports_against int, hazards_7d int, hazards_removed int, reasons text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not allowed'; end if;
  return query
  with rep as (select reported_user_id as uid, count(*)::int c from public.chat_reports group by 1),
       haz as (select h.user_id as uid, count(*)::int c from public.hazards h
               where h.reported_at > now() - interval '7 days' group by 1),
       rem as (select r.user_id as uid, count(*)::int c from public.hazard_removals r
               where r.removed_by_admin group by 1),
       ids as (select uid from rep union select uid from haz union select uid from rem)
  select p.id,
         coalesce(rep.c, 0), coalesce(haz.c, 0), coalesce(rem.c, 0),
         trim(both ', ' from
           (case when coalesce(rep.c, 0) >= 3 then 'reported ' || rep.c || 'x, ' else '' end) ||
           (case when coalesce(haz.c, 0) >= 15 then haz.c || ' hazards in 7 days, ' else '' end) ||
           (case when coalesce(rem.c, 0) >= 2 then rem.c || ' hazards removed by admin, ' else '' end))
  from ids
  join public.profiles p on p.id = ids.uid
  left join rep on rep.uid = ids.uid
  left join haz on haz.uid = ids.uid
  left join rem on rem.uid = ids.uid
  where coalesce(rep.c, 0) >= 3 or coalesce(haz.c, 0) >= 15 or coalesce(rem.c, 0) >= 2
  order by coalesce(rep.c, 0) + coalesce(rem.c, 0) desc;
end $$;
revoke all on function public.admin_flagged_users() from public;
grant execute on function public.admin_flagged_users() to authenticated;

-- =====================================================================
-- 3. LOCATION PRIVACY
-- Every activity keeps its full route for its owner, plus public_route:
-- the same route with the first and last `privacy_zone_m` metres removed.
-- Other users' screens (feed) read public_route, so home/work are not exposed.
-- =====================================================================
alter table public.activities add column if not exists public_route jsonb;

create or replace function public.trim_route(p_route jsonb, p_zone int) returns jsonb
language plpgsql immutable as $$
declare
  n int; i int; s int := 0; e int; acc double precision := 0;
  total double precision := 0;
  d double precision[];
  la1 double precision; lo1 double precision; la2 double precision; lo2 double precision;
  a double precision;
begin
  if p_route is null or jsonb_typeof(p_route) <> 'array' then return '[]'::jsonb; end if;
  n := jsonb_array_length(p_route);
  if n < 2 then return '[]'::jsonb; end if;
  if p_zone <= 0 then return p_route; end if;

  -- cumulative distance (m) at each point, haversine
  d := array_fill(0::double precision, array[n]);
  for i in 1 .. n - 1 loop
    la1 := radians((p_route->(i-1)->>'lat')::double precision);
    lo1 := radians((p_route->(i-1)->>'lng')::double precision);
    la2 := radians((p_route->i->>'lat')::double precision);
    lo2 := radians((p_route->i->>'lng')::double precision);
    a := sin((la2-la1)/2)^2 + cos(la1)*cos(la2)*sin((lo2-lo1)/2)^2;
    total := total + 2 * 6371000 * asin(least(1, sqrt(a)));
    d[i+1] := total;
  end loop;

  if total < p_zone * 2 + 50 then return '[]'::jsonb;  -- too short to share safely
  end if;

  return coalesce((
    select jsonb_agg(p_route->(k-1) order by k)
    from generate_series(1, n) k
    where d[k] >= p_zone and d[k] <= total - p_zone
  ), '[]'::jsonb);
exception when others then
  return '[]'::jsonb;   -- if anything is odd, share nothing rather than too much
end $$;

create or replace function public.set_public_route() returns trigger
language plpgsql security definer set search_path = public as $$
declare zone int; v jsonb;
begin
  select coalesce(privacy_zone_m, 200) into zone from public.profiles where id = new.user_id;
  v := to_jsonb(new.route);
  if jsonb_typeof(v) = 'string' then v := (new.route::text)::jsonb; end if;
  new.public_route := public.trim_route(v, coalesce(zone, 200));
  return new;
end $$;
drop trigger if exists set_public_route on public.activities;
create trigger set_public_route before insert or update of route on public.activities
  for each row execute function public.set_public_route();

-- when someone changes their privacy distance, recompute their activities
create or replace function public.refresh_public_routes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.privacy_zone_m is distinct from old.privacy_zone_m then
    update public.activities set route = route where user_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists refresh_public_routes on public.profiles;
create trigger refresh_public_routes after update of privacy_zone_m on public.profiles
  for each row execute function public.refresh_public_routes();

-- back-fill existing activities
update public.activities set route = route;

-- =====================================================================
-- 5. DELETE ACCOUNT
-- =====================================================================
-- Removes everything a user owns, then the sign-in account. Works even if
-- some foreign keys don't cascade: every public table with a user column
-- is cleaned first.
create or replace function public.purge_user_data(uid uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare r record;
begin
  for r in
    select c.table_name, c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
    where c.table_schema = 'public'
      and c.column_name in ('user_id','sender_id','reporter_id','reported_user_id','blocker_id','blocked_id',
                            'verifier_id','actor_id','original_user_id','owner_id')
      and c.table_name not in ('admin_audit_log','hazard_removals')
  loop
    begin
      execute format('delete from public.%I where %I = $1', r.table_name, r.column_name) using uid;
    exception when others then
      raise notice 'skip %.%: %', r.table_name, r.column_name, sqlerrm;
    end;
  end loop;
  begin delete from public.profiles where id = uid; exception when others then null; end;
  -- profile picture / uploads in storage owned by this user
  begin delete from storage.objects where owner = uid; exception when others then null; end;
  delete from auth.users where id = uid;
end $$;
revoke all on function public.purge_user_data(uuid) from public;

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if coalesce((select is_admin from public.profiles where id = auth.uid()), false) then
    raise exception 'Admins must be demoted before deleting their account';
  end if;
  perform public.purge_user_data(auth.uid());
end $$;
revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- admin delete now uses the same purge and is written to the audit log
create or replace function public.admin_delete_user(target uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
declare em text;
begin
  if not public.is_admin() then raise exception 'Not allowed'; end if;
  if target = auth.uid() then raise exception 'You cannot delete your own account'; end if;
  if coalesce((select p.is_admin from public.profiles p where p.id = target), false) then
    raise exception 'Remove admin rights first';
  end if;
  select email into em from auth.users where id = target;
  perform public.write_audit('delete user', 'auth.users', target::text, jsonb_build_object('email', em));
  perform public.purge_user_data(target);
end $$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;
