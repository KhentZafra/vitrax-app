-- 036: proof of payment for challenge prizes.
-- The creator attaches a screenshot of the GCash receipt when marking a
-- prize as paid. Only the creator and the winner can see it.
-- Run this once in the Supabase SQL editor BEFORE using the new app build.

alter table public.challenge_prize_payments
  add column if not exists proof_url text;

-- Private bucket: receipts are never public. Path: <creator id>/<challenge id>.jpg
insert into storage.buckets (id, name, public, file_size_limit)
values ('prize-proofs', 'prize-proofs', false, 5242880)
on conflict (id) do update set public = false, file_size_limit = 5242880;

drop policy if exists "Creator uploads prize proof" on storage.objects;
create policy "Creator uploads prize proof"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'prize-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Creator replaces prize proof" on storage.objects;
create policy "Creator replaces prize proof"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'prize-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Creator, winner and admin view prize proof" on storage.objects;
create policy "Creator, winner and admin view prize proof"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'prize-proofs'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
      or exists (
        select 1
        from public.challenge_prize_payments p
        where p.proof_url = name
          and p.winner_user_id = auth.uid()
      )
    )
  );
