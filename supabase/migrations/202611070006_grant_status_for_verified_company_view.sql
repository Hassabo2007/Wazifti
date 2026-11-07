-- The security-invoker view filters on status, so callers need permission
-- to read that column. RLS still restricts anonymous rows to verified companies.
grant select (status) on table public.companies to anon;
