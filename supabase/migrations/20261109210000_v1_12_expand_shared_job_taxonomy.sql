-- V1.12: extend the shared taxonomy used by profiles, job posting,
-- search, and job-alert preferences. Stable slugs preserve existing IDs.
-- Supports both current production and the lean test schema.

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

-- Keep ordering/activation consistent on schemas that expose these columns.
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
