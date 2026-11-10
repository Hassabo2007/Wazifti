-- Local-only Supabase Vault stand-in for the PostgreSQL 17 historical replay.
-- The pg_cron/pg_net scheduler migration is excluded from this test, but the
-- VAPID RPC migration references vault.decrypted_secrets at function creation.
CREATE SCHEMA vault;
CREATE TABLE vault.decrypted_secrets (
  name text NOT NULL,
  decrypted_secret text
);
