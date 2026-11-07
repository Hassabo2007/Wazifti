-- Enable Postgres Changes for public job listings.
-- Clients still fetch rows through the existing public SELECT RLS policy.
alter publication supabase_realtime add table public.jobs;
