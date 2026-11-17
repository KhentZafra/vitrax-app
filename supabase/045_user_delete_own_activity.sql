-- 045: makes sure a signed-in user can delete THEIR OWN activities (for example
-- a 0.01 km test tap). Safe to re-run. Nobody can delete other people's.
-- Undo: drop policy "Users can delete their own activities" on public.activities;

drop policy if exists "Users can delete their own activities" on public.activities;
create policy "Users can delete their own activities" on public.activities
  for delete to authenticated using (user_id = auth.uid());
