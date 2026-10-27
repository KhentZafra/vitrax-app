-- 030_rls_hardening.sql  (version 2)
-- Fixes found while reviewing all 90 row-level-security rules and the storage rules.
-- Safe to run more than once, including if you already ran version 1.

-- ---------------------------------------------------------------------------
-- 1. Logged-out visitors must not be able to read or write app data.
--    Rules written "TO public" also apply to the anon role (anyone holding the
--    public key that ships inside the app). The worst case was activities:
--    anyone could read every shared run, including its GPS route.
-- ---------------------------------------------------------------------------
alter policy "Users can view their own or shared activities" on public.activities to authenticated;
alter policy "Users can insert their own activities"          on public.activities to authenticated;
alter policy "Users can update their own activities"          on public.activities to authenticated;
alter policy "Users can delete their own activities"          on public.activities to authenticated;

alter policy "Users can like as themselves"     on public.activity_likes to authenticated;
alter policy "Users can remove their own like"  on public.activity_likes to authenticated;

alter policy "Users can insert their own hazard reports" on public.hazards to authenticated;
alter policy "Users can update their own hazard reports" on public.hazards to authenticated;
alter policy "Users can delete their own hazard reports" on public.hazards to authenticated;

-- ---------------------------------------------------------------------------
-- 2. A chat participant could edit their own participant row, including
--    conversation_id, which would let them move themselves into someone else's
--    conversation and read it. Only last_read_at / archive fields may change.
-- ---------------------------------------------------------------------------
create or replace function public.guard_conversation_participants()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.conversation_id is distinct from old.conversation_id
     or new.user_id is distinct from old.user_id then
    raise exception 'conversation_id and user_id cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_conversation_participants on public.conversation_participants;
create trigger trg_guard_conversation_participants
  before update on public.conversation_participants
  for each row execute function public.guard_conversation_participants();

revoke execute on function public.guard_conversation_participants() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Clean-up of version 1: profiles are ALREADY protected by the existing
--    guard_profile_admin_cols trigger (018 and 019), so the extra one is removed.
-- ---------------------------------------------------------------------------
drop trigger if exists trg_guard_profile_privileged on public.profiles;
drop function if exists public.guard_profile_privileged_columns();

-- ---------------------------------------------------------------------------
-- 4. GCash QR codes: only the owner, the creator of a challenge the owner
--    joined, and admins may list or download them through the storage API.
--    (Anyone could list every QR code before.)
-- ---------------------------------------------------------------------------
drop policy if exists "Public can view GCash QR codes" on storage.objects;
drop policy if exists "Owner, challenge creator and admin can view GCash QR codes" on storage.objects;
create policy "Owner, challenge creator and admin can view GCash QR codes"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'gcash-qr-codes'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (
        select 1
        from public.challenge_participants cp
        join public.challenges c on c.id = cp.challenge_id
        where cp.user_id::text = (storage.foldername(name))[1]
          and c.creator_id = auth.uid()
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 5. Avatar rules were open to "public" (including logged-out). Logged-in only.
-- ---------------------------------------------------------------------------
alter policy "Users can upload their own avatar" on storage.objects to authenticated;
alter policy "Users can update their own avatar" on storage.objects to authenticated;
alter policy "Users can delete their own avatar" on storage.objects to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Upload size limits so nobody can fill your storage with huge files.
-- ---------------------------------------------------------------------------
update storage.buckets set file_size_limit = 5242880  where id in ('gcash-qr-codes', 'avatars');
update storage.buckets set file_size_limit = 10485760 where id = 'activity-photos';
