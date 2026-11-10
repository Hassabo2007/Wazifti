-- Behavioral RLS tests using UUID keys and required columns matching live Supabase metadata.
-- Runs only against the disposable PostgreSQL service in GitHub Actions.

INSERT INTO auth.users (id) VALUES
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333'),
 ('44444444-4444-4444-8444-444444444444');

INSERT INTO public.profiles (id, full_name, account_type) VALUES
 ('11111111-1111-4111-8111-111111111111','Candidate','candidate'),
 ('22222222-2222-4222-8222-222222222222','Company owner','employer'),
 ('33333333-3333-4333-8333-333333333333','Individual poster','candidate');

INSERT INTO public.companies (id, owner_id, company_name, status)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'Test Company', 'verified');

INSERT INTO public.jobs (id, company_id, title, description, poster_type, posted_by_user_id)
VALUES
  ('10000000-0000-4000-8000-000000000010', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Company test role', 'Test description', 'company', NULL),
  ('11000000-0000-4000-8000-000000000011', NULL, 'Individual test role', 'Test description', 'individual', '33333333-3333-4333-8333-333333333333');

INSERT INTO public.applications (id, job_id, candidate_id)
VALUES
  ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111'),
  ('21000000-0000-4000-8000-000000000101', '11000000-0000-4000-8000-000000000011', '11111111-1111-4111-8111-111111111111');

INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
VALUES
  ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'candidate seed'),
  ('21000000-0000-4000-8000-000000000101', '11000000-0000-4000-8000-000000000011', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
   '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'candidate seed');

GRANT USAGE ON SCHEMA public, auth TO authenticated;
GRANT SELECT ON public.applications, public.jobs, public.companies, public.job_messages TO authenticated;
GRANT INSERT ON public.job_messages TO authenticated;

SET ROLE authenticated;

-- Candidate can read both conversations.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages;
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'Candidate should see 2 messages, saw %', visible_count;
  END IF;
END $$;

-- Candidate can send to the company poster.
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
VALUES
  ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'candidate reply');

-- Candidate cannot spoof another sender.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.job_messages
      (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
    VALUES
      ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
       '44444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222', 'spoof attempt');
    RAISE EXCEPTION 'Expected RLS to reject spoofed sender';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;

-- Company owner can read and reply.
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages WHERE job_id = '10000000-0000-4000-8000-000000000010';
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'Company owner should see 2 messages, saw %', visible_count;
  END IF;
END $$;
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
VALUES
  ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
   '22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 'company reply');

-- Individual poster can read and reply.
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages WHERE job_id = '11000000-0000-4000-8000-000000000011';
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'Individual poster should see 1 message, saw %', visible_count;
  END IF;
END $$;
INSERT INTO public.job_messages
  (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
VALUES
  ('21000000-0000-4000-8000-000000000101', '11000000-0000-4000-8000-000000000011', '11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333',
   '33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', 'individual reply');

-- Outsider sees no messages and cannot insert.
SELECT set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', false);
DO $$
DECLARE visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM public.job_messages;
  IF visible_count <> 0 THEN
    RAISE EXCEPTION 'Outsider unexpectedly saw % messages', visible_count;
  END IF;
  BEGIN
    INSERT INTO public.job_messages
      (application_id, job_id, candidate_id, poster_id, sender_id, recipient_id, body)
    VALUES
      ('20000000-0000-4000-8000-000000000100', '10000000-0000-4000-8000-000000000010', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222',
       '44444444-4444-4444-8444-444444444444', '22222222-2222-4222-8222-222222222222', 'outsider attempt');
    RAISE EXCEPTION 'Expected RLS to reject outsider insert';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;

RESET ROLE;
