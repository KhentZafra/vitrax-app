-- 012_auto_create_profile.sql
-- Creates each user's `profiles` row automatically right when their auth
-- account is created, instead of relying on the Flutter app to insert it
-- itself right after sign-up.
--
-- Why this was broken: supabase.auth.signUp() does NOT give the calling
-- client an authenticated session while email confirmation is required
-- (Authentication -> Providers -> Email -> "Confirm email" is ON for this
-- project). So the insert the app used to run immediately after signUp()
-- was sent unauthenticated, and the profiles table's row-level security
-- policy (which only allows a user to insert their own row, matched via
-- auth.uid() = id) correctly rejected it:
--
--   PostgrestException(message: new row violates row-level security
--   policy for table "profiles", code: 42501)
--
-- Fix: a SECURITY DEFINER trigger on auth.users runs with elevated
-- privileges and bypasses that RLS check entirely, so the profile row
-- is always created, regardless of email-confirmation state. The app's
-- signUp() call now passes first_name/last_name/primary_activity as
-- user metadata so this trigger can read them back out.
--
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, first_name, last_name, email, primary_activity)
  values (
    new.id,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.email,
    coalesce(new.raw_user_meta_data ->> 'primary_activity', 'Cyclist')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
