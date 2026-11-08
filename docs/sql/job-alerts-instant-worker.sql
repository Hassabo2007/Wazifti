-- Wazifti immediate in-app job-alert processor.
-- Apply to the isolated test project first; do not run on production without separate approval.

create or replace function public.process_job_alert_outbox(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_event record;
  v_job public.jobs%rowtype;
  v_pref record;
  v_notification_id uuid;
  v_processed integer := 0;
  v_created integer := 0;
  v_failed integer := 0;
  v_skipped integer := 0;
begin
  for v_event in
    select o.id, o.job_id, o.attempt_count
    from public.job_alert_outbox o
    where o.status = 'pending' and o.available_at <= now()
    order by o.created_at asc
    for update skip locked
    limit least(greatest(coalesce(p_limit, 10), 1), 25)
  loop
    update public.job_alert_outbox
       set status = 'processing', locked_at = now(),
           attempt_count = v_event.attempt_count + 1
     where id = v_event.id;

    begin
      select j.* into v_job from public.jobs j where j.id = v_event.job_id;

      if not found or v_job.status <> 'published' then
        update public.job_alert_outbox
           set status = 'completed', processed_at = now(),
               locked_at = null, last_error = null
         where id = v_event.id;
        v_skipped := v_skipped + 1;
      else
        for v_pref in
          select p.*
          from public.job_alert_preferences p
          where p.is_enabled = true
            and p.delivery_mode in ('instant', 'both')
            and p.in_app_enabled = true
            and (
              not exists (select 1 from public.job_alert_preference_locations pl where pl.preference_id = p.id)
              or exists (select 1 from public.job_alert_preference_locations pl where pl.preference_id = p.id and pl.state = v_job.state)
            )
            and (
              not exists (select 1 from public.job_alert_preference_employment_types pet where pet.preference_id = p.id)
              or exists (select 1 from public.job_alert_preference_employment_types pet where pet.preference_id = p.id and pet.employment_type = v_job.employment_type)
            )
            and (
              (
                exists (select 1 from public.job_alert_preference_categories pc where pc.preference_id = p.id)
                and exists (
                  select 1 from public.job_alert_preference_categories pc
                  where pc.preference_id = p.id and pc.category_id = v_job.category_id
                    and (
                      not exists (
                        select 1
                        from public.job_alert_preference_specialties ps
                        join public.job_specialties js on js.id = ps.specialty_id
                        where ps.preference_id = p.id and js.category_id = pc.category_id
                      )
                      or exists (
                        select 1 from public.job_alert_preference_specialties ps
                        where ps.preference_id = p.id and ps.specialty_id = v_job.specialty_id
                      )
                    )
                )
              )
              or
              (
                not exists (select 1 from public.job_alert_preference_categories pc where pc.preference_id = p.id)
                and (
                  not exists (select 1 from public.job_alert_preference_specialties ps where ps.preference_id = p.id)
                  or exists (select 1 from public.job_alert_preference_specialties ps where ps.preference_id = p.id and ps.specialty_id = v_job.specialty_id)
                )
              )
            )
        loop
          v_notification_id := null;
          insert into public.job_alert_notifications
            (user_id, job_id, job_title_snapshot, job_location_snapshot, available_at)
          values
            (v_pref.user_id, v_job.id, v_job.title,
             coalesce(nullif(btrim(v_job.state), ''), nullif(btrim(v_job.location), '')), now())
          on conflict (user_id, job_id) where job_id is not null do nothing
          returning id into v_notification_id;

          if v_notification_id is not null then
            v_created := v_created + 1;
          else
            select n.id into v_notification_id
            from public.job_alert_notifications n
            where n.user_id = v_pref.user_id and n.job_id = v_job.id
            limit 1;
          end if;

          if v_notification_id is not null then
            insert into public.job_alert_deliveries
              (notification_id, channel, delivery_kind, status, sent_at)
            values (v_notification_id, 'in_app', 'instant', 'sent', now())
            on conflict (notification_id, channel, delivery_kind) do nothing;
          end if;
        end loop;

        update public.job_alert_outbox
           set status = 'completed', processed_at = now(),
               locked_at = null, last_error = null
         where id = v_event.id;
      end if;
      v_processed := v_processed + 1;
    exception when others then
      update public.job_alert_outbox
         set status = case when v_event.attempt_count + 1 >= 5 then 'failed' else 'pending' end,
             available_at = now() + interval '1 minute' * power(2, least(v_event.attempt_count, 5)),
             locked_at = null, last_error = left(sqlerrm, 1000)
       where id = v_event.id;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'processed_events', v_processed,
    'created_notifications', v_created,
    'failed_events', v_failed,
    'skipped_events', v_skipped
  );
end;
$$;

revoke all on function public.process_job_alert_outbox(integer) from public, anon, authenticated;
grant execute on function public.process_job_alert_outbox(integer) to service_role;
