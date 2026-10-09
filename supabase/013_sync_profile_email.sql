-- Keeps public.profiles.email in step with auth.users.email.
-- When a user changes their email from Edit Profile, Supabase only updates
-- auth.users after they open the confirmation link; this copies the new
-- address into profiles at that moment.
-- Run once in Supabase Dashboard -> SQL Editor -> New query -> Run.

create or replace function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles set email = new.email where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function public.sync_profile_email();
