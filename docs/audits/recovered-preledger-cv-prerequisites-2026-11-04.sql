-- WAZIFTI PRE-LEDGER CV PREREQUISITES — recovered from pg_stat_statements.
-- This is a forensic reconstruction of statements observed before/around the
-- first tracked migration sequence. Exact wall-clock order is not retained.
-- DO NOT RUN ON PRODUCTION. The storage.foldername function is Supabase-managed;
-- a local test double is supplied only by tests/postgres17/manual_bootstrap_fixture.sql.

-- Wazifti: Candidate CV Management

create table if not exists public.candidate_resumes (
    id uuid primary key default gen_random_uuid(),

    candidate_id uuid not null
        references public.profiles(id) on delete cascade,

    file_name text not null,
    file_path text not null unique,

    file_size_bytes bigint
        check (file_size_bytes <= 5242880),

    mime_type text not null default 'application/pdf'
        check (mime_type = 'application/pdf'),

    is_default boolean not null default false,

    created_at timestamptz not null default now()
);

-- Enable security
alter table public.candidate_resumes
enable row level security;

-- Candidates can view their own CVs
create policy "Candidates view own CVs"
on public.candidate_resumes
for select
to authenticated
using (candidate_id = (select auth.uid()));

-- Candidates add own CVs; current observed definition also binds the path to the user.
create policy "Candidates add own CVs"
on public.candidate_resumes
for insert
to authenticated
with check (
  candidate_id = (select auth.uid())
  and (storage.foldername(file_path))[1] = (select auth.uid())::text
);

-- Candidates update own CVs; current observed definition also binds the path to the user.
create policy "Candidates update own CVs"
on public.candidate_resumes
for update
to authenticated
using (candidate_id = (select auth.uid()))
with check (
  candidate_id = (select auth.uid())
  and (storage.foldername(file_path))[1] = (select auth.uid())::text
);

-- Candidates can delete their own CV records
create policy "Candidates delete own CVs"
on public.candidate_resumes
for delete
to authenticated
using (candidate_id = (select auth.uid()));

-- Private helper required by the applied 20261107203156 application policy.
create schema if not exists private;

create or replace function private.candidate_owns_resume(
  p_resume_id uuid,
  p_candidate_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_candidate_id = (select auth.uid())
    and exists (
      select 1
      from public.candidate_resumes r
      where r.id = p_resume_id
        and r.candidate_id = p_candidate_id
        and (storage.foldername(r.file_path))[1] = p_candidate_id::text
    );
$$;

revoke all on function private.candidate_owns_resume(uuid, uuid) from public;
grant execute on function private.candidate_owns_resume(uuid, uuid) to authenticated;

-- Link each job application to the selected CV.
alter table public.applications
add column if not exists resume_id uuid
references public.candidate_resumes(id)
on delete set null;

-- The current production policy also permits employers to see only resumes
-- attached to their own applications; this is included as observed current
-- policy text, not asserted to be part of the first CV table-creation query.
create policy "Employers view resumes attached to their applications"
on public.candidate_resumes
for select
to authenticated
using (
  exists (
    select 1
    from public.applications a
    join public.jobs j on j.id = a.job_id
    join public.companies c on c.id = j.company_id
    where a.resume_id = candidate_resumes.id
      and a.candidate_id = candidate_resumes.candidate_id
      and (storage.foldername(candidate_resumes.file_path))[1] = candidate_resumes.candidate_id::text
      and c.owner_id = (select auth.uid())
  )
);

-- Historical ambiguity: pg_stat_statements also retained an earlier definition
-- of private.candidate_owns_resume() without the storage.foldername path check,
-- and earlier add/update CV policies without path checks. The current catalog
-- matches the hardened definitions preserved above. The exact chronology of
-- those variants is not retained by pg_stat_statements.
