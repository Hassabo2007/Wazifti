-- Final assertions after the partial historical replay on PostgreSQL 17.
DO $assert$
DECLARE
  expected_tables text[] := ARRAY[
    'job_categories','job_specialties','candidate_experiences',
    'push_subscriptions','in_app_notifications','job_messages',
    'job_alert_preferences','job_alert_preference_categories',
    'job_alert_preference_specialties','job_alert_preference_locations',
    'job_alert_preference_employment_types','job_alert_notifications',
    'job_alert_deliveries','job_alert_digest_runs','job_alert_outbox'
  ];
  item text;
BEGIN
  FOREACH item IN ARRAY expected_tables LOOP
    IF to_regclass('public.' || item) IS NULL THEN
      RAISE EXCEPTION 'Historical replay table missing: %', item;
    END IF;
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='jobs' AND column_name='state') THEN
    RAISE EXCEPTION 'jobs.state missing after historical replay';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='jobs' AND column_name='poster_type') THEN
    RAISE EXCEPTION 'jobs.poster_type missing after historical replay';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='applications' AND column_name='resume_id') THEN
    RAISE EXCEPTION 'applications.resume_id missing after historical replay';
  END IF;

  IF to_regprocedure('public.get_job_alert_vapid_config()') IS NULL THEN
    RAISE EXCEPTION 'VAPID configuration RPC missing after historical replay';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='process_job_alert_outbox') THEN
    RAISE EXCEPTION 'Job alert outbox worker missing after historical replay';
  END IF;
  IF to_regprocedure('private.candidate_owns_resume(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Pre-ledger CV ownership prerequisite missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.job_messages'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS not enabled on job_messages';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.job_alert_preferences'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS not enabled on job_alert_preferences';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='job_messages') THEN
    RAISE EXCEPTION 'job_messages policies missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='job_alert_preferences') THEN
    RAISE EXCEPTION 'job_alert_preferences policies missing';
  END IF;
END $assert$;

SELECT '24 of 26 captured production migrations replayed and key schema assertions passed on PostgreSQL 17 (two Supabase-managed migrations excluded)' AS result;
