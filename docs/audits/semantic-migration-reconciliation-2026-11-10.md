# Wazifti — semantic migration reconciliation

**Date:** 2026-11-10  
**Scope:** 13 applied production-ledger entries without an exact/normalized repository SQL match, and 8 repository files without an exact/normalized applied-ledger match.  
**Production access:** read-only catalog queries only. No SQL was applied, no rows were changed, and no migration-history entries were inserted or edited.  
**Evidence:** production ledger SQL archive exported by workflow run `42805956945`; current production catalog (policies, functions, triggers, indexes, constraints, grants, publication membership and cron jobs); repository files on `audit/migration-history-reconciliation`.

## Executive result

The semantic review narrows the apparent drift:

- Several applied migrations are genuinely missing from the canonical repository and should be restored as **forensic historical records**, not replayed.
- Some files are later/squashed representations of effects already applied, rather than unapplied migrations.
- The job-alert partial files are superseded or redundant relative to the applied complete job-alert migration and earlier push-subscription migration.
- Two repository files describe effects visible in production but absent from the 26-entry ledger. Their origin is therefore **catalog-confirmed, provenance-unresolved**; do not label them as ledger-applied.
- V1.15 remains intentionally pending. Production still lacks the five FK indexes proposed by V1.15.

No production change is recommended as part of this audit.

## A. Thirteen applied ledger entries without exact/normalized repository matches

| Applied version / migration | Current semantic evidence | Classification | Safe repository action |
|---|---|---|---|
| `20261106215107 guard_application_updates` | `public.guard_application_updates()` and its BEFORE UPDATE trigger exist. Function body matches the recovered ledger SQL: trusted server/admin bypass; non-status application-field changes rejected. | Applied effect confirmed; repository history missing. | Restore the exact captured SQL as a clearly labelled historical migration artifact, after canonical ordering review. |
| `20261107065459 add_job_taxonomy_and_candidate_experiences` | `job_categories`, `job_specialties`, `candidate_experiences`, category/specialty columns, indexes and their RLS policies exist. | Applied effect confirmed; repository history missing. | Restore captured SQL as historical evidence; retain its dependency on the manual bootstrap. |
| `20261107090850 employer_job_management_policies_v1_7` | Current jobs policies include verified-company pending-job creation, verified-owner pending-job updates and admin management. Later policy changes further restrict deletion to pending/rejected jobs. | Applied effect confirmed; later policies supersede part of its original policy state. | Restore exact SQL as historical record; document later policy replacement rather than rewriting history. |
| `20261107110343 enable_jobs_realtime_publication` | `public.jobs` is present in `supabase_realtime`. Applied SQL is a direct ALTER PUBLICATION; repository version checks `pg_publication_tables` first and adds only when absent. | Semantic effect equivalent; repository version is more idempotent. | Keep the guarded repository version. Record that production ledger used the direct statement; do not force text identity. |
| `20261107193907 add_private_push_notification_subscriptions` | `push_subscriptions` exists with endpoint uniqueness/length and JSON-object constraints, RLS, owner policy, and `push_subscriptions_user_id_idx`. The later complete job-alert migration explicitly says it does not recreate/alter this table. | Applied effect confirmed; repository history missing. | Restore captured SQL as historical evidence. Do not substitute the later partial V1.10 file as the original source. |
| `20261107200249 add_in_app_application_status_notifications` | `in_app_notifications`, owner SELECT/UPDATE policies, and `applications_status_in_app_notification` trigger exist. | Applied effect confirmed; repository history missing. | Restore captured SQL as historical evidence. The additional `message` status constraint is a separate, unledgered catalog effect (see file 08110000 below). |
| `20261107203156 add_job_state_and_allow_resume_optional_applications` | `jobs.state` exists. Current candidate application INSERT policy allows NULL resume or validates ownership through `private.candidate_owns_resume`, and requires a published job. | Applied effect confirmed; repository history missing. | Restore exact captured SQL as historical record, retaining the pre-ledger CV prerequisites. |
| `20261107210157 prepare_individual_job_posting_v1_1` | Individual poster columns and current SELECT/INSERT/UPDATE/DELETE policies exist. | Applied effect confirmed; repository history missing. | Restore captured SQL as historical record; document subsequent policy hardening separately. |
| `20261108071633 tighten_job_message_insert_privileges` | Authenticated has SELECT at table level and INSERT only on the seven intended columns (job/application/candidate/poster/sender/recipient/body); no table-wide INSERT grant is present. | Applied effect confirmed; repository history missing. | Restore exact captured SQL as historical record. |
| `20261108072503 revoke_unneeded_admin_users_table_privileges` | No anon/authenticated table privileges were returned for `admin_users`; consistent with the intended revoke. | Applied effect confirmed; repository history missing. | Restore exact captured SQL as historical record. |
| `20261108123633 close_and_archive_filled_jobs` | Closed/archive columns, indexes, RPC, private archive/close functions and close trigger exist. The subsequent applied `20261108123637` changes the close trigger function to reject other applicants after acceptance. | Repository file 08080000 is a consolidated/adjusted counterpart, not a text-equivalent historical copy. | Keep both historical facts distinct. Do not replace the captured applied SQL with the later repository variant. |
| `20261108123757 remove_duplicate_individual_application_select_policy` | The specifically removed policy is absent; a distinct current policy, `Individuals view applications for own jobs`, remains. | Cleanup step reflected in final policy state; standalone SQL effect is historical/transient. | Record as a historical cleanup migration. Do not recreate the removed policy. |
| `20261109185459 job_alerts_daily_digest_scheduler` | Daily digest and worker functions exist with service_role-only execute grants. Both named cron jobs are active at every minute and their commands match the captured scheduler design, including Vault-backed Edge Function call. | Semantic effect confirmed; repository file has textual/content-format drift but its key catalog effects match. | Keep the repository scheduler file as the candidate canonical representation; compare full captured SQL before any filename/comment cleanup. Do not re-run it on production. |

## B. Eight repository files without exact/normalized applied-ledger matches

| Repository file | Semantic comparison | Classification / disposition |
|---|---|---|
| `20261107110343_enable_jobs_realtime_publication.sql` | Its guarded publication-membership check achieves the same final publication membership as the direct production ALTER, while avoiding duplicate-add failure. | **Equivalent implementation.** Keep; document the historical SQL difference. |
| `20261108080000_close_and_archive_filled_jobs.sql` | Closely tracks applied `20261108123633`, but intentionally omits creation of the temporary policy named `Individual job owners view applications`. Production later dropped that policy in `20261108123757`; a differently named individual-owner SELECT policy remains. The accepted-applicant trigger was subsequently extended by `20261108123637` to reject other active applicants. | **Consolidated final-state variant**, not an exact historical replacement. Preserve as an explanatory candidate, but do not count as the applied SQL or replay it. |
| `20261108110000_allow_message_notification_status.sql` | Production has `in_app_notifications_new_status_check` allowing submitted/reviewing/shortlisted/rejected/accepted/message. The applied notification-table migration initially allowed only application statuses, and the applied complete job-alert migration explicitly leaves `in_app_notifications` untouched. | **Catalog effect present, provenance unresolved.** The file is a plausible source, but the 26-entry ledger does not prove it was applied. Keep separate from applied-history claims. |
| `20261108120000_individual_posters_view_applicant_profiles.sql` | Production has the policy `Individual job posters view applicant profiles` with the same ownership/application predicate. No matching ledger entry was found. | **Catalog effect present, provenance unresolved.** Retain as a likely manual/unledgered SQL artifact; do not label as a recorded migration. |
| `20261109120000_job_alerts_preferences_push_queue.sql` | Its preference-saving and instant-outbox/push-claim logic substantially overlaps the later applied `20261109134139_job_alerts_complete_schema_security`. The applied complete migration is the canonical complete job-alert schema/security step and explicitly does not alter push_subscriptions or in_app_notifications. | **Superseded/overlapping design.** Do not replay or add as a separate historical applied migration. Preserve as draft evidence only; compare individual function signatures before removing from the repository. |
| `20261109123000_job_alerts_push_subscription_index.sql` | The same `push_subscriptions_user_id_idx` already exists, and the applied `20261107193907` migration created it. | **Redundant.** No new schema effect; do not treat as pending work. |
| `20261109185459_job_alerts_daily_digest_scheduler.sql` | Current production has the daily-digest and worker functions, service_role-only grants, and both active cron schedules matching this scheduler design. The applied ledger contains the same version but a different SQL text representation. | **Semantic match with content drift.** Preserve the file; do not execute again. A later documentation-only reconciliation may identify exact statement-level differences. |
| `20261110100000_v1_15_security_performance_hygiene.sql` | Not in the captured applied ledger. Current production lacks `in_app_notifications(application_id)` and the four proposed `job_messages` FK indexes (`application_id`, `candidate_id`, `poster_id`, `sender_id`). | **Intentionally pending.** Do not mark applied. Continue separate free PostgreSQL 17 compatibility validation and security review before any production application. |

## C. Read-only production checks performed

1. **Policies and functions:** inspected current policies for applications, jobs, profiles, taxonomy, push subscriptions, notifications and messages; inspected relevant function definitions and ACLs.
2. **Triggers:** confirmed application-update guard, notification trigger, close-on-acceptance trigger, job-alert enqueue trigger and message notification trigger.
3. **Realtime:** confirmed `public.jobs` is in `supabase_realtime`.
4. **Message privileges:** confirmed authenticated has table SELECT and column-limited INSERT only on the intended seven columns.
5. **Push subscriptions:** confirmed owner RLS policy, endpoint uniqueness/validation, JSON object validation and user index.
6. **Notifications:** confirmed the message status check constraint and notification trigger/policies.
7. **Scheduler:** confirmed both Wazifti cron jobs are active at `* * * * *`; commands invoke the database worker and the Vault-token-protected Edge Function.
8. **V1.15 indexes:** confirmed the five proposed indexes are still absent from production.

## D. Required follow-up before closing PR #28

1. **Completed:** restored the nine exact recovered SQL texts that had no repository counterpart under `docs/audits/production-ledger-archive/2026-11-10/`. The archive includes a README safety warning and SHA-256 manifest. It is outside `supabase/migrations` and must never be replayed.
2. **Completed:** documented both catalog-present/unledgered effects in `docs/audits/unledgered-production-change-provenance-2026-11-10.md`. Their current definitions are confirmed, but their execution channel/time/actor remain unproven.
3. Document the `close_and_archive_filled_jobs` sequence as applied 08123633 → applied 08123637 function hardening → applied 08123757 duplicate-policy cleanup, and explain how repository file 08080000 represents a later consolidated state.
4. Mark the V1.10 partial preference/queue file as superseded/overlapping and the standalone push index as redundant; do not delete either until the repository history and consumers are checked.
5. Keep PR #28 Draft. Do not run `supabase db push`, replay recovered SQL on production, or edit `supabase_migrations.schema_migrations`.

## Archive and provenance deliverables

- Exact recovered historical SQL archive (9 files): `docs/audits/production-ledger-archive/2026-11-10/`.
- Integrity file: `docs/audits/production-ledger-archive/2026-11-10/manifest.sha256`.
- Provenance assessment for the two unledgered catalog effects: `docs/audits/unledgered-production-change-provenance-2026-11-10.md`.
- The two related files already in `supabase/migrations` remain unledgered candidates; they were not moved into the historical archive and were not executed.

## Confidence and limits

- **High confidence:** current catalog effects listed above, because they were checked directly with read-only production queries.
- **High confidence:** the 13 applied migration SQL texts are present in the captured production-ledger export.
- **Not proven:** exact execution provenance for catalog-present changes absent from the ledger; exact original transaction grouping/order of the 2026-11-04 manual bootstrap; full production equivalence of the stock PostgreSQL 17 replay.
- **Not authorized or performed:** any production DDL, data mutation, scheduler modification, migration-ledger repair, or PR merge.
