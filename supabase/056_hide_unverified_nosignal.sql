-- 056: hide the false "No signal" pins made by the old dead-zone bug.
-- Only hides (not deletes) No Signal hazards that nobody has verified.
-- UNDO one pin: admin Hazards page -> Restore.
-- UNDO all:     update public.hazards set shared = true, status = 'active', expired_at = null
--               where lower(type::text) = 'nosignal' and expired_at >= now() - interval '1 day';
update public.hazards h
   set shared = false, status = 'expired', expired_at = now()
 where h.shared = true
   and lower(h.type::text) = 'nosignal'
   and not exists (select 1 from public.hazard_verifications v where v.hazard_id = h.id);
