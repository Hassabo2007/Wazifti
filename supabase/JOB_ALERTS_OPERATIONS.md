# Wazifti job-alert worker operations

## Required per-project Vault secrets

Provision these secrets in each Supabase project before applying the scheduler migration:

- `project_url`: the project's HTTPS URL.
- `publishable_key`: the project's active publishable API key.
- `wazifti_job_alert_cron_token`: a cryptographically random, server-only token.
- `wazifti_vapid_public_key`: VAPID public key used by the browser.
- `wazifti_vapid_private_key`: matching VAPID private key; never commit or expose it.
- `wazifti_vapid_subject`: a valid HTTPS URL or mailto subject.

The `WAZIFTI_VAPID_PUBLIC_KEY` constant in `index.html` must match the public key stored in Vault. Never put the private key or cron token in frontend code.

## Deploy the worker

Deploy `supabase/functions/process-job-alerts/index.ts` as the `process-job-alerts` Edge Function with JWT verification disabled only because the function performs its own authorization: scheduled requests must present the Vault-backed cron token, and browser-triggered requests must be authenticated admins.

## Scheduling

The `job_alerts_daily_digest_scheduler` migration creates two minute-level jobs:

- `wazifti-job-alerts-db-worker`: processes the outbox and due Africa/Khartoum daily in-app digests.
- `wazifti-job-alerts-push-worker`: invokes the Edge Function to deliver queued browser push notifications.

The daily digest is idempotent per user, local date, and channel. Job notifications are unique per user and job. Check `cron.job_run_details` and `net._http_response` when diagnosing scheduled runs.

## Push subscription changes

After rotating the VAPID keypair, the next attempt to enable browser push checks the saved subscription key and automatically replaces a stale subscription with one using the current public key. The user may need to grant browser notification permission again.
