-- 037: winner confirms (or disputes) a prize that the creator marked as paid.
-- Run once in the Supabase SQL editor BEFORE using the new app build and admin.
-- Safe to re-run.

alter table public.challenge_prize_payments
  add column if not exists marked_paid_at timestamptz default now(),
  add column if not exists confirmed_at   timestamptz;

-- Log of disputes ("I did not receive it") for admins to review.
create table if not exists public.prize_disputes (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  winner_user_id uuid not null references auth.users(id) on delete cascade,
  creator_id uuid not null references auth.users(id) on delete cascade,
  note text,
  status text not null default 'open' check (status in ('open','upheld','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id)
);
create unique index if not exists prize_disputes_one_open
  on public.prize_disputes (challenge_id, winner_user_id) where status = 'open';

alter table public.prize_disputes enable row level security;
drop policy if exists "Parties and admins read disputes" on public.prize_disputes;
create policy "Parties and admins read disputes" on public.prize_disputes
  for select to authenticated
  using (winner_user_id = auth.uid() or creator_id = auth.uid() or public.is_admin());
-- No insert/update/delete policies: all changes go through the functions below.

-- Winner: "I received it".
create or replace function public.confirm_prize_receipt(p_challenge uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.challenge_prize_payments
     set confirmed_at = now()
   where challenge_id = p_challenge and winner_user_id = auth.uid() and confirmed_at is null;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- Winner: "I did not receive it".
create or replace function public.dispute_prize(p_challenge uuid, p_note text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare pay record; ch record;
begin
  select * into pay from public.challenge_prize_payments
   where challenge_id = p_challenge and winner_user_id = auth.uid();
  if pay.challenge_id is null then return false; end if;       -- nothing marked as paid
  if pay.confirmed_at is not null then return false; end if;   -- already confirmed
  select id, title, creator_id into ch from public.challenges where id = p_challenge;
  insert into public.prize_disputes (challenge_id, winner_user_id, creator_id, note)
  values (p_challenge, auth.uid(), ch.creator_id, nullif(trim(coalesce(p_note,'')), ''))
  on conflict do nothing;
  begin
    perform public.push_challenge(array[ch.creator_id], 'Vitrax Challenges',
      'The winner says they did not receive the prize for "' || ch.title || '". An admin will review it.', ch.id);
  exception when others then null;
  end;
  return true;
end $$;

-- Admin: settle a dispute. p_upheld = true  -> the prize was NOT paid (payment mark removed,
--                           creator must pay again); false -> payment was real (counts as confirmed).
create or replace function public.resolve_prize_dispute(p_dispute uuid, p_upheld boolean, p_note text default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare d record; ch record;
begin
  if not public.is_admin() then raise exception 'admins only'; end if;
  select * into d from public.prize_disputes where id = p_dispute and status = 'open';
  if d.id is null then return false; end if;
  update public.prize_disputes
     set status = case when p_upheld then 'upheld' else 'rejected' end,
         admin_note = nullif(trim(coalesce(p_note,'')), ''),
         resolved_at = now(), resolved_by = auth.uid()
   where id = p_dispute;
  if p_upheld then
    delete from public.challenge_prize_payments
     where challenge_id = d.challenge_id and winner_user_id = d.winner_user_id;
  else
    update public.challenge_prize_payments set confirmed_at = now()
     where challenge_id = d.challenge_id and winner_user_id = d.winner_user_id;
  end if;
  select id, title into ch from public.challenges where id = d.challenge_id;
  begin
    perform public.push_challenge(array[d.winner_user_id, d.creator_id], 'Vitrax Challenges',
      case when p_upheld
        then 'An admin ruled that the prize for "' || ch.title || '" was not paid. The creator must send it.'
        else 'An admin ruled that the prize for "' || ch.title || '" was paid.' end, ch.id);
  exception when others then null;
  end;
  return true;
end $$;

-- A creator who still owes a prize (open dispute, or upheld and not re-paid)
-- cannot start a new challenge with a prize.
create or replace function public.block_prize_if_unpaid() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.prize_amount, 0) > 0 and exists (
    select 1 from public.prize_disputes d
    where d.creator_id = new.creator_id
      and (d.status = 'open'
           or (d.status = 'upheld' and not exists (
                 select 1 from public.challenge_prize_payments p
                 where p.challenge_id = d.challenge_id and p.winner_user_id = d.winner_user_id)))
  ) then
    raise exception 'You have an unpaid prize under dispute. Settle it before creating a new prize challenge.';
  end if;
  return new;
end $$;
drop trigger if exists block_prize_if_unpaid on public.challenges;
create trigger block_prize_if_unpaid before insert on public.challenges
  for each row execute function public.block_prize_if_unpaid();

-- Tell the winner to confirm when the creator marks the prize as paid.
create or replace function public.push_prize_paid() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c record;
begin
  select id, title into c from public.challenges where id = new.challenge_id;
  if c.id is null then return new; end if;
  perform public.push_challenge(array[new.winner_user_id], 'Vitrax Challenges',
    'Your prize for "' || c.title || '" was marked as paid. Open the challenge and confirm that you received it.', c.id);
  return new;
exception when others then
  return new;
end $$;

grant execute on function public.confirm_prize_receipt(uuid) to authenticated;
grant execute on function public.dispute_prize(uuid, text) to authenticated;
grant execute on function public.resolve_prize_dispute(uuid, boolean, text) to authenticated;
revoke execute on function public.block_prize_if_unpaid() from public, anon, authenticated;
