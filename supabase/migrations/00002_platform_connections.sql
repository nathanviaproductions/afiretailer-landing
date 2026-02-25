-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00002: Platform Connections & OAuth Token Storage
-- ============================================================================
-- Stores OAuth credentials for each store's connected social media accounts.
-- Tokens are encrypted at rest using pgcrypto. RLS policies (applied in a
-- later migration) ensure tokens are NEVER exposed to client-side queries.
-- ============================================================================

-- ===========================================
-- 1. Platform Connections
-- ===========================================
-- One row per platform per store. A single Meta connection covers both
-- Facebook and Instagram. YouTube and GBP are separate Google OAuth flows.

create table public.platform_connections (
  id                   uuid primary key default uuid_generate_v4(),
  org_id               uuid not null references public.organizations(id) on delete cascade,
  platform             public.platform_type not null,
  status               public.connection_status not null default 'pending',

  -- Platform account identifiers (safe to expose via API)
  platform_account_id  text,          -- e.g. Meta Business Account ID, YouTube Channel ID
  platform_account_name text,         -- Human-readable name shown in the sidebar
  platform_page_id     text,          -- Facebook Page ID (Meta connections)
  platform_ig_user_id  text,          -- Instagram Business Account ID (Meta connections)

  -- OAuth tokens - encrypted at rest. NEVER exposed via RLS.
  -- We store them encrypted using pgcrypto's pgp_sym_encrypt.
  -- The encryption key is stored in Supabase Vault or as an env var.
  access_token_encrypted  bytea,      -- pgp_sym_encrypt(token, key)
  refresh_token_encrypted bytea,      -- pgp_sym_encrypt(token, key)
  token_expires_at        timestamptz, -- When the access token expires
  token_scope             text,        -- OAuth scopes granted

  -- Sync tracking
  last_sync_at         timestamptz,    -- Last successful data pull
  last_sync_status     public.sync_status,
  last_sync_error      text,           -- Error message from last failed sync
  sync_cursor          jsonb,          -- Platform-specific pagination cursor for incremental sync

  -- Connection metadata
  connected_at         timestamptz,    -- When the OAuth flow was completed
  connected_by         uuid references public.users(id) on delete set null,
  disconnected_at      timestamptz,
  metadata             jsonb default '{}',

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),

  -- Each store can have only one connection per platform
  unique (org_id, platform)
);

comment on table public.platform_connections is
  'OAuth connections to social media platforms. Tokens encrypted at rest via pgcrypto.';

-- ===========================================
-- 2. Token encryption/decryption helpers
-- ===========================================
-- These functions run as SECURITY DEFINER so they can access the encryption
-- key from Supabase Vault without exposing it to the calling user.
-- The key is stored as a Supabase secret: OAUTH_ENCRYPTION_KEY

-- Encrypt a token before storage
create or replace function public.encrypt_token(plain_token text)
returns bytea as $$
begin
  return pgp_sym_encrypt(
    plain_token,
    current_setting('app.settings.oauth_encryption_key', true)
  );
end;
$$ language plpgsql security definer;

-- Decrypt a token for use in Edge Functions (never called from client)
create or replace function public.decrypt_token(encrypted_token bytea)
returns text as $$
begin
  return pgp_sym_decrypt(
    encrypted_token,
    current_setting('app.settings.oauth_encryption_key', true)
  );
end;
$$ language plpgsql security definer;

-- Revoke execute from public - only service_role can call these
revoke execute on function public.encrypt_token(text) from public, anon, authenticated;
revoke execute on function public.decrypt_token(bytea) from public, anon, authenticated;

-- ===========================================
-- 3. Sync History Log
-- ===========================================
-- Audit trail of every data sync attempt per connection.
-- Useful for debugging rate limits and tracking data freshness.

create table public.sync_log (
  id              uuid primary key default uuid_generate_v4(),
  connection_id   uuid not null references public.platform_connections(id) on delete cascade,
  org_id          uuid not null references public.organizations(id) on delete cascade,
  platform        public.platform_type not null,
  status          public.sync_status not null,
  started_at      timestamptz not null default now(),
  completed_at    timestamptz,
  records_fetched integer default 0,
  records_upserted integer default 0,
  error_message   text,
  error_code      text,              -- Platform-specific error code
  rate_limit_remaining integer,      -- API rate limit remaining after this call
  rate_limit_reset timestamptz,      -- When the rate limit window resets
  metadata        jsonb default '{}'
);

comment on table public.sync_log is
  'Audit log of every API data sync attempt. Used for debugging and rate limit tracking.';

-- ===========================================
-- 4. Triggers
-- ===========================================

create trigger trg_platform_connections_updated_at
  before update on public.platform_connections
  for each row execute function public.set_updated_at();
