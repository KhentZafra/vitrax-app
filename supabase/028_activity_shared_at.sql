-- 028: remember exactly when an activity/route was shared to the community.
alter table public.activities add column if not exists shared_at timestamptz;

-- Existing shared routes: use the time they were saved.
update public.activities set shared_at = created_at where shared = true and shared_at is null;

create or replace function public.set_activity_shared_at()
returns trigger
language plpgsql
security definer set search_path = public as $$
begin
  if new.shared is true and (tg_op = 'INSERT' or old.shared is distinct from true) then
    new.shared_at := now();
  elsif new.shared is not true then
    new.shared_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_activity_shared_at on public.activities;
create trigger trg_activity_shared_at
before insert or update of shared on public.activities
for each row execute function public.set_activity_shared_at();

-- Triggers only; not callable directly by app users.
revoke execute on function public.set_activity_shared_at() from public, anon, authenticated;
