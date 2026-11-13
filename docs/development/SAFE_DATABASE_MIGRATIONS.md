# Safe Supabase migration policy — Wazifti

**Status:** required engineering procedure for every future schema/security change.
**Production rule:** no direct SQL edits and no `supabase db push` to production outside an explicitly reviewed release procedure.

## 1. Before writing a migration

1. Start from an up-to-date `main` and create a feature branch.
2. Inspect the live schema, migration ledger, existing policies, indexes, triggers, functions, grants, and Storage policies relevant to the change.
3. Record the intended change, affected objects, expected user-visible effect, rollback/forward-fix plan, and whether existing data needs backfill.
4. Never reconstruct a historical migration from memory. Recovered SQL belongs only in `docs/audits/production-ledger-archive/` and must never be copied into `supabase/migrations/`.

## 2. Authoring rules

- Create new files using `supabase migration new <descriptive_name>`; do not invent timestamps.
- Migrations are forward-only, uniquely versioned, narrowly scoped, and safe to run once in order.
- Prefer additive changes first: add nullable columns/tables/indexes, deploy compatible application code, backfill in bounded batches, then enforce constraints in a later migration.
- Make operations idempotent where practical, but do not use `IF NOT EXISTS` to conceal schema drift.
- Do not drop/rename columns, tables, indexes, constraints, or policies in the same release that stops using them. Use expand → migrate → contract.
- Never disable RLS as a workaround. Every exposed table must have RLS enabled and policies must enforce row ownership/authorization, not merely `TO authenticated`.
- UPDATE policies need both `USING` and `WITH CHECK`. Avoid authorization based on user-editable `user_metadata`.
- Review views for RLS bypass; use `security_invoker = true` where supported and appropriate.
- Review SECURITY DEFINER functions as privileged API surfaces: explicit authorization, fixed safe search_path, minimal grants, and no unintended PUBLIC execution.
- Never put service-role/secret keys in client code or committed files.

## 3. Required pre-merge validation

For each migration PR, attach evidence for all applicable checks:

- [ ] SQL reviewed against the current production schema and ledger; no historical migration replay.
- [ ] Fresh-database application test using a free local PostgreSQL/Supabase-compatible workflow where feasible.
- [ ] Upgrade-path test against a schema snapshot or sanitized copy representing current production; do not use a paid Supabase branch.
- [ ] RLS and grants reviewed for every affected table/view/function/Storage object.
- [ ] Data backfill is bounded, resumable, and checked for row counts / nulls / duplicates.
- [ ] Rollback or forward-fix procedure documented; destructive changes have a recovery plan.
- [ ] Supabase advisors (or equivalent SQL checks) reviewed; findings documented.
- [ ] Application tests and preview checks pass.
- [ ] Migration ledger and schema diff reviewed after deployment.

A migration must not be merged merely because SQL parses. If a production-shaped upgrade test is unavailable, mark the limitation clearly and do not claim full validation.

## 4. Production release protocol

1. Merge through a reviewed PR only after all required checks pass.
2. Take/verify a recoverable backup or export appropriate to the change and confirm restore access before risky changes.
3. Confirm the exact pending migration list against the production ledger. Stop if any version is already applied, missing, out of order, or differs from the repository.
4. Apply only the reviewed pending migration(s), never a blind full replay or historical archive.
5. Immediately verify schema, RLS, grants, indexes, functions, and application smoke tests.
6. Record deployed migration versions, commit SHA, operator, timestamp, validation evidence, and any deviations in the deployment audit log.

## 5. Stop conditions

Stop deployment and investigate if:
- repository and production migration histories differ;
- a migration would re-run an already-applied version;
- the SQL includes unreviewed DROP/TRUNCATE, broad DELETE/UPDATE, RLS disablement, privilege broadening, or SECURITY DEFINER changes;
- the live schema differs from the reviewed baseline;
- backup/restore readiness for a high-risk change is unknown;
- a check fails or the expected result cannot be verified.

## 6. Wazifti-specific historical safeguards

The recovered SQL archive under `docs/audits/production-ledger-archive/2026-11-10/` is forensic evidence only. The two production-only changes documented in the reconciliation report have uncertain original provenance. Preserve that uncertainty; do not invent dates or re-run the SQL to make repository history appear complete.

The production migration ledger currently includes V1.15 version `20261110173838`. Treat it as applied; do not recreate or replay it.

## 7. Branch protection

Configure GitHub repository rules for `main`:
- require pull requests before merging;
- require the migration-safety and application CI checks;
- require branch to be up to date before merge;
- block force pushes and branch deletion;
- disallow direct pushes/bypasses except an explicitly documented emergency process.

If GitHub plan/permissions do not expose these settings, keep the PR-only process and document that enforcement is administrative rather than technically locked.
