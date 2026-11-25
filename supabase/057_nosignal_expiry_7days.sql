-- 057: No Signal pins expire after 7 days unless someone loses signal there again.
-- Age is counted from restored_at (set by admin Restore or by a renewal) else reported_at.
-- The hourly pg_cron job from 019 already calls expire_stale_hazards, so no new job is needed.
--
-- UNDO: re-run the function body from 048_hazard_expiry_rules.sql.

create or replace function public.expire_stale_hazards(p_hours int default 72) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.hazards h
     set shared = false, status = 'expired', expired_at = now()
   where h.shared = true
     and (
       -- No Signal: 7 days from the last time it was seen or restored
       (lower(h.type::text) = 'nosignal'
        and coalesce(h.restored_at, h.reported_at) < now() - interval '7 days')
       or
       -- everything else: as in 048, only if nobody verified it
       (lower(h.type::text) <> 'nosignal'
        and coalesce(h.restored_at, h.reported_at) <
            now() - case when lower(h.type::text) = 'roadconstruction'
                         then interval '30 days'
                         else make_interval(hours => p_hours) end
        and not exists (select 1 from public.hazard_verifications v where v.hazard_id = h.id))
     );
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.expire_stale_hazards(int) from public;

-- Called by the app when a rider loses signal inside an area that is already pinned.
-- Restarts the 7-day clock. At most once per hour per pin; No Signal pins only.
create or replace function public.renew_no_signal(p_ids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if auth.uid() is null then return 0; end if;
  update public.hazards h
     set restored_at = now()
   where h.id = any(p_ids)
     and h.shared = true
     and lower(h.type::text) = 'nosignal'
     and coalesce(h.restored_at, h.reported_at) < now() - interval '1 hour';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.renew_no_signal(uuid[]) from public;
grant execute on function public.renew_no_signal(uuid[]) to authenticated;
