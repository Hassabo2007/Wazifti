CREATE TABLE IF NOT EXISTS public.in_app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  application_id uuid NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
  job_title text NOT NULL DEFAULT 'الوظيفة',
  old_status text,
  new_status text NOT NULL CHECK (new_status IN ('submitted','reviewing','shortlisted','rejected','accepted')),
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

CREATE INDEX IF NOT EXISTS in_app_notifications_user_created_idx
  ON public.in_app_notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS in_app_notifications_user_unread_idx
  ON public.in_app_notifications (user_id) WHERE read_at IS NULL;

ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.in_app_notifications FROM anon, authenticated;
GRANT SELECT ON TABLE public.in_app_notifications TO authenticated;
GRANT UPDATE (read_at) ON TABLE public.in_app_notifications TO authenticated;

DROP POLICY IF EXISTS "Candidates read their own in-app notifications" ON public.in_app_notifications;
CREATE POLICY "Candidates read their own in-app notifications"
  ON public.in_app_notifications FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Candidates mark their own in-app notifications read" ON public.in_app_notifications;
CREATE POLICY "Candidates mark their own in-app notifications read"
  ON public.in_app_notifications FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION private.create_application_status_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_job_title text;
  v_status_label text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT j.title INTO v_job_title
    FROM public.jobs AS j
    WHERE j.id = NEW.job_id;

    v_status_label := CASE NEW.status
      WHEN 'submitted' THEN 'تم استلام الطلب'
      WHEN 'reviewing' THEN 'قيد المراجعة'
      WHEN 'shortlisted' THEN 'ضمن القائمة المختصرة'
      WHEN 'rejected' THEN 'لم يتم الاختيار'
      WHEN 'accepted' THEN 'تم القبول'
      ELSE NEW.status
    END;

    INSERT INTO public.in_app_notifications
      (user_id, application_id, job_title, old_status, new_status, message)
    VALUES
      (NEW.candidate_id, NEW.id, COALESCE(v_job_title, 'الوظيفة'), OLD.status, NEW.status,
       'تم تحديث حالة طلبك إلى: ' || v_status_label);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.create_application_status_notification() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS applications_status_in_app_notification ON public.applications;
CREATE TRIGGER applications_status_in_app_notification
AFTER UPDATE OF status ON public.applications
FOR EACH ROW
EXECUTE FUNCTION private.create_application_status_notification();
