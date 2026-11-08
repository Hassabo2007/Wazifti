-- Wazifti V1.3: private conversations between applicants and job posters.
-- This file is committed to the feature branch only; it is NOT applied to Supabase.

alter table public.in_app_notifications
  alter column application_id drop not null,
  add column if not exists notification_type text not null default 'application_status';

create table if not exists public.job_messages (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs(id) on delete cascade,
  application_id uuid not null references public.applications(id) on delete cascade,
  candidate_id uuid not null references auth.users(id) on delete cascade,
  poster_id uuid not null references auth.users(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint job_messages_distinct_participants check (candidate_id <> poster_id and sender_id <> recipient_id)
);

create index if not exists job_messages_conversation_idx
  on public.job_messages(job_id, application_id, created_at);
create index if not exists job_messages_recipient_unread_idx
  on public.job_messages(recipient_id, created_at desc) where read_at is null;

alter table public.job_messages enable row level security;

revoke all on public.job_messages from anon, authenticated;
grant select, insert on public.job_messages to authenticated;

drop policy if exists "Conversation participants read messages" on public.job_messages;
create policy "Conversation participants read messages"
on public.job_messages for select to authenticated
using (auth.uid() in (candidate_id, poster_id));

drop policy if exists "Conversation participants send messages" on public.job_messages;
create policy "Conversation participants send messages"
on public.job_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    (
      sender_id = candidate_id and recipient_id = poster_id
      and exists (
        select 1
        from public.applications a
        join public.jobs j on j.id = a.job_id
        left join public.companies c on c.id = j.company_id
        where a.id = job_messages.application_id
          and a.job_id = job_messages.job_id
          and a.candidate_id = job_messages.candidate_id
          and job_messages.poster_id = case
            when j.poster_type = 'individual' then j.posted_by_user_id
            else c.owner_id
          end
      )
    )
    or
    (
      sender_id = poster_id and recipient_id = candidate_id
      and exists (
        select 1
        from public.applications a
        join public.jobs j on j.id = a.job_id
        left join public.companies c on c.id = j.company_id
        where a.id = job_messages.application_id and a.job_id = job_messages.job_id and a.candidate_id = job_messages.candidate_id
          and (
            (j.poster_type = 'individual' and j.posted_by_user_id = auth.uid())
            or c.owner_id = auth.uid()
          )
      )
    )
  )
);


create or replace function public.get_job_conversation_context(p_application_id uuid)
returns table(job_id uuid, application_id uuid, candidate_id uuid, poster_id uuid, job_title text)
language plpgsql
security definer
set search_path = ''
as $ctx$
begin
  return query
  select j.id, a.id, a.candidate_id,
         case when j.poster_type = 'individual' then j.posted_by_user_id else c.owner_id end,
         j.title
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  where a.id = p_application_id
    and (
      a.candidate_id = auth.uid()
      or (j.poster_type = 'individual' and j.posted_by_user_id = auth.uid())
      or c.owner_id = auth.uid()
    );
end;
$ctx$;

revoke all on function public.get_job_conversation_context(uuid) from public, anon;
grant execute on function public.get_job_conversation_context(uuid) to authenticated;

create or replace function public.mark_job_messages_read(p_job_id uuid, p_application_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  update public.job_messages
  set read_at = now()
  where job_id = p_job_id
    and application_id = p_application_id
    and recipient_id = auth.uid()
    and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.mark_job_messages_read(uuid, uuid) from public, anon;
grant execute on function public.mark_job_messages_read(uuid, uuid) to authenticated;

create or replace function private.notify_new_job_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_title text;
begin
  select j.title into v_title from public.jobs j where j.id = new.job_id;
  insert into public.in_app_notifications
    (user_id, application_id, job_title, old_status, new_status, message, notification_type)
  values
    (new.recipient_id, new.application_id, coalesce(v_title, 'وظيفة'), null, 'message',
     'وصلتك رسالة جديدة بخصوص وظيفة: ' || coalesce(v_title, 'وظيفة'), 'message');
  return new;
end;
$$;

revoke all on function private.notify_new_job_message() from public, anon, authenticated;
drop trigger if exists notify_new_job_message on public.job_messages;
create trigger notify_new_job_message
after insert on public.job_messages
for each row execute function private.notify_new_job_message();

-- Mark-as-read is available only through the scoped RPC above; no direct UPDATE policy is granted.
