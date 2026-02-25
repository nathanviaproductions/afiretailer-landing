-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00004: KPI Summary Rollups
-- ============================================================================
-- Pre-computed daily KPI aggregates per store. These power the KPI summary
-- cards at the top of the dashboard and enable fast cross-store comparisons
-- for AFI admins without scanning millions of metric rows.
-- ============================================================================

-- ===========================================
-- 1. Daily KPI Rollup Table
-- ===========================================
-- One row per store per day per optional filter dimension.
-- Materialized by a cron job or triggered after each sync.

create table public.kpi_daily_rollup (
  id               uuid primary key default uuid_generate_v4(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  rollup_date      date not null,
  platform         public.sub_platform,   -- NULL = all platforms combined
  channel          public.channel_type,    -- NULL = all channels combined

  -- Aggregate KPIs (matches the 5 KPI cards in the dashboard)
  total_reach         bigint not null default 0,
  total_impressions   bigint not null default 0,
  total_video_views   bigint not null default 0,
  total_likes         bigint not null default 0,
  total_comments      bigint not null default 0,
  total_shares        bigint not null default 0,
  total_clicks        bigint not null default 0,
  avg_engagement_rate numeric(6,3) not null default 0,
  total_spend         numeric(12,2) not null default 0,
  total_revenue       numeric(12,2) not null default 0,
  roas                numeric(8,2) not null default 0,
  avg_ctr             numeric(6,3) not null default 0,
  avg_cpm             numeric(10,2) not null default 0,
  total_conversions   integer not null default 0,

  -- Counts for averaging
  creative_count      integer not null default 0,
  active_campaigns    integer not null default 0,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- One rollup per store/date/platform/channel combination
  unique (org_id, rollup_date, platform, channel)
);

comment on table public.kpi_daily_rollup is
  'Pre-computed daily KPI aggregates per store. Powers the dashboard KPI cards and AFI-wide reports.';

-- ===========================================
-- 2. Function to compute rollups for a store/date
-- ===========================================
-- Called by the sync process after metrics are updated.
-- Computes rollups at 4 granularities:
--   1. Per platform + per channel
--   2. Per platform + all channels (channel = NULL)
--   3. All platforms + per channel (platform = NULL)
--   4. All platforms + all channels (both NULL) -- the "totals" row

create or replace function public.compute_daily_rollup(
  p_org_id uuid,
  p_date date
)
returns void as $$
begin
  -- Delete existing rollups for this store/date to recompute
  delete from public.kpi_daily_rollup
  where org_id = p_org_id and rollup_date = p_date;

  -- Insert rollups at all 4 granularities using GROUPING SETS
  insert into public.kpi_daily_rollup (
    org_id, rollup_date, platform, channel,
    total_reach, total_impressions, total_video_views,
    total_likes, total_comments, total_shares, total_clicks,
    avg_engagement_rate, total_spend, total_revenue, roas,
    avg_ctr, avg_cpm, total_conversions, creative_count
  )
  select
    p_org_id,
    p_date,
    pm.platform,
    pm.channel,
    coalesce(sum(pm.reach), 0),
    coalesce(sum(pm.impressions), 0),
    coalesce(sum(pm.video_views), 0),
    coalesce(sum(pm.likes), 0),
    coalesce(sum(pm.comments), 0),
    coalesce(sum(pm.shares), 0),
    coalesce(sum(pm.clicks), 0),
    coalesce(avg(pm.engagement_rate), 0),
    coalesce(sum(pm.spend), 0),
    coalesce(sum(pm.revenue), 0),
    case when sum(pm.spend) > 0
         then round(sum(pm.revenue) / sum(pm.spend), 2)
         else 0
    end,
    coalesce(avg(pm.ctr), 0),
    coalesce(avg(pm.cpm), 0),
    coalesce(sum(pm.conversions), 0),
    count(distinct pm.creative_id)
  from public.performance_metrics pm
  where pm.org_id = p_org_id
    and pm.metric_date = p_date
  group by grouping sets (
    (pm.platform, pm.channel),   -- per platform + per channel
    (pm.platform),               -- per platform, all channels
    (pm.channel),                -- all platforms, per channel
    ()                           -- grand total
  );
end;
$$ language plpgsql security definer;

comment on function public.compute_daily_rollup is
  'Recomputes KPI daily rollups for a given store and date at all granularity levels.';

-- ===========================================
-- 3. AFI-wide (network) rollup view
-- ===========================================
-- A view that aggregates across ALL stores for AFI admin dashboards.
-- Not materialized - it reads from the pre-computed per-store rollups.

create or replace view public.kpi_network_rollup as
select
  rollup_date,
  platform,
  channel,
  sum(total_reach) as total_reach,
  sum(total_impressions) as total_impressions,
  sum(total_video_views) as total_video_views,
  sum(total_likes) as total_likes,
  sum(total_comments) as total_comments,
  sum(total_shares) as total_shares,
  sum(total_clicks) as total_clicks,
  avg(avg_engagement_rate) as avg_engagement_rate,
  sum(total_spend) as total_spend,
  sum(total_revenue) as total_revenue,
  case when sum(total_spend) > 0
       then round(sum(total_revenue) / sum(total_spend), 2)
       else 0
  end as roas,
  avg(avg_ctr) as avg_ctr,
  avg(avg_cpm) as avg_cpm,
  sum(total_conversions) as total_conversions,
  sum(creative_count) as creative_count,
  count(distinct org_id) as store_count
from public.kpi_daily_rollup
where platform is null and channel is null  -- Use the grand-total rows
group by rollup_date, platform, channel
order by rollup_date desc;

comment on view public.kpi_network_rollup is
  'Aggregated KPIs across all stores. Used by AFI admin dashboards for network-wide reporting.';

-- ===========================================
-- 4. Top-performing creatives view (AFI)
-- ===========================================
-- Shows the best-performing creatives across ALL stores.
-- Used by AFI to identify winning ad creative for the network.

create or replace view public.top_creatives_network as
select
  c.id as creative_id,
  c.org_id,
  o.name as store_name,
  c.platform,
  c.channel,
  c.content_type,
  c.title,
  c.thumbnail_path,
  c.reach,
  c.impressions,
  c.video_views,
  c.likes,
  c.engagement_rate,
  c.spend,
  c.revenue,
  c.roas,
  c.published_at
from public.creatives c
join public.organizations o on o.id = c.org_id
where c.is_active = true
order by c.engagement_rate desc;

comment on view public.top_creatives_network is
  'All active creatives ranked by engagement. Used by AFI admins to find top-performing content across the network.';

-- ===========================================
-- 5. Trigger
-- ===========================================

create trigger trg_kpi_daily_rollup_updated_at
  before update on public.kpi_daily_rollup
  for each row execute function public.set_updated_at();
