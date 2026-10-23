-- 026_chat_archive_delete.sql
-- Per-person archive and delete for chats (the long-press menu in the chat list).
-- Both are stored on YOUR row in conversation_participants, so archiving or
-- deleting a conversation never affects the other person.
--   archived_at: set while the chat sits in "Archived chats".
--   deleted_at:  set when you delete the conversation. Messages up to that
--                moment are hidden from you; a new message brings the chat
--                back with only the newer messages.
-- The existing UPDATE policy ("Users can mark their own participation read")
-- already lets you change only your own row. Run once in the Supabase SQL
-- Editor. Safe to re-run.

alter table public.conversation_participants
  add column if not exists archived_at timestamptz,
  add column if not exists deleted_at timestamptz;
