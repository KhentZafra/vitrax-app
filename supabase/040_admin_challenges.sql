-- 040: admins can create official challenges (with optional prizes).
-- Run once in the Supabase SQL Editor (after 039). Safe to re-run.

alter table public.challenges add column if not exists is_official boolean not null default false;

-- Only admins may mark a challenge as official.
create or replace function public.guard_official_flag() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.is_official, false) and not public.is_admin() then
    new.is_official := false;
  end if;
  return new;
end $$;
drop trigger if exists guard_official_flag on public.challenges;
create trigger guard_official_flag before insert on public.challenges
  for each row execute function public.guard_official_flag();

-- Admin may insert challenges (the creator is the admin's own account).
drop policy if exists admin_insert_challenges on public.challenges;
create policy admin_insert_challenges on public.challenges
  for insert to authenticated
  with check (public.is_admin() and creator_id = auth.uid());

-- Tell every active user when an official challenge is posted.
create or replace function public.push_official_challenge() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare recipients uuid[];
begin
  if not coalesce(new.is_official, false) then return new; end if;
  select array_agg(id) into recipients from public.profiles
    where coalesce(is_suspended, false) = false and id <> new.creator_id;
  perform public.push_challenge(recipients, 'New Vitrax challenge',
    '"' || new.title || '"' ||
    case when coalesce(new.prize_amount, 0) > 0
      then ' with a ₱' || trim(to_char(new.prize_amount, 'FM999,999,990')) || ' prize'
      else '' end || '. Join now!', new.id);
  return new;
exception when others then
  return new;
end $$;
drop trigger if exists on_official_challenge_push on public.challenges;
create trigger on_official_challenge_push after insert on public.challenges
  for each row execute function public.push_official_challenge();
revoke execute on function public.push_official_challenge() from public, anon, authenticated;
