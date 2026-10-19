-- 021_consent.sql
-- Records that each user accepted the Privacy Policy and Terms of Use
-- (Data Privacy Act, RA 10173). Run once in the Supabase SQL Editor. Safe to re-run.
--
-- New sign-ups pass consent_version / consent_at in their sign-up
-- metadata and this copies them to the profile. Existing users have NULL
-- and are asked to accept once the next time they open the app.

alter table public.profiles add column if not exists consent_version text;
alter table public.profiles add column if not exists consent_at timestamptz;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, first_name, last_name, email, primary_activity, consent_version, consent_at)
  values (
    new.id,
    new.raw_user_meta_data ->> 'first_name',
    new.raw_user_meta_data ->> 'last_name',
    new.email,
    coalesce(new.raw_user_meta_data ->> 'primary_activity', 'Cyclist'),
    new.raw_user_meta_data ->> 'consent_version',
    nullif(new.raw_user_meta_data ->> 'consent_at', '')::timestamptz
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- (the trigger on auth.users from 012 keeps pointing at this function)
