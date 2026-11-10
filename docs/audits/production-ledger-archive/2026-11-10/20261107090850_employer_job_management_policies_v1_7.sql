drop policy if exists "Verified companies create jobs" on public.jobs;
create policy "Verified companies create pending jobs"
on public.jobs for insert to authenticated
with check (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
);

drop policy if exists "Employers update own pending jobs" on public.jobs;
create policy "Employers update own pending jobs"
on public.jobs for update to authenticated
using (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
)
with check (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
);

drop policy if exists "Employers delete own non-published jobs" on public.jobs;
create policy "Employers delete own non-published jobs"
on public.jobs for delete to authenticated
using (
  status in ('pending','closed','rejected')
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
  )
);
