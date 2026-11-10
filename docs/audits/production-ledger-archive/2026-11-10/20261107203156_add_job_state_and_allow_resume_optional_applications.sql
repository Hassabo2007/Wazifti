alter table public.jobs add column if not exists state text;

drop policy if exists "Candidates submit applications" on public.applications;
create policy "Candidates submit applications"
on public.applications
for insert
to authenticated
with check (
  candidate_id = (select auth.uid())
  and (
    resume_id is null
    or private.candidate_owns_resume(resume_id, candidate_id)
  )
  and exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.status = 'published'
  )
);
