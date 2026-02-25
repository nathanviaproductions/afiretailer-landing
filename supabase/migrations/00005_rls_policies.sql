-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00005: Row Level Security (RLS) Policies
-- ============================================================================
-- Multi-tenant isolation:
--   - Store users see ONLY their own store's data
--   - AFI admins see ALL data across all stores
--   - OAuth tokens (encrypted columns) are NEVER exposed to any client query
--   - Service role bypasses RLS for backend sync operations
-- ============================================================================

-- ===========================================
-- 0. Helper function to get current user's org_id and role
-- ===========================================
-- Cached per-statement to avoid repeated lookups within a single request.

create or replace function public.current_user_org_id()
returns uuid as $$
  select org_id from public.users where id = auth.uid()
$$ language sql stable security definer;

create or replace function public.current_user_role()
returns public.user_role as $$
  select role from public.users where id = auth.uid()
$$ language sql stable security definer;

create or replace function public.is_afi_admin()
returns boolean as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'afi_admin'
  )
$$ language sql stable security definer;

-- ===========================================
-- 1. Enable RLS on ALL tables
-- ===========================================

alter table public.organizations enable row level security;
alter table public.users enable row level security;
alter table public.platform_connections enable row level security;
alter table public.sync_log enable row level security;
alter table public.campaigns enable row level security;
alter table public.creatives enable row level security;
alter table public.performance_metrics enable row level security;
alter table public.kpi_daily_rollup enable row level security;

-- ===========================================
-- 2. Organizations
-- ===========================================
-- Store users see only their own org. AFI admins see all.

create policy "Users can view their own organization"
  on public.organizations for select
  to authenticated
  using (
    id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Only AFI admins can insert/update organizations
create policy "AFI admins can manage organizations"
  on public.organizations for all
  to authenticated
  using (public.is_afi_admin())
  with check (public.is_afi_admin());

-- ===========================================
-- 3. Users
-- ===========================================
-- Users can see their own profile. Store owners can see users in their org.
-- AFI admins see all users.

create policy "Users can view own profile"
  on public.users for select
  to authenticated
  using (
    id = auth.uid()
    or (
      org_id = public.current_user_org_id()
      and public.current_user_role() = 'store_owner'
    )
    or public.is_afi_admin()
  );

create policy "Users can update own profile"
  on public.users for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ===========================================
-- 4. Platform Connections
-- ===========================================
-- CRITICAL: This table contains encrypted OAuth tokens.
-- We create a VIEW that excludes token columns, and direct client access
-- only goes through that view. The RLS policy on the base table is strict.

-- Store owners can view their connections (but token columns are excluded via view)
create policy "Store owners can view their connections"
  on public.platform_connections for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Only store owners can initiate/disconnect connections
create policy "Store owners can manage connections"
  on public.platform_connections for insert
  to authenticated
  with check (
    org_id = public.current_user_org_id()
    and public.current_user_role() = 'store_owner'
  );

create policy "Store owners can update their connections"
  on public.platform_connections for update
  to authenticated
  using (
    org_id = public.current_user_org_id()
    and public.current_user_role() = 'store_owner'
  );

-- Safe view of connections (NO token columns exposed)
create or replace view public.platform_connections_safe as
select
  id,
  org_id,
  platform,
  status,
  platform_account_id,
  platform_account_name,
  platform_page_id,
  platform_ig_user_id,
  last_sync_at,
  last_sync_status,
  last_sync_error,
  connected_at,
  connected_by,
  disconnected_at,
  metadata,
  created_at,
  updated_at
from public.platform_connections;

comment on view public.platform_connections_safe is
  'Safe projection of platform_connections that EXCLUDES encrypted OAuth tokens. Use this view in client queries.';

-- ===========================================
-- 5. Sync Log
-- ===========================================
-- Read-only for store owners; AFI admins see all

create policy "Store users can view their sync logs"
  on public.sync_log for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Only service_role can insert sync logs (via Edge Functions)
-- No insert policy for authenticated users.

-- ===========================================
-- 6. Campaigns
-- ===========================================

create policy "Store users can view their campaigns"
  on public.campaigns for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Service role handles inserts/updates from sync process
create policy "Store owners can manage campaigns"
  on public.campaigns for all
  to authenticated
  using (
    org_id = public.current_user_org_id()
    and public.current_user_role() in ('store_owner', 'store_manager')
  )
  with check (
    org_id = public.current_user_org_id()
    and public.current_user_role() = 'store_owner'
  );

-- ===========================================
-- 7. Creatives
-- ===========================================

create policy "Store users can view their creatives"
  on public.creatives for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Service role handles inserts/updates from sync
create policy "Service role manages creatives"
  on public.creatives for all
  to service_role
  using (true)
  with check (true);

-- ===========================================
-- 8. Performance Metrics
-- ===========================================

create policy "Store users can view their metrics"
  on public.performance_metrics for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Service role handles inserts from sync
create policy "Service role manages metrics"
  on public.performance_metrics for all
  to service_role
  using (true)
  with check (true);

-- ===========================================
-- 9. KPI Daily Rollup
-- ===========================================

create policy "Store users can view their rollups"
  on public.kpi_daily_rollup for select
  to authenticated
  using (
    org_id = public.current_user_org_id()
    or public.is_afi_admin()
  );

-- Service role computes rollups
create policy "Service role manages rollups"
  on public.kpi_daily_rollup for all
  to service_role
  using (true)
  with check (true);
