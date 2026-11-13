## Change summary
<!-- What changes and why? -->

## Database impact
- [ ] No database/schema/security change
- [ ] Adds/changes tables, columns, indexes, constraints, triggers, functions, views, grants, RLS, or Storage policies
- [ ] Includes data backfill

## Migration safety checklist (required when database impact is selected)
- [ ] New migration created with `supabase migration new`; unique version; forward-only
- [ ] Compared with current production schema and migration ledger
- [ ] Does not replay or copy files from the historical archive
- [ ] RLS, grants, ownership predicates, and Storage access reviewed
- [ ] Destructive/privilege-changing operations explicitly justified and independently reviewed
- [ ] Fresh install and production-shaped upgrade tests completed, or limitations documented
- [ ] Backfill, verification queries, and rollback/forward-fix plan documented
- [ ] Advisors and application tests reviewed
- [ ] Production deployment steps and post-deploy verification documented

## Evidence
<!-- Link CI runs, SQL review, test output, schema diff, and audit notes. -->

## Risk and recovery
- Risk level: low / medium / high
- Recovery or forward-fix plan:
- Data backup/restore readiness (if applicable):
