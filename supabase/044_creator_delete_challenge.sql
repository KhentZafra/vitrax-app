-- 044: the creator of a challenge can delete it while nobody else has joined
-- (a mistaken post, or backing out). Once anyone else joins, only an admin can
-- remove it, so participants and prizes are protected.
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- Undo (removes the feature): drop function public.delete_my_challenge(uuid);

create or replace function public.delete_my_challenge(p_challenge uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_creator uuid;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  select creator_id into v_creator from public.challenges where id = p_challenge for update;
  if not found then
    raise exception 'not_found';
  end if;
  if v_creator is distinct from auth.uid() then
    raise exception 'not_creator';
  end if;
  if exists (select 1 from public.challenge_participants
              where challenge_id = p_challenge and user_id <> auth.uid()) then
    raise exception 'others_joined';
  end if;

  delete from public.challenge_participants where challenge_id = p_challenge;
  delete from public.challenges where id = p_challenge;
end $$;

revoke execute on function public.delete_my_challenge(uuid) from public, anon;
grant  execute on function public.delete_my_challenge(uuid) to authenticated;
