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
