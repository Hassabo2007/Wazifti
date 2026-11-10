-- Behavioral RLS tests for the V1.15 job_messages policies.
-- Runs only against the disposable PostgreSQL service in GitHub Actions.

INSERT INTO public.companies (id, owner_id)
VALUES (20, '22222222-2222-4222-8222-222222222222');

INSERT INTO public.jobs (id, company_id, poster_type, posted_by_user_id)
VALUES
  (10, 20, 'company', NULL),
  (11, NULL, 'individual', '33333333-3333-4333-8333-333333333333');

INSERT INTO public.applications (id, job_id, candidate_id)
VALUES
  (100, 10, '11111111-1111-4111-8111-111111111111'),
  (101, 11, '11111111-1111-4111-8111-111111111111');

INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
VALUES
  (100, 10, '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222'),
  (101, 11, '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333');

GRANT USAGE ON SCHEMA public, auth TO authenticated;
GRANT SELECT ON public.applications, public.jobs, public.companies, public.job_messages TO authenticated;
GRANT INSERT ON public.job_messages TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.job_messages_id_seq TO authenticated;

SET ROLE authenticated;

-- Candidate can read their company and individual-job conversations.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages;
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'Candidate should see 2 own conversation messages, saw %', visible_count;
  END IF;
END $$;

-- Candidate can send to the verified company poster when the application/job link matches.
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
VALUES
  (100, 10, '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222');

-- Candidate cannot spoof a different sender or send against a mismatched application.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.job_messages
      (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
    VALUES
      (100, 10, '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
       '44444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222');
    RAISE EXCEPTION 'Expected RLS to reject spoofed sender';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;

-- Company owner can read and reply to the candidate's company conversation.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages WHERE job_id = 10;
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'Company owner should see 2 company-conversation messages, saw %', visible_count;
  END IF;
END $$;
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
VALUES
  (100, 10, '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111');

-- Individual poster can read and reply using posted_by_user_id ownership.
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages WHERE job_id = 11;
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'Individual poster should see their conversation message, saw %', visible_count;
  END IF;
END $$;
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
VALUES
  (101, 11, '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
   '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111');

-- A non-participant sees no messages and cannot insert into either conversation.
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages;
  IF visible_count <> 0 THEN
    RAISE EXCEPTION 'Non-participant unexpectedly saw % messages', visible_count;
  END IF;

  BEGIN
    INSERT INTO public.job_messages
      (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id)
    VALUES
      (100, 10, '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
       '44444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222');
    RAISE EXCEPTION 'Expected RLS to reject non-participant insert';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;

RESET ROLE;
