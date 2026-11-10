# Provenance note — catalog-present changes absent from the production migration ledger

**Date:** 2026-11-10  
**Production project:** Wazifti Supabase project `zaucmxoxgpmipizzhbqs`  
**Method:** read-only catalog and migration-ledger queries. No DDL, DML, policy changes, or migration-history edits were performed.

## Summary

Two effects exist in the current production catalog but do not have corresponding version entries among the 26 captured rows in `supabase_migrations.schema_migrations`. Their current definitions can be confirmed, and repository files contain SQL that reproduces those definitions. However, the evidence does **not** establish when, by whom, or through which execution path those SQL statements were applied.

They must therefore be described as **catalog-confirmed, execution provenance unresolved** — not as ledger-applied migrations.

## 1. Notification status constraint accepts `message`

### Current production evidence

Read-only query of `pg_constraint` for `public.in_app_notifications` returned:

```sql
CHECK ((new_status = ANY (ARRAY[
  'submitted'::text,
  'reviewing'::text,
  'shortlisted'::text,
  'rejected'::text,
  'accepted'::text,
  'message'::text
])))
```

Constraint name: `in_app_notifications_new_status_check`.

### Candidate repository SQL

`supabase/migrations/20261108110000_allow_message_notification_status.sql` drops and recreates this named constraint with the six allowed values above. Its semantic effect matches the live catalog definition.

### Ledger comparison

The captured production ledger has no version `20261108110000`, and none of the 26 recorded migration SQL texts matches this operation. The earlier applied notification migration `20261107200249` creates the original check with only the five application statuses. The later applied complete job-alert migration explicitly leaves `in_app_notifications` untouched.

### Finding

The current constraint is confirmed. The repository file is a strong candidate source of the change, but the ledger cannot prove it was applied via Supabase migration tooling. It may have been run manually, applied through another unrecorded path, or the catalog state may have been produced by a later untracked operation. The available evidence cannot distinguish these possibilities.

**Disposition:** keep the SQL file as an unledgered provenance candidate; do not move it into the historical applied archive or run it again.

## 2. Individual job posters can view profiles of applicants to their own jobs

### Current production evidence

Read-only query of `pg_policies` returned policy:

- Table: `public.profiles`
- Name: `Individual job posters view applicant profiles`
- Command: `SELECT`
- Role: `authenticated`
- Predicate: profile ID belongs to an application whose job is `poster_type = 'individual'` and whose `posted_by_user_id = (select auth.uid())`.

This is a narrow, ownership-scoped policy. It does not grant individual posters unrestricted profile access.

### Candidate repository SQL

`supabase/migrations/20261108120000_individual_posters_view_applicant_profiles.sql` drops and recreates this exact named policy using the same application/job ownership predicate. Its semantics match the live policy.

### Ledger comparison

No version `20261108120000` exists in the captured 26-entry production ledger, and no recorded ledger SQL contains this policy definition. The applied individual-posting migration `20261107210157` creates job poster columns and job policies, but does not create this profile SELECT policy.

### Finding

The policy is confirmed in production, and the repository file is a strong candidate source. Its execution time and execution channel are not established by the available ledger/catalog evidence. It may have been applied manually or through an unrecorded workflow.

**Disposition:** retain the file as an unledgered provenance candidate; do not classify it as a recorded applied migration and do not re-run it.

## Evidence limits

- The migration ledger is not a complete audit log of every possible SQL Editor action or direct database operation.
- Current catalog state proves what exists now, not the original actor, timestamp, or delivery mechanism.
- No attempt was made to infer provenance from object creation timestamps, which are not reliably available for these PostgreSQL catalog objects.
- No ledger rows were inserted to make the two changes appear migration-managed.

## Safe future handling

If historical execution evidence is later found (SQL Editor history, deployment logs, or a dated backup), append it here with source and timestamp. Until then, keep both SQL files outside any claim of ledger-applied history. If future schema work needs to change either object, create a new forward-only migration after reviewing the current production definition; do not replay these candidate files as historical migrations.


## CI integrity safeguard

The audit workflow now verifies the SHA-256 manifest for the recovered SQL archive on pushes and pull requests that touch the archive or its audit documentation. This check validates byte-for-byte integrity only; it does not execute the archived SQL.
