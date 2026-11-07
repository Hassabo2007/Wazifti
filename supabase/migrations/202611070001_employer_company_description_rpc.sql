create or replace function public.update_owned_company_description(p_company_id uuid, p_description text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.companies
     set description = nullif(btrim(p_description), '')
   where id = p_company_id
     and owner_id = auth.uid();

  if not found then
    raise exception 'Company not found or access denied';
  end if;
end;
$$;

revoke all on function public.update_owned_company_description(uuid, text) from public;
grant execute on function public.update_owned_company_description(uuid, text) to authenticated;
