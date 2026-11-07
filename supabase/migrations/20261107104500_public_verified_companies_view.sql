-- Expose only public-facing fields for verified companies.
-- This avoids granting anonymous users access to private company ownership data.
create or replace view public.public_verified_companies
with (security_barrier = true)
as
select id, company_name, description
from public.companies
where status = 'verified';

grant select on public.public_verified_companies to anon, authenticated;
