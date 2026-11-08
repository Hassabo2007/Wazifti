-- Save the signed-in user's job-alert preferences atomically.
-- Apply only to the isolated job-alerts test project until separately approved for production.

create or replace function public.save_job_alert_preferences(
  p_is_enabled boolean,
  p_delivery_mode text,
  p_locations text[] default array[]::text[],
  p_employment_types text[] default array[]::text[],
  p_daily_send_time time default '08:00'
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_preference_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if p_delivery_mode not in ('instant', 'daily', 'both') then
    raise exception 'Invalid delivery mode' using errcode = '22023';
  end if;

  insert into public.job_alert_preferences
    (user_id, is_enabled, delivery_mode, in_app_enabled, push_enabled, daily_send_time, timezone)
  values
    (v_user_id, coalesce(p_is_enabled, false), p_delivery_mode, true, false,
     coalesce(p_daily_send_time, '08:00'::time), 'Africa/Khartoum')
  on conflict (user_id) do update
    set is_enabled = excluded.is_enabled,
        delivery_mode = excluded.delivery_mode,
        in_app_enabled = true,
        push_enabled = false,
        daily_send_time = excluded.daily_send_time,
        timezone = 'Africa/Khartoum',
        updated_at = now()
  returning id into v_preference_id;

  delete from public.job_alert_preference_locations
  where preference_id = v_preference_id;

  insert into public.job_alert_preference_locations(preference_id, state)
  select v_preference_id, btrim(value)
  from unnest(coalesce(p_locations, array[]::text[])) as value
  where btrim(value) <> ''
  on conflict do nothing;

  delete from public.job_alert_preference_employment_types
  where preference_id = v_preference_id;

  insert into public.job_alert_preference_employment_types(preference_id, employment_type)
  select v_preference_id, value
  from unnest(coalesce(p_employment_types, array[]::text[])) as value
  where value in ('full_time','part_time','remote','contract','temporary','internship')
  on conflict do nothing;

  return v_preference_id;
end;
$$;

revoke all on function public.save_job_alert_preferences(boolean,text,text[],text[],time) from public, anon;
grant execute on function public.save_job_alert_preferences(boolean,text,text[],text[],time) to authenticated;

comment on function public.save_job_alert_preferences(boolean,text,text[],text[],time) is
  'Atomically saves the signed-in user job-alert settings in the isolated test project.';
