-- Enable Postgres Changes for public job listings.
-- Safe to apply even when the table was already added manually.
-- Clients still fetch rows through the existing public SELECT RLS policy.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'jobs'
  ) then
    alter publication supabase_realtime add table public.jobs;
  end if;
end
$$;
