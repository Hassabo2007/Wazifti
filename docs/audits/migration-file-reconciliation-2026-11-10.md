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

## Initial manual bootstrap and historical dependency boundary

Prior-conversation provenance from 2026-11-04 records that the initial SQL Editor table-creation block created:
- `public.profiles`
- `public.companies`
- `public.jobs`
- `public.applications`

The block reportedly included primary/foreign keys, defaults, check constraints, unique `(job_id, candidate_id)`, timestamp fields and RLS enablement. The user reported **“Success – No rows returned”** after running this block.

A separate later block covered `handle_new_user()`, an `auth.users` trigger and initial RLS policies; the retrieved history does not independently confirm its successful execution. The exact SQL text has not yet been returned by the available retrieval interface. See `initial-manual-bootstrap-provenance-2026-11-10.md`.

The 26-entry production ledger starts on 2026-11-06, after those base tables already existed. Therefore:
- the 26 entries cannot be replayed from an empty PostgreSQL database by themselves;
- the first manual bootstrap is a required predecessor;
- the Auth/role/publication/Vault/extension prerequisites must be supplied explicitly for any isolated test;
- a current-state schema snapshot cannot be reversed mechanically into the exact initial schema.

## Safe next work

1. Recover the verbatim 2026-11-04 bootstrap SQL (or a trustworthy schema-only export from immediately after that bootstrap).
2. Recover/verify the separate `handle_new_user()` and initial RLS block.
3. For each of the 13 applied entries without a matching repository file, compare the captured SQL statement against the current catalog snapshot and adjacent applied entries. Do not infer equivalence solely from migration names.
4. For the 8 repository files without any exact/normalized applied match, identify whether they are pending, superseded, or partially consolidated.
5. Build additional PostgreSQL 17 fixtures per migration family only when every prerequisite is either recovered or explicitly stubbed and the test scope is labelled partial.
6. Keep all recovered historical SQL outside `supabase/migrations` until canonical ordering and semantic equivalence are verified.

**No production SQL, migration-history rows, or data were changed during this comparison. Do not run `supabase db push`, replay the forensic archive, or repair the production migration ledger as part of this audit.**
