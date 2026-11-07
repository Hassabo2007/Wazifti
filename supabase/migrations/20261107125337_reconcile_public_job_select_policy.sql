-- Keep anonymous published-job reads independent of private company owner fields.
-- Authenticated employers retain access to their own jobs, including pending jobs.
-- Drop both legacy and current policy names so this migration is safe to re-run
-- and can reconcile databases where the SQL was previously applied manually.
drop policy if exists "Public view published jobs" on public.jobs;
drop policy if exists "Anonymous view published jobs" on public.jobs;
drop policy if exists "Authenticated view published and own jobs" on public.jobs;

create policy "Anonymous view published jobs"
  on public.jobs
  for select
  to anon
  using (status = 'published');

create policy "Authenticated view published and own jobs"
  on public.jobs
  for select
  to authenticated
  using (
    status = 'published'
    or exists (
      select 1
      from public.companies c
      where c.id = jobs.company_id
        and c.owner_id = (select auth.uid())
    )
  );
