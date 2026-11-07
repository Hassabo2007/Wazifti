-- Ensure the public verified-company view follows caller RLS and exposes only
-- explicitly granted columns. This prevents the view owner from bypassing RLS.
create or replace view public.public_verified_companies
with (security_invoker = true, security_barrier = true)
as
select id, company_name, description
from public.companies
where status = 'verified';

-- Limit anonymous access to the public-facing company fields only.
revoke all privileges on table public.companies from anon;
revoke all privileges on table public.companies from authenticated;

grant select (id, company_name, description)
  on table public.companies to anon;

-- Authenticated app flows need these columns for owner and admin dashboards.
grant select (id, owner_id, company_name, description, website, status, created_at)
  on table public.companies to authenticated;

grant insert (owner_id, company_name, description, website, status)
  on table public.companies to authenticated;

grant update (status)
  on table public.companies to authenticated;

drop policy if exists "Public can view verified companies" on public.companies;
create policy "Public can view verified companies"
  on public.companies
  for select
  to anon, authenticated
  using (status = 'verified');

-- The description RPC checks auth.uid() and company ownership explicitly.
-- An empty search_path prevents object-shadowing attacks.
alter function public.update_owned_company_description(uuid, text)
  set search_path = '';
