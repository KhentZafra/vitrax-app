-- 038: up to 5 photos per hazard report.
-- Run once in the Supabase SQL editor BEFORE using the new app build. Safe to re-run.
--
-- Photos live in a private bucket "hazard-photos" at <user id>/<hazard id>/<name>.jpg.
-- Any signed-in user can view them (hazards are community information); only the
-- reporter can add or delete their own; admins can delete any.

create table if not exists public.hazard_photos (
  id uuid primary key default gen_random_uuid(),
  hazard_id uuid not null references public.hazards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  path text not null,
  created_at timestamptz not null default now()
);
create index if not exists hazard_photos_hazard_idx on public.hazard_photos (hazard_id);

alter table public.hazard_photos enable row level security;

drop policy if exists "Signed-in users view hazard photos" on public.hazard_photos;
create policy "Signed-in users view hazard photos" on public.hazard_photos
  for select to authenticated using (true);

drop policy if exists "Reporter adds own hazard photos" on public.hazard_photos;
create policy "Reporter adds own hazard photos" on public.hazard_photos
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.hazards h where h.id = hazard_id and h.user_id = auth.uid())
  );

drop policy if exists "Reporter or admin deletes hazard photos" on public.hazard_photos;
create policy "Reporter or admin deletes hazard photos" on public.hazard_photos
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- Maximum 5 photos per hazard.
create or replace function public.limit_hazard_photos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.hazard_photos where hazard_id = new.hazard_id) >= 5 then
    raise exception 'A hazard can have at most 5 photos.';
  end if;
  return new;
end $$;
drop trigger if exists limit_hazard_photos on public.hazard_photos;
create trigger limit_hazard_photos before insert on public.hazard_photos
  for each row execute function public.limit_hazard_photos();

-- When a photo row goes away (hazard removed, cleared, undone or deleted by an admin),
-- remove the file too so storage does not fill up.
create or replace function public.delete_hazard_photo_file() returns trigger
language plpgsql security definer set search_path = public, storage as $$
begin
  delete from storage.objects where bucket_id = 'hazard-photos' and name = old.path;
  return old;
end $$;
drop trigger if exists delete_hazard_photo_file on public.hazard_photos;
create trigger delete_hazard_photo_file after delete on public.hazard_photos
  for each row execute function public.delete_hazard_photo_file();

-- Private bucket, 3 MB per photo, images only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('hazard-photos', 'hazard-photos', false, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 3145728;

drop policy if exists "Users upload own hazard photos" on storage.objects;
create policy "Users upload own hazard photos" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'hazard-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Signed-in users view hazard photo files" on storage.objects;
create policy "Signed-in users view hazard photo files" on storage.objects
  for select to authenticated using (bucket_id = 'hazard-photos');

drop policy if exists "Users delete own hazard photo files" on storage.objects;
create policy "Users delete own hazard photo files" on storage.objects
  for delete to authenticated
  using (bucket_id = 'hazard-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
