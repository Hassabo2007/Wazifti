alter table public.profiles
      add column if not exists can_post_individual_jobs boolean not null default false;

    alter table public.jobs
      alter column company_id drop not null,
      add column if not exists posted_by_user_id uuid references public.profiles(id) on delete restrict,
      add column if not exists poster_type text not null default 'company';

    update public.jobs j
       set posted_by_user_id = c.owner_id,
           poster_type = 'company'
      from public.companies c
     where j.company_id = c.id
       and j.posted_by_user_id is null;

    alter table public.jobs
      add constraint jobs_poster_type_check
      check (poster_type in ('company','individual'));

    create index if not exists jobs_posted_by_user_id_idx
      on public.jobs(posted_by_user_id);

    drop policy if exists "Authenticated view published and own jobs" on public.jobs;
    create policy "Authenticated view published and own jobs"
      on public.jobs for select to authenticated
      using (
        status = 'published'
        or exists (
          select 1 from public.companies c
          where c.id = jobs.company_id and c.owner_id = (select auth.uid())
        )
        or posted_by_user_id = (select auth.uid())
      );

    drop policy if exists "Individual users create pending jobs when enabled" on public.jobs;
    create policy "Individual users create pending jobs when enabled"
      on public.jobs for insert to authenticated
      with check (
        company_id is null
        and poster_type = 'individual'
        and posted_by_user_id = (select auth.uid())
        and status = 'pending'
        and exists (
          select 1 from public.profiles p
          where p.id = (select auth.uid())
            and p.can_post_individual_jobs = true
        )
      );

    drop policy if exists "Individuals update own pending jobs" on public.jobs;
    create policy "Individuals update own pending jobs"
      on public.jobs for update to authenticated
      using (
        poster_type = 'individual'
        and posted_by_user_id = (select auth.uid())
        and status = 'pending'
      )
      with check (
        poster_type = 'individual'
        and posted_by_user_id = (select auth.uid())
        and company_id is null
        and status = 'pending'
      );

    drop policy if exists "Individuals delete own non-published jobs" on public.jobs;
    create policy "Individuals delete own non-published jobs"
      on public.jobs for delete to authenticated
      using (
        poster_type = 'individual'
        and posted_by_user_id = (select auth.uid())
        and status in ('pending','rejected','closed')
      );
