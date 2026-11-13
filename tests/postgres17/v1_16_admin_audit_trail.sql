-- V1.16: append-only audit capture for administrator status changes.
-- This migration records identifiers and status transitions only; it never copies
-- CV URLs, resume IDs, cover letters, phone numbers, documents, or raw payloads.

create schema if not exists private;

create table private.admin_audit_logs (
  id bigint generated always as identity primary key,
  transaction_id bigint not null,
  actor_user_id uuid not null,
  actor_type text not null check (actor_type = 'admin'),
  entity_type text not null check (entity_type in ('company', 'job', 'application')),
  entity_id uuid not null,
  action text not null,
  old_status text not null,
  new_status text not null,
  created_at timestamptz not null default clock_timestamp()
);

create index admin_audit_logs_transaction_id_idx
  on private.admin_audit_logs (transaction_id);
create index admin_audit_logs_created_at_idx
  on private.admin_audit_logs (created_at desc);
create index admin_audit_logs_actor_created_at_idx
  on private.admin_audit_logs (actor_user_id, created_at desc);
create index admin_audit_logs_entity_created_at_idx
  on private.admin_audit_logs (entity_type, entity_id, created_at desc);

alter table private.admin_audit_logs enable row level security;

revoke all on table private.admin_audit_logs from public, anon, authenticated, service_role;
revoke all on sequence private.admin_audit_logs_id_seq from public, anon, authenticated, service_role;

create or replace function private.capture_admin_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor_user_id uuid;
  v_entity_type text;
begin
  if old.status is not distinct from new.status then
    return new;
  end if;

  if not public.is_admin() then
    return new;
  end if;

  v_actor_user_id := auth.uid();
  if v_actor_user_id is null then
    raise exception 'Administrator audit actor could not be established.'
      using errcode = '42501';
  end if;

  v_entity_type := tg_argv[0];
  if v_entity_type not in ('company', 'job', 'application') then
    raise exception 'Unsupported administrator audit entity type.'
      using errcode = '22023';
  end if;

  insert into private.admin_audit_logs (
    transaction_id,
    actor_user_id,
    actor_type,
    entity_type,
    entity_id,
    action,
    old_status,
    new_status
  )
  values (
    txid_current(),
    v_actor_user_id,
    'admin',
    v_entity_type,
    new.id,
    v_entity_type || '.status_changed',
    old.status,
    new.status
  );

  return new;
end;
$function$;

create or replace function private.prevent_admin_audit_log_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Administrator audit logs are append-only.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.capture_admin_status_change() from public, anon, authenticated, service_role;
revoke all on function private.prevent_admin_audit_log_mutation() from public, anon, authenticated, service_role;

create trigger admin_audit_logs_append_only
before update or delete on private.admin_audit_logs
for each row execute function private.prevent_admin_audit_log_mutation();

create trigger zz_admin_audit_company_status
after update of status on public.companies
for each row execute function private.capture_admin_status_change('company');

create trigger zz_admin_audit_job_status
after update of status on public.jobs
for each row execute function private.capture_admin_status_change('job');

create trigger zz_admin_audit_application_status
after update of status on public.applications
for each row execute function private.capture_admin_status_change('application');
