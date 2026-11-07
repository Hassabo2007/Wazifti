-- Add indexes for foreign-key joins and common ownership lookups.
create index if not exists applications_candidate_id_idx on public.applications (candidate_id);
create index if not exists applications_resume_id_idx on public.applications (resume_id);
create index if not exists companies_owner_id_idx on public.companies (owner_id);
create index if not exists jobs_company_id_idx on public.jobs (company_id);
create index if not exists jobs_specialty_category_fk_idx on public.jobs (specialty_id, category_id);
create index if not exists profiles_specialty_category_fk_idx on public.profiles (specialty_id, category_id);

-- Evaluate auth.uid() once per statement rather than once per candidate row.
drop policy if exists "Enable insert for users based on user_id" on public.profiles;
create policy "Enable insert for users based on user_id"
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "User update own profile" on public.profiles;
create policy "User update own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
