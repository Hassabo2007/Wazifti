-- V1.10 job alerts: preference taxonomy, push delivery queue, and server-only claim RPC.
-- This migration is designed to be additive. It does not modify application-status notifications.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 1 and 2048),
  subscription jsonb not null check (jsonb_typeof(subscription) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists "Users manage their own push subscriptions" on public.push_subscriptions;
create policy "Users manage their own push subscriptions"
  on public.push_subscriptions for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop function if exists public.save_job_alert_preferences(boolean,text,text[],text[],time without time zone);
create or replace function public.save_job_alert_preferences(
  p_is_enabled boolean,
  p_delivery_mode text default 'instant',
  p_locations text[] default array[]::text[],
  p_employment_types text[] default array[]::text[],
  p_daily_send_time time without time zone default '08:00',
  p_categories uuid[] default array[]::uuid[],
  p_specialties uuid[] default array[]::uuid[],
  p_push_enabled boolean default false
) returns uuid
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_preference_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_delivery_mode not in ('instant','daily','both') then
    raise exception 'Invalid delivery mode' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_categories),0) > 100 or coalesce(cardinality(p_specialties),0) > 200 then
    raise exception 'Too many category or specialty filters' using errcode = '22023';
  end if;
  if coalesce(p_push_enabled,false) and not exists (
    select 1 from public.push_subscriptions s where s.user_id = v_user_id
  ) then
    raise exception 'Enable browser push notifications on this device first' using errcode = '22023';
  end if;

  insert into public.job_alert_preferences
    (user_id,is_enabled,delivery_mode,in_app_enabled,push_enabled,daily_send_time,timezone)
  values
    (v_user_id,coalesce(p_is_enabled,false),p_delivery_mode,true,coalesce(p_push_enabled,false),
     coalesce(p_daily_send_time,'08:00'::time),'Africa/Khartoum')
  on conflict (user_id) do update set
    is_enabled=excluded.is_enabled,
    delivery_mode=excluded.delivery_mode,
    in_app_enabled=true,
    push_enabled=excluded.push_enabled,
    daily_send_time=excluded.daily_send_time,
    timezone='Africa/Khartoum',
    updated_at=now()
  returning id into v_preference_id;

  delete from public.job_alert_preference_categories where preference_id=v_preference_id;
  insert into public.job_alert_preference_categories(preference_id,category_id)
  select v_preference_id,x from unnest(coalesce(p_categories,array[]::uuid[])) x
  on conflict do nothing;

  delete from public.job_alert_preference_specialties where preference_id=v_preference_id;
  insert into public.job_alert_preference_specialties(preference_id,specialty_id)
  select v_preference_id,x from unnest(coalesce(p_specialties,array[]::uuid[])) x
  on conflict do nothing;

  delete from public.job_alert_preference_locations where preference_id=v_preference_id;
  insert into public.job_alert_preference_locations(preference_id,state)
  select v_preference_id,btrim(x) from unnest(coalesce(p_locations,array[]::text[])) x
  where btrim(x) <> '' on conflict do nothing;

  delete from public.job_alert_preference_employment_types where preference_id=v_preference_id;
  insert into public.job_alert_preference_employment_types(preference_id,employment_type)
  select v_preference_id,x from unnest(coalesce(p_employment_types,array[]::text[])) x
  where x in ('full_time','part_time','remote','contract','temporary','internship')
  on conflict do nothing;

  return v_preference_id;
end;
$$;
revoke all on function public.save_job_alert_preferences(boolean,text,text[],text[],time without time zone,uuid[],uuid[],boolean) from public, anon;
grant execute on function public.save_job_alert_preferences(boolean,text,text[],text[],time without time zone,uuid[],uuid[],boolean) to authenticated;

-- Rebuild the processor so it creates inbox records and queues Push independently.
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
  v_push_queued integer := 0;
begin
  for v_event in
    select o.id,o.job_id,o.attempt_count
    from public.job_alert_outbox o
    where o.status='pending' and o.available_at<=now()
    order by o.created_at asc
    for update skip locked
    limit least(greatest(coalesce(p_limit,10),1),25)
  loop
    update public.job_alert_outbox
       set status='processing',locked_at=now(),attempt_count=v_event.attempt_count+1
     where id=v_event.id;
    begin
      select j.* into v_job from public.jobs j where j.id=v_event.job_id;
      if not found or v_job.status <> 'published' then
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
        v_skipped:=v_skipped+1;
      else
        for v_pref in
          select p.*
          from public.job_alert_preferences p
          where p.is_enabled=true
            and p.delivery_mode in ('instant','both')
            and (p.in_app_enabled or p.push_enabled)
            and (not exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id)
              or exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id and pl.state=coalesce(v_job.state,v_job.location)))
            and (not exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id)
              or exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id and pet.employment_type=v_job.employment_type))
            and (
              (exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id)
                and exists(
                  select 1 from public.job_alert_preference_categories pc
                  where pc.preference_id=p.id and pc.category_id=v_job.category_id
                    and (not exists(
                      select 1 from public.job_alert_preference_specialties ps
                      join public.job_specialties js on js.id=ps.specialty_id
                      where ps.preference_id=p.id and js.category_id=pc.category_id
                    ) or exists(
                      select 1 from public.job_alert_preference_specialties ps
                      where ps.preference_id=p.id and ps.specialty_id=v_job.specialty_id
                    ))
                ))
              or (not exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id)
                and (not exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id)
                  or exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id and ps.specialty_id=v_job.specialty_id)))
            )
        loop
          v_notification_id:=null;
          insert into public.job_alert_notifications(user_id,job_id,job_title_snapshot,job_location_snapshot,available_at)
          values(v_pref.user_id,v_job.id,v_job.title,
            coalesce(nullif(btrim(v_job.state),''),nullif(btrim(v_job.location),'')),now())
          on conflict (user_id,job_id) where job_id is not null do nothing
          returning id into v_notification_id;

          if v_notification_id is not null then
            v_created:=v_created+1;
          else
            select n.id into v_notification_id from public.job_alert_notifications n
            where n.user_id=v_pref.user_id and n.job_id=v_job.id limit 1;
          end if;

          if v_notification_id is not null and v_pref.in_app_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status,sent_at)
            values(v_notification_id,'in_app','instant','sent',now())
            on conflict(notification_id,channel,delivery_kind) do nothing;
          end if;
          if v_notification_id is not null and v_pref.push_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status)
            values(v_notification_id,'push','instant','pending')
            on conflict(notification_id,channel,delivery_kind) do nothing;
            v_push_queued:=v_push_queued+1;
          end if;
        end loop;
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
      end if;
      v_processed:=v_processed+1;
    exception when others then
      update public.job_alert_outbox
      set status=case when v_event.attempt_count+1>=5 then 'failed' else 'pending' end,
          available_at=now()+interval '1 minute'*power(2,least(v_event.attempt_count,5)),
          locked_at=null,last_error=left(sqlerrm,1000)
      where id=v_event.id;
      v_failed:=v_failed+1;
    end;
  end loop;
  return jsonb_build_object('processed_events',v_processed,'created_notifications',v_created,
    'failed_events',v_failed,'skipped_events',v_skipped,'push_deliveries_queued',v_push_queued);
end;
$$;
revoke all on function public.process_job_alert_outbox(integer) from public, anon, authenticated;
grant execute on function public.process_job_alert_outbox(integer) to service_role;

-- Atomically claim pending Push deliveries; browser clients cannot execute this function.
create or replace function public.claim_job_alert_push_deliveries(p_limit integer default 20)
returns table(delivery_id uuid,notification_id uuid,user_id uuid,job_title text,job_location text,job_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  return query
  with picked as (
    select d.id
    from public.job_alert_deliveries d
    where d.channel='push' and d.delivery_kind='instant' and d.status='pending'
    order by d.created_at
    for update skip locked
    limit least(greatest(coalesce(p_limit,20),1),50)
  ), claimed as (
    update public.job_alert_deliveries d
    set status='processing',attempt_count=d.attempt_count+1,last_error=null
    from picked p where d.id=p.id
    returning d.id,d.notification_id
  )
  select c.id,n.id,n.user_id,n.job_title_snapshot,n.job_location_snapshot,n.job_id
  from claimed c join public.job_alert_notifications n on n.id=c.notification_id;
end;
$$;
revoke all on function public.claim_job_alert_push_deliveries(integer) from public, anon, authenticated;
grant execute on function public.claim_job_alert_push_deliveries(integer) to service_role;
