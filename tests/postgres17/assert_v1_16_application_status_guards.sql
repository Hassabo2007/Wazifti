\set ON_ERROR_STOP on

-- The audit test creates candidates 1 and 2. Add a third candidate for a second
-- application on the individual-posted vacancy.
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-4000-8000-000000000013',
        'status-guard-candidate-3@example.test',
        '{"full_name":"Status Guard Candidate Three"}')
on conflict (id) do nothing;

-- The recovered fixture intentionally does not reproduce every live Data API
-- grant. Production grants authenticated UPDATE on applications; model that
-- existing privilege here so the test reaches RLS and the BEFORE trigger.
grant select, update on public.applications to authenticated;
grant select on public.jobs to authenticated;
grant select (id, owner_id, status) on public.companies to authenticated;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.role() to authenticated;

-- Seed disposable rows as the database owner. All writes under test below run
-- with the authenticated JWT and the real employer RLS policies.
insert into public.companies (id, owner_id, company_name, status)
values ('60000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000011',
        'Status Guard Test Company', 'verified')
on conflict (id) do nothing;

insert into public.jobs
  (id, company_id, title, description, status, poster_type, posted_by_user_id)
values
  ('40000000-0000-4000-8000-000000000001', null,
   'Individual status guard test', 'Disposable test vacancy',
   'published', 'individual', '00000000-0000-4000-8000-000000000011'),
  ('50000000-0000-4000-8000-000000000001',
   '60000000-0000-4000-8000-000000000001',
   'Company status guard test', 'Disposable test vacancy',
   'published', 'company', '00000000-0000-4000-8000-000000000011'),
  ('50000000-0000-4000-8000-000000000002',
   '60000000-0000-4000-8000-000000000001',
   'Closed vacancy status guard test', 'Disposable test vacancy',
   'closed', 'company', '00000000-0000-4000-8000-000000000011');

-- Reproduce the exact production employer UPDATE policy in the recovered
-- fixture; the historic replay fixture may not include this policy revision.
drop policy if exists "Employers update own application statuses" on public.applications;
create policy "Employers update own application statuses"
on public.applications
for update
to authenticated
using (
  exists (
    select 1
    from public.jobs j
    join public.companies c on c.id = j.company_id
    where j.id = applications.job_id
      and c.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.jobs j
    join public.companies c on c.id = j.company_id
    where j.id = applications.job_id
      and c.owner_id = (select auth.uid())
  )
);

insert into public.applications (id, job_id, candidate_id, status)
values
  ('70000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000012', 'submitted'),
  ('70000000-0000-4000-8000-000000000002',
   '40000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000013', 'rejected'),
  ('70000000-0000-4000-8000-000000000003',
   '50000000-0000-4000-8000-000000000001',
   '00000000-0000-4000-8000-000000000012', 'submitted'),
  ('70000000-0000-4000-8000-000000000004',
   '50000000-0000-4000-8000-000000000002',
   '00000000-0000-4000-8000-000000000012', 'submitted');

select set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000011', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
set session authorization authenticated;

do $assert_authenticated_session$
begin
  if session_user <> 'authenticated' or current_user <> 'authenticated' then
    raise exception 'Test session did not assume the authenticated role';
  end if;
end;
$assert_authenticated_session$;

-- A legitimate individual-employer status update continues to work.
select public.update_individual_job_application_status(
  '70000000-0000-4000-8000-000000000001', 'reviewing'
);

-- Individual posters cannot accept through the general status RPC.
do $assert_individual_cannot_accept$
declare v_message text;
begin
  begin
    perform public.update_individual_job_application_status(
      '70000000-0000-4000-8000-000000000001', 'accepted');
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('Invalid application status' in v_message) = 0 then raise; end if;
  end;
end;
$assert_individual_cannot_accept$;

-- A rejected application cannot be accepted later.
do $assert_rejected_application_cannot_be_accepted$
declare v_message text;
begin
  begin
    perform public.finalize_job_hiring(
      '70000000-0000-4000-8000-000000000002');
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('Only an active application can be accepted' in v_message) = 0 then raise; end if;
  end;
end;
$assert_rejected_application_cannot_be_accepted$;

-- Valid hiring remains atomic and invokes the existing close/reject trigger.
select public.finalize_job_hiring(
  '70000000-0000-4000-8000-000000000001');

-- Confirm the test is still an ordinary authenticated session after the
-- SECURITY DEFINER hiring RPC has returned; its trusted context is transaction-local.
do $assert_untrusted_context_reset$
begin
  if session_user <> 'authenticated' or current_user <> 'authenticated' then
    raise exception 'Direct-write test is not running as authenticated';
  end if;
  if public.is_admin() then
    raise exception 'The ordinary employer test identity unexpectedly has admin access';
  end if;
  if coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Unexpected JWT role in direct-write test: %', auth.role();
  end if;
  if auth.uid() <> '00000000-0000-4000-8000-000000000011'::uuid then
    raise exception 'Unexpected JWT user in direct-write test: %', auth.uid();
  end if;
  if current_setting('wazifti.application_status_rpc', true) = 'on' then
    raise exception 'Trusted RPC context leaked beyond its transaction';
  end if;
end;
$assert_untrusted_context_reset$;

-- Confirm the company owner can see the application row; the direct-update
-- test must reach the BEFORE trigger rather than silently matching zero RLS rows.
do $assert_company_application_visible$
begin
  if (select count(*) from public.applications
      where id = '70000000-0000-4000-8000-000000000003') <> 1 then
    raise exception 'Company owner cannot see the seeded application under RLS';
  end if;
end;
$assert_company_application_visible$;

-- A non-admin company employer cannot bypass the finalization RPC by writing
-- accepted directly through the Data API.
do $assert_direct_acceptance_blocked$
declare
  v_message text;
  v_rows integer;
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.applications'::regclass
      and tgname = 'guard_application_updates'
      and not tgisinternal
      and tgenabled = 'O'
  ) then
    raise exception 'Application guard trigger is missing or disabled';
  end if;

  begin
    update public.applications
    set status = 'accepted'
    where id = '70000000-0000-4000-8000-000000000003';
    get diagnostics v_rows = row_count;
    if v_rows = 0 then
      raise exception 'RLS filtered the company update before the guard trigger';
    end if;
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('Use finalize_job_hiring' in v_message) = 0 then raise; end if;
  end;
end;
$assert_direct_acceptance_blocked$;

-- Ordinary company-employer status updates remain supported for a live vacancy.
update public.applications
set status = 'reviewing'
where id = '70000000-0000-4000-8000-000000000003';

reset session authorization;

-- Close the second company vacancy as a trusted database operation.
update public.jobs
set status = 'closed'
where id = '50000000-0000-4000-8000-000000000002';

set session authorization authenticated;

-- A company employer cannot change an application after the vacancy is closed.
do $assert_closed_job_update_blocked$
declare v_message text;
begin
  begin
    update public.applications
    set status = 'reviewing'
    where id = '70000000-0000-4000-8000-000000000004';
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('no longer accepting application updates' in v_message) = 0 then raise; end if;
  end;
end;
$assert_closed_job_update_blocked$;

-- An accepted decision is terminal, even through the individual RPC.
do $assert_accepted_status_is_terminal$
declare v_message text;
begin
  begin
    perform public.update_individual_job_application_status(
      '70000000-0000-4000-8000-000000000001', 'rejected');
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('final and cannot be changed' in v_message) = 0 then raise; end if;
  end;
end;
$assert_accepted_status_is_terminal$;

-- A different authenticated user cannot update the individual employer's
-- application through the SECURITY DEFINER RPC.
select set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000012', false);
do $assert_non_owner_denied$
declare v_message text;
begin
  begin
    perform public.update_individual_job_application_status(
      '70000000-0000-4000-8000-000000000001', 'reviewing');
    raise exception 'TEST_EXPECTED_FAILURE_MISSING';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message = 'TEST_EXPECTED_FAILURE_MISSING' then raise; end if;
    if position('not authorized' in v_message) = 0 then raise; end if;
  end;
end;
$assert_non_owner_denied$;

reset session authorization;

do $assert_final_states$
begin
  if (select status from public.applications
      where id = '70000000-0000-4000-8000-000000000001') <> 'accepted' then
    raise exception 'Valid acceptance was not preserved';
  end if;

  if (select status from public.jobs
      where id = '40000000-0000-4000-8000-000000000001') <> 'closed' then
    raise exception 'Valid hiring did not close the vacancy';
  end if;

  if (select status from public.applications
      where id = '70000000-0000-4000-8000-000000000003') <> 'reviewing' then
    raise exception 'Normal company-employer status update regressed';
  end if;

  if (select status from public.applications
      where id = '70000000-0000-4000-8000-000000000004') <> 'submitted' then
    raise exception 'Closed-job application status was unexpectedly changed';
  end if;
end;
$assert_final_states$;

select 'PASS: application status RPC ownership, terminal states, direct-acceptance block, closed-job guard, and valid hiring flow' as result;
