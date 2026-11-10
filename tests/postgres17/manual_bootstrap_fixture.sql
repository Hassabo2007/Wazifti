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

-- Supabase Storage path helper test double; production Storage is not installed here.
CREATE SCHEMA storage;
CREATE FUNCTION storage.foldername(p_name text)
RETURNS text[] LANGUAGE sql IMMUTABLE
AS $
  SELECT CASE WHEN cardinality(parts) <= 1 THEN ARRAY[]::text[]
              ELSE parts[1:cardinality(parts)-1] END
  FROM (SELECT string_to_array(p_name, '/') AS parts) s
$;

\ir ../../docs/audits/recovered-preledger-cv-prerequisites-2026-11-04.sql

-- Exercise the recovered Auth trigger against the local auth.users test double.
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '00000000-0000-4000-8000-000000000001',
  'candidate@example.test',
  '{"full_name":"Bootstrap Candidate"}'::jsonb
);
