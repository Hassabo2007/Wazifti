\set ON_ERROR_STOP on

-- The audit test creates candidates 1 and 2. Add a third candidate for a second
-- application on the individual-posted vacancy.
insert into auth.users (id, email, raw_user_meta_data)
values ('00000000-0000-4000-8000-000000000013',
        'status-guard-candidate-3@example.test',
        '{"full_name":"Status Guard Candidate Three"}')
on conflict (id) do nothing;

-- Seed disposable rows as the database owner. All writes under test below run
-- with the authenticated JWT and the real employer RLS policies.
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

insert into public.companies (id, owner_id, company_name, status)
values ('60000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000011',
        'Status Guard Test Company', 'verified')
on conflict (id) do nothing;

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
set role authenticated;

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

-- A non-admin company employer cannot bypass the finalization RPC by writing
-- accepted directly through the Data API.
do $assert_direct_acceptance_blocked$
declare v_message text;
begin
  begin
    update public.applications
    set status = 'accepted'
    where id = '70000000-0000-4000-8000-000000000003';
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

reset role;

-- Close the second company vacancy as a trusted database operation.
update public.jobs
set status = 'closed'
where id = '50000000-0000-4000-8000-000000000002';

set role authenticated;

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

reset role;

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
