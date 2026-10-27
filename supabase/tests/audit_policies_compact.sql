-- READ-ONLY. Returns every database rule as ONE block of text.
-- Run it, click the single result cell, copy it, and paste it to me.
select string_agg(
  tablename || ' | ' || cmd || ' | ' || policyname || ' | roles=' || array_to_string(roles, ',') ||
  ' | using=' || coalesce(qual, '-') || ' | check=' || coalesce(with_check, '-'),
  E'\n' order by tablename, cmd, policyname
) as all_policies
from pg_policies
where schemaname = 'public';
