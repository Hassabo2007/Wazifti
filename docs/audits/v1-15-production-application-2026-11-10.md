# V1.15 production application and migration-version verification

**Date:** 2026-11-10  
**Production Supabase project:** `zaucmxoxgpmipizzhbqs`  
**Historical audit baseline:** migration-history snapshot captured earlier on 2026-11-10 (26 applied entries).

## Production application

The V1.15 migration source from `supabase/migrations/20261110100000_v1_15_security_performance_hygiene.sql` was applied through the Supabase migration API as `v1_15_security_performance_hygiene`.

Supabase recorded the actual applied version as:

- Version: `20261110173838`
- Name: `v1_15_security_performance_hygiene`

The production ledger therefore contains 27 entries after this operation. The original historical snapshot remains preserved unchanged at 26 entries; it is a point-in-time record from before V1.15 and must not be overwritten.

## Post-application verification

Read-only catalog checks confirmed all five indexes now exist:

- `in_app_notifications_application_id_idx`
- `job_messages_application_id_idx`
- `job_messages_candidate_id_idx`
- `job_messages_poster_id_idx`
- `job_messages_sender_id_idx`

The three existing `job_messages` policies remain present:

- `Conversation participants read messages` (SELECT, authenticated)
- `Conversation participants send messages` (INSERT, authenticated)
- `Recipients mark own messages read` (UPDATE, authenticated)

The SELECT and INSERT predicates retain the same candidate/poster, sender/recipient, application/job, and actual-poster ownership checks. The SELECT and INSERT policies now wrap `auth.uid()` in scalar subqueries, addressing the two corresponding Auth RLS initialization-plan findings. The UPDATE policy was left unchanged.

The performance advisor no longer reports the five missing foreign-key indexes or the two `auth_rls_initplan` findings for `job_messages`. Other pre-existing findings (unused indexes, multiple permissive policies, and a duplicate index on `applications`) remain outside V1.15 scope and were not modified.

## Repository synchronization

The initial migration filename used timestamp `20261110100000`, while the Supabase migration API recorded the actual execution version `20261110173838`. To keep the repository migration filename aligned with the authoritative production ledger, the source file is renamed to:

`supabase/migrations/20261110173838_v1_15_security_performance_hygiene.sql`

The SQL content is unchanged. The prior filename is removed from the active migration directory so a future migration listing/push does not treat the already-applied migration as pending.

## Safety

- V1.15 creates five indexes and replaces two RLS policies with semantically equivalent, more efficient predicates.
- No application rows, user data, auth users, or storage objects were modified.
- No historical ledger rows were inserted, edited, or deleted.
- The nine archived historical migrations remain outside `supabase/migrations` and must never be replayed.
- The two catalog-confirmed unledgered changes remain documented as execution-provenance unresolved; V1.15 does not claim to resolve their historical origin.
- The free GitHub Actions PostgreSQL 17 tests are compatibility checks, not a full Supabase service clone.
