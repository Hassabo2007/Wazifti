-- WAZIFTI MANUAL BOOTSTRAP RECOVERY — 2026-11-04
-- Source: pg_stat_statements.query from the production PostgreSQL catalog.
-- Read-only forensic recovery; no query in this file has been re-executed.
-- IMPORTANT:
--   * DO NOT run this file against production.
--   * Statements are grouped into dependency order for review/testing.
--   * Original editor submission order and transaction boundaries are not retained.
--   * Core table DDL and the first-generation policies were recovered as query text.
--   * The admin/security statements were also found in query history; their exact
--     relative order within the original setup session is not established.

-- ============================================================================
-- A. Core tables — exact SQL text recovered
-- ============================================================================

-- Wazifti: Initial database structure

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text not null,
    email text,
    phone text,
    account_type text not null default 'candidate'
        check (account_type in ('candidate', 'employer', 'admin')),
    created_at timestamptz default now()
);

create table public.companies (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id),
    company_name text not null,
    description text,
    website text,
    status text not null default 'pending'
        check (status in ('pending', 'verified', 'rejected', 'suspended')),
    created_at timestamptz default now()
);

create table public.jobs (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id),
    title text not null,
    description text not null,
    location text,
    employment_type text,
    salary_min numeric,
    salary_max numeric,
    currency text default 'SDG',
    status text not null default 'pending'
        check (status in ('pending', 'published', 'closed', 'rejected')),
    created_at timestamptz default now()
);

create table public.applications (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null references public.jobs(id),
    candidate_id uuid not null references public.profiles(id),
    cv_url text,
    cover_letter text,
    status text not null default 'submitted'
        check (status in ('submitted', 'reviewing', 'shortlisted', 'rejected', 'accepted')),
    created_at timestamptz default now(),
    unique (job_id, candidate_id)
);

-- ============================================================================
-- B. Initial admin registry and RLS activation — exact SQL text recovered
-- ============================================================================

-- Wazifti: Admin Security

-- Create a private table for administrators
create table public.admin_users (
    user_id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz default now()
);

-- Enable Row Level Security
alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;
alter table public.admin_users enable row level security;

-- Secure function to check administrator status
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.admin_users
        where user_id = (select auth.uid())
    );
$$;

-- Restrict access to the function
revoke all on function public.is_admin() from public;
revoke all on function public.is_admin() from anon;
grant execute on function public.is_admin() to authenticated;

-- ============================================================================
-- C. Signup profile function and Auth trigger — exact SQL text recovered
-- ============================================================================

-- 1. Automatically create candidate profile after signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      split_part(coalesce(new.email, ''), '@', 1)
    ),
    new.email
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================================
-- D. First-generation public-table policies — exact SQL text recovered
-- ============================================================================

-- 2. Profiles: users can only view their own profile
create policy "Users view own profile"
on public.profiles
for select to authenticated
using (id = (select auth.uid()));

-- 3. Companies: owners can view and register their companies
create policy "Owners view own companies"
on public.companies
for select to authenticated
using (owner_id = (select auth.uid()));

-- 4. Jobs: published jobs are publicly visible
create policy "Public view published jobs"
on public.jobs
for select to anon, authenticated
using (
  status = 'published'
  or exists (
    select 1
    from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
  )
);

-- 5. Applications: candidates submit applications
create policy "Candidates submit applications"
on public.applications
for insert to authenticated
with check (
  candidate_id = (select auth.uid())
  and exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.status = 'published'
  )
);

-- Candidates and relevant employers can view applications
create policy "Candidates and employers view applications"
on public.applications
for select to authenticated
using (
  candidate_id = (select auth.uid())
  or exists (
    select 1
    from public.jobs j
    join public.companies c on c.id = j.company_id
    where j.id = applications.job_id
      and c.owner_id = (select auth.uid())
  )
);

-- Only administrators can manage applications
create policy "Admins manage applications"
on public.applications
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Only administrators can manage companies
create policy "Admins manage companies"
on public.companies
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Only administrators can manage jobs
create policy "Admins manage jobs"
on public.jobs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Only administrators can view all profiles
create policy "Admins view all profiles"
on public.profiles
for select
to authenticated
using (public.is_admin());

-- Only verified company owners can publish jobs
create policy "Verified companies create jobs"
on public.jobs
for insert to authenticated
with check (
  exists (
    select 1
    from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
);

-- ============================================================================
-- E. Provenance notes
-- ============================================================================
-- pg_stat_statements reported stats_reset = 2026-11-04 08:34:44.350849+00,
-- before the initial bootstrap messages in the conversation (09:56–09:58).
-- The table DDL, function, trigger, RLS activation, admin function and policies
-- were present as retained query text with recorded calls.
-- No exact original transaction boundaries or wall-clock execution timestamps
-- per individual statement are available in pg_stat_statements.
-- Storage-object policies and later policies are intentionally excluded.
