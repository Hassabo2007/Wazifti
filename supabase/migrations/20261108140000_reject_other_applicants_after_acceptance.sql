-- Wazifti: finalize a hiring decision atomically and notify all other active applicants.
-- Existing applications and conversations are retained. The existing status-change trigger
-- creates an in-app notification for every application whose status changes.

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

  -- Serialize hiring decisions for the same vacancy to prevent multiple acceptances.
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

  -- Other active applications are rejected; their status trigger creates notices.
  update public.applications
  set status = 'rejected'
  where job_id = new.job_id
    and id <> new.id
    and status not in ('accepted', 'rejected');

  return new;
end;
$$;

revoke all on function private.close_job_when_applicant_accepted() from public, anon, authenticated;

drop trigger if exists close_job_when_applicant_accepted on public.applications;
create trigger close_job_when_applicant_accepted
after update of status on public.applications
for each row
execute function private.close_job_when_applicant_accepted();


-- A scoped RPC is required for the final acceptance action. This prevents the UI
-- from writing an accepted status if the close/reject trigger has not been installed.
create or replace function public.finalize_job_hiring(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_poster_type text;
  v_posted_by_user_id uuid;
  v_company_owner_id uuid;
  v_job_status text;
  v_owner_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.';
  end if;

  select a.job_id, j.poster_type, j.posted_by_user_id, c.owner_id, j.status
    into v_job_id, v_poster_type, v_posted_by_user_id, v_company_owner_id, v_job_status
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
  for update of j;

  if not found then
    raise exception 'Application or job not found.';
  end if;

  v_owner_id := case
    when v_poster_type = 'individual' then v_posted_by_user_id
    else v_company_owner_id
  end;

  if v_owner_id is distinct from (select auth.uid()) then
    raise exception 'You are not authorized to finalize this hiring decision.';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.';
  end if;

  if exists (
    select 1 from public.applications a
    where a.job_id = v_job_id and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.';
  end if;

  update public.applications
  set status = 'accepted'
  where id = p_application_id and job_id = v_job_id;
end;
$$;

revoke all on function public.finalize_job_hiring(uuid) from public, anon;
grant execute on function public.finalize_job_hiring(uuid) to authenticated;


-- Make rejection notifications clear when the vacancy has been filled by another applicant.
create or replace function private.create_application_status_notification()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_job_title text;
  v_job_status text;
  v_status_label text;
  v_message text;
begin
  if new.status is distinct from old.status then
    select j.title, j.status
      into v_job_title, v_job_status
    from public.jobs as j
    where j.id = new.job_id;

    v_status_label := case new.status
      when 'submitted' then 'تم استلام الطلب'
      when 'reviewing' then 'قيد المراجعة'
      when 'shortlisted' then 'ضمن القائمة المختصرة'
      when 'rejected' then 'لم يتم الاختيار'
      when 'accepted' then 'تم القبول'
      else new.status
    end;

    if new.status = 'rejected' and v_job_status = 'closed' then
      v_message := 'تم شغل الوظيفة واختيار متقدم آخر. نشكرك على اهتمامك، ولم يتم اختيار طلبك لهذه الوظيفة.';
    else
      v_message := 'تم تحديث حالة طلبك إلى: ' || v_status_label;
    end if;

    insert into public.in_app_notifications
      (user_id, application_id, job_title, old_status, new_status, message)
    values
      (new.candidate_id, new.id, coalesce(v_job_title, 'الوظيفة'), old.status, new.status, v_message);
  end if;
  return new;
end;
$function$;
