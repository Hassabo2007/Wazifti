create or replace function public.auto_publish_verified_company_jobs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Company verification does not publish jobs automatically.
  -- Every newly submitted job remains pending until an admin approves it.
  return new;
end;
$$;
