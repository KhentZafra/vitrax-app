-- 047: lets an admin edit the TITLE and DESCRIPTION of a challenge, nothing else.
-- Dates, target and prize stay fixed on purpose: changing them after people
-- joined would change who is winning. No notification is sent when it is edited.
--
-- Undo: drop function public.admin_edit_challenge(uuid, text, text);

create or replace function public.admin_edit_challenge(p_challenge uuid, p_title text, p_description text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  if p_title is null or length(trim(p_title)) = 0 or length(p_title) > 80 then
    raise exception 'bad_title';
  end if;
  if p_description is not null and length(p_description) > 400 then
    raise exception 'bad_description';
  end if;
  update public.challenges
     set title = trim(p_title),
         description = nullif(trim(coalesce(p_description, '')), '')
   where id = p_challenge;
  if not found then
    raise exception 'not_found';
  end if;
end $$;

revoke all on function public.admin_edit_challenge(uuid, text, text) from public, anon;
grant execute on function public.admin_edit_challenge(uuid, text, text) to authenticated;
