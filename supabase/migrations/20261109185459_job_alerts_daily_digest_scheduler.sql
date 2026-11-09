-- Job-alert scheduling and daily in-app digest processing.
-- Additive only. Provision the required per-project Vault secrets before applying; this migration creates the cron schedules.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.process_job_alert_daily_digests(p_limit integer default 25)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_pref record;
  v_job record;
  v_run_id uuid;
  v_batch_id uuid;
  v_notification_id uuid;
  v_local_now timestamp;
  v_local_date date;
  v_count integer;
  v_users integer := 0;
  v_jobs integer := 0;
  v_skipped integer := 0;
begin
  for v_pref in
    select p.*
    from public.job_alert_preferences p
    where p.is_enabled = true
      and p.delivery_mode in ('daily','both')
      and p.in_app_enabled = true
      and date_trunc('minute', now() at time zone coalesce(nullif(p.timezone,''),'Africa/Khartoum'))::time
          = date_trunc('minute', p.daily_send_time)::time
    order by p.updated_at desc
    limit least(greatest(coalesce(p_limit,25),1),100)
  loop
    v_local_now := now() at time zone coalesce(nullif(v_pref.timezone,''),'Africa/Khartoum');
    v_local_date := v_local_now::date;
    v_run_id := null;
    v_batch_id := gen_random_uuid();
    insert into public.job_alert_digest_runs(user_id,digest_date,channel,batch_id,status)
    values(v_pref.user_id,v_local_date,'in_app',v_batch_id,'processing')
    on conflict(user_id,digest_date,channel) do nothing
    returning id,batch_id into v_run_id,v_batch_id;

    if v_run_id is null then continue; end if;
    v_users := v_users + 1;
    v_count := 0;

    for v_job in
      select j.id,j.title,j.state,j.location
      from public.jobs j
      where j.status='published'
        and j.created_at >= now() - interval '24 hours'
        and (not exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=v_pref.id and pl.state=coalesce(j.state,j.location)))
        and (not exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=v_pref.id and pet.employment_type=j.employment_type))
        and (not exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=v_pref.id and pc.category_id=j.category_id))
        and (not exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=v_pref.id)
          or exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=v_pref.id and ps.specialty_id=j.specialty_id))
      order by j.created_at desc
      limit 100
    loop
      v_notification_id := null;
      insert into public.job_alert_notifications(user_id,job_id,job_title_snapshot,job_location_snapshot,available_at)
      values(v_pref.user_id,v_job.id,v_job.title,coalesce(nullif(btrim(v_job.state),''),nullif(btrim(v_job.location),'')),now())
      on conflict(user_id,job_id) where job_id is not null do nothing
      returning id into v_notification_id;

      if v_notification_id is null then
        select n.id into v_notification_id from public.job_alert_notifications n
        where n.user_id=v_pref.user_id and n.job_id=v_job.id limit 1;
      end if;

      if v_notification_id is not null then
        insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,batch_id,status,sent_at)
        values(v_notification_id,'in_app','daily_digest',v_batch_id,'sent',now())
        on conflict(notification_id,channel,delivery_kind) do nothing;
        v_count := v_count + 1;
      end if;
    end loop;

    if v_count > 0 then
      update public.job_alert_digest_runs set status='sent',sent_at=now(),last_error=null where id=v_run_id;
      v_jobs := v_jobs + v_count;
    else
      update public.job_alert_digest_runs set status='skipped',sent_at=null,last_error='No matching jobs in the last 24 hours' where id=v_run_id;
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object('digest_users_processed',v_users,'matching_jobs_added',v_jobs,'empty_digests_skipped',v_skipped);
end;
$$;

revoke all on function public.process_job_alert_daily_digests(integer) from public,anon,authenticated;
grant execute on function public.process_job_alert_daily_digests(integer) to service_role;

create or replace function public.run_job_alerts_db_worker()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_instant jsonb;
  v_daily jsonb;
begin
  v_instant := public.process_job_alert_outbox(20);
  v_daily := public.process_job_alert_daily_digests(50);
  return jsonb_build_object('instant',v_instant,'daily',v_daily,'ran_at',now());
end;
$$;
revoke all on function public.run_job_alerts_db_worker() from public,anon,authenticated;
grant execute on function public.run_job_alerts_db_worker() to service_role;

create or replace function public.verify_job_alert_cron_token(p_token text)
returns boolean
language sql
security definer
set search_path = pg_catalog, vault
as $$
  select coalesce(bool_or(decrypted_secret = p_token),false)
  from vault.decrypted_secrets
  where name = 'wazifti_job_alert_cron_token'
    and p_token is not null
$$;
revoke all on function public.verify_job_alert_cron_token(text) from public,anon,authenticated;
grant execute on function public.verify_job_alert_cron_token(text) to service_role;


-- Per-project Vault values must be provisioned before applying this migration:
-- project_url, publishable_key, and wazifti_job_alert_cron_token.
do $$
begin
  if not exists (select 1 from vault.secrets where name='project_url')
     or not exists (select 1 from vault.secrets where name='publishable_key')
     or not exists (select 1 from vault.secrets where name='wazifti_job_alert_cron_token') then
    raise exception 'Missing Vault secrets required for Wazifti job-alert scheduling';
  end if;
end;
$$;

-- Database worker handles instant in-app alerts and due daily digests.
select cron.schedule(
  'wazifti-job-alerts-db-worker',
  '* * * * *',
  'select public.run_job_alerts_db_worker();'
);

-- Push worker uses a Vault token; the Edge Function verifies it against Vault.
select cron.schedule(
  'wazifti-job-alerts-push-worker',
  '* * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name='project_url') || '/functions/v1/process-job-alerts',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'apikey',(select decrypted_secret from vault.decrypted_secrets where name='publishable_key'),
        'x-wazifti-cron-token',(select decrypted_secret from vault.decrypted_secrets where name='wazifti_job_alert_cron_token')
      ),
      body := jsonb_build_object('limit',10),
      timeout_milliseconds := 15000
    );
  $job$
);
