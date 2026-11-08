-- Harden messaging RPCs: use invoker privileges and narrowly scoped read receipts.
grant update (read_at) on public.job_messages to authenticated;

drop policy if exists "Recipients mark own messages read" on public.job_messages;
create policy "Recipients mark own messages read"
on public.job_messages
for update
to authenticated
using (recipient_id = (select auth.uid()))
with check (recipient_id = (select auth.uid()));

create or replace function public.get_job_conversation_context(p_application_id uuid)
returns table(job_id uuid, application_id uuid, candidate_id uuid, poster_id uuid, job_title text)
language plpgsql
security invoker
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

create or replace function public.mark_job_messages_read(p_job_id uuid, p_application_id uuid)
returns integer
language plpgsql
security invoker
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

revoke all on function public.get_job_conversation_context(uuid) from public, anon;
grant execute on function public.get_job_conversation_context(uuid) to authenticated;
revoke all on function public.mark_job_messages_read(uuid, uuid) from public, anon;
grant execute on function public.mark_job_messages_read(uuid, uuid) to authenticated;
