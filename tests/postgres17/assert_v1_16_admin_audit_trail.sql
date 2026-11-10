\set ON_ERROR_STOP on

-- Create one administrator and two candidates. The recovered Auth trigger
-- creates their public.profiles rows in this disposable PostgreSQL 17 database.
insert into auth.users (id, email, raw_user_meta_data) values
('00000000-0000-4000-8000-000000000010', 'audit-admin@example.test', '{"full_name":"Audit Admin"}'),
('00000000-0000-4000-8000-000000000011', 'audit-candidate-1@example.test', '{"full_name":"Audit Candidate One"}'),
('00000000-0000-4000-8000-000000000012', 'audit-candidate-2@example.test', '{"full_name":"Audit Candidate Two"}')
on conflict (id) do nothing;

insert into public.admin_users (user_id)
values ('00000000-0000-4000-8000-000000000010')
on conflict (user_id) do nothing;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000010', false);
select set_config('request.jwt.claim.role', 'authenticated', false);

-- The live production role currently has no table-level SELECT/INSERT/UPDATE
-- grants on public.companies, despite the admin RLS policy. Keep this migration
-- test independent of that pre-existing admin UI/grant mismatch: create and
-- transition the company as the database owner while retaining the admin JWT.
insert into public.companies (id, owner_id, company_name, status)
values (
  '10000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000010',
  'Audit Test Company',
  'pending'
);
update public.companies
set status = 'verified'
where id = '10000000-0000-4000-8000-000000000001';

-- Jobs and applications have authenticated table grants in production, so
-- exercise those admin Data API-style writes under the authenticated role.
set role authenticated;

insert into public.jobs (id, company_id, title, description, status)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'Audit Test Vacancy',
  'Disposable PostgreSQL audit test',
  'pending'
);
update public.jobs
set status = 'published'
where id = '20000000-0000-4000-8000-000000000001';

insert into public.applications (id, job_id, candidate_id, status)
values
(
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000011',
  'submitted'
),
(
  '30000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000012',
  'submitted'
);

-- Acceptance must atomically close the vacancy and reject the other applicant.
update public.applications
set status = 'accepted'
where id = '30000000-0000-4000-8000-000000000001';

reset role;

do $assert$
declare
  v_count integer;
  v_acceptance_tx bigint;
begin
  select count(*) into v_count
  from private.admin_audit_logs
  where actor_user_id = '00000000-0000-4000-8000-000000000010';

  if v_count <> 5 then
    raise exception 'Expected 5 administrator audit events, found %', v_count;
  end if;

  if exists (
    select 1 from private.admin_audit_logs
    where actor_user_id <> '00000000-0000-4000-8000-000000000010'
       or actor_type <> 'admin'
  ) then
    raise exception 'Audit actor was not derived from the authenticated administrator';
  end if;

  select transaction_id into v_acceptance_tx
  from private.admin_audit_logs
  where entity_type = 'application'
    and entity_id = '30000000-0000-4000-8000-000000000001'
    and old_status = 'submitted'
    and new_status = 'accepted';

  if v_acceptance_tx is null then
    raise exception 'Accepted application audit event is missing';
  end if;

  if (
    select count(*) from private.admin_audit_logs
    where transaction_id = v_acceptance_tx
      and (
        (entity_type = 'application' and entity_id in (
          '30000000-0000-4000-8000-000000000001',
          '30000000-0000-4000-8000-000000000002'
        ))
        or (entity_type = 'job' and entity_id = '20000000-0000-4000-8000-000000000001')
      )
  ) <> 3 then
    raise exception 'Hiring side effects were not correlated in one transaction';
  end if;

  if not exists (
    select 1 from private.admin_audit_logs
    where entity_type = 'job' and entity_id = '20000000-0000-4000-8000-000000000001'
      and old_status = 'published' and new_status = 'closed'
      and transaction_id = v_acceptance_tx
  ) then
    raise exception 'Job closure audit event is missing';
  end if;

  if not exists (
    select 1 from private.admin_audit_logs
    where entity_type = 'application' and entity_id = '30000000-0000-4000-8000-000000000002'
      and old_status = 'submitted' and new_status = 'rejected'
      and transaction_id = v_acceptance_tx
  ) then
    raise exception 'Other-applicant rejection audit event is missing';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'private' and table_name = 'admin_audit_logs'
      and column_name in ('cv_url','resume_id','cover_letter','phone','document_url','raw_payload')
  ) then
    raise exception 'Sensitive applicant or document field found in audit table';
  end if;
end;
$assert$;

-- Anon cannot read the private audit table.
set role anon;
do $deny_anon$
begin
  begin
    execute 'select count(*) from private.admin_audit_logs';
    raise exception 'Anon unexpectedly read the private audit table';
  exception when insufficient_privilege then
    null;
  end;
end;
$deny_anon$;
reset role;

-- Even an authenticated administrator cannot forge audit rows directly.
set role authenticated;
do $deny_insert$
begin
  begin
    execute $sql$
      insert into private.admin_audit_logs
        (transaction_id, actor_user_id, actor_type, entity_type, entity_id, action, old_status, new_status)
      values
        (1, 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'admin', 'company',
         '10000000-0000-4000-8000-000000000001', 'company.status_changed', 'pending', 'verified')
    $sql$;
    raise exception 'Authenticated user unexpectedly inserted a forged audit row';
  exception when insufficient_privilege then
    null;
  end;
end;
$deny_insert$;
reset role;

-- Defense in depth: even the table owner cannot UPDATE or DELETE an audit row.
do $append_only$
begin
  begin
    update private.admin_audit_logs
    set new_status = old_status
    where id = (select min(id) from private.admin_audit_logs);
    raise exception 'Audit UPDATE was not blocked';
  exception when insufficient_privilege then
    null;
  end;

  begin
    delete from private.admin_audit_logs
    where id = (select min(id) from private.admin_audit_logs);
    raise exception 'Audit DELETE was not blocked';
  exception when insufficient_privilege then
    null;
  end;
end;
$append_only$;

-- Force an audit sink failure and prove the source status change rolls back.
create or replace function private.test_force_audit_insert_failure()
returns trigger
language plpgsql
set search_path = ''
as $failure$
begin
  raise exception 'forced audit sink failure';
end;
$failure$;

create trigger test_force_audit_insert_failure
before insert on private.admin_audit_logs
for each row execute function private.test_force_audit_insert_failure();

do $rollback_test$
declare
  v_message text;
  v_status text;
begin
  begin
    update public.companies
    set status = 'rejected'
    where id = '10000000-0000-4000-8000-000000000001';
    raise exception 'Audit failure did not abort the company status update';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message <> 'forced audit sink failure' then
      raise;
    end if;
  end;

  select status into v_status
  from public.companies
  where id = '10000000-0000-4000-8000-000000000001';

  if v_status <> 'verified' then
    raise exception 'Company status was not rolled back after audit failure';
  end if;
end;
$rollback_test$;

drop trigger test_force_audit_insert_failure on private.admin_audit_logs;
drop function private.test_force_audit_insert_failure();

do $final_count$
begin
  if (select count(*) from private.admin_audit_logs) <> 5 then
    raise exception 'Failed audit transaction left a partial audit event';
  end if;
end;
$final_count$;

select 'PASS: admin audit capture, correlated hiring side effects, actor integrity, private access, append-only protection, and atomic rollback' as result;
