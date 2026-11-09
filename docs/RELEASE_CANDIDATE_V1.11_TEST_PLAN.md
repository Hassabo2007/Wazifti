# Wazifti V1.11 Release Candidate — Test Plan

## Environment isolation
- Git branch: `release/v1.11-rc-test`
- Supabase project: `igkemvtpfumbixajfrjr` (test only)
- Vercel deployment target: Preview only
- Do not merge this branch or deploy it to Production.
- Do not apply the daily-digest migration to Production as part of this test.
- Test project secrets and VAPID private key remain in Supabase/Vercel secret stores; never commit them.

## Pre-flight checks
- [ ] Confirm the preview is connected to the test Supabase project.
- [ ] Confirm the browser bundle contains only the test project URL, test publishable key, and test VAPID public key.
- [ ] Confirm no service-role key, cron token, VAPID private key, or Vault secret is present in repository files.
- [ ] Confirm the deployed Edge Function in the test project validates the cron token/admin authorization and has test-only VAPID configuration.

## Employer dashboard
- [ ] Arabic: summary counts show total applicants, submitted, reviewing, and shortlisted.
- [ ] English: same labels and counts are translated correctly.
- [ ] Per-job applicant counts are correct.
- [ ] Search by applicant name narrows the cards and the visible count.
- [ ] Status filter works for every status and combines correctly with name search.
- [ ] Changing an application status updates the card state and filter result.
- [ ] Unauthorized employer cannot open another employer's applicant list or change its status.
- [ ] CV preview/download and applicant messaging remain functional.

## Job alerts
- [ ] Save and reload alert preferences when Push is unsupported or denied; saving must still succeed.
- [ ] Save and reload preferences with Push enabled on a supported browser.
- [ ] Confirm matching published jobs create in-app notifications.
- [ ] Confirm a matching job sends a real Push notification to the subscribed test device.
- [ ] Confirm non-matching category, specialty, location, and employment type do not notify.
- [ ] Confirm daily digest preferences are saved and the test worker processes a due digest only once per user/local date.
- [ ] Confirm English and Arabic alert screens, messages, and controls.

## Database / scheduler checks (test project only)
- [ ] Verify RLS is enabled on all job-alert tables.
- [ ] Verify worker-only RPCs are executable only by service_role.
- [ ] Verify user preference RPC is executable by authenticated users only.
- [ ] Verify cron jobs run successfully in the test project.
- [ ] Verify retry/idempotency behavior and that duplicate digests are not created.
- [ ] Remove QA job records and their notifications/deliveries after testing; preserve user preferences and push subscriptions.

## Release gate
Do not merge PR #21 or PR #22 until all applicable checks above pass, the production migration is reviewed separately, and project-specific Production secrets/schedules are configured intentionally. The daily-digest migration is additive but must not be applied to Production without a separate approved rollout.
