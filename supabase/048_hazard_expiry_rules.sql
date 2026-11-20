-- 048: per-type hazard expiry + restore resets the clock
-- No Signal  : never auto-expires
-- Road construction : 30 days if nobody verified it
-- Everything else   : p_hours (default 72h) if nobody verified it
-- Age is counted from restored_at (if an admin restored it) else reported_at.
--
-- UNDO: re-run the expire_stale_hazards body from 019_admin_safety.sql
--   (update ... where shared and reported_at < now() - p_hours and no verifications)

alter table public.hazards add column if not exists restored_at timestamptz;

create or replace function public.expire_stale_hazards(p_hours int default 72) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.hazards h
     set shared = false, status = 'expired', expired_at = now()
   where h.shared = true
     and lower(h.type::text) <> 'nosignal'
     and coalesce(h.restored_at, h.reported_at) <
         now() - case when lower(h.type::text) = 'roadconstruction'
                      then interval '30 days'
                      else make_interval(hours => p_hours) end
     and not exists (select 1 from public.hazard_verifications v where v.hazard_id = h.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.expire_stale_hazards(int) from public;
