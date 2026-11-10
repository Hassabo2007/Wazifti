# Wazifti — migration file reconciliation and prerequisite map

**Snapshot:** 2026-11-10  
**Source of applied history:** captured production `supabase_migrations.schema_migrations` ledger (26 entries).  
**Comparison target:** 21 SQL files in `supabase/migrations` on `audit/migration-history-reconciliation`.  
**Safety:** static text comparison only; no SQL from this report was executed against Supabase or copied into the active migration directory.

## Comparison method

The comparison distinguishes:
1. **Exact content match** — trimmed repository file equals the captured production SQL text.
2. **Normalized-text match** — content matches after removing comments, case, and whitespace differences. This is weaker evidence, not a byte-for-byte match.
3. **Timestamp drift** — the same SQL content appears under a different filename version.
4. **No match / content drift** — no exact or normalized repository equivalent was found.

Even exact SQL-text matching does not establish that a migration can be replayed safely without its historical prerequisites.

## Reconciled counts

| Classification | Count |
|---|---:|
| Production ledger entries | 26 |
| Repository migration files | 21 |
| Exact SQL matches (3 same version + 4 timestamp drift) | 7 |
| Additional normalized-only matches (5 same version + 1 timestamp drift) | 6 |
| Applied ledger entries with no exact or normalized repository match | 13 |
| Repository files without an exact raw match | 14 |
| Repository files with no exact or normalized applied-ledger match | 8 |

These counts supersede earlier wording that conflated exact and normalized matches. The updated exporter records these categories separately in its manifest.

## Applied production migrations with exact repository SQL

| Applied version | Production migration name | Repository file |
|---|---|---|
| `20261107092525` | `employer_company_description_rpc_v1_8` | `20261107092525_employer_company_description_rpc_v1_8.sql` |
| `20261107101004` | `disable_auto_publish_jobs_require_manual_approval` | `20261107101004_disable_auto_publish_jobs_require_manual_approval.sql` |
| `20261107125405` | `add_fk_indexes_and_optimize_profile_policies` | `20261107125405_add_fk_indexes_and_optimize_profile_policies.sql` |
| `20261108061230` | `private_job_messaging` | `20261108090000_private_job_messaging.sql` (timestamp drift) |
| `20261108061255` | `harden_job_message_rpcs` | `20261108100000_harden_job_message_rpcs.sql` (timestamp drift) |
| `20261108123637` | `reject_other_applicants_after_acceptance` | `20261108140000_reject_other_applicants_after_acceptance.sql` (timestamp drift) |
| `20261109134139` | `job_alerts_complete_schema_security` | `20261109140000_job_alerts_complete_schema_security.sql` (timestamp drift) |

**Important contradiction to preserve:** the repository file `20261108090000_private_job_messaging.sql` contains a comment saying it is not applied to Supabase, while the production ledger contains byte-for-byte identical SQL under applied version `20261108061230`. The production ledger is evidence that this SQL was recorded as applied. The misleading comment must not be used to override the production ledger; resolve the historical filename/version and comment only after reviewing the full migration sequence.

## Applied migrations with normalized-only repository matches

| Applied version | Production migration name | Repository file | Difference |
|---|---|---|---|
| `20261107104500` | `public_verified_companies_view` | `20261107104500_public_verified_companies_view.sql` | Comments/formatting differ |
| `20261107122912` | `harden_public_verified_companies_access` | `20261107122912_harden_public_verified_companies_access.sql` | Comments/formatting differ |
| `20261107122952` | `grant_status_for_verified_company_view` | `20261107122952_grant_status_for_verified_company_view.sql` | Comments/formatting differ |
| `20261107125337` | `reconcile_public_job_select_policy` | `20261107125337_reconcile_public_job_select_policy.sql` | Comments/formatting differ |
| `20261109185912` | `job_alerts_vapid_config_rpc` | `20261109185912_job_alerts_vapid_config_rpc.sql` | Comments/formatting differ |
| `20261109192948` | `v1_12_expand_shared_job_taxonomy` | `20261109210000_v1_12_expand_shared_job_taxonomy.sql` | Timestamp drift plus comments/formatting |

These are normalized text matches, not exact raw matches. They should be reviewed semantically before any canonical filename change.

## Applied ledger entries without a repository SQL match

The following 13 production-applied entries have no exact or normalized repository file equivalent:

| Applied version | Production migration name | Main prerequisite area / objects |
|---|---|---|
| `20261106215107` | `guard_application_updates` | Existing `applications`, `public.is_admin()`, `auth.role()`; adds a trigger/function |
| `20261107065459` | `add_job_taxonomy_and_candidate_experiences` | Existing `profiles`, `jobs`; creates categories, specialties, candidate experiences |
| `20261107090850` | `employer_job_management_policies_v1_7` | Existing `jobs`, `companies`; replaces job policies |
| `20261107110343` | `enable_jobs_realtime_publication` | Existing `jobs` and Supabase publication `supabase_realtime`; repository file has an idempotent DO wrapper, production SQL is a direct ALTER |
| `20261107193907` | `add_private_push_notification_subscriptions` | `auth.users`, `auth.uid()`; creates `push_subscriptions` and RLS |
| `20261107200249` | `add_in_app_application_status_notifications` | Existing `applications`, `jobs`; creates `in_app_notifications`, private function and trigger |
| `20261107203156` | `add_job_state_and_allow_resume_optional_applications` | Existing `jobs`, `applications`; adds job state and replaces application policy |
| `20261107210157` | `prepare_individual_job_posting_v1_1` | Existing `profiles`, `jobs`, `companies`; individual poster columns and policies |
| `20261108071633` | `tighten_job_message_insert_privileges` | Existing `job_messages`; privilege change |
| `20261108072503` | `revoke_unneeded_admin_users_table_privileges` | Existing `admin_users`; privilege revocation |
| `20261108123633` | `close_and_archive_filled_jobs` | Existing `jobs`, `applications`, `companies`; close/archive columns, functions, trigger, policies |
| `20261108123757` | `remove_duplicate_individual_application_select_policy` | Existing `applications`; removes duplicate policy |
| `20261109185459` | `job_alerts_daily_digest_scheduler` | Job-alert tables/functions, `pg_cron`, `pg_net`, Vault secrets and scheduled jobs; same-version repository file has content drift |

The production ledger archive preserves the SQL statements for these entries. They are recoverable as forensic evidence, but are not yet restored as canonical runnable repository migrations.

## Repository files with no exact or normalized applied-ledger match

1. `20261107110343_enable_jobs_realtime_publication.sql` — same version as an applied entry, but implementation text differs (idempotent wrapper vs direct ALTER).
2. `20261108080000_close_and_archive_filled_jobs.sql` — no exact/normalized match to applied `20261108123633`; semantic comparison required.
3. `20261108110000_allow_message_notification_status.sql` — may overlap with notification status changes in other applied entries; not proven consolidated.
4. `20261108120000_individual_posters_view_applicant_profiles.sql` — may overlap with other individual-poster policy work; not proven consolidated.
5. `20261109120000_job_alerts_preferences_push_queue.sql` — may be an earlier/partial design relative to the applied complete job-alert migration; not proven consolidated.
6. `20261109123000_job_alerts_push_subscription_index.sql` — requires comparison with the applied push-subscription DDL and indexes.
7. `20261109185459_job_alerts_daily_digest_scheduler.sql` — same timestamp as applied entry, but content differs; compare every function, secret reference, cron schedule and permission before resolving.
8. `20261110100000_v1_15_security_performance_hygiene.sql` — intentionally pending; not in the captured production ledger.

## Recovered manual bootstrap and historical dependency boundary

A read-only query against production `pg_stat_statements` recovered the original SQL text for the 2026-11-04 manual bootstrap. The recorded statistics reset was `2026-11-04 08:34:44.350849+00`, before the initial setup messages. The source retained the CREATE TABLE statements for `profiles`, `companies`, `jobs`, `applications`, plus the `admin_users` table, `is_admin()`, `handle_new_user()`, the Auth trigger, RLS activation and first-generation policies.

The exact query texts are preserved in `docs/audits/recovered-manual-bootstrap-2026-11-04.sql`. They are forensic evidence, grouped in dependency order for the test; the original transaction boundaries and precise statement ordering are not retained. The user separately confirmed successful execution of the first four table-creation statements with **“Success – No rows returned”**. Query statistics retained the later Auth/security statements with recorded calls, but the explicit user success confirmation applies to the first table-creation block. See `initial-manual-bootstrap-provenance-2026-11-10.md`.

A live read-only comparison against current `information_schema.columns` found:
- `companies` still has the original column set.
- `profiles` adds `category_id`, `specialty_id`, and `can_post_individual_jobs`.
- `jobs` adds `category_id`, `specialty_id`, `state`, `posted_by_user_id`, `poster_type`, `closed_at`, and `archived_at`; `company_id` changed from NOT NULL to nullable for individual postings.
- `applications` adds `resume_id`; original `cv_url` remains.
- `admin_users` still matches the recovered initial column set.

The pre-ledger setup also includes `public.candidate_resumes`, RLS policies for CV ownership, `private.candidate_owns_resume(uuid, uuid)`, and `applications.resume_id`. These were recovered from query statistics and are preserved separately in `docs/audits/recovered-preledger-cv-prerequisites-2026-11-04.sql`. They are prerequisites for applied migration `20261107203156`, which references them but does not create them.

The 26-entry production ledger starts on 2026-11-06, after this manual/pre-ledger setup.

## PostgreSQL 17 validation results

A free GitHub-hosted PostgreSQL 17 workflow now builds the recovered manual baseline and pre-ledger CV prerequisites in a disposable database, then replays the captured production SQL in chronological version order.

**Latest validated run:** `42805760976` — all three jobs passed.

- Recovered manual bootstrap: passed. Assertions cover `profiles`, `companies`, `jobs`, `applications`, `admin_users`, `candidate_resumes`, the application resume link, RLS activation, recovered policies, Auth signup trigger, `is_admin()`, and `candidate_owns_resume()`.
- Historical ledger replay: **24 of 26** captured applied migrations passed in order on PostgreSQL 17.
- Final schema assertions passed for taxonomy/experience, push subscriptions, notifications, messaging, individual job posting, job-alert tables, key columns, functions and RLS policies.
- The isolated V1.15 compatibility fixture also passed independently.

Two migrations were intentionally excluded from the stock PostgreSQL 17 replay:

1. `20261107110343_enable_jobs_realtime_publication` — requires the Supabase-managed `supabase_realtime` publication and matching WAL configuration.
2. `20261109185459_job_alerts_daily_digest_scheduler` — requires Supabase-managed `pg_cron`, `pg_net`, Vault-backed cron configuration and scheduled jobs.

The replay used only a local `auth.users` / `auth.uid()` / `auth.role()` test double, a minimal Storage `foldername()` helper, and an empty local Vault `decrypted_secrets` table. No Supabase credentials, secrets, production data or production connection were used. The two skipped migrations remain untested in this stock PostgreSQL environment.

## Remaining reconciliation work

1. Perform semantic comparison of the 13 applied ledger entries without an exact or normalized repository match, focusing on effects visible in the production catalog and adjacent migration statements.
2. Resolve the 8 repository files without any exact/normalized applied-ledger match as pending, superseded, or consolidated; do not delete or promote them automatically.
3. Compare the final PostgreSQL 17 test schema with the captured production catalog at the object level (constraints, indexes, policies, functions and triggers), noting differences caused by the two exclusions and Supabase-managed services.
4. Keep recovered historical SQL outside `supabase/migrations` until canonical ordering and semantic equivalence are reviewed. The PR remains Draft.

**Validation is substantial but partial:** 24/26 historical SQL statements replay on PostgreSQL 17 from the recovered manual/pre-ledger baseline; the two Supabase-managed migrations and full production equivalence are not certified.

**No production SQL, migration-history rows, or data were changed during this comparison. Do not run `supabase db push`, replay the forensic archive on production, or repair the production migration ledger as part of this audit.**
