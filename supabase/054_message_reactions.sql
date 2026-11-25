-- 054_message_reactions.sql
-- Emoji reactions on chat messages (long-press a message). One reaction per
-- person per message; tapping the same emoji again removes it.
-- Run once in the Supabase SQL Editor. Safe to re-run.
--
-- UNDO: drop table public.message_reactions;

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists message_reactions_conv_idx on public.message_reactions (conversation_id);

-- The conversation is always taken from the message itself (a phone cannot lie about it).
create or replace function public.reaction_set_conversation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select conversation_id into new.conversation_id from public.messages where id = new.message_id;
  return new;
end $$;
revoke all on function public.reaction_set_conversation() from public, anon, authenticated;

drop trigger if exists reaction_set_conversation on public.message_reactions;
create trigger reaction_set_conversation before insert or update of message_id on public.message_reactions
  for each row execute function public.reaction_set_conversation();

-- Is the signed-in person part of this conversation?
create or replace function public.in_conversation(p_conv uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.conversation_participants p
                  where p.conversation_id = p_conv and p.user_id = auth.uid())
$$;
grant execute on function public.in_conversation(uuid) to authenticated;

alter table public.message_reactions enable row level security;

drop policy if exists "Members read reactions" on public.message_reactions;
create policy "Members read reactions" on public.message_reactions for select to authenticated
  using (public.in_conversation(conversation_id));

drop policy if exists "Members add own reaction" on public.message_reactions;
create policy "Members add own reaction" on public.message_reactions for insert to authenticated
  with check (user_id = auth.uid()
              and public.in_conversation((select m.conversation_id from public.messages m where m.id = message_id)));

drop policy if exists "Members change own reaction" on public.message_reactions;
create policy "Members change own reaction" on public.message_reactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Members remove own reaction" on public.message_reactions;
create policy "Members remove own reaction" on public.message_reactions for delete to authenticated
  using (user_id = auth.uid());

do $$ begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null; end $$;
