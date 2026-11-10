-- Assertions for the recovered manual bootstrap on PostgreSQL 17.
DO $$
DECLARE
  expected_tables text[] := ARRAY['profiles','companies','jobs','applications','admin_users','candidate_resumes'];
  expected_policies text[] := ARRAY[
    'Users view own profile',
    'Owners view own companies',
    'Public view published jobs',
    'Candidates submit applications',
    'Candidates and employers view applications',
    'Admins manage applications',
    'Admins manage companies',
    'Admins manage jobs',
    'Admins view all profiles',
    'Verified companies create jobs',
    'Candidates view own CVs',
    'Candidates add own CVs',
    'Candidates update own CVs',
    'Candidates delete own CVs',
    'Employers view resumes attached to their applications'
  ];
  item text;
BEGIN
  FOREACH item IN ARRAY expected_tables LOOP
    IF to_regclass('public.' || item) IS NULL THEN
      RAISE EXCEPTION 'Recovered bootstrap table missing: %', item;
    END IF;
  END LOOP;

  FOREACH item IN ARRAY expected_tables LOOP
    IF NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid=to_regclass('public.' || item)) THEN
      RAISE EXCEPTION 'RLS is not enabled on recovered table: %', item;
    END IF;
  END LOOP;

  FOREACH item IN ARRAY expected_policies LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname='public' AND policyname=item
    ) THEN
      RAISE EXCEPTION 'Recovered bootstrap policy missing: %', item;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname='on_auth_user_created' AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Auth user creation trigger missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id='00000000-0000-4000-8000-000000000001'
      AND full_name='Bootstrap Candidate'
      AND email='candidate@example.test'
  ) THEN
    RAISE EXCEPTION 'handle_new_user() did not create the expected profile';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='applications' AND column_name='resume_id'
  ) THEN
    RAISE EXCEPTION 'Recovered applications.resume_id column missing';
  END IF;

  IF to_regprocedure('private.candidate_owns_resume(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Recovered candidate_owns_resume helper missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.applications'::regclass
      AND contype='u'
      AND pg_get_constraintdef(oid) ILIKE '%job_id, candidate_id%'
  ) THEN
    RAISE EXCEPTION 'Unique(job_id, candidate_id) constraint missing';
  END IF;
END $$;

-- Verify the recovered admin lookup under an authenticated identity.
INSERT INTO public.admin_users(user_id)
VALUES ('00000000-0000-4000-8000-000000000001');

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);
SET ROLE authenticated;
DO $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Recovered is_admin() did not recognize the seeded admin';
  END IF;
END $$;
RESET ROLE;

-- Verify the CV ownership helper uses the authenticated identity and path prefix.
INSERT INTO public.candidate_resumes(candidate_id,file_name,file_path,file_size_bytes)
VALUES ('00000000-0000-4000-8000-000000000001','cv.pdf',
        '00000000-0000-4000-8000-000000000001/cv.pdf',1024);
SELECT set_config('test.resume_id', (SELECT id::text FROM public.candidate_resumes WHERE candidate_id='00000000-0000-4000-8000-000000000001'), false);
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SET ROLE authenticated;
DO $test$
DECLARE v_resume_id uuid := current_setting('test.resume_id')::uuid;
BEGIN
  IF NOT private.candidate_owns_resume(v_resume_id,'00000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'candidate_owns_resume rejected the candidate own-CV path';
  END IF;
  IF private.candidate_owns_resume(v_resume_id,'00000000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'candidate_owns_resume accepted a mismatched candidate';
  END IF;
END $test$;
RESET ROLE;

SELECT 'Recovered 2026-11-04 manual bootstrap passed PostgreSQL 17 checks' AS result;
