-- 029: in-app error log, so crashes on other people's phones are visible.
create table if not exists public.app_errors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message text,
  stack text,
  source text,
  platform text,
  created_at timestamptz not null default now()
);

create index if not exists app_errors_created_idx on public.app_errors (created_at desc);

alter table public.app_errors enable row level security;

-- Any signed-in user may add an error about themselves; only admins can read or clear them.
create policy app_errors_insert_own on public.app_errors
  for insert to authenticated with check (user_id = auth.uid());
create policy app_errors_admin_select on public.app_errors
  for select to authenticated using (public.is_admin());
create policy app_errors_admin_delete on public.app_errors
  for delete to authenticated using (public.is_admin());

-- Spam guard: at most 100 error rows per user per hour.
create or replace function public.limit_app_errors()
returns trigger
language plpgsql
security definer set search_path = public as $$
begin
  if (select count(*) from public.app_errors where user_id = new.user_id and created_at > now() - interval '1 hour') >= 100 then
    raise exception 'error log limit reached';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_limit_app_errors on public.app_errors;
create trigger trg_limit_app_errors before insert on public.app_errors
for each row execute function public.limit_app_errors();

revoke execute on function public.limit_app_errors() from public, anon, authenticated;
