# Wazifti shared job taxonomy (V1.12)

Wazifti uses one database taxonomy for all job discovery and matching flows:

- Candidate profile: `profiles.category_id` and `profiles.specialty_id`
- Employer and individual job posts: `jobs.category_id` and `jobs.specialty_id`
- Public search and category filters: `job_categories` and `job_specialties`
- Job alerts: `job_alert_preference_categories` and `job_alert_preference_specialties`

The specialty-to-category relationship is enforced by the composite foreign keys on profiles and jobs. Do not introduce separate hard-coded category lists in the frontend.

## V1.12 expansion

The migration `20261109210000_v1_12_expand_shared_job_taxonomy.sql` adds two categories and 21 specialties using stable slugs and upserts, preserving existing IDs and existing profile/job references:

- Construction & Building: masonry, painting, tiling, plastering, steel fixing, site supervision, heavy equipment operation, construction labor.
- Domestic & Care Services: domestic work, childcare, elderly care, laundry/ironing, home cooking.
- Technical trades: electronics/appliance repair, solar installation, carpentry, metal fabrication, motorcycle repair.
- Agriculture: farm work, harvesting/packing.
- Transport: delivery/courier services.

## Release procedure

1. Review the migration and confirm the preview UI on candidate profile, job posting, search filters, and job alerts.
2. Apply the migration to the production Supabase project only when the release is approved.
3. Verify the new rows are active and that each specialty references the intended category.
4. Deploy the merged frontend. Do not change or recreate existing category/specialty IDs.
