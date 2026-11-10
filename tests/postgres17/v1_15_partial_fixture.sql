-- PARTIAL TEST FIXTURE ONLY. Not an authoritative Wazifti bootstrap.
-- Minimal PostgreSQL objects required to parse/apply V1.15. No production data or Supabase services.
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TABLE public.companies (
  id uuid PRIMARY KEY,
  owner_id uuid
);
CREATE TABLE public.jobs (
  id uuid PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id),
  poster_type text,
  posted_by_user_id uuid
);
CREATE TABLE public.applications (
  id uuid PRIMARY KEY,
  job_id uuid REFERENCES public.jobs(id),
  candidate_id uuid
);
CREATE TABLE public.job_messages (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  application_id uuid,
  job_id uuid,
  candidate_id uuid,
  poster_id uuid,
  sender_id uuid,
  recipient_id uuid
);
CREATE TABLE public.in_app_notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  application_id uuid
);
ALTER TABLE public.job_messages ENABLE ROW LEVEL SECURITY;
