-- V1.16 follow-up: close application status transition bypasses.
-- This SQL is first exercised by the PostgreSQL 17 fixture before production rollout.

create or replace function public.guard_application_updates()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_job_status text;
begin
  -- Trusted maintenance, service-role jobs, and audited administrator actions
  -- retain their existing privileged path.
  -- PostgREST sessions use authenticator as session_user. SECURITY DEFINER
  -- RPCs explicitly set a transaction-local context before their trusted update.
  if session_user in ('postgres', 'supabase_admin')
     or coalesce(auth.role(), '') = 'service_role'
     or public.is_admin()
     or current_setting('wazifti.application_status_rpc', true) = 'on' then
    return new;
  end if;

  if (select auth.uid()) is null then
    raise exception 'Authentication required.'
      using errcode = '42501';
  end if;

  -- Employers may change only the application status.
  if (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status') then
    raise exception 'You may update only the application status.'
      using errcode = '42501';
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  -- Acceptance must pass through finalize_job_hiring so the vacancy lock,
  -- ownership check, closure, and competing-applicant updates remain atomic.
  if new.status = 'accepted' then
    raise exception 'Use finalize_job_hiring to accept an applicant.'
      using errcode = '42501';
  end if;

  -- Accepted and rejected decisions are terminal for ordinary employers.
  if old.status in ('accepted', 'rejected') then
    raise exception 'This application status is final and cannot be changed.'
      using errcode = '42501';
  end if;

  if new.status not in ('submitted', 'reviewing', 'shortlisted', 'rejected') then
    raise exception 'Invalid application status transition.'
      using errcode = '22023';
  end if;

  select j.status
    into v_job_status
  from public.jobs j
  where j.id = old.job_id;

  if not found or v_job_status <> 'published' then
    raise exception 'This job is no longer accepting application updates.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

create or replace function public.update_individual_job_application_status(
  p_application_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id uuid;
  v_job_status text;
  v_poster_type text;
  v_posted_by_user_id uuid;
  v_current_status text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.'
      using errcode = '42501';
  end if;

  if p_new_status not in ('submitted', 'reviewing', 'shortlisted', 'rejected') then
    raise exception 'Invalid application status. Acceptance must use finalize_job_hiring.'
      using errcode = '22023';
  end if;

  select a.job_id, a.status, j.status, j.poster_type, j.posted_by_user_id
    into v_job_id, v_current_status, v_job_status, v_poster_type, v_posted_by_user_id
  from public.applications a
  join public.jobs j on j.id = a.job_id
  where a.id = p_application_id
  for update of j, a;

  if not found then
    raise exception 'Application or job not found.'
      using errcode = 'P0002';
  end if;

  if v_poster_type <> 'individual'
     or v_posted_by_user_id is distinct from (select auth.uid()) then
    raise exception 'You are not authorized to update this application.'
      using errcode = '42501';
  end if;

  if v_current_status in ('accepted', 'rejected') then
    raise exception 'This application status is final and cannot be changed.'
      using errcode = '42501';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting application updates.'
      using errcode = '42501';
  end if;

  perform set_config('wazifti.application_status_rpc', 'on', true);

  update public.applications
  set status = p_new_status
  where id = p_application_id
    and status in ('submitted', 'reviewing', 'shortlisted');
end;
$function$;

create or replace function public.finalize_job_hiring(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id uuid;
  v_poster_type text;
  v_posted_by_user_id uuid;
  v_company_owner_id uuid;
  v_job_status text;
  v_application_status text;
  v_owner_id uuid;
  v_updated_count integer;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.'
      using errcode = '42501';
  end if;

  select a.job_id, a.status, j.poster_type, j.posted_by_user_id, c.owner_id, j.status
    into v_job_id, v_application_status, v_poster_type, v_posted_by_user_id,
         v_company_owner_id, v_job_status
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
  for update of j, a;

  if not found then
    raise exception 'Application or job not found.'
      using errcode = 'P0002';
  end if;

  v_owner_id := case
    when v_poster_type = 'individual' then v_posted_by_user_id
    else v_company_owner_id
  end;

  if v_owner_id is distinct from (select auth.uid()) then
    raise exception 'You are not authorized to finalize this hiring decision.'
      using errcode = '42501';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.'
      using errcode = '42501';
  end if;

  if v_application_status not in ('submitted', 'reviewing', 'shortlisted') then
    raise exception 'Only an active application can be accepted.'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.applications a
    where a.job_id = v_job_id and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.'
      using errcode = '23505';
  end if;

  perform set_config('wazifti.application_status_rpc', 'on', true);

  update public.applications
  set status = 'accepted'
  where id = p_application_id
    and job_id = v_job_id
    and status in ('submitted', 'reviewing', 'shortlisted');

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> 1 then
    raise exception 'The application status changed before hiring could be finalized.'
      using errcode = '40001';
  end if;
end;
$function$;

revoke all on function public.update_individual_job_application_status(uuid, text) from public, anon;
grant execute on function public.update_individual_job_application_status(uuid, text) to authenticated;
revoke all on function public.finalize_job_hiring(uuid) from public, anon;
grant execute on function public.finalize_job_hiring(uuid) to authenticated;
