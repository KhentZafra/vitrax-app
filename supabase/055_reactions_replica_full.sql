-- 055_reactions_replica_full.sql
-- Makes a removed reaction disappear live on the other phone too (Realtime
-- needs the full old row to match the conversation filter on deletes).
-- Run once in the Supabase SQL Editor. Safe to re-run.
alter table public.message_reactions replica identity full;
