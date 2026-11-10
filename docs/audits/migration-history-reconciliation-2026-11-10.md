# Wazifti — Supabase migration-history reconciliation

**Snapshot date:** 2026-11-10  
**Production project:** `zaucmxoxgpmipizzhbqs`  
**Repository:** `Hassabo2007/Wazifti`  
**Method:** read-only Supabase SQL/catalog inspection; no production writes.

## Captured evidence

- `supabase-production-migration-ledger-2026-11-10.json`: complete 26-entry `supabase_migrations.schema_migrations` snapshot, including the SQL statements recorded by Supabase for each applied version.
- `supabase-production-schema-snapshot-2026-11-10.json`: captured table/column metadata, public RLS policies, indexes, and constraints.
- A separate runtime catalog snapshot is still desirable for views, functions, triggers, extensions, enum types, grants, and publications before claiming full schema equivalence.

## Findings

- Production records **26 applied migrations**.
- The current `main` branch contains **21 SQL files** in `supabase/migrations`.
- Several applied migrations have no corresponding file under the same historical filename/version; some existing files contain SQL matching a production ledger statement but use a different timestamped filename.
- Some current repository files do not exactly match any stored production migration statement. In particular, the current daily-digest and VAPID migration files have content differences from the production ledger entries; the close/archive migration file also differs in length/content from its applied counterpart.
- The repository contains job-alert migration files whose exact SQL is not represented as a separate applied production ledger entry. They may be consolidated into the later complete job-alert migration, but that must be proven by content/DDL comparison before removing or retaining them as runnable migrations.
- V1.15 remains a proposed, unapplied migration. This reconciliation work does not apply it.

## Changes made in this branch

1. Preserve the production migration ledger exactly as captured, including the SQL text Supabase says it executed.
2. Preserve the current production catalog metadata snapshot as a comparison baseline.
3. Add a free GitHub Actions audit that compares repository migration file contents against the captured production ledger. It uses GitHub-hosted runners only; it does not create a Supabase branch or incur Supabase compute charges.

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

Then the full runtime catalog must be captured (views, functions, triggers, extensions, types, grants, publications and relevant RLS metadata), and a clean, free PostgreSQL 17 test database must be built from a verified baseline before replaying the canonical migration sequence. The existing V1.15 fixture is a focused schema-faithful test slice, not a full Supabase clone.

**Current result: historical evidence is preserved and automated drift detection is in place; the migration history is not yet repaired, and full schema compatibility is not yet certified.**
