-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00006: Performance Indexes
-- ============================================================================
-- Indexes optimized for the dashboard's primary query patterns:
--   1. Filtering creatives by org + platform + channel
--   2. Sorting creatives by engagement, reach, ROAS, views, spend
--   3. Querying metrics by date range for time-series charts
--   4. KPI rollup lookups by org + date range
--   5. Sync management queries on platform_connections
-- ============================================================================

-- ===========================================
-- 1. Organizations
-- ===========================================

create index idx_organizations_slug
  on public.organizations (slug);

create index idx_organizations_licensee_group
  on public.organizations (licensee_group)
  where licensee_group is not null;

create index idx_organizations_state
  on public.organizations (state)
  where is_active = true;

-- ===========================================
-- 2. Users
-- ===========================================

create index idx_users_org_id
  on public.users (org_id)
  where is_active = true;

create index idx_users_email
  on public.users (email);

create index idx_users_role
  on public.users (role);

-- ===========================================
-- 3. Platform Connections
-- ===========================================

-- Primary lookup: which connections does a store have?
create index idx_platform_connections_org_id
  on public.platform_connections (org_id);

-- Find connections needing token refresh
create index idx_platform_connections_token_expiry
  on public.platform_connections (token_expires_at)
  where status = 'active';

-- Find connections by sync status for the cron job
create index idx_platform_connections_sync_status
  on public.platform_connections (last_sync_at, status)
  where status in ('active', 'token_expired');

-- ===========================================
-- 4. Sync Log
-- ===========================================

create index idx_sync_log_connection_id
  on public.sync_log (connection_id, started_at desc);

create index idx_sync_log_org_status
  on public.sync_log (org_id, status, started_at desc);

-- ===========================================
-- 5. Campaigns
-- ===========================================

create index idx_campaigns_org_platform
  on public.campaigns (org_id, platform);

create index idx_campaigns_org_channel
  on public.campaigns (org_id, channel);

create index idx_campaigns_date_range
  on public.campaigns (org_id, start_date, end_date);

-- ===========================================
-- 6. Creatives - the most critical indexes
-- ===========================================

-- Base filter: store's creatives filtered by platform and channel
-- This supports the sidebar filter chips
create index idx_creatives_org_platform_channel
  on public.creatives (org_id, platform, channel)
  where is_active = true;

-- Sort by engagement rate (default sort in dashboard)
create index idx_creatives_org_engagement_desc
  on public.creatives (org_id, engagement_rate desc)
  where is_active = true;

-- Sort by reach
create index idx_creatives_org_reach_desc
  on public.creatives (org_id, reach desc)
  where is_active = true;

-- Sort by ROAS (paid content sorting)
create index idx_creatives_org_roas_desc
  on public.creatives (org_id, roas desc)
  where is_active = true and channel = 'paid';

-- Sort by video views
create index idx_creatives_org_views_desc
  on public.creatives (org_id, video_views desc)
  where is_active = true;

-- Sort by spend
create index idx_creatives_org_spend_desc
  on public.creatives (org_id, spend desc)
  where is_active = true and channel = 'paid';

-- Campaign membership
create index idx_creatives_campaign_id
  on public.creatives (campaign_id)
  where campaign_id is not null;

-- Deduplication check during sync
create index idx_creatives_platform_content_id
  on public.creatives (org_id, platform, platform_content_id)
  where platform_content_id is not null;

-- Published date for time-based queries
create index idx_creatives_published_at
  on public.creatives (org_id, published_at desc)
  where is_active = true;

-- AFI admin: top creatives across all stores (network view)
create index idx_creatives_engagement_network
  on public.creatives (engagement_rate desc)
  where is_active = true;

create index idx_creatives_roas_network
  on public.creatives (roas desc)
  where is_active = true and channel = 'paid';

-- ===========================================
-- 7. Performance Metrics - time-series queries
-- ===========================================

-- Primary time-series query: metrics for a store over a date range
-- This powers the "Performance Over Time" chart
create index idx_metrics_org_date
  on public.performance_metrics (org_id, metric_date desc);

-- Filter by platform within a date range
create index idx_metrics_org_platform_date
  on public.performance_metrics (org_id, platform, metric_date desc);

-- Filter by channel within a date range
create index idx_metrics_org_channel_date
  on public.performance_metrics (org_id, channel, metric_date desc);

-- Full filter: org + platform + channel + date range
create index idx_metrics_org_platform_channel_date
  on public.performance_metrics (org_id, platform, channel, metric_date desc);

-- Lookup metrics for a specific creative over time
create index idx_metrics_creative_date
  on public.performance_metrics (creative_id, metric_date desc);

-- AFI admin: network-wide date queries
create index idx_metrics_date_platform
  on public.performance_metrics (metric_date desc, platform);

-- ===========================================
-- 8. KPI Daily Rollup
-- ===========================================

-- Store dashboard: rollup by date range
create index idx_kpi_rollup_org_date
  on public.kpi_daily_rollup (org_id, rollup_date desc);

-- Filtered rollup: by platform
create index idx_kpi_rollup_org_platform_date
  on public.kpi_daily_rollup (org_id, platform, rollup_date desc);

-- Filtered rollup: by channel
create index idx_kpi_rollup_org_channel_date
  on public.kpi_daily_rollup (org_id, channel, rollup_date desc);

-- AFI admin: network-wide rollup queries
create index idx_kpi_rollup_date_all
  on public.kpi_daily_rollup (rollup_date desc)
  where platform is null and channel is null;
