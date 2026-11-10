create or replace function public.guard_application_updates()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  -- Preserve unrestricted maintenance and trusted server-side operations.
  if current_user in ('postgres', 'supabase_admin')
     or coalesce(auth.role(), '') = 'service_role'
     or public.is_admin() then
    return new;
  end if;

  -- Employers may change only the application status.
  if (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status') then
    raise exception 'You may update only the application status.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

drop trigger if exists guard_application_updates on public.applications;

create trigger guard_application_updates
before update on public.applications
for each row
execute function public.guard_application_updates();
