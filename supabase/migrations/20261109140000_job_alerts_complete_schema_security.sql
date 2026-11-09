-- V1.10: complete job-alert schema, ownership policies, private worker queue, and publish trigger.
-- Additive only: does not modify application-status notifications or existing taxonomy.
-- push_subscriptions already exists in production; it is intentionally not recreated or altered here.

create table if not exists public.job_alert_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  is_enabled boolean not null default false,
  delivery_mode text not null default 'both' check (delivery_mode in ('instant','daily','both')),
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default false,
  daily_send_time time not null default '08:00',
  timezone text not null default 'Africa/Khartoum',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.job_alert_preferences is 'User-owned job alert preferences; billing tiers are intentionally not implemented in V1.';

create table if not exists public.job_alert_preference_categories (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  category_id uuid not null references public.job_categories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (preference_id, category_id)
);
create table if not exists public.job_alert_preference_specialties (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  specialty_id uuid not null references public.job_specialties(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (preference_id, specialty_id)
);
create table if not exists public.job_alert_preference_locations (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  state text not null check (length(btrim(state)) > 0),
  created_at timestamptz not null default now(),
  primary key (preference_id, state)
);
create table if not exists public.job_alert_preference_employment_types (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  employment_type text not null check (employment_type in ('full_time','part_time','remote','contract','temporary','internship')),
  created_at timestamptz not null default now(),
  primary key (preference_id, employment_type)
);

create table if not exists public.job_alert_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  job_id uuid references public.jobs(id) on delete set null,
  job_title_snapshot text not null,
  job_location_snapshot text,
  created_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  read_at timestamptz
);
comment on table public.job_alert_notifications is 'In-app job alert inbox, separate from application-status notifications.';

create table if not exists public.job_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.job_alert_notifications(id) on delete cascade,
  channel text not null check (channel in ('in_app','push')),
  delivery_kind text not null default 'instant' check (delivery_kind in ('instant','daily_digest')),
  batch_id uuid,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (notification_id, channel, delivery_kind)
);
comment on table public.job_alert_deliveries is 'Worker-managed delivery attempts per channel and delivery kind; digest items share a batch id.';

create table if not exists public.job_alert_digest_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  digest_date date not null,
  channel text not null check (channel in ('in_app','push')),
  batch_id uuid not null unique default gen_random_uuid(),
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, digest_date, channel)
);
comment on table public.job_alert_digest_runs is 'Worker-managed per-user, per-local-date digest run; prevents duplicate daily summaries.';

create table if not exists public.job_alert_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type = 'job_published'),
  job_id uuid not null references public.jobs(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','processing','completed','failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (event_type, job_id)
);
comment on table public.job_alert_outbox is 'Worker queue populated when a job first becomes published.';

-- Indexes mirror the verified test schema. Existing taxonomy and push indexes are not recreated.
create index if not exists job_alert_preference_categories_category_idx on public.job_alert_preference_categories(category_id);
create index if not exists job_alert_preference_specialties_specialty_idx on public.job_alert_preference_specialties(specialty_id);
create index if not exists job_alert_preference_locations_state_idx on public.job_alert_preference_locations(state);
create index if not exists job_alert_preference_employment_types_type_idx on public.job_alert_preference_employment_types(employment_type);
create index if not exists job_alert_notifications_job_id_idx on public.job_alert_notifications(job_id);
create index if not exists job_alert_notifications_user_created_idx on public.job_alert_notifications(user_id, available_at, created_at desc);
create unique index if not exists job_alert_notifications_user_job_uidx on public.job_alert_notifications(user_id, job_id) where job_id is not null;
create index if not exists job_alert_deliveries_status_created_idx on public.job_alert_deliveries(status, created_at);
create index if not exists job_alert_deliveries_batch_idx on public.job_alert_deliveries(batch_id) where batch_id is not null;
create index if not exists job_alert_digest_runs_due_idx on public.job_alert_digest_runs(status, digest_date, created_at);
create index if not exists job_alert_outbox_ready_idx on public.job_alert_outbox(status, available_at, created_at);
create index if not exists job_alert_outbox_job_id_idx on public.job_alert_outbox(job_id);

-- All alert tables are protected. Worker-only tables are not accessible to browser roles.
alter table public.job_alert_preferences enable row level security;
alter table public.job_alert_preference_categories enable row level security;
alter table public.job_alert_preference_specialties enable row level security;
alter table public.job_alert_preference_locations enable row level security;
alter table public.job_alert_preference_employment_types enable row level security;
alter table public.job_alert_notifications enable row level security;
alter table public.job_alert_deliveries enable row level security;
alter table public.job_alert_digest_runs enable row level security;
alter table public.job_alert_outbox enable row level security;

drop policy if exists "Users manage own job alert preferences" on public.job_alert_preferences;
create policy "Users manage own job alert preferences" on public.job_alert_preferences
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users read own alert categories" on public.job_alert_preference_categories;
drop policy if exists "Users add own alert categories" on public.job_alert_preference_categories;
drop policy if exists "Users remove own alert categories" on public.job_alert_preference_categories;
create policy "Users read own alert categories" on public.job_alert_preference_categories
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert categories" on public.job_alert_preference_categories
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert categories" on public.job_alert_preference_categories
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert specialties" on public.job_alert_preference_specialties;
drop policy if exists "Users add own alert specialties" on public.job_alert_preference_specialties;
drop policy if exists "Users remove own alert specialties" on public.job_alert_preference_specialties;
create policy "Users read own alert specialties" on public.job_alert_preference_specialties
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert specialties" on public.job_alert_preference_specialties
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert specialties" on public.job_alert_preference_specialties
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert locations" on public.job_alert_preference_locations;
drop policy if exists "Users add own alert locations" on public.job_alert_preference_locations;
drop policy if exists "Users remove own alert locations" on public.job_alert_preference_locations;
create policy "Users read own alert locations" on public.job_alert_preference_locations
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert locations" on public.job_alert_preference_locations
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert locations" on public.job_alert_preference_locations
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own alert employment types" on public.job_alert_preference_employment_types;
drop policy if exists "Users add own alert employment types" on public.job_alert_preference_employment_types;
drop policy if exists "Users remove own alert employment types" on public.job_alert_preference_employment_types;
create policy "Users read own alert employment types" on public.job_alert_preference_employment_types
  for select to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users add own alert employment types" on public.job_alert_preference_employment_types
  for insert to authenticated with check (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));
create policy "Users remove own alert employment types" on public.job_alert_preference_employment_types
  for delete to authenticated using (exists (select 1 from public.job_alert_preferences p where p.id=preference_id and p.user_id=(select auth.uid())));

drop policy if exists "Users read own job alert notifications" on public.job_alert_notifications;
drop policy if exists "Users mark own job alert notifications read" on public.job_alert_notifications;
create policy "Users read own job alert notifications" on public.job_alert_notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users mark own job alert notifications read" on public.job_alert_notifications
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Explicitly close browser access to worker tables, then grant service_role only.
revoke all on table public.job_alert_preferences, public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types, public.job_alert_notifications,
  public.job_alert_deliveries, public.job_alert_digest_runs, public.job_alert_outbox
  from public, anon, authenticated;
grant select, insert, update, delete on public.job_alert_preferences to authenticated;
grant select, insert, delete on public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types to authenticated;
grant select on public.job_alert_notifications to authenticated;
grant update (read_at) on public.job_alert_notifications to authenticated;
grant all on public.job_alert_preferences, public.job_alert_preference_categories,
  public.job_alert_preference_specialties, public.job_alert_preference_locations,
  public.job_alert_preference_employment_types, public.job_alert_notifications,
  public.job_alert_deliveries, public.job_alert_digest_runs, public.job_alert_outbox
  to service_role;

-- User-facing save RPC: invoker rights + auth.uid ownership, no SECURITY DEFINER.
create or replace function public.save_job_alert_preferences(
  p_is_enabled boolean,
  p_delivery_mode text default 'instant',
  p_locations text[] default array[]::text[],
  p_employment_types text[] default array[]::text[],
  p_daily_send_time time default '08:00',
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
  if v_user_id is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if p_delivery_mode not in ('instant','daily','both') then raise exception 'Invalid delivery mode' using errcode = '22023'; end if;
  if coalesce(cardinality(p_locations),0) > 100 or coalesce(cardinality(p_employment_types),0) > 20
     or coalesce(cardinality(p_categories),0) > 100 or coalesce(cardinality(p_specialties),0) > 200 then
    raise exception 'Too many alert filters' using errcode = '22023';
  end if;
  if coalesce(p_push_enabled,false) and not exists (select 1 from public.push_subscriptions s where s.user_id=v_user_id) then
    raise exception 'Enable browser push notifications on this device first' using errcode = '22023';
  end if;
  insert into public.job_alert_preferences(user_id,is_enabled,delivery_mode,in_app_enabled,push_enabled,daily_send_time,timezone)
  values(v_user_id,coalesce(p_is_enabled,false),p_delivery_mode,true,coalesce(p_push_enabled,false),coalesce(p_daily_send_time,'08:00'::time),'Africa/Khartoum')
  on conflict(user_id) do update set is_enabled=excluded.is_enabled,delivery_mode=excluded.delivery_mode,
    in_app_enabled=true,push_enabled=excluded.push_enabled,daily_send_time=excluded.daily_send_time,
    timezone='Africa/Khartoum',updated_at=now()
  returning id into v_preference_id;

  delete from public.job_alert_preference_categories where preference_id=v_preference_id;
  insert into public.job_alert_preference_categories(preference_id,category_id)
    select v_preference_id,x from unnest(coalesce(p_categories,array[]::uuid[])) x on conflict do nothing;
  delete from public.job_alert_preference_specialties where preference_id=v_preference_id;
  insert into public.job_alert_preference_specialties(preference_id,specialty_id)
    select v_preference_id,x from unnest(coalesce(p_specialties,array[]::uuid[])) x on conflict do nothing;
  delete from public.job_alert_preference_locations where preference_id=v_preference_id;
  insert into public.job_alert_preference_locations(preference_id,state)
    select v_preference_id,btrim(x) from unnest(coalesce(p_locations,array[]::text[])) x where btrim(x)<>'' on conflict do nothing;
  delete from public.job_alert_preference_employment_types where preference_id=v_preference_id;
  insert into public.job_alert_preference_employment_types(preference_id,employment_type)
    select v_preference_id,x from unnest(coalesce(p_employment_types,array[]::text[])) x
    where x in ('full_time','part_time','remote','contract','temporary','internship') on conflict do nothing;
  return v_preference_id;
end;
$$;
revoke all on function public.save_job_alert_preferences(boolean,text,text[],text[],time,uuid[],uuid[],boolean) from public, anon;
grant execute on function public.save_job_alert_preferences(boolean,text,text[],text[],time,uuid[],uuid[],boolean) to authenticated;

-- Server-only queue processor and atomic Push claim function.
create or replace function public.process_job_alert_outbox(p_limit integer default 10)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_event record; v_job public.jobs%rowtype; v_pref record; v_notification_id uuid;
  v_processed integer:=0; v_created integer:=0; v_failed integer:=0; v_skipped integer:=0; v_push_queued integer:=0;
begin
  for v_event in select o.id,o.job_id,o.attempt_count from public.job_alert_outbox o
    where o.status='pending' and o.available_at<=now() order by o.created_at asc
    for update skip locked limit least(greatest(coalesce(p_limit,10),1),25)
  loop
    update public.job_alert_outbox set status='processing',locked_at=now(),attempt_count=v_event.attempt_count+1 where id=v_event.id;
    begin
      select j.* into v_job from public.jobs j where j.id=v_event.job_id;
      if not found or v_job.status<>'published' then
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
        v_skipped:=v_skipped+1;
      else
        for v_pref in select p.* from public.job_alert_preferences p
          where p.is_enabled=true and p.delivery_mode in ('instant','both') and (p.in_app_enabled or p.push_enabled)
          and (not exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_locations pl where pl.preference_id=p.id and pl.state=coalesce(v_job.state,v_job.location)))
          and (not exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_employment_types pet where pet.preference_id=p.id and pet.employment_type=v_job.employment_type))
          and (not exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_categories pc where pc.preference_id=p.id and pc.category_id=v_job.category_id))
          and (not exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id)
            or exists(select 1 from public.job_alert_preference_specialties ps where ps.preference_id=p.id and ps.specialty_id=v_job.specialty_id))
        loop
          v_notification_id:=null;
          insert into public.job_alert_notifications(user_id,job_id,job_title_snapshot,job_location_snapshot,available_at)
          values(v_pref.user_id,v_job.id,v_job.title,coalesce(nullif(btrim(v_job.state),''),nullif(btrim(v_job.location),'')),now())
          on conflict(user_id,job_id) where job_id is not null do nothing returning id into v_notification_id;
          if v_notification_id is not null then v_created:=v_created+1;
          else select n.id into v_notification_id from public.job_alert_notifications n where n.user_id=v_pref.user_id and n.job_id=v_job.id limit 1;
          end if;
          if v_notification_id is not null and v_pref.in_app_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status,sent_at)
            values(v_notification_id,'in_app','instant','sent',now()) on conflict(notification_id,channel,delivery_kind) do nothing;
          end if;
          if v_notification_id is not null and v_pref.push_enabled then
            insert into public.job_alert_deliveries(notification_id,channel,delivery_kind,status)
            values(v_notification_id,'push','instant','pending') on conflict(notification_id,channel,delivery_kind) do nothing;
            v_push_queued:=v_push_queued+1;
          end if;
        end loop;
        update public.job_alert_outbox set status='completed',processed_at=now(),locked_at=null,last_error=null where id=v_event.id;
      end if;
      v_processed:=v_processed+1;
    exception when others then
      update public.job_alert_outbox set status=case when v_event.attempt_count+1>=5 then 'failed' else 'pending' end,
        available_at=now()+interval '1 minute'*power(2,least(v_event.attempt_count,5)),locked_at=null,last_error=left(sqlerrm,1000)
        where id=v_event.id;
      v_failed:=v_failed+1;
    end;
  end loop;
  return jsonb_build_object('processed_events',v_processed,'created_notifications',v_created,'failed_events',v_failed,
    'skipped_events',v_skipped,'push_deliveries_queued',v_push_queued);
end;
$$;
revoke all on function public.process_job_alert_outbox(integer) from public, anon, authenticated;
grant execute on function public.process_job_alert_outbox(integer) to service_role;

create or replace function public.claim_job_alert_push_deliveries(p_limit integer default 20)
returns table(delivery_id uuid,notification_id uuid,user_id uuid,job_title text,job_location text,job_id uuid)
language plpgsql security definer set search_path = pg_catalog, public
as $$
begin
  return query with picked as (
    select d.id from public.job_alert_deliveries d
    where d.channel='push' and d.delivery_kind='instant' and d.status='pending'
    order by d.created_at for update skip locked limit least(greatest(coalesce(p_limit,20),1),50)
  ), claimed as (
    update public.job_alert_deliveries d set status='processing',attempt_count=d.attempt_count+1,last_error=null
    from picked p where d.id=p.id returning d.id,d.notification_id
  )
  select c.id,n.id,n.user_id,n.job_title_snapshot,n.job_location_snapshot,n.job_id
  from claimed c join public.job_alert_notifications n on n.id=c.notification_id;
end;
$$;
revoke all on function public.claim_job_alert_push_deliveries(integer) from public, anon, authenticated;
grant execute on function public.claim_job_alert_push_deliveries(integer) to service_role;

-- Trigger enqueue is isolated in a non-exposed schema. It fires only on first transition to published.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to postgres, service_role;
create or replace function private.enqueue_job_alert_on_publish()
returns trigger language plpgsql security definer set search_path = pg_catalog
as $$
begin
  if tg_op='INSERT' then
    if new.status='published' then
      insert into public.job_alert_outbox(event_type,job_id) values('job_published',new.id)
      on conflict(event_type,job_id) do nothing;
    end if;
  elsif tg_op='UPDATE' then
    if new.status='published' and old.status is distinct from new.status then
      insert into public.job_alert_outbox(event_type,job_id) values('job_published',new.id)
      on conflict(event_type,job_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enqueue_job_alert_on_publish() from public, anon, authenticated;
grant execute on function private.enqueue_job_alert_on_publish() to postgres, service_role;
drop trigger if exists enqueue_job_alert_after_publish on public.jobs;
create trigger enqueue_job_alert_after_publish after insert or update of status on public.jobs
for each row execute function private.enqueue_job_alert_on_publish();


-- Explicit service-only policies document the worker access model and satisfy RLS linting.
drop policy if exists "Worker manages job alert deliveries" on public.job_alert_deliveries;
create policy "Worker manages job alert deliveries" on public.job_alert_deliveries
  for all to service_role using (true) with check (true);
drop policy if exists "Worker manages job alert digest runs" on public.job_alert_digest_runs;
create policy "Worker manages job alert digest runs" on public.job_alert_digest_runs
  for all to service_role using (true) with check (true);
drop policy if exists "Worker manages job alert outbox" on public.job_alert_outbox;
create policy "Worker manages job alert outbox" on public.job_alert_outbox
  for all to service_role using (true) with check (true);

-- Do not touch public.in_app_notifications, push_notification_events, applications, or push_subscriptions.
