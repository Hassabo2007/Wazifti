-- V1.15 security/performance hygiene
-- Safe, additive changes only. Does not alter application data or user access rules.
-- Keep client access to admin_users and push_notification_events denied by RLS (no policies).

create index if not exists in_app_notifications_application_id_idx on public.in_app_notifications (application_id);
create index if not exists job_messages_application_id_idx on public.job_messages (application_id);
create index if not exists job_messages_candidate_id_idx on public.job_messages (candidate_id);
create index if not exists job_messages_poster_id_idx on public.job_messages (poster_id);
create index if not exists job_messages_sender_id_idx on public.job_messages (sender_id);

drop policy if exists "Conversation participants read messages" on public.job_messages;
create policy "Conversation participants read messages" on public.job_messages for select to authenticated using ((select auth.uid()) = candidate_id or (select auth.uid()) = poster_id);

drop policy if exists "Conversation participants send messages" on public.job_messages;
create policy "Conversation participants send messages" on public.job_messages for insert to authenticated with check (
 sender_id = (select auth.uid()) and (
  (sender_id = candidate_id and recipient_id = poster_id and exists (
   select 1 from public.applications a join public.jobs j on j.id=a.job_id left join public.companies c on c.id=j.company_id
   where a.id=job_messages.application_id and a.job_id=job_messages.job_id and a.candidate_id=job_messages.candidate_id
   and job_messages.poster_id = case when j.poster_type='individual' then j.posted_by_user_id else c.owner_id end
  )) or
  (sender_id = poster_id and recipient_id = candidate_id and exists (
   select 1 from public.applications a join public.jobs j on j.id=a.job_id left join public.companies c on c.id=j.company_id
   where a.id=job_messages.application_id and a.job_id=job_messages.job_id and a.candidate_id=job_messages.candidate_id
   and ((j.poster_type='individual' and j.posted_by_user_id=(select auth.uid())) or c.owner_id=(select auth.uid()))
  ))
 )
);

-- Intentional deny-by-default RLS: admin_users and push_notification_events remain without client policies.
-- SECURITY DEFINER RPC grants remain restricted from anon and PUBLIC; authenticated grants are required by app flows.
-- pg_net remains in place because scheduled alert routines call net.*; moving it needs a dedicated scheduler migration.
