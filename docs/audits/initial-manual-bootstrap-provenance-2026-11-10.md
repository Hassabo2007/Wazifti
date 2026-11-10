# Initial Supabase schema provenance — 2026-11-10

## Recovered evidence from the 2026-11-04 conversation

A targeted search of prior project history found a stronger provenance lead than was available in the first audit draft:

- At **2026-11-04 09:56:48**, the conversation records a verbatim SQL block for the initial `CREATE TABLE` statements for `public.profiles`, `public.companies`, `public.jobs`, and `public.applications`.
- The recorded block included primary keys, foreign keys, defaults, check constraints, a unique constraint on `(job_id, candidate_id)`, timestamp fields, and `ENABLE ROW LEVEL SECURITY`.
- The prior conversation records the user's successful execution response as **“Success – No rows returned”** for that initial table-creation block. This is evidence that the SQL was executed successfully, but the exact SQL text itself has not yet been returned by the available conversation-retrieval interface in this audit session.
- At **2026-11-04 09:58:19**, a separate block was generated for `handle_new_user()`, a trigger on `auth.users`, and initial RLS policies for profiles, companies, jobs, and applications. The conversation summary says the block was reported as run, but does not preserve an explicit successful execution result for this second block. Treat this as **reported execution, not independently confirmed success**.
- At **2026-11-04 10:37:47–10:41:54**, a separate set of Storage object policies for candidate/company uploads was proposed and the user reported success. This is not the same as the initial public-table bootstrap and must not be merged into its provenance record.
- The user clarified that SQL Editor queries were not named/saved, so guessed query titles are withdrawn and must not be used as search targets.

## What is and is not recovered

**Supported by prior conversation evidence**
- The initial public tables were `profiles`, `companies`, `jobs`, and `applications`.
- The first table-creation block included the constraint/default/timestamp/RLS elements listed above.
- The user reported successful execution of that first block.
- A follow-up block covered `handle_new_user()`, the Auth trigger, and initial RLS policies, but its successful execution is not separately confirmed in the recovered summary.
- Storage policies were a later, separate operation.

**Still unavailable for forensic reconstruction**
- The verbatim contents of the first SQL block.
- The verbatim contents and exact success status of the follow-up function/trigger/RLS block.
- Exact policy expressions, role grants, trigger options, and any additional indexes not represented in the retrieved summary.
- A contemporaneous schema-only export from immediately after the initial manual bootstrap.

The conversation retrieval surfaced the timestamp and detailed characteristics of the original SQL but did not return the SQL code itself. Do not synthesize an executable historical migration from this summary.

## Important distinction: generated proposal vs executed bootstrap

A generated reference file named `wazifti_mvp_database_schema.sql` exists in the ChatGPT file library (created 2026-11-04). It describes a broader proposed schema, including `company_documents`, `candidate_resumes`, `job_promotions`, and `payments`, plus several enums and indexes.

That file explicitly says it should be run only in a new development project after review. It is not evidence that this exact SQL was executed against the Wazifti production project. A contemporaneous initial profile inspection recorded only `id`, `full_name`, and `email`; the generated proposal contains additional profile columns. Consequently, the generated proposal MUST NOT be treated as the authoritative production bootstrap.

## Reconciliation decision

1. Preserve the prior-conversation evidence as provenance, but do not claim the exact SQL has been recovered.
2. Do not synthesize an executable baseline migration from the current production schema and label it as the historical initial migration.
3. Do not put the generated proposal SQL into `supabase/migrations`.
4. Do not mark historical versions as applied or alter the production migration ledger to make counts agree.
5. Continue free PostgreSQL 17 CI with explicitly labelled reconstruction fixtures only where prerequisites can be independently stated.
6. Full replay requires the exact first SQL block plus verifiable contents/status for the follow-up trigger/RLS block, or an authoritative schema-only export from the period immediately after the manual bootstrap and before the first tracked migration (2026-11-06).

## Current confidence

- Initial table names: **high confidence**.
- Initial CREATE TABLE constraints/defaults/timestamps/RLS were present: **high-level confidence** from the conversation record.
- Successful execution of the initial table-creation block: **high confidence** from the recorded user success response.
- Exact original table DDL: **not recovered verbatim**.
- Follow-up Auth function/trigger/RLS definitions: **known to have been drafted; successful execution not independently confirmed**.
- Full clean-room replay of the complete historical sequence: **not certified**.
- Production database and migration ledger: **unchanged by this audit**.
