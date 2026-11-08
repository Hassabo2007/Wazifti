-- Wazifti V1.3: close a job when one applicant is accepted and archive it after 30 days.
-- No job or application rows are deleted; historical records remain available to their owners.

alter table public.jobs
  add column if not exists closed_at timestamptz,
  add column if not exists archived_at timestamptz;

create index if not exists jobs_filled_archive_due_idx
  on public.jobs (closed_at)
  where status = 'closed' and archived_at is null and closed_at is not null;

create index if not exists applications_job_status_idx
  on public.applications (job_id, status);

-- Let an individual who posted a job view and manage applications to that job.
drop policy if exists "Individual job owners view applications" on public.applications;
create policy "Individual job owners view applications"
on public.applications
for select
to authenticated
using (
  exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
);

drop policy if exists "Individual job owners update application statuses" on public.applications;
create policy "Individual job owners update application statuses"
on public.applications
for update
to authenticated
using (
  exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
);

-- The trigger serializes acceptance by locking the job row. This prevents two
-- applicants from being accepted for the same vacancy concurrently.
create or replace function private.close_job_when_applicant_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_status text;
begin
  if new.status <> 'accepted' or old.status is not distinct from new.status then
    return new;
  end if;

  select j.status
    into v_job_status
  from public.jobs j
  where j.id = new.job_id
  for update;

  if not found then
    raise exception 'The related job could not be found.';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.';
  end if;

  if exists (
    select 1
    from public.applications a
    where a.job_id = new.job_id
      and a.id <> new.id
      and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.';
  end if;

  update public.jobs
  set status = 'closed',
      closed_at = coalesce(closed_at, now()),
      archived_at = null
  where id = new.job_id;

  return new;
end;
$$;

revoke all on function private.close_job_when_applicant_accepted() from public, anon, authenticated;

drop trigger if exists close_job_when_applicant_accepted on public.applications;
create trigger close_job_when_applicant_accepted
after update of status on public.applications
for each row
execute function private.close_job_when_applicant_accepted();

-- Archive filled jobs after 30 days. This marks records as archived; it does
-- not delete jobs, applications, resumes, or conversations.
create or replace function private.archive_filled_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_archived_count integer;
begin
  update public.jobs
  set archived_at = now()
  where status = 'closed'
    and closed_at is not null
    and archived_at is null
    and closed_at <= now() - interval '30 days';

  get diagnostics v_archived_count = row_count;
  return v_archived_count;
end;
$$;

revoke all on function private.archive_filled_jobs() from public, anon, authenticated;

-- Supabase Cron runs this once daily. The extension is installed only if absent.
create extension if not exists pg_cron;

do $$
declare
  v_existing_job_id bigint;
begin
  select jobid into v_existing_job_id
  from cron.job
  where jobname = 'wazifti_archive_filled_jobs';

  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;

  perform cron.schedule(
    'wazifti_archive_filled_jobs',
    '0 2 * * *',
    'select private.archive_filled_jobs();'
  );
end;
$$;
