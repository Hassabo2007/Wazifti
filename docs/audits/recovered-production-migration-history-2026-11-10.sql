-- WAZIFTI: RECOVERED PRODUCTION MIGRATION LEDGER
-- Snapshot: 2026-11-10. Source: supabase_migrations.schema_migrations.statements.
-- FORENSIC ARCHIVE ONLY: DO NOT RUN THIS FILE AS A MIGRATION OR REPLAY IT ON PRODUCTION.
-- Individual entries may depend on earlier schema state, extensions, Supabase-managed objects, and secrets.

-- ============================================================================
-- APPLIED VERSION: 20261106215107
-- MIGRATION NAME: guard_application_updates
-- ============================================================================

create or replace function public.guard_application_updates()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  -- Preserve unrestricted maintenance and trusted server-side operations.
  if current_user in ('postgres', 'supabase_admin')
     or coalesce(auth.role(), '') = 'service_role'
     or public.is_admin() then
    return new;
  end if;

  -- Employers may change only the application status.
  if (to_jsonb(new) - 'status') is distinct from (to_jsonb(old) - 'status') then
    raise exception 'You may update only the application status.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

drop trigger if exists guard_application_updates on public.applications;

create trigger guard_application_updates
before update on public.applications
for each row
execute function public.guard_application_updates();


-- ============================================================================
-- APPLIED VERSION: 20261107065459
-- MIGRATION NAME: add_job_taxonomy_and_candidate_experiences
-- ============================================================================

create table public.job_categories (
 id uuid primary key default gen_random_uuid(),
 slug text not null unique,
 name_ar text not null,
 name_en text not null,
 sort_order integer not null default 0,
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.job_specialties (
 id uuid primary key default gen_random_uuid(),
 category_id uuid not null references public.job_categories(id) on delete restrict,
 slug text not null unique,
 name_ar text not null,
 name_en text not null,
 sort_order integer not null default 0,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 constraint job_specialties_id_category_unique unique (id, category_id)
);
alter table public.profiles
 add column category_id uuid references public.job_categories(id) on delete set null,
 add column specialty_id uuid,
 add constraint profiles_specialty_category_fkey foreign key (specialty_id, category_id)
 references public.job_specialties(id, category_id) on delete restrict;
alter table public.jobs
 add column category_id uuid references public.job_categories(id) on delete set null,
 add column specialty_id uuid,
 add constraint jobs_specialty_category_fkey foreign key (specialty_id, category_id)
 references public.job_specialties(id, category_id) on delete restrict;
create index job_specialties_category_id_idx on public.job_specialties(category_id);
create index profiles_category_specialty_idx on public.profiles(category_id, specialty_id);
create index jobs_category_specialty_status_idx on public.jobs(category_id, specialty_id, status);
create table public.candidate_experiences (
 id uuid primary key default gen_random_uuid(),
 candidate_id uuid not null references public.profiles(id) on delete cascade,
 company_name text not null,
 job_title text not null,
 start_date date,
 end_date date,
 is_current boolean not null default false,
 description text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint candidate_experiences_dates_check check (start_date is null or end_date is null or end_date >= start_date),
 constraint candidate_experiences_current_end_check check (not is_current or end_date is null)
);
create index candidate_experiences_candidate_id_idx on public.candidate_experiences(candidate_id);
alter table public.job_categories enable row level security;
alter table public.job_specialties enable row level security;
alter table public.candidate_experiences enable row level security;
grant select on public.job_categories, public.job_specialties to anon, authenticated;
grant insert, update, delete on public.job_categories, public.job_specialties to authenticated;
grant select, insert, update, delete on public.candidate_experiences to authenticated;
create policy "Public can view active job categories" on public.job_categories for select to anon, authenticated using (is_active = true);
create policy "Admins manage job categories" on public.job_categories for all to authenticated using (is_admin()) with check (is_admin());
create policy "Public can view active job specialties" on public.job_specialties for select to anon, authenticated using (
 is_active = true and exists (select 1 from public.job_categories c where c.id = job_specialties.category_id and c.is_active = true)
);
create policy "Admins manage job specialties" on public.job_specialties for all to authenticated using (is_admin()) with check (is_admin());
create policy "Candidates and admins view candidate experiences" on public.candidate_experiences for select to authenticated using (candidate_id = (select auth.uid()) or is_admin());
create policy "Candidates create own experiences" on public.candidate_experiences for insert to authenticated with check (candidate_id = (select auth.uid()));
create policy "Candidates update own experiences" on public.candidate_experiences for update to authenticated using (candidate_id = (select auth.uid())) with check (candidate_id = (select auth.uid()));
create policy "Candidates delete own experiences" on public.candidate_experiences for delete to authenticated using (candidate_id = (select auth.uid()));
insert into public.job_categories (slug,name_ar,name_en,sort_order) values
('healthcare-medical','الطب والمهن الصحية','Healthcare & Medical',1),
('engineering','الهندسة','Engineering',2),
('information-technology','تقنية المعلومات والتكنولوجيا','Information Technology',3),
('education','التعليم والتدريب','Education & Training',4),
('business-administration','الإدارة والأعمال','Business & Administration',5),
('agriculture-veterinary','الزراعة والطب البيطري','Agriculture & Veterinary',6),
('environment-natural-resources','البيئة والموارد الطبيعية','Environment & Natural Resources',7),
('technical-trades','المهن الفنية والحرفية','Technical & Skilled Trades',8),
('transport-logistics','النقل والخدمات اللوجستية','Transport & Logistics',9),
('media-communications','الإعلام والاتصال','Media & Communications',10),
('hospitality-tourism','الضيافة والسياحة','Hospitality & Tourism',11),
('law-social-development','القانون والتنمية الاجتماعية','Law & Social Development',12),
('general-services','الخدمات العامة والأعمال المساندة','General Services & Support',13);
insert into public.job_specialties (category_id,slug,name_ar,name_en,sort_order)
select c.id,s.slug,s.name_ar,s.name_en,s.sort_order
from public.job_categories c
join (values
('healthcare-medical','medicine','الطب البشري','Medicine',1),
('healthcare-medical','medical-laboratory-sciences','علوم المختبرات الطبية','Medical Laboratory Sciences',2),
('healthcare-medical','nursing','التمريض','Nursing',3),
('healthcare-medical','pharmacy','الصيدلة','Pharmacy',4),
('healthcare-medical','dentistry','طب الأسنان','Dentistry',5),
('healthcare-medical','public-health','الصحة العامة','Public Health',6),
('healthcare-medical','medical-imaging','الأشعة والتصوير الطبي','Medical Imaging',7),
('healthcare-medical','physiotherapy','العلاج الطبيعي','Physiotherapy',8),
('healthcare-medical','health-administration','الإدارة الصحية','Health Administration',9),
('engineering','civil-engineering','الهندسة المدنية','Civil Engineering',1),
('engineering','electrical-engineering','الهندسة الكهربائية','Electrical Engineering',2),
('engineering','mechanical-engineering','الهندسة الميكانيكية','Mechanical Engineering',3),
('engineering','chemical-engineering','الهندسة الكيميائية','Chemical Engineering',4),
('engineering','architecture','العمارة','Architecture',5),
('engineering','renewable-energy','الطاقة المتجددة','Renewable Energy',6),
('information-technology','software-development','تطوير البرمجيات','Software Development',1),
('information-technology','networks','الشبكات','Networks',2),
('information-technology','cybersecurity','الأمن السيبراني','Cybersecurity',3),
('information-technology','data-ai','البيانات والذكاء الاصطناعي','Data & AI',4),
('information-technology','it-support','الدعم الفني وتقنية المعلومات','IT Support',5),
('education','early-childhood-education','تعليم ما قبل المدرسة','Early Childhood Education',1),
('education','primary-education','التعليم الأساسي','Primary Education',2),
('education','secondary-education','التعليم الثانوي','Secondary Education',3),
('education','higher-education','التعليم الجامعي','Higher Education',4),
('education','special-education','التربية الخاصة','Special Education',5),
('education','educational-administration','الإدارة التربوية','Educational Administration',6),
('business-administration','accounting','المحاسبة','Accounting',1),
('business-administration','finance-banking','التمويل والمصارف','Finance & Banking',2),
('business-administration','human-resources','الموارد البشرية','Human Resources',3),
('business-administration','marketing','التسويق','Marketing',4),
('business-administration','sales','المبيعات','Sales',5),
('business-administration','project-management','إدارة المشاريع','Project Management',6),
('business-administration','office-administration','الإدارة المكتبية','Office Administration',7),
('agriculture-veterinary','agronomy','الإنتاج النباتي','Agronomy',1),
('agriculture-veterinary','animal-production','الإنتاج الحيواني','Animal Production',2),
('agriculture-veterinary','veterinary-medicine','الطب البيطري','Veterinary Medicine',3),
('agriculture-veterinary','irrigation-water','الري وإدارة المياه','Irrigation & Water',4),
('agriculture-veterinary','food-science','علوم الأغذية','Food Science',5),
('environment-natural-resources','environmental-health','الصحة البيئية','Environmental Health',1),
('environment-natural-resources','environmental-science','علوم البيئة','Environmental Science',2),
('environment-natural-resources','pest-control','مكافحة الآفات','Pest Control',3),
('environment-natural-resources','water-sanitation','المياه والإصحاح البيئي','Water & Sanitation',4),
('environment-natural-resources','waste-management','إدارة النفايات','Waste Management',5),
('technical-trades','electrician','الكهرباء','Electrical Work',1),
('technical-trades','plumbing','السباكة','Plumbing',2),
('technical-trades','automotive-mechanics','ميكانيكا السيارات','Automotive Mechanics',3),
('technical-trades','welding','اللحام','Welding',4),
('technical-trades','hvac','التبريد والتكييف','HVAC',5),
('technical-trades','maintenance','الصيانة','Maintenance',6),
('transport-logistics','driving','القيادة','Driving',1),
('transport-logistics','supply-chain','سلاسل الإمداد','Supply Chain',2),
('transport-logistics','warehousing','المخازن','Warehousing',3),
('transport-logistics','procurement','المشتريات','Procurement',4),
('media-communications','journalism','الصحافة','Journalism',1),
('media-communications','graphic-design','التصميم الجرافيكي','Graphic Design',2),
('media-communications','content-writing','كتابة المحتوى','Content Writing',3),
('media-communications','public-relations','العلاقات العامة','Public Relations',4),
('hospitality-tourism','hotel-management','إدارة الفنادق','Hotel Management',1),
('hospitality-tourism','food-beverage','الأغذية والمشروبات','Food & Beverage',2),
('hospitality-tourism','tourism','السياحة','Tourism',3),
('law-social-development','law','القانون','Law',1),
('law-social-development','social-work','الخدمة الاجتماعية','Social Work',2),
('law-social-development','community-development','تنمية المجتمع','Community Development',3),
('general-services','customer-service','خدمة العملاء','Customer Service',1),
('general-services','security','الأمن والحراسة','Security',2),
('general-services','cleaning-facilities','النظافة وإدارة المرافق','Cleaning & Facilities',3),
('general-services','general-labor','العمالة العامة','General Labor',4)
) as s(category_slug,slug,name_ar,name_en,sort_order) on c.slug=s.category_slug;


-- ============================================================================
-- APPLIED VERSION: 20261107090850
-- MIGRATION NAME: employer_job_management_policies_v1_7
-- ============================================================================

drop policy if exists "Verified companies create jobs" on public.jobs;
create policy "Verified companies create pending jobs"
on public.jobs for insert to authenticated
with check (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
);

drop policy if exists "Employers update own pending jobs" on public.jobs;
create policy "Employers update own pending jobs"
on public.jobs for update to authenticated
using (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
)
with check (
  status = 'pending'
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
      and c.status = 'verified'
  )
);

drop policy if exists "Employers delete own non-published jobs" on public.jobs;
create policy "Employers delete own non-published jobs"
on public.jobs for delete to authenticated
using (
  status in ('pending','closed','rejected')
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
  )
);


-- ============================================================================
-- APPLIED VERSION: 20261107092525
-- MIGRATION NAME: employer_company_description_rpc_v1_8
-- ============================================================================
create or replace function public.update_owned_company_description(p_company_id uuid, p_description text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.companies
     set description = nullif(btrim(p_description), '')
   where id = p_company_id
     and owner_id = auth.uid();

  if not found then
    raise exception 'Company not found or access denied';
  end if;
end;
$$;

revoke all on function public.update_owned_company_description(uuid, text) from public;
grant execute on function public.update_owned_company_description(uuid, text) to authenticated;

-- ============================================================================
-- APPLIED VERSION: 20261107101004
-- MIGRATION NAME: disable_auto_publish_jobs_require_manual_approval
-- ============================================================================
create or replace function public.auto_publish_verified_company_jobs()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Company verification does not publish jobs automatically.
  -- Every newly submitted job remains pending until an admin approves it.
  return new;
end;
$$;

-- ============================================================================
-- APPLIED VERSION: 20261107104500
-- MIGRATION NAME: public_verified_companies_view
-- ============================================================================
create or replace view public.public_verified_companies with (security_barrier = true) as select id, company_name, description from public.companies where status = 'verified'; grant select on public.public_verified_companies to anon, authenticated;

-- ============================================================================
-- APPLIED VERSION: 20261107110343
-- MIGRATION NAME: enable_jobs_realtime_publication
-- ============================================================================
alter publication supabase_realtime add table public.jobs;

-- ============================================================================
-- APPLIED VERSION: 20261107122912
-- MIGRATION NAME: harden_public_verified_companies_access
-- ============================================================================

begin;

-- Harden the public-facing company view: it must obey the caller's RLS policies.
create or replace view public.public_verified_companies
with (security_invoker = true, security_barrier = true)
as
select id, company_name, description
from public.companies
where status = 'verified';

-- Restrict direct company-table access to the columns actually used by the app.
revoke all privileges on table public.companies from anon;
revoke all privileges on table public.companies from authenticated;

grant select (id, company_name, description)
  on table public.companies to anon;

grant select (id, owner_id, company_name, description, website, status, created_at)
  on table public.companies to authenticated;

grant insert (owner_id, company_name, description, website, status)
  on table public.companies to authenticated;

grant update (status)
  on table public.companies to authenticated;

-- Public users and signed-in users may see only verified companies through the
-- safe column grants above; owners/admins retain their existing RLS access.
drop policy if exists "Public can view verified companies" on public.companies;
create policy "Public can view verified companies"
  on public.companies
  for select
  to anon, authenticated
  using (status = 'verified');

-- Keep the narrowly scoped owner-checked RPC, but remove mutable schemas
-- from its search path.
alter function public.update_owned_company_description(uuid, text)
  set search_path = '';

commit;


-- ============================================================================
-- APPLIED VERSION: 20261107122952
-- MIGRATION NAME: grant_status_for_verified_company_view
-- ============================================================================
-- The verified-company view filters on status; the invoker must be allowed
-- to read that column too. RLS limits anonymous rows to verified companies.
grant select (status) on table public.companies to anon;

-- ============================================================================
-- APPLIED VERSION: 20261107125337
-- MIGRATION NAME: reconcile_public_job_select_policy
-- ============================================================================
-- Reconcile anonymous and authenticated job-read policies.
-- Safe when the policy SQL was previously applied outside migration history.
drop policy if exists "Public view published jobs" on public.jobs;
drop policy if exists "Anonymous view published jobs" on public.jobs;
drop policy if exists "Authenticated view published and own jobs" on public.jobs;

create policy "Anonymous view published jobs"
  on public.jobs
  for select
  to anon
  using (status = 'published');

create policy "Authenticated view published and own jobs"
  on public.jobs
  for select
  to authenticated
  using (
    status = 'published'
    or exists (
      select 1
      from public.companies c
      where c.id = jobs.company_id
        and c.owner_id = (select auth.uid())
    )
  );

-- ============================================================================
-- APPLIED VERSION: 20261107125405
-- MIGRATION NAME: add_fk_indexes_and_optimize_profile_policies
-- ============================================================================
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


-- ============================================================================
-- APPLIED VERSION: 20261107193907
-- MIGRATION NAME: add_private_push_notification_subscriptions
-- ============================================================================
create table if not exists public.push_subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    endpoint text not null unique,
    subscription jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint push_subscriptions_endpoint_length check (char_length(endpoint) between 1 and 2048),
    constraint push_subscriptions_json_object check (jsonb_typeof(subscription) = 'object')
  );
  create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions(user_id);
  alter table public.push_subscriptions enable row level security;
  revoke all on public.push_subscriptions from anon, authenticated;
  grant select, insert, update, delete on public.push_subscriptions to authenticated;
  drop policy if exists "Users manage their own push subscriptions" on public.push_subscriptions;
  create policy "Users manage their own push subscriptions"
    on public.push_subscriptions
    for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

-- ============================================================================
-- APPLIED VERSION: 20261107200249
-- MIGRATION NAME: add_in_app_application_status_notifications
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.in_app_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  application_id uuid NOT NULL REFERENCES public.applications(id) ON DELETE CASCADE,
  job_title text NOT NULL DEFAULT 'الوظيفة',
  old_status text,
  new_status text NOT NULL CHECK (new_status IN ('submitted','reviewing','shortlisted','rejected','accepted')),
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);

CREATE INDEX IF NOT EXISTS in_app_notifications_user_created_idx
  ON public.in_app_notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS in_app_notifications_user_unread_idx
  ON public.in_app_notifications (user_id) WHERE read_at IS NULL;

ALTER TABLE public.in_app_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.in_app_notifications FROM anon, authenticated;
GRANT SELECT ON TABLE public.in_app_notifications TO authenticated;
GRANT UPDATE (read_at) ON TABLE public.in_app_notifications TO authenticated;

DROP POLICY IF EXISTS "Candidates read their own in-app notifications" ON public.in_app_notifications;
CREATE POLICY "Candidates read their own in-app notifications"
  ON public.in_app_notifications FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Candidates mark their own in-app notifications read" ON public.in_app_notifications;
CREATE POLICY "Candidates mark their own in-app notifications read"
  ON public.in_app_notifications FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION private.create_application_status_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_job_title text;
  v_status_label text;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT j.title INTO v_job_title
    FROM public.jobs AS j
    WHERE j.id = NEW.job_id;

    v_status_label := CASE NEW.status
      WHEN 'submitted' THEN 'تم استلام الطلب'
      WHEN 'reviewing' THEN 'قيد المراجعة'
      WHEN 'shortlisted' THEN 'ضمن القائمة المختصرة'
      WHEN 'rejected' THEN 'لم يتم الاختيار'
      WHEN 'accepted' THEN 'تم القبول'
      ELSE NEW.status
    END;

    INSERT INTO public.in_app_notifications
      (user_id, application_id, job_title, old_status, new_status, message)
    VALUES
      (NEW.candidate_id, NEW.id, COALESCE(v_job_title, 'الوظيفة'), OLD.status, NEW.status,
       'تم تحديث حالة طلبك إلى: ' || v_status_label);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.create_application_status_notification() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS applications_status_in_app_notification ON public.applications;
CREATE TRIGGER applications_status_in_app_notification
AFTER UPDATE OF status ON public.applications
FOR EACH ROW
EXECUTE FUNCTION private.create_application_status_notification();

-- ============================================================================
-- APPLIED VERSION: 20261107203156
-- MIGRATION NAME: add_job_state_and_allow_resume_optional_applications
-- ============================================================================
alter table public.jobs add column if not exists state text;

drop policy if exists "Candidates submit applications" on public.applications;
create policy "Candidates submit applications"
on public.applications
for insert
to authenticated
with check (
  candidate_id = (select auth.uid())
  and (
    resume_id is null
    or private.candidate_owns_resume(resume_id, candidate_id)
  )
  and exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.status = 'published'
  )
);

-- ============================================================================
-- APPLIED VERSION: 20261107210157
-- MIGRATION NAME: prepare_individual_job_posting_v1_1
-- ============================================================================

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
  

-- ============================================================================
-- APPLIED VERSION: 20261108061230
-- MIGRATION NAME: private_job_messaging
-- ============================================================================
-- Wazifti V1.3: private conversations between applicants and job posters.
-- This file is committed to the feature branch only; it is NOT applied to Supabase.

alter table public.in_app_notifications
  add column if not exists notification_type text not null default 'application_status';

create table if not exists public.job_messages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id),
  application_id uuid not null references public.applications(id),
  candidate_id uuid not null references auth.users(id) on delete cascade,
  poster_id uuid not null references auth.users(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint job_messages_distinct_participants check (candidate_id <> poster_id and sender_id <> recipient_id)
);

create index if not exists job_messages_conversation_idx
  on public.job_messages(job_id, application_id, created_at);
create index if not exists job_messages_recipient_unread_idx
  on public.job_messages(recipient_id, created_at desc) where read_at is null;

-- Allow an individual job poster to see applications on their own ads only.
drop policy if exists "Individuals view applications for own jobs" on public.applications;
create policy "Individuals view applications for own jobs"
on public.applications
for select
to authenticated
using (
  exists (
    select 1 from public.jobs j
    where j.id = applications.job_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
);

alter table public.job_messages enable row level security;

revoke all on public.job_messages from anon, authenticated;
grant select, insert on public.job_messages to authenticated;

drop policy if exists "Conversation participants read messages" on public.job_messages;
create policy "Conversation participants read messages"
on public.job_messages for select to authenticated
using (auth.uid() in (candidate_id, poster_id));

drop policy if exists "Conversation participants send messages" on public.job_messages;
create policy "Conversation participants send messages"
on public.job_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    (
      sender_id = candidate_id and recipient_id = poster_id
      and exists (
        select 1
        from public.applications a
        join public.jobs j on j.id = a.job_id
        left join public.companies c on c.id = j.company_id
        where a.id = job_messages.application_id
          and a.job_id = job_messages.job_id
          and a.candidate_id = job_messages.candidate_id
          and job_messages.poster_id = case
            when j.poster_type = 'individual' then j.posted_by_user_id
            else c.owner_id
          end
      )
    )
    or
    (
      sender_id = poster_id and recipient_id = candidate_id
      and exists (
        select 1
        from public.applications a
        join public.jobs j on j.id = a.job_id
        left join public.companies c on c.id = j.company_id
        where a.id = job_messages.application_id and a.job_id = job_messages.job_id and a.candidate_id = job_messages.candidate_id
          and (
            (j.poster_type = 'individual' and j.posted_by_user_id = auth.uid())
            or c.owner_id = auth.uid()
          )
      )
    )
  )
);


create or replace function public.get_job_conversation_context(p_application_id uuid)
returns table(job_id uuid, application_id uuid, candidate_id uuid, poster_id uuid, job_title text)
language plpgsql
security definer
set search_path = ''
as $ctx$
begin
  return query
  select j.id, a.id, a.candidate_id,
         case when j.poster_type = 'individual' then j.posted_by_user_id else c.owner_id end,
         j.title
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
    and (
      a.candidate_id = auth.uid()
      or (j.poster_type = 'individual' and j.posted_by_user_id = auth.uid())
      or c.owner_id = auth.uid()
    );
end;
$ctx$;

revoke all on function public.get_job_conversation_context(uuid) from public, anon;
grant execute on function public.get_job_conversation_context(uuid) to authenticated;

create or replace function public.mark_job_messages_read(p_job_id uuid, p_application_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  update public.job_messages
  set read_at = now()
  where job_id = p_job_id
    and application_id = p_application_id
    and recipient_id = auth.uid()
    and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.mark_job_messages_read(uuid, uuid) from public, anon;
grant execute on function public.mark_job_messages_read(uuid, uuid) to authenticated;

create or replace function private.notify_new_job_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_title text;
begin
  select j.title into v_title from public.jobs j where j.id = new.job_id;
  insert into public.in_app_notifications
    (user_id, application_id, job_title, old_status, new_status, message, notification_type)
  values
    (new.recipient_id, new.application_id, coalesce(v_title, 'وظيفة'), null, 'message',
     'وصلتك رسالة جديدة بخصوص وظيفة: ' || coalesce(v_title, 'وظيفة'), 'message');
  return new;
end;
$$;

revoke all on function private.notify_new_job_message() from public, anon, authenticated;
drop trigger if exists notify_new_job_message on public.job_messages;
create trigger notify_new_job_message
after insert on public.job_messages
for each row execute function private.notify_new_job_message();

-- Mark-as-read is available only through the scoped RPC above; no direct UPDATE policy is granted.


-- ============================================================================
-- APPLIED VERSION: 20261108061255
-- MIGRATION NAME: harden_job_message_rpcs
-- ============================================================================
-- Harden messaging RPCs: use invoker privileges and narrowly scoped read receipts.
grant update (read_at) on public.job_messages to authenticated;

drop policy if exists "Recipients mark own messages read" on public.job_messages;
create policy "Recipients mark own messages read"
on public.job_messages
for update
to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create or replace function public.get_job_conversation_context(p_application_id uuid)
returns table(job_id uuid, application_id uuid, candidate_id uuid, poster_id uuid, job_title text)
language plpgsql
security invoker
set search_path = ''
as $ctx$
begin
  return query
  select j.id, a.id, a.candidate_id,
         case when j.poster_type = 'individual' then j.posted_by_user_id else c.owner_id end,
         j.title
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
    and (
      a.candidate_id = auth.uid()
      or (j.poster_type = 'individual' and j.posted_by_user_id = auth.uid())
      or c.owner_id = auth.uid()
    );
end;
$ctx$;

create or replace function public.mark_job_messages_read(p_job_id uuid, p_application_id uuid)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare v_count integer;
begin
  update public.job_messages
  set read_at = now()
  where job_id = p_job_id
    and application_id = p_application_id
    and recipient_id = auth.uid()
    and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.get_job_conversation_context(uuid) from public, anon;
grant execute on function public.get_job_conversation_context(uuid) to authenticated;
revoke all on function public.mark_job_messages_read(uuid, uuid) from public, anon;
grant execute on function public.mark_job_messages_read(uuid, uuid) to authenticated;


-- ============================================================================
-- APPLIED VERSION: 20261108071633
-- MIGRATION NAME: tighten_job_message_insert_privileges
-- ============================================================================
revoke insert on table public.job_messages from authenticated;
revoke insert (id, created_at, read_at) on table public.job_messages from authenticated;
grant insert (job_id, application_id, candidate_id, poster_id, sender_id, recipient_id, body)
on table public.job_messages to authenticated;

-- ============================================================================
-- APPLIED VERSION: 20261108072503
-- MIGRATION NAME: revoke_unneeded_admin_users_table_privileges
-- ============================================================================
REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE public.admin_users FROM anon, authenticated;

-- ============================================================================
-- APPLIED VERSION: 20261108123633
-- MIGRATION NAME: close_and_archive_filled_jobs
-- ============================================================================
-- Wazifti V1.3: close a job when one applicant is accepted and archive it after 30 days.
-- No job or application rows are deleted; historical records remain available to their owners.

alter table public.jobs
  add column if not exists closed_at timestamptz,
  add column if not exists archived_at timestamptz;

create index if not exists jobs_filled_archive_due_idx
  on public.jobs (closed_at)
  where status = 'closed' and archived_at is null and closed_at is not null;

create index if not exists applications_job_status_idx
  on public.applications (job_id, status);

-- Let an individual who posted a job view and manage applications to that job.
drop policy if exists "Individual job owners view applications" on public.applications;
create policy "Individual job owners view applications"
on public.applications
for select
to authenticated
using (
  exists (
    select 1
    from public.jobs j
    where j.id = applications.job_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  )
);

-- Application status changes for individual-job owners will be exposed through
-- a narrowly scoped RPC after the existing company policies are audited.
-- Do not grant broad UPDATE access to application rows.


-- Keep filled company-job history as well; closed jobs remain in the owner's archive.
drop policy if exists "Employers delete own non-published jobs" on public.jobs;
create policy "Employers delete own pending or rejected jobs"
on public.jobs
for delete
to authenticated
using (
  status in ('pending', 'rejected')
  and exists (
    select 1 from public.companies c
    where c.id = jobs.company_id
      and c.owner_id = (select auth.uid())
  )
);

-- Keep filled individual-job history: owners may delete only pending/rejected ads.
drop policy if exists "Individuals delete own non-published jobs" on public.jobs;
create policy "Individuals delete own pending or rejected jobs"
on public.jobs
for delete
to authenticated
using (
  poster_type = 'individual'
  and posted_by_user_id = (select auth.uid())
  and status in ('pending', 'rejected')
);

-- Narrow RPC for individual posters to update application status without granting
-- UPDATE access to every column in the applications table.
create or replace function public.update_individual_job_application_status(
  p_application_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_new_status not in ('submitted', 'reviewing', 'shortlisted', 'rejected', 'accepted') then
    raise exception 'Invalid application status.';
  end if;

  if not exists (
    select 1
    from public.applications a
    join public.jobs j on j.id = a.job_id
    where a.id = p_application_id
      and j.poster_type = 'individual'
      and j.posted_by_user_id = (select auth.uid())
  ) then
    raise exception 'You are not authorized to update this application.';
  end if;

  update public.applications
  set status = p_new_status
  where id = p_application_id;
end;
$$;

revoke all on function public.update_individual_job_application_status(uuid, text) from public, anon;
grant execute on function public.update_individual_job_application_status(uuid, text) to authenticated;

-- The trigger serializes acceptance by locking the job row. This prevents two
-- applicants from being accepted for the same vacancy concurrently.
create or replace function private.close_job_when_applicant_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_status text;
begin
  if new.status <> 'accepted' or old.status is not distinct from new.status then
    return new;
  end if;

  select j.status
    into v_job_status
  from public.jobs j
  where j.id = new.job_id
  for update;

  if not found then
    raise exception 'The related job could not be found.';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.';
  end if;

  if exists (
    select 1
    from public.applications a
    where a.job_id = new.job_id
      and a.id <> new.id
      and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.';
  end if;

  update public.jobs
  set status = 'closed',
      closed_at = coalesce(closed_at, now()),
      archived_at = null
  where id = new.job_id;

  return new;
end;
$$;

revoke all on function private.close_job_when_applicant_accepted() from public, anon, authenticated;

drop trigger if exists close_job_when_applicant_accepted on public.applications;
create trigger close_job_when_applicant_accepted
after update of status on public.applications
for each row
execute function private.close_job_when_applicant_accepted();

-- Archive filled jobs after 30 days. This marks records as archived; it does
-- not delete jobs, applications, resumes, or conversations.
create or replace function private.archive_filled_jobs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_archived_count integer;
begin
  update public.jobs
  set archived_at = now()
  where status = 'closed'
    and closed_at is not null
    and archived_at is null
    and closed_at <= now() - interval '30 days';

  get diagnostics v_archived_count = row_count;
  return v_archived_count;
end;
$$;

revoke all on function private.archive_filled_jobs() from public, anon, authenticated;

-- Scheduling is intentionally not configured in this migration.
-- Run this function from a separately reviewed Supabase Scheduled Edge Function
-- after confirming the project's scheduler configuration. No extension is installed here.


-- ============================================================================
-- APPLIED VERSION: 20261108123637
-- MIGRATION NAME: reject_other_applicants_after_acceptance
-- ============================================================================
-- Wazifti: finalize a hiring decision atomically and notify all other active applicants.
-- Existing applications and conversations are retained. The existing status-change trigger
-- creates an in-app notification for every application whose status changes.

create or replace function private.close_job_when_applicant_accepted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_status text;
begin
  if new.status <> 'accepted' or old.status is not distinct from new.status then
    return new;
  end if;

  -- Serialize hiring decisions for the same vacancy to prevent multiple acceptances.
  select j.status
    into v_job_status
  from public.jobs j
  where j.id = new.job_id
  for update;

  if not found then
    raise exception 'The related job could not be found.';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.';
  end if;

  if exists (
    select 1
    from public.applications a
    where a.job_id = new.job_id
      and a.id <> new.id
      and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.';
  end if;

  update public.jobs
  set status = 'closed',
      closed_at = coalesce(closed_at, now()),
      archived_at = null
  where id = new.job_id;

  -- Other active applications are rejected; their status trigger creates notices.
  update public.applications
  set status = 'rejected'
  where job_id = new.job_id
    and id <> new.id
    and status not in ('accepted', 'rejected');

  return new;
end;
$$;

revoke all on function private.close_job_when_applicant_accepted() from public, anon, authenticated;

drop trigger if exists close_job_when_applicant_accepted on public.applications;
create trigger close_job_when_applicant_accepted
after update of status on public.applications
for each row
execute function private.close_job_when_applicant_accepted();


-- A scoped RPC is required for the final acceptance action. This prevents the UI
-- from writing an accepted status if the close/reject trigger has not been installed.
create or replace function public.finalize_job_hiring(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_poster_type text;
  v_posted_by_user_id uuid;
  v_company_owner_id uuid;
  v_job_status text;
  v_owner_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required.';
  end if;

  select a.job_id, j.poster_type, j.posted_by_user_id, c.owner_id, j.status
    into v_job_id, v_poster_type, v_posted_by_user_id, v_company_owner_id, v_job_status
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
  for update of j;

  if not found then
    raise exception 'Application or job not found.';
  end if;

  v_owner_id := case
    when v_poster_type = 'individual' then v_posted_by_user_id
    else v_company_owner_id
  end;

  if v_owner_id is distinct from (select auth.uid()) then
    raise exception 'You are not authorized to finalize this hiring decision.';
  end if;

  if v_job_status <> 'published' then
    raise exception 'This job is no longer accepting applicants.';
  end if;

  if exists (
    select 1 from public.applications a
    where a.job_id = v_job_id and a.status = 'accepted'
  ) then
    raise exception 'An applicant has already been accepted for this job.';
  end if;

  update public.applications
  set status = 'accepted'
  where id = p_application_id and job_id = v_job_id;
end;
$$;

revoke all on function public.finalize_job_hiring(uuid) from public, anon;
grant execute on function public.finalize_job_hiring(uuid) to authenticated;


-- Make rejection notifications clear when the vacancy has been filled by another applicant.
create or replace function private.create_application_status_notification()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_job_title text;
  v_job_status text;
  v_status_label text;
  v_message text;
begin
  if new.status is distinct from old.status then
    select j.title, j.status
      into v_job_title, v_job_status
    from public.jobs as j
    where j.id = new.job_id;

    v_status_label := case new.status
      when 'submitted' then 'تم استلام الطلب'
      when 'reviewing' then 'قيد المراجعة'
      when 'shortlisted' then 'ضمن القائمة المختصرة'
      when 'rejected' then 'لم يتم الاختيار'
      when 'accepted' then 'تم القبول'
      else new.status
    end;

    if new.status = 'rejected' and v_job_status = 'closed' then
      v_message := 'تم شغل الوظيفة واختيار متقدم آخر. نشكرك على اهتمامك، ولم يتم اختيار طلبك لهذه الوظيفة.';
    else
      v_message := 'تم تحديث حالة طلبك إلى: ' || v_status_label;
    end if;

    insert into public.in_app_notifications
      (user_id, application_id, job_title, old_status, new_status, message)
    values
      (new.candidate_id, new.id, coalesce(v_job_title, 'الوظيفة'), old.status, new.status, v_message);
  end if;
  return new;
end;
$function$;


-- ============================================================================
-- APPLIED VERSION: 20261108123757
-- MIGRATION NAME: remove_duplicate_individual_application_select_policy
-- ============================================================================
drop policy if exists "Individual job owners view applications" on public.applications;

-- ============================================================================
-- APPLIED VERSION: 20261109134139
-- MIGRATION NAME: job_alerts_complete_schema_security
-- ============================================================================
-- V1.10: complete job-alert schema, ownership policies, private worker queue, and publish trigger.
-- Additive only: does not modify application-status notifications or existing taxonomy.
-- push_subscriptions already exists in production; it is intentionally not recreated or altered here.

create table if not exists public.job_alert_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  is_enabled boolean not null default false,
  delivery_mode text not null default 'both' check (delivery_mode in ('instant','daily','both')),
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default false,
  daily_send_time time not null default '08:00',
  timezone text not null default 'Africa/Khartoum',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.job_alert_preferences is 'User-owned job alert preferences; billing tiers are intentionally not implemented in V1.';

create table if not exists public.job_alert_preference_categories (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  category_id uuid not null references public.job_categories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (preference_id, category_id)
);
create table if not exists public.job_alert_preference_specialties (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  specialty_id uuid not null references public.job_specialties(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (preference_id, specialty_id)
);
create table if not exists public.job_alert_preference_locations (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  state text not null check (length(btrim(state)) > 0),
  created_at timestamptz not null default now(),
  primary key (preference_id, state)
);
create table if not exists public.job_alert_preference_employment_types (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  employment_type text not null check (employment_type in ('full_time','part_time','remote','contract','temporary','internship')),
  created_at timestamptz not null default now(),
  primary key (preference_id, employment_type)
);

create table if not exists public.job_alert_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete set null,
  job_title_snapshot text not null,
  job_location_snapshot text,
  created_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  read_at timestamptz
);
comment on table public.job_alert_notifications is 'In-app job alert inbox, separate from application-status notifications.';

create table if not exists public.job_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.job_alert_notifications(id) on delete cascade,
  channel text not null check (channel in ('in_app','push')),
  delivery_kind text not null default 'instant' check (delivery_kind in ('instant','daily_digest')),
  batch_id uuid,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (notification_id, channel, delivery_kind)
);
comment on table public.job_alert_deliveries is 'Worker-managed delivery attempts per channel and delivery kind; digest items share a batch id.';

create table if not exists public.job_alert_digest_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  digest_date date not null,
  channel text not null check (channel in ('in_app','push')),
  batch_id uuid not null unique default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, digest_date, channel)
);
comment on table public.job_alert_digest_runs is 'Worker-managed per-user, per-local-date digest run; prevents duplicate daily summaries.';

create table if not exists public.job_alert_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type = 'job_published'),
  job_id uuid not null references public.jobs(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','completed','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (event_type, job_id)
);
comment on table public.job_alert_outbox is 'Worker queue populated when a job first becomes published.';

-- Indexes mirror the verified test schema. Existing taxonomy and push indexes are not recreated.
create index if not exists job_alert_preference_categories_category_idx on public.job_alert_preference_categories(category_id);
create index if not exists job_alert_preference_specialties_specialty_idx on public.job_alert_preference_specialties(specialty_id);
create index if not exists job_alert_preference_locations_state_idx on public.job_alert_preference_locations(state);
create index if not exists job_alert_preference_employment_types_type_idx on public.job_alert_preference_employment_types(employment_type);
create index if not exists job_alert_notifications_job_id_idx on public.job_alert_notifications(job_id);
create index if not exists job_alert_notifications_user_created_idx on public.job_alert_notifications(user_id, available_at, created_at desc);
create unique index if not exists job_alert_notifications_user_job_uidx on public.job_alert_notifications(user_id, job_id) where job_id is not null;
create index if not exists job_alert_deliveries_status_created_idx on public.job_alert_deliveries(status, created_at);
create index if not exists job_alert_deliveries_batch_idx on public.job_alert_deliveries(batch_id) where batch_id is not null;
create index if not exists job_alert_digest_runs_due_idx on public.job_alert_digest_runs(status, digest_date, created_at);
create index if not exists job_alert_outbox_ready_idx on public.job_alert_outbox(status, available_at, created_at);
create index if not exists job_alert_outbox_job_id_idx on public.job_alert_outbox(job_id);

-- All alert tables are protected. Worker-only tables are not accessible to browser roles.
alter table public.job_alert_preferences enable row level security;
alter table public.job_alert_preference_categories enable row level security;
alter table public.job_alert_preference_specialties enable row level security;
alter table public.job_alert_preference_locations enable row level security;
alter table public.job_alert_preference_employment_types enable row level security;
alter table public.job_alert_notifications enable row level security;
alter table public.job_alert_deliveries enable row level security;
alter table public.job_alert_digest_runs enable row level security;
alter table public.job_alert_outbox enable row level security;

drop policy if exists "Users manage own job alert preferences" on public.job_alert_preferences;
create policy "Users manage own job alert preferences" on public.job_alert_preferences
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users read own alert categories" on public.job_alert_preference_categories;
drop policy if exists "Users add own alert categories" on public.job_alert_preference_categories;
drop policy if exists "Users remove own alert categories" on public.job_alert_preference_categories;
create policy "Users read own alert categories" on public.job_alert_preference_categories
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert categories" on public.job_alert_preference_categories
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert categories" on public.job_alert_preference_categories
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert specialties" on public.job_alert_preference_specialties;
drop policy if exists "Users add own alert specialties" on public.job_alert_preference_specialties;
drop policy if exists "Users remove own alert specialties" on public.job_alert_preference_specialties;
create policy "Users read own alert specialties" on public.job_alert_preference_specialties
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert specialties" on public.job_alert_preference_specialties
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert specialties" on public.job_alert_preference_specialties
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert locations" on public.job_alert_preference_locations;
drop policy if exists "Users add own alert locations" on public.job_alert_preference_locations;
drop policy if exists "Users remove own alert locations" on public.job_alert_preference_locations;
create policy "Users read own alert locations" on public.job_alert_preference_locations
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert locations" on public.job_alert_preference_locations
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert locations" on public.job_alert_preference_locations
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert employment types" on public.job_alert_preference_employment_types;
drop policy if exists "Users add own alert employment types" on public.job_alert_preference_employment_types;
drop policy if exists "Users remove own alert employment types" on public.job_alert_preference_employment_types;
create policy "Users read own alert employment types" on public.job_alert_preference_employment_types
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert employment types" on public.job_alert_preference_employment_types
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert employment types" on public.job_alert_preference_employment_types
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own job alert notifications" on public.job_alert_notifications;
drop policy if exists "Users mark own job alert notifications read" on public.job_alert_notifications;
create policy "Users read own job alert notifications" on public.job_alert_notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users mark own job alert notifications read" on public.job_alert_notifications
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Explicitly close browser access to worker tables, then grant service_role only.
revoke all on table public.job_alert_preferences, public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types, public.job_alert_notifications,
  public.job_alert_deliveries, public.job_alert_digest_runs, public.job_alert_outbox
  from public, anon, authenticated;
grant select, insert, update, delete on public.job_alert_preferences to authenticated;
grant select, insert, delete on public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types to authenticated;
grant select on public.job_alert_notifications to authenticated;
grant update (read_at) on public.job_alert_notifications to authenticated;
grant all on public.job_alert_preferences, public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types, public.job_alert_notifications,
  public.job_alert_deliveries, public.job_alert_digest_runs, public.job_alert_outbox
  to service_role;

-- User-facing save RPC: invoker rights + auth.uid ownership, no SECURITY DEFINER.
create or replace function public.save_job_alert_preferences(
  p_is_enabled boolean,
  p_delivery_mode text default 'instant',
  p_locations text[] default array[]::text[],
  p_employment_types text[] default array[]::text[],
  p_daily_send_time time default '08:00',
  p_categories uuid[] default array[]::uuid[],
  p_specialties uuid[] default array[]::uuid[],
  p_push_enabled boolean default false
) returns uuid
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_preference_id uuid;
begin
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_delivery_mode not in ('instant','daily','both') then raise exception 'Invalid delivery mode' using errcode = '22023'; end if;
  if coalesce(cardinality(p_locations),0) > 100 or coalesce(cardinality(p_employment_types),0) > 20
     or coalesce(cardinality(p_categories),0) > 100 or coalesce(cardinality(p_specialties),0) > 200 then
    raise exception 'Too many alert filters' using errcode = '22023';
  end if;
  if coalesce(p_push_enabled,false) and not exists (select 1 from public.push_subscriptions s where s.user_id=v_user_id) then
    raise exception 'Enable browser push notifications on this device first' using errcode = '22023';
  end if;
  insert into public.job_alert_preferences(user_id,is_enabled,delivery_mode,in_app_enabled,push_enabled,daily_send_time,timezone)
  values(v_user_id,coalesce(p_is_enabled,false),p_delivery_mode,true,coalesce(p_push_enabled,false),coalesce(p_daily_send_time,'08:00'::time),'Africa/Khartoum')
  on conflict(user_id) do update set is_enabled=excluded.is_enabled,delivery_mode=excluded.delivery_mode,
    in_app_enabled=true,push_enabled=excluded.push_enabled,daily_send_time=excluded.daily_send_time,
    timezone='Africa/Khartoum',updated_at=now()
  returning id into v_preference_id;

  delete from public.job_alert_preference_categories where preference_id=v_preference_id;
  insert into public.job_alert_preference_categories(preference_id,category_id)
    select v_preference_id,x from unnest(coalesce(p_categories,array[]::uuid[])) x on conflict do nothing;
  delete from public.job_alert_preference_specialties where preference_id=v_preference_id;
  insert into public.job_alert_preference_specialties(preference_id,specialty_id)
    select v_preference_id,x from unnest(coalesce(p_specialties,array[]::uuid[])) x on conflict do nothing;
  delete from public.job_alert_preference_locations where preference_id=v_preference_id;
  insert into public.job_alert_preference_locations(preference_id,state)
    select v_preference_id,btrim(x) from unnest(coalesce(p_locations,array[]::text[])) x where btrim(x)<>'' on conflict do nothing;
  delete from public.job_alert_preference_employment_types where preference_id=v_preference_id;
  insert into public.job_alert_preference_employment_types(preference_id,employment_type)
    select v_preference_id,x from unnest(coalesce(p_employment_types,array[]::text[])) x
    where x in ('full_time','part_time','remote','contract','temporary','internship') on conflict do nothing;
  return v_preference_id;
end;
$$;
revoke all on function public.save_job_alert_preferences(boolean,text,text[],text[],time,uuid[],uuid[],boolean) from public, anon;
grant execute on function public.save_job_alert_preferences(boolean,text,text[],text[],time,uuid[],uuid[],boolean) to authenticated;

-- Server-only queue processor and atomic Push claim function.
create or replace function public.process_job_alert_outbox(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_event record; v_job public.jobs%rowtype; v_pref record; v_notification_id uuid;
  v_processed integer:=0; v_created integer:=0; v_failed integer:=0; v_skipped integer:=0; v_push_queued integer:=0;
begin
  for v_event in select o.id,o.job_id,o.attempt_count from public.job_alert_outbox o
    where o.status='pending' and o.available_at<=now() order by o.created_at asc
    for update skip locked limit least(greatest(coalesce(p_limit,10),1),25)
  loop
    update public.job_alert_outbox set status='processing',locked_at=now(),attempt_count=v_event.attempt_count+1 where id=v_event.id;
    begin
      select j.* into v_job from public.jobs j where j.id=v_event.job_id;
      if not found or v_job.status<>'published' then
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
        v_skipped:=v_skipped+1;
      else
        for v_pref in select p.* from public.job_alert_preferences p
          where p.is_enabled=true and p.delivery_mode in ('instant','both') and (p.in_app_enabled or p.push_enabled)
          and (not exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id and pl.state=coalesce(v_job.state,v_job.location)))
          and (not exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id and pet.employment_type=v_job.employment_type))
          and (not exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id and pc.category_id=v_job.category_id))
          and (not exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id and ps.specialty_id=v_job.specialty_id))
        loop
          v_notification_id:=null;
          insert into public.job_alert_notifications(user_id,job_id,job_title_snapshot,job_location_snapshot,available_at)
          values(v_pref.user_id,v_job.id,v_job.title,coalesce(nullif(btrim(v_job.state),''),nullif(btrim(v_job.location),'')),now())
          on conflict(user_id,job_id) where job_id is not null do nothing returning id into v_notification_id;
          if v_notification_id is not null then v_created:=v_created+1;
          else select n.id into v_notification_id from public.job_alert_notifications n where n.user_id=v_pref.user_id and n.job_id=v_job.id limit 1;
          end if;
          if v_notification_id is not null and v_pref.in_app_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status,sent_at)
            values(v_notification_id,'in_app','instant','sent',now()) on conflict(notification_id,channel,delivery_kind) do nothing;
          end if;
          if v_notification_id is not null and v_pref.push_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status)
            values(v_notification_id,'push','instant','pending') on conflict(notification_id,channel,delivery_kind) do nothing;
            v_push_queued:=v_push_queued+1;
          end if;
        end loop;
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
      end if;
      v_processed:=v_processed+1;
    exception when others then
      update public.job_alert_outbox set status=case when v_event.attempt_count+1>=5 then 'failed' else 'pending' end,
        available_at=now()+interval '1 minute'*power(2,least(v_event.attempt_count,5)),locked_at=null,last_error=left(sqlerrm,1000)
        where id=v_event.id;
      v_failed:=v_failed+1;
    end;
  end loop;
  return jsonb_build_object('processed_events',v_processed,'created_notifications',v_created,'failed_events',v_failed,
    'skipped_events',v_skipped,'push_deliveries_queued',v_push_queued);
end;
$$;
revoke all on function public.process_job_alert_outbox(integer) from public, anon, authenticated;
grant execute on function public.process_job_alert_outbox(integer) to service_role;

create or replace function public.claim_job_alert_push_deliveries(p_limit integer default 20)
returns table(delivery_id uuid,notification_id uuid,user_id uuid,job_title text,job_location text,job_id uuid)
language plpgsql security definer set search_path = pg_catalog, public
as $$
begin
  return query with picked as (
    select d.id from public.job_alert_deliveries d
    where d.channel='push' and d.delivery_kind='instant' and d.status='pending'
    order by d.created_at for update skip locked limit least(greatest(coalesce(p_limit,20),1),50)
  ), claimed as (
    update public.job_alert_deliveries d set status='processing',attempt_count=d.attempt_count+1,last_error=null
    from picked p where d.id=p.id returning d.id,d.notification_id
  )
  select c.id,n.id,n.user_id,n.job_title_snapshot,n.job_location_snapshot,n.job_id
  from claimed c join public.job_alert_notifications n on n.id=c.notification_id;
end;
$$;
revoke all on function public.claim_job_alert_push_deliveries(integer) from public, anon, authenticated;
grant execute on function public.claim_job_alert_push_deliveries(integer) to service_role;

-- Trigger enqueue is isolated in a non-exposed schema. It fires only on first transition to published.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to postgres, service_role;
create or replace function private.enqueue_job_alert_on_publish()
returns trigger language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if tg_op='INSERT' then
    if new.status='published' then
      insert into public.job_alert_outbox(event_type,job_id) values('job_published',new.id)
      on conflict(event_type,job_id) do nothing;
    end if;
  elsif tg_op='UPDATE' then
    if new.status='published' and old.status is distinct from new.status then
      insert into public.job_alert_outbox(event_type,job_id) values('job_published',new.id)
      on conflict(event_type,job_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_job_alert_on_publish() from public, anon, authenticated;
grant execute on function private.enqueue_job_alert_on_publish() to postgres, service_role;
drop trigger if exists enqueue_job_alert_after_publish on public.jobs;
create trigger enqueue_job_alert_after_publish after insert or update of status on public.jobs
for each row execute function private.enqueue_job_alert_on_publish();


-- Explicit service-only policies document the worker access model and satisfy RLS linting.
drop policy if exists "Worker manages job alert deliveries" on public.job_alert_deliveries;
create policy "Worker manages job alert deliveries" on public.job_alert_deliveries
  for all to service_role using (true) with check (true);
drop policy if exists "Worker manages job alert digest runs" on public.job_alert_digest_runs;
create policy "Worker manages job alert digest runs" on public.job_alert_digest_runs
  for all to service_role using (true) with check (true);
drop policy if exists "Worker manages job alert outbox" on public.job_alert_outbox;
create policy "Worker manages job alert outbox" on public.job_alert_outbox
  for all to service_role using (true) with check (true);

-- Do not touch public.in_app_notifications, push_notification_events, applications, or push_subscriptions.


-- ============================================================================
-- APPLIED VERSION: 20261109185459
-- MIGRATION NAME: job_alerts_daily_digest_scheduler
-- ============================================================================
-- Job-alert scheduling and daily in-app digest processing.
-- Additive only. Cron schedules and per-project Vault secrets are configured separately.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.process_job_alert_daily_digests(p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_pref record;
  v_job record;
  v_run_id uuid;
  v_batch_id uuid;
  v_notification_id uuid;
  v_local_now timestamp;
  v_local_date date;
  v_count integer;
  v_users integer := 0;
  v_jobs integer := 0;
  v_skipped integer := 0;
begin
  for v_pref in
    select p.*
    from public.job_alert_preferences p
    where p.is_enabled = true
      and p.delivery_mode in ('daily','both')
      and p.in_app_enabled = true
      and date_trunc('minute', now() at time zone coalesce(nullif(p.timezone,''),'Africa/Khartoum'))::time
          = date_trunc('minute', p.daily_send_time)::time
    order by p.updated_at desc
    limit least(greatest(coalesce(p_limit,25),1),100)
  loop
    v_local_now := now() at time zone coalesce(nullif(v_pref.timezone,''),'Africa/Khartoum');
    v_local_date := v_local_now::date;
    v_run_id := null;
    v_batch_id := gen_random_uuid();
    insert into public.job_alert_digest_runs(user_id,digest_date,channel,batch_id,status)
    values(v_pref.user_id,v_local_date,'in_app',v_batch_id,'processing')
    on conflict(user_id,digest_date,channel) do nothing
    returning id,batch_id into v_run_id,v_batch_id;

    if v_run_id is null then continue; end if;
    v_users := v_users + 1;
    v_count := 0;

    for v_job in
      select j.id,j.title,j.state,j.location
      from public.jobs j
      where j.status='published'
        and j.created_at >= now() - interval '24 hours'
        and (not exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=v_pref.id and pl.state=coalesce(j.state,j.location)))
        and (not exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=v_pref.id and pet.employment_type=j.employment_type))
        and (not exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=v_pref.id and pc.category_id=j.category_id))
        and (not exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=v_pref.id and ps.specialty_id=j.specialty_id))
      order by j.created_at desc
      limit 100
    loop
      v_notification_id := null;
      insert into public.job_alert_notifications(user_id,job_id,job_title_snapshot,job_location_snapshot,available_at)
      values(v_pref.user_id,v_job.id,v_job.title,coalesce(nullif(btrim(v_job.state),''),nullif(btrim(v_job.location),'')),now())
      on conflict(user_id,job_id) where job_id is not null do nothing
      returning id into v_notification_id;

      if v_notification_id is null then
        select n.id into v_notification_id from public.job_alert_notifications n
        where n.user_id=v_pref.user_id and n.job_id=v_job.id limit 1;
      end if;

      if v_notification_id is not null then
        insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,batch_id,status,sent_at)
        values(v_notification_id,'in_app','daily_digest',v_batch_id,'sent',now())
        on conflict(notification_id,channel,delivery_kind) do nothing;
        v_count := v_count + 1;
      end if;
    end loop;

    if v_count > 0 then
      update public.job_alert_digest_runs set status='sent',sent_at=now(),last_error=null where id=v_run_id;
      v_jobs := v_jobs + v_count;
    else
      update public.job_alert_digest_runs set status='skipped',sent_at=null,last_error='No matching jobs in the last 24 hours' where id=v_run_id;
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object('digest_users_processed',v_users,'matching_jobs_added',v_jobs,'empty_digests_skipped',v_skipped);
end;
$$;

revoke all on function public.process_job_alert_daily_digests(integer) from public,anon,authenticated;
grant execute on function public.process_job_alert_daily_digests(integer) to service_role;

create or replace function public.run_job_alerts_db_worker()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_instant jsonb;
  v_daily jsonb;
begin
  v_instant := public.process_job_alert_outbox(20);
  v_daily := public.process_job_alert_daily_digests(50);
  return jsonb_build_object('instant',v_instant,'daily',v_daily,'ran_at',now());
end;
$$;
revoke all on function public.run_job_alerts_db_worker() from public,anon,authenticated;
grant execute on function public.run_job_alerts_db_worker() to service_role;

create or replace function public.verify_job_alert_cron_token(p_token text)
returns boolean
language sql
security definer
set search_path = pg_catalog, vault
as $$
  select coalesce(bool_or(decrypted_secret = p_token),false)
  from vault.decrypted_secrets
  where name = 'wazifti_job_alert_cron_token'
    and p_token is not null
$$;
revoke all on function public.verify_job_alert_cron_token(text) from public,anon,authenticated;
grant execute on function public.verify_job_alert_cron_token(text) to service_role;


-- ============================================================================
-- APPLIED VERSION: 20261109185912
-- MIGRATION NAME: job_alerts_vapid_config_rpc
-- ============================================================================

create or replace function public.get_job_alert_vapid_config()
returns jsonb
language sql
security definer
set search_path = pg_catalog, vault
as $$
  select jsonb_build_object(
    'public_key', max(decrypted_secret) filter (where name='wazifti_vapid_public_key'),
    'private_key', max(decrypted_secret) filter (where name='wazifti_vapid_private_key'),
    'subject', max(decrypted_secret) filter (where name='wazifti_vapid_subject')
  )
  from vault.decrypted_secrets
  where name in ('wazifti_vapid_public_key','wazifti_vapid_private_key','wazifti_vapid_subject')
$$;
revoke all on function public.get_job_alert_vapid_config() from public, anon, authenticated;
grant execute on function public.get_job_alert_vapid_config() to service_role;


-- ============================================================================
-- APPLIED VERSION: 20261109192948
-- MIGRATION NAME: v1_12_expand_shared_job_taxonomy
-- ============================================================================
insert into public.job_categories (slug, name_ar, name_en)
values
  ('construction-building', 'البناء والتشييد', 'Construction & Building'),
  ('domestic-care-services', 'الخدمات المنزلية والرعاية', 'Domestic & Care Services')
on conflict (slug) do update
set name_ar = excluded.name_ar,
    name_en = excluded.name_en;

with specialty_seed(category_slug, slug, name_ar, name_en, sort_order) as (
  values
    ('technical-trades', 'electronics-repair', 'صيانة الأجهزة والإلكترونيات', 'Electronics & Appliance Repair', 7),
    ('technical-trades', 'solar-installation', 'تركيب وصيانة الطاقة الشمسية', 'Solar Installation & Maintenance', 8),
    ('technical-trades', 'carpentry', 'النجارة', 'Carpentry', 9),
    ('technical-trades', 'metal-fabrication', 'تشكيل المعادن', 'Metal Fabrication', 10),
    ('technical-trades', 'motorcycle-repair', 'صيانة الدراجات النارية', 'Motorcycle Repair', 11),
    ('construction-building', 'masonry', 'البناء والطوب', 'Masonry & Bricklaying', 1),
    ('construction-building', 'painting-decoration', 'الدهانات والديكور', 'Painting & Decoration', 2),
    ('construction-building', 'tiling-flooring', 'تركيب البلاط والأرضيات', 'Tiling & Flooring', 3),
    ('construction-building', 'plastering', 'اللياسة والجبس', 'Plastering & Gypsum', 4),
    ('construction-building', 'rebar-steel-fixing', 'حدادة التسليح', 'Rebar & Steel Fixing', 5),
    ('construction-building', 'construction-supervision', 'الإشراف على مواقع البناء', 'Construction Site Supervision', 6),
    ('construction-building', 'heavy-equipment-operation', 'تشغيل المعدات الثقيلة', 'Heavy Equipment Operation', 7),
    ('construction-building', 'construction-labor', 'عمال البناء', 'Construction Labor', 8),
    ('agriculture-veterinary', 'farm-worker', 'العمالة الزراعية', 'Farm Worker', 6),
    ('agriculture-veterinary', 'harvesting-packing', 'الحصاد والتعبئة الزراعية', 'Harvesting & Agricultural Packing', 7),
    ('transport-logistics', 'delivery-courier', 'التوصيل وخدمات البريد', 'Delivery & Courier Services', 5),
    ('domestic-care-services', 'domestic-worker', 'العمالة المنزلية', 'Domestic Worker', 1),
    ('domestic-care-services', 'childcare', 'رعاية الأطفال', 'Childcare', 2),
    ('domestic-care-services', 'elderly-care', 'رعاية كبار السن', 'Elderly Care', 3),
    ('domestic-care-services', 'laundry-services', 'الغسيل والكي', 'Laundry & Ironing', 4),
    ('domestic-care-services', 'home-cooking', 'الطهي المنزلي', 'Home Cooking', 5)
)
insert into public.job_specialties (category_id, slug, name_ar, name_en)
select c.id, s.slug, s.name_ar, s.name_en
from specialty_seed s
join public.job_categories c on c.slug = s.category_slug
on conflict (slug) do update
set category_id = excluded.category_id,
    name_ar = excluded.name_ar,
    name_en = excluded.name_en;

do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='job_categories' and column_name='sort_order') then
    execute $q$update public.job_categories set sort_order = case slug
      when 'construction-building' then 14 when 'domestic-care-services' then 15 else sort_order end$q$;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='job_categories' and column_name='is_active') then
    execute $q$update public.job_categories set is_active = true where slug in ('construction-building','domestic-care-services')$q$;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='job_specialties' and column_name='sort_order') then
    execute $q$update public.job_specialties set sort_order = v.sort_order
      from (values
        ('electronics-repair',7),('solar-installation',8),('carpentry',9),('metal-fabrication',10),('motorcycle-repair',11),
        ('masonry',1),('painting-decoration',2),('tiling-flooring',3),('plastering',4),('rebar-steel-fixing',5),
        ('construction-supervision',6),('heavy-equipment-operation',7),('construction-labor',8),
        ('farm-worker',6),('harvesting-packing',7),('delivery-courier',5),
        ('domestic-worker',1),('childcare',2),('elderly-care',3),('laundry-services',4),('home-cooking',5)
      ) as v(slug,sort_order) where public.job_specialties.slug=v.slug$q$;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='job_specialties' and column_name='is_active') then
    execute $q$update public.job_specialties set is_active = true where slug in (
      'electronics-repair','solar-installation','carpentry','metal-fabrication','motorcycle-repair',
      'masonry','painting-decoration','tiling-flooring','plastering','rebar-steel-fixing',
      'construction-supervision','heavy-equipment-operation','construction-labor',
      'farm-worker','harvesting-packing','delivery-courier',
      'domestic-worker','childcare','elderly-care','laundry-services','home-cooking'
    )$q$;
  end if;
end $$;