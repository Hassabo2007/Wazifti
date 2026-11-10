# Recovered production-ledger SQL archive

**Purpose:** preserve exact SQL text captured from the production Supabase migration ledger for forensic/history reconciliation.

**Source:** GitHub Actions artifact `wazifti-recovered-production-migrations`, workflow run `42805956945`, artifact ID `13758740698`, captured 2026-11-10. The archive contains the 9 applied-ledger entries that had no canonical repository SQL counterpart at the time of recovery.

## Critical safety notice

**DO NOT EXECUTE THESE FILES. DO NOT COPY THEM INTO `supabase/migrations`.**

These files are historical evidence, not a replay bundle. Production already records these versions as applied. Several statements are not idempotent, depend on earlier manual bootstrap SQL or Supabase-specific objects, and their effects have since been modified by later migrations. Replaying them can fail or damage production state.

The archive is intentionally outside the active migration directory.

## Included historical ledger entries

1. `20261106215107_guard_application_updates.sql`
2. `20261107065459_add_job_taxonomy_and_candidate_experiences.sql`
3. `20261107090850_employer_job_management_policies_v1_7.sql`
4. `20261107193907_add_private_push_notification_subscriptions.sql`
5. `20261107200249_add_in_app_application_status_notifications.sql`
6. `20261107203156_add_job_state_and_allow_resume_optional_applications.sql`
7. `20261107210157_prepare_individual_job_posting_v1_1.sql`
8. `20261108071633_tighten_job_message_insert_privileges.sql`
9. `20261108072503_revoke_unneeded_admin_users_table_privileges.sql`

The two additional applied-ledger entries without text matches but with later repository counterparts are documented in the semantic reconciliation report: `20261108123633_close_and_archive_filled_jobs` and `20261108123757_remove_duplicate_individual_application_select_policy`. Their exact captured SQL remains in the source artifact; the current repository contains related later/consolidated implementations. They are not duplicated here to avoid implying that the repository counterpart is the exact historical text.

## Integrity

Each archived file's SHA-256 is recorded in `manifest.sha256`. The hashes are calculated from the exact recovered SQL bytes. No SQL normalization or rewriting is performed in these files.

## Dependencies and limitations

- The archive depends on the recovered 2026-11-04 manual bootstrap and, for CV ownership logic, the pre-ledger CV prerequisites documented elsewhere under `docs/audits`.
- The migration ledger preserves version identifiers and SQL text, but not original transaction boundaries or a complete execution transcript.
- Presence in this archive confirms historical ledger text, not that the same SQL is safe to replay on any database.
