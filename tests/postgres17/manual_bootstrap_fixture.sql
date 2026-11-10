-- PostgreSQL 17-only harness for the recovered manual bootstrap.
-- These Supabase-managed objects are minimal local test doubles, not production DDL.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

CREATE SCHEMA auth;
CREATE TABLE auth.users (
  id uuid PRIMARY KEY,
  email text,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

CREATE FUNCTION auth.role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.role', true), '')
$$;

\ir ../../docs/audits/recovered-manual-bootstrap-2026-11-04.sql

-- Exercise the recovered Auth trigger against the local auth.users test double.
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '00000000-0000-4000-8000-000000000001',
  'candidate@example.test',
  '{"full_name":"Bootstrap Candidate"}'::jsonb
);
