create table if not exists public.push_subscriptions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    endpoint text not null unique,
    subscription jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint push_subscriptions_endpoint_length check (char_length(endpoint) between 1 and 2048),
    constraint push_subscriptions_json_object check (jsonb_typeof(subscription) = 'object')
  );
  create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions(user_id);
  alter table public.push_subscriptions enable row level security;
  revoke all on public.push_subscriptions from anon, authenticated;
  grant select, insert, update, delete on public.push_subscriptions to authenticated;
  drop policy if exists "Users manage their own push subscriptions" on public.push_subscriptions;
  create policy "Users manage their own push subscriptions"
    on public.push_subscriptions
    for all
    to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));
