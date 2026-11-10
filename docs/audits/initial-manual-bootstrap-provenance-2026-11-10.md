# Initial Supabase schema provenance — 2026-11-10

## Recovery breakthrough: original SQL recovered from PostgreSQL query statistics

On 2026-11-10, a read-only query against production `pg_stat_statements` recovered the original manual bootstrap statements.

The statistics view reported:
- `stats_reset = 2026-11-04 08:34:44.350849+00`.
- The reset occurred before the initial SQL Editor work recorded in the project conversation (09:56–09:58 on 2026-11-04).
- The query texts below were present with recorded calls. The user's prior conversation separately confirms successful execution of the first table-creation block with **“Success – No rows returned”**.

### Recovered core table definitions

The exact query text was recovered for all four initial tables:
- `public.profiles`: `id`, `full_name`, `email`, `phone`, `account_type`, `created_at`.
- `public.companies`: `id`, `owner_id`, `company_name`, `description`, `website`, `status`, `created_at`.
- `public.jobs`: `id`, `company_id`, `title`, `description`, `location`, `employment_type`, `salary_min`, `salary_max`, `currency`, `status`, `created_at`.
- `public.applications`: `id`, `job_id`, `candidate_id`, `cv_url`, `cover_letter`, `status`, `created_at`, and unique `(job_id, candidate_id)`.

The exact statements are preserved in `docs/audits/recovered-manual-bootstrap-2026-11-04.sql`. That file is a forensic record, not a production migration. Its statements are grouped in dependency order for review; original transaction boundaries and exact inter-statement order were not preserved by `pg_stat_statements`.

### Recovered admin and Auth setup

The same read-only query-history source also preserved:
- `public.admin_users(user_id, created_at)`, referencing `auth.users`.
- `public.is_admin()` as a stable SECURITY DEFINER function checking `admin_users`, plus the recorded revoke/grant statements.
- RLS enablement for `profiles`, `companies`, `jobs`, `applications`, and `admin_users`.
- `public.handle_new_user()`, which creates a profile from Auth user metadata/email.
- The `on_auth_user_created` trigger on `auth.users`.
- The first-generation policies for profile self-read, company-owner read, public/owner job read, candidate application insert/read, employer application read, administrator access, and verified-company job insertion.

The exact captured statements are preserved in the forensic SQL file. The conversation history records the function/trigger/policy block as having been reported as run; the explicit “Success – No rows returned” confirmation was associated with the initial table-creation block. Query statistics show the statements were submitted/executed and retained, but do not retain a per-statement wall-clock timestamp or original transaction grouping.

### Additional pre-ledger CV prerequisites recovered

A further read-only `pg_stat_statements` search recovered the manual CV setup needed by the applied migration `20261107203156`:

- `public.candidate_resumes` with UUID id, candidate owner FK, file name/path, 5 MiB file-size check, PDF-only MIME check, default flag and creation timestamp.
- RLS enablement and candidate-owned CV policies.
- `private.candidate_owns_resume(uuid, uuid)`, including the current path-prefix check through `storage.foldername(file_path)`, with EXECUTE granted to `authenticated` and PUBLIC revoked.
- `public.applications.resume_id` referencing `public.candidate_resumes(id)` with `ON DELETE SET NULL`.

The exact statements are preserved separately in `docs/audits/recovered-preledger-cv-prerequisites-2026-11-04.sql`. Query history also contains earlier variants of the CV ownership helper and add/update policies without the storage path check. The current production function and policies match the hardened path-checking variants; exact ordering of those variants is not retained. The local PostgreSQL test provides a minimal `storage.foldername()` test double and does not install or emulate Supabase Storage itself.

This pre-ledger CV setup is a necessary predecessor for `20261107203156`, which references `applications.resume_id` and `private.candidate_owns_resume()` but does not create them.

### Current schema comparison (read-only)

A live read-only comparison of the five recovered base tables against current `information_schema.columns` found:

- `companies`: the current column set still matches the recovered initial column set.
- `profiles`: current schema adds `category_id`, `specialty_id`, and `can_post_individual_jobs`.
- `jobs`: current schema adds `category_id`, `specialty_id`, `state`, `posted_by_user_id`, `poster_type`, `closed_at`, and `archived_at`. The initial `company_id NOT NULL` is now nullable to support individual job posters.
- `applications`: current schema adds `resume_id`; the original `cv_url` remains.
- `admin_users`: current column set still matches the recovered initial definition.

This comparison confirms the recovered baseline is a meaningful predecessor to the current schema. It does not by itself prove every intervening migration or constraint/policy change.

## Provenance boundaries

- `pg_stat_statements` is a statistics store, not an immutable audit log. Its retained query text is strong evidence of submitted SQL, but it does not preserve exact execution timestamps or transaction grouping.
- The query text for the first four CREATE TABLE statements is recovered verbatim.
- The `handle_new_user()`, trigger, `is_admin()`, RLS activation, and first-generation policy statements are also recovered verbatim as individual query texts.
- The user's successful execution confirmation applies explicitly to the initial table-creation block. For later setup statements, use the recorded query presence as execution evidence but do not overstate the user-confirmed success status.
- The forensic file groups statements into dependency order for testing; it is not claimed to be the exact original multi-statement editor submission.

## Important distinction: generated proposal vs executed bootstrap

A generated reference file named `wazifti_mvp_database_schema.sql` exists in the ChatGPT file library (created 2026-11-04). It describes a broader proposed schema, including `company_documents`, `candidate_resumes`, `job_promotions`, and `payments`, plus several enums and indexes.

That file explicitly says it should be run only in a new development project after review. It is not evidence that this exact SQL was executed against the Wazifti production project. It remains excluded from the recovered bootstrap.

## PostgreSQL 17 test outcome

The recovered manual bootstrap plus pre-ledger CV prerequisites were applied to a disposable PostgreSQL 17 database on GitHub-hosted Actions. The assertions passed for:
- all five base tables plus `candidate_resumes`;
- RLS enablement and recovered first-generation policies;
- Auth signup trigger and profile creation;
- the `is_admin()` function and authenticated EXECUTE grant;
- `applications.resume_id` and the `candidate_owns_resume()` helper's candidate/path ownership behavior.

The test uses minimal local stand-ins for Supabase Auth and Storage; it does not install or reproduce Supabase Auth/Storage services. The test result validates the recovered SQL slice on PostgreSQL 17, not full production equivalence.

## Safe test plan

1. Apply the recovered statements only to a temporary PostgreSQL 17 test database, with minimal local stand-ins for Supabase-managed `auth.users`, `auth.uid()`, and roles.
2. Assert the five tables, their RLS flags, all recovered policies, the Auth trigger, the admin lookup function, the unique application constraint, and profile creation on Auth insert.
3. Replay the captured production migration SQL in chronological order only after the baseline test passes. Skip or separately stub Supabase-managed extensions/services that do not exist in stock PostgreSQL 17; clearly report each exclusion.
4. Keep all recovered SQL outside `supabase/migrations` until the complete migration mapping is verified.

## Safety decisions

- No production DDL, RLS policy, function, trigger, table data, or migration-history row was modified.
- The query-history reads were SELECT-only.
- Do not run `supabase db push`, replay the forensic SQL on production, or repair the production migration ledger as part of this audit.
- The free PostgreSQL 17 test uses GitHub-hosted CI only; no paid Supabase branch or project is created.
