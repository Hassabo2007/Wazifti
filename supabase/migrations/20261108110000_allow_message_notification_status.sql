-- Allow message notifications to use the message status marker.
-- Existing application-status values remain unchanged.
alter table public.in_app_notifications
  drop constraint if exists in_app_notifications_new_status_check;

alter table public.in_app_notifications
  add constraint in_app_notifications_new_status_check
  check (new_status = any (array[
    'submitted'::text,
    'reviewing'::text,
    'shortlisted'::text,
    'rejected'::text,
    'accepted'::text,
    'message'::text
  ]));
