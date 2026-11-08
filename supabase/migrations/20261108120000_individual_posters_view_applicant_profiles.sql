-- Allow an individual job poster to view only the profiles of people
-- who applied to that poster's own individual job.
create policy "Individual job posters view applicant profiles"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.applications a
    join public.jobs j on j.id = a.job_id
    where a.candidate_id = profiles.id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
);
