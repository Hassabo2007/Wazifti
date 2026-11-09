-- Expose VAPID configuration only to the server-side job-alert worker.
-- The private key is read from Vault and must never be accessible to browser roles.

create or replace function public.get_job_alert_vapid_config()
returns jsonb
language sql
security definer
set search_path = pg_catalog, vault
as $$
  select jsonb_build_object(
    'public_key', max(decrypted_secret) filter (where name='wazifti_vapid_public_key'),
    'private_key', max(decrypted_secret) filter (where name='wazifti_vapid_private_key'),
    'subject', max(decrypted_secret) filter (where name='wazifti_vapid_subject')
  )
  from vault.decrypted_secrets
  where name in ('wazifti_vapid_public_key','wazifti_vapid_private_key','wazifti_vapid_subject')
$$;

revoke all on function public.get_job_alert_vapid_config() from public, anon, authenticated;
grant execute on function public.get_job_alert_vapid_config() to service_role;
