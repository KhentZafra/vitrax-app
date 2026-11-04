-- 039: no-signal areas recorded automatically as a stretch (start, end, length).
-- Run once in the Supabase SQL editor BEFORE using the new app build. Safe to re-run.
alter table public.hazards
  add column if not exists end_lat   double precision,
  add column if not exists end_lng   double precision,
  add column if not exists length_m  double precision,
  add column if not exists auto_detected boolean not null default false;
