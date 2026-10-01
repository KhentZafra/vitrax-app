-- 011_profile_avatars.sql
-- Adds profile picture support: a column on `profiles` plus a storage
-- bucket (and its access policies) to hold the actual image files.
-- Run this once in Supabase Dashboard -> SQL Editor -> New query -> Run.

-- 1. Column that stores each user's avatar URL (null = no photo set).
alter table public.profiles add column if not exists avatar_url text;

-- 2. Storage bucket for avatar files. Public so avatar images can be
--    displayed anywhere in the app (chat, feed, routes, challenges,
--    home) without needing a signed URL per request.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 3. Access policies for that bucket, mirroring the same
--    one-file-per-user-id pattern already used by activity-photos and
--    community-media: anyone can view, but a user can only write to a
--    path matching their own user id ({user_id}.jpg).

drop policy if exists "Avatar images are publicly accessible" on storage.objects;
create policy "Avatar images are publicly accessible"
on storage.objects for select
using (bucket_id = 'avatars');

drop policy if exists "Users can upload their own avatar" on storage.objects;
create policy "Users can upload their own avatar"
on storage.objects for insert
with check (
  bucket_id = 'avatars'
  and name = auth.uid()::text || '.jpg'
);

drop policy if exists "Users can update their own avatar" on storage.objects;
create policy "Users can update their own avatar"
on storage.objects for update
using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg')
with check (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');

drop policy if exists "Users can delete their own avatar" on storage.objects;
create policy "Users can delete their own avatar"
on storage.objects for delete
using (bucket_id = 'avatars' and name = auth.uid()::text || '.jpg');
