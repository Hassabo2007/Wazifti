revoke insert on table public.job_messages from authenticated;
revoke insert (id, created_at, read_at) on table public.job_messages from authenticated;
grant insert (job_id, application_id, candidate_id, poster_id, sender_id, recipient_id, body)
on table public.job_messages to authenticated;
