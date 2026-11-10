-- Assertions for V1.15 only; run after the migration on the partial fixture.
DO $$
DECLARE
  expected text[] := ARRAY[
    'in_app_notifications_application_id_idx',
    'job_messages_application_id_idx',
    'job_messages_candidate_id_idx',
    'job_messages_poster_id_idx',
    'job_messages_sender_id_idx'
  ];
  item text;
BEGIN
  FOREACH item IN ARRAY expected LOOP
    IF to_regclass('public.' || item) IS NULL THEN
      RAISE EXCEPTION 'Expected index missing: %', item;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='job_messages'
      AND policyname='Conversation participants read messages'
      AND cmd='SELECT' AND roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'V1.15 SELECT policy missing or incorrect';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='job_messages'
      AND policyname='Conversation participants send messages'
      AND cmd='INSERT' AND roles @> ARRAY['authenticated']::name[]
  ) THEN
    RAISE EXCEPTION 'V1.15 INSERT policy missing or incorrect';
  END IF;
END $$;

SELECT 'V1.15 partial PostgreSQL 17 compatibility checks passed' AS result;
