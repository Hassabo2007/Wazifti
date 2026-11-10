# Initial Supabase schema provenance — 2026-11-10

## Finding from the project history

The Wazifti Supabase database was initially bootstrapped manually in the Supabase SQL Editor before the repository's tracked migration history began.

The recovered project notes identify the following initial manually-created public tables:
- `public.profiles`
- `public.companies`
- `public.jobs`
- `public.applications`

The project notes also record a follow-up manual SQL step that created:
- `handle_new_user()`
- an Auth trigger on `auth.users`
- initial RLS policies for profiles, companies, jobs, and applications.

The user has clarified that they were unable to name the queries in the SQL Editor. Accordingly, the two query names mentioned in an earlier draft of this audit were assumptions, not verified titles, and must not be used as search targets or cited as evidence. The current project file/library search did not locate the exact manually executed SQL or an authoritative export. Therefore, the original DDL, exact policy expressions, grants, and trigger body cannot yet be reproduced byte-for-byte from available evidence.

## Important distinction: generated proposal vs executed bootstrap

A generated reference file named `wazifti_mvp_database_schema.sql` exists in the ChatGPT file library (created 2026-11-04). It describes a broader proposed schema, including `company_documents`, `candidate_resumes`, `job_promotions`, and `payments`, plus several enums and indexes.

That file explicitly says it should be run only in a new development project after review. It is not evidence that this exact SQL was executed against the Wazifti production project. Earlier project notes instead identify only the four tables above as the manually created initial tables, and a contemporaneous inspection of `profiles` recorded only `id`, `full_name`, and `email`. Consequently, the generated proposal MUST NOT be treated as the authoritative production bootstrap.

## Reconciliation decision

1. Do not synthesize an executable baseline migration from the current production schema and label it as the historical initial migration.
2. Do not put the generated proposal SQL into `supabase/migrations`.
3. Do not mark any historical versions as applied or alter the production migration ledger to make the counts agree.
4. Continue the free PostgreSQL 17 CI work using an explicitly labelled reconstruction fixture only if its provenance and omissions are documented. It can validate later migration behavior but cannot certify a byte-for-byte replay of the original manual bootstrap.
5. To certify full replay compatibility, recover the original manually executed SQL by another verifiable route, or obtain an authoritative schema-only export from the period immediately after the manual bootstrap and before the first tracked migration (2026-11-06). Do not rely on guessed query titles. If the SQL can be located in the dashboard or another record, export its exact contents without executing it.

## Current confidence

- Initial manual table names: supported by recovered project notes.
- Initial trigger/function and RLS setup: supported at a high-level by recovered project notes.
- Exact original columns, constraints, indexes, trigger body, grants, and policy expressions: not yet recovered.
- Full clean-room replay of the complete historical sequence: not certified.
- Production database and migration ledger: unchanged by this audit.
