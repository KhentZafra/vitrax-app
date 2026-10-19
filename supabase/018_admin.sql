-- 018_admin.sql
-- Backend for the VITRAX admin website (admin/ folder).
-- Run once in Supabase SQL Editor. Safe to run again.
--
-- Security model: the website uses only the public anon key and signs in
-- with a normal Supabase account. What that account may see or change is
-- decided HERE, by row-level security, only if profiles.is_admin = true.
-- Nothing in the browser can grant admin rights to itself.

-- ---------------------------------------------------------------- flags
alter table public.profiles add column if not exists is_admin boolean not null default false;
alter table public.profiles add column if not exists is_suspended boolean not null default false;

-- ------------------------------------------------------------ is_admin()
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false)
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- ---------------------------------------- nobody can promote themselves
-- Users may edit their own profile row (name, photo...) but must never be
-- able to flip is_admin / is_suspended on it. Only an existing admin - or
-- you, from the SQL Editor (no auth.uid() there) - can change them.
create or replace function public.guard_profile_admin_cols() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.is_admin := false;
      new.is_suspended := false;
    elsif new.is_admin is distinct from old.is_admin
       or new.is_suspended is distinct from old.is_suspended then
      raise exception 'Not allowed';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_profile_admin_cols on public.profiles;
create trigger guard_profile_admin_cols before insert or update on public.profiles
  for each row execute function public.guard_profile_admin_cols();

-- ------------------------------------------------------- admin policies
-- Extra (permissive) policies: they only ADD access for admins and leave
-- every existing app policy untouched. Tables that don't exist are skipped.
do $$
declare r record; pname text;
begin
  for r in select * from (values
    ('profiles','select'), ('profiles','update'),
    ('activities','select'), ('activities','delete'),
    ('community_posts','select'), ('community_posts','delete'),
    ('post_likes','select'), ('activity_likes','select'),
    ('feed_comments','select'), ('feed_comments','delete'),
    ('hazards','select'), ('hazards','delete'),
    ('hazard_verifications','select'), ('hazard_clear_confirmations','select'),
    ('challenges','select'), ('challenges','delete'),
    ('challenge_participants','select'),
    ('challenge_prize_payments','select'), ('challenge_prize_payments','insert'),
    ('chat_reports','select'), ('chat_reports','delete'),
    ('blocked_users','select')
  ) as t(tbl, cmd) loop
    if to_regclass('public.' || r.tbl) is null then continue; end if;
    pname := 'admin_' || r.cmd || '_' || r.tbl;
    execute format('drop policy if exists %I on public.%I', pname, r.tbl);
    if r.cmd = 'insert' then
      execute format('create policy %I on public.%I for insert to authenticated with check (public.is_admin())', pname, r.tbl);
    elsif r.cmd = 'update' then
      execute format('create policy %I on public.%I for update to authenticated using (public.is_admin()) with check (public.is_admin())', pname, r.tbl);
    else
      execute format('create policy %I on public.%I for %s to authenticated using (public.is_admin())', pname, r.tbl, r.cmd);
    end if;
  end loop;
end $$;

-- ------------------------------------------------- account list (admin)
-- Sign-up and last-login times live in auth.users, which the browser can
-- never read directly. This function returns them to admins only.
create or replace function public.admin_list_users()
returns table (id uuid, email text, created_at timestamptz, last_sign_in_at timestamptz, email_confirmed_at timestamptz)
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Not allowed'; end if;
  return query
    select u.id, u.email::text, u.created_at, u.last_sign_in_at, u.email_confirmed_at
    from auth.users u order by u.created_at desc;
end $$;
revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

-- ------------------------------------------------ delete an account
-- Removes the sign-in account (and, through the existing foreign keys,
-- the data that belongs to it). Refuses to delete yourself or another admin.
create or replace function public.admin_delete_user(target uuid) returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Not allowed'; end if;
  if target = auth.uid() then raise exception 'You cannot delete your own account'; end if;
  if coalesce((select p.is_admin from public.profiles p where p.id = target), false) then
    raise exception 'Remove admin rights first';
  end if;
  delete from auth.users where id = target;
end $$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- ------------------------------------------------------- FIRST ADMIN
-- Make yourself the first admin (replace with the email you sign in with):
--
--   update public.profiles set is_admin = true where email = 'YOUR_EMAIL_HERE';
