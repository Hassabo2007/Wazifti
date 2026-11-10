# Wazifti — Supabase migration-history reconciliation

**Snapshot date:** 2026-11-10  
**Production project:** `zaucmxoxgpmipizzhbqs`  
**Repository:** `Hassabo2007/Wazifti`  
**Method:** read-only Supabase SQL/catalog inspection; no production writes.

## Captured evidence

- `supabase-production-migration-ledger-2026-11-10.json`: complete 26-entry `supabase_migrations.schema_migrations` snapshot, including the SQL statements recorded by Supabase for each applied version.
- `recovered-production-migration-history-2026-11-10.sql`: a readable forensic archive of all 26 applied SQL entries, kept under `docs/audits` so Supabase CLI will not treat it as pending migrations. It is explicitly marked DO NOT RUN.
- `supabase-production-schema-snapshot-2026-11-10.json`: captured table/column metadata, public RLS policies, indexes, and constraints.
- A separate runtime catalog snapshot is included for views, functions, triggers, extensions, enum types, grants, and publications. It remains a point-in-time metadata export, not a restorable database dump.

## Findings

- Production records **26 applied migrations**.
- The current repository branch contains **21 SQL files** in `supabase/migrations`.
- The free CI content audit found **7 exact SQL-content matches** between repository files and production history: 3 with matching timestamps and 4 with filename timestamp drift. The other **19 applied ledger entries have no exact matching repository file**.
- The current repository also contains 14 files without an exact applied-ledger match. Some are the intended unapplied V1.15 migration; others include the daily-digest, VAPID, and close/archive files whose content differs from production. They require semantic diffing, not automatic replacement.
- The repository contains job-alert migration files whose exact SQL is not represented as a separate applied production ledger entry. They may be consolidated into the later complete job-alert migration, but that must be proven by content/DDL comparison before removing or retaining them as runnable migrations.
- A live read-only comparison on 2026-11-10 found **22 public tables** in both the saved schema snapshot and current Supabase catalog, with no differences in column names, data types, defaults, or nullability.
- V1.15 remains a proposed, unapplied migration. This reconciliation work does not apply it.

## Changes made in this branch

1. Preserve the production migration ledger exactly as captured, including the SQL text Supabase says it executed.
2. Preserve the current production catalog metadata snapshot as a comparison baseline.
3. Add a free GitHub Actions audit that compares repository migration file contents against the captured production ledger. It uses GitHub-hosted runners only; it does not create a Supabase branch or incur Supabase compute charges.
4. Add `scripts/export_recovered_migrations.py`, which exports all 26 ledger SQL entries to a temporary CI artifact outside `supabase/migrations`, with SHA-256 hashes and explicit classifications. The artifact is retained for 14 days and marked forensic-only / DO NOT RUN.

## Safety decisions

- No Supabase migration-history rows were inserted, deleted, renamed, or repaired.
- No production DDL, RLS policies, indexes, functions, triggers, or data were changed.
- Do not run `supabase db push` while this drift exists: local files that are not represented remotely may be treated as pending, while missing or differently named historical files can make a blind repair unsafe.
- Do not mark historical migrations as applied merely to make the counts match.
- Do not replay the captured historical SQL on production.

## What remains before a full compatibility sign-off

The exact comparison must be used to reconstruct an authoritative historical file set, with separate treatment for:
- applied SQL that is missing from the repository;
- files whose content matches production but whose filename timestamp differs;
- files whose content differs from the production-applied SQL;
- repository-only files that are either genuinely pending or already consolidated into a later applied migration;
- the intentionally pending V1.15 migration.

Then compare the captured catalog against a clean, free PostgreSQL 17 baseline. The 26-entry production ledger begins on 2026-11-06, after the application's base tables already existed; therefore these 26 migrations alone are not a complete from-empty bootstrap history. A true replay requires a verified pre-2026-11-06 baseline (or the original initial schema migrations) plus the Supabase-managed prerequisites. A current-state `pg_dump --schema-only` would help preserve the present schema, but cannot substitute for that pre-migration baseline. The existing V1.15 fixture is a focused schema-faithful test slice, not a full Supabase clone.

**Current result: historical evidence is preserved and automated drift detection is in place; the migration history is not yet repaired, and full schema compatibility is not yet certified.**


## Newly recovered bootstrap provenance

Project history confirms that the first production schema was created manually in the Supabase SQL Editor before tracked migrations began. The initial manually-created tables were `profiles`, `companies`, `jobs`, and `applications`; a follow-up query created `handle_new_user()`, its `auth.users` trigger, and initial RLS policies. The SQL Editor queries were described as saved under `Wazifti - Initial Database Schema` and `Wazifti - Security Policies`, but neither exact query was found in the currently accessible project files/library.

A generated reference file `wazifti_mvp_database_schema.sql` was found in the file library. It is a proposal, not proof of what was executed; it contains additional tables and a wider profile schema than the contemporaneous initial profile inspection. It is therefore explicitly excluded as an authoritative bootstrap. See [initial manual bootstrap provenance](initial-manual-bootstrap-provenance-2026-11-10.md).

**Consequence:** a true historical replay from empty PostgreSQL is still blocked on recovering the exact manual SQL Editor queries (or an authoritative pre-2026-11-06 schema-only export). No guessed baseline migration will be added to the active migration directory.
