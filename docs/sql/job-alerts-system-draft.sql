-- Wazifti Job Alerts — REVIEW DRAFT ONLY
-- Target: Supabase project zaucmxoxgpmipizzhbqs
-- Branch: feature/job-alerts-system
-- This file has NOT been applied. Review and approve separately before execution.
-- No extensions are enabled, no schedules are created, and no Edge Function is deployed here.

begin;

create table if not exists public.job_alert_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  is_enabled boolean not null default true,
  delivery_mode text not null default 'both'
    check (delivery_mode in ('instant', 'daily', 'both')),
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default false,
  daily_send_time time not null default time '08:00',
  timezone text not null default 'Africa/Khartoum',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

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

-- V1 uses the existing jobs.state field. City matching is deferred until
-- Wazifti has a normalized city catalogue; free-text city values are unsafe to match.
create table if not exists public.job_alert_preference_locations (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  state text not null check (length(btrim(state)) > 0),
  created_at timestamptz not null default now(),
  primary key (preference_id, state)
);

create table if not exists public.job_alert_preference_employment_types (
  preference_id uuid not null references public.job_alert_preferences(id) on delete cascade,
  employment_type text not null
    check (employment_type in ('full_time', 'part_time', 'remote', 'contract', 'temporary', 'internship')),
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

create unique index if not exists job_alert_notifications_user_job_uidx
  on public.job_alert_notifications(user_id, job_id)
  where job_id is not null;

create index if not exists job_alert_notifications_user_created_idx
  on public.job_alert_notifications(user_id, available_at, created_at desc);

create table if not exists public.job_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.job_alert_notifications(id) on delete cascade,
  channel text not null check (channel in ('in_app', 'push')),
  delivery_kind text not null default 'instant'
    check (delivery_kind in ('instant', 'daily_digest')),
  batch_id uuid,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (notification_id, channel, delivery_kind)
);

create index if not exists job_alert_deliveries_status_created_idx
  on public.job_alert_deliveries(status, created_at);

create index if not exists job_alert_deliveries_batch_idx
  on public.job_alert_deliveries(batch_id)
  where batch_id is not null;

create table if not exists public.job_alert_digest_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  digest_date date not null,
  channel text not null check (channel in ('in_app', 'push')),
  batch_id uuid not null unique default gen_random_uuid(),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, digest_date, channel)
);

create index if not exists job_alert_digest_runs_due_idx
  on public.job_alert_digest_runs(status, digest_date, created_at);

create table if not exists public.job_alert_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in ('job_published')),
  job_id uuid not null references public.jobs(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (event_type, job_id)
);

create index if not exists job_alert_outbox_ready_idx
  on public.job_alert_outbox(status, available_at, created_at);

create index if not exists job_alert_preference_categories_category_idx
  on public.job_alert_preference_categories(category_id);

create index if not exists job_alert_preference_specialties_specialty_idx
  on public.job_alert_preference_specialties(specialty_id);

create index if not exists job_alert_preference_locations_state_idx
  on public.job_alert_preference_locations(state);

create index if not exists job_alert_preference_employment_types_type_idx
  on public.job_alert_preference_employment_types(employment_type);

-- RLS: preferences are owned by the signed-in user.
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
create policy "Users manage own job alert preferences"
  on public.job_alert_preferences
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users read own alert categories" on public.job_alert_preference_categories;
create policy "Users read own alert categories"
  on public.job_alert_preference_categories
  for select to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_categories.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users add own alert categories" on public.job_alert_preference_categories;
create policy "Users add own alert categories"
  on public.job_alert_preference_categories
  for insert to authenticated
  with check (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_categories.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users remove own alert categories" on public.job_alert_preference_categories;
create policy "Users remove own alert categories"
  on public.job_alert_preference_categories
  for delete to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_categories.preference_id
      and p.user_id = (select auth.uid())
  ));

drop policy if exists "Users read own alert specialties" on public.job_alert_preference_specialties;
create policy "Users read own alert specialties"
  on public.job_alert_preference_specialties
  for select to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_specialties.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users add own alert specialties" on public.job_alert_preference_specialties;
create policy "Users add own alert specialties"
  on public.job_alert_preference_specialties
  for insert to authenticated
  with check (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_specialties.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users remove own alert specialties" on public.job_alert_preference_specialties;
create policy "Users remove own alert specialties"
  on public.job_alert_preference_specialties
  for delete to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_specialties.preference_id
      and p.user_id = (select auth.uid())
  ));

drop policy if exists "Users read own alert locations" on public.job_alert_preference_locations;
create policy "Users read own alert locations"
  on public.job_alert_preference_locations
  for select to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_locations.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users add own alert locations" on public.job_alert_preference_locations;
create policy "Users add own alert locations"
  on public.job_alert_preference_locations
  for insert to authenticated
  with check (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_locations.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users remove own alert locations" on public.job_alert_preference_locations;
create policy "Users remove own alert locations"
  on public.job_alert_preference_locations
  for delete to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_locations.preference_id
      and p.user_id = (select auth.uid())
  ));

drop policy if exists "Users read own alert employment types" on public.job_alert_preference_employment_types;
create policy "Users read own alert employment types"
  on public.job_alert_preference_employment_types
  for select to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_employment_types.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users add own alert employment types" on public.job_alert_preference_employment_types;
create policy "Users add own alert employment types"
  on public.job_alert_preference_employment_types
  for insert to authenticated
  with check (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_employment_types.preference_id
      and p.user_id = (select auth.uid())
  ));
drop policy if exists "Users remove own alert employment types" on public.job_alert_preference_employment_types;
create policy "Users remove own alert employment types"
  on public.job_alert_preference_employment_types
  for delete to authenticated
  using (exists (
    select 1 from public.job_alert_preferences p
    where p.id = job_alert_preference_employment_types.preference_id
      and p.user_id = (select auth.uid())
  ));

drop policy if exists "Users read own job alert notifications" on public.job_alert_notifications;
create policy "Users read own job alert notifications"
  on public.job_alert_notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users mark own job alert notifications read" on public.job_alert_notifications;
create policy "Users mark own job alert notifications read"
  on public.job_alert_notifications
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Clients may update only read_at; delivery and outbox state are worker-owned.
revoke all on public.job_alert_preferences,
  public.job_alert_preference_categories,
  public.job_alert_preference_specialties,
  public.job_alert_preference_locations,
  public.job_alert_preference_employment_types,
  public.job_alert_notifications,
  public.job_alert_deliveries,
  public.job_alert_digest_runs,
  public.job_alert_outbox
from anon, authenticated;

grant select, insert, update, delete on public.job_alert_preferences to authenticated;
grant select, insert, delete on public.job_alert_preference_categories to authenticated;
grant select, insert, delete on public.job_alert_preference_specialties to authenticated;
grant select, insert, delete on public.job_alert_preference_locations to authenticated;
grant select, insert, delete on public.job_alert_preference_employment_types to authenticated;
grant select on public.job_alert_notifications to authenticated;
grant update (read_at) on public.job_alert_notifications to authenticated;

grant all on public.job_alert_preferences,
  public.job_alert_preference_categories,
  public.job_alert_preference_specialties,
  public.job_alert_preference_locations,
  public.job_alert_preference_employment_types,
  public.job_alert_notifications,
  public.job_alert_deliveries,
  public.job_alert_digest_runs,
  public.job_alert_outbox
to service_role;

-- A private trigger enqueues only the transition into the actual published state.
create schema if not exists private;

create or replace function private.enqueue_job_alert_on_publish()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'published' then
      insert into public.job_alert_outbox (event_type, job_id)
      values ('job_published', new.id)
      on conflict (event_type, job_id) do nothing;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.status = 'published' and old.status is distinct from new.status then
      insert into public.job_alert_outbox (event_type, job_id)
      values ('job_published', new.id)
      on conflict (event_type, job_id) do nothing;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.enqueue_job_alert_on_publish() from public, anon, authenticated;

drop trigger if exists enqueue_job_alert_after_publish on public.jobs;
create trigger enqueue_job_alert_after_publish
  after insert or update of status on public.jobs
  for each row
  execute function private.enqueue_job_alert_on_publish();

comment on table public.job_alert_preferences is
  'User-owned job alert preferences; billing tiers are intentionally not implemented in V1.';
comment on table public.job_alert_notifications is
  'In-app job alert inbox, separate from application-status notifications.';
comment on table public.job_alert_deliveries is
  'Worker-managed delivery attempts per channel and delivery kind; digest items share a batch id.';
comment on table public.job_alert_digest_runs is
  'Worker-managed per-user, per-local-date digest run; prevents duplicate daily summaries.';
comment on table public.job_alert_outbox is
  'Worker queue populated when a job first becomes published.';

commit;
