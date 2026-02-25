-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00007: Database Functions and Triggers
-- ============================================================================
-- Server-side functions for dashboard queries, metric computation, and
-- data management. These are called from the frontend via supabase.rpc()
-- or from Edge Functions via the service_role client.
-- ============================================================================

-- ===========================================
-- 1. Dashboard KPI Query Function
-- ===========================================
-- Returns the 5 KPI card values for a store over a date range.
-- Called from the dashboard with: supabase.rpc('get_dashboard_kpis', { ... })

create or replace function public.get_dashboard_kpis(
  p_org_id uuid,
  p_start_date date,
  p_end_date date,
  p_platform public.sub_platform default null,
  p_channel public.channel_type default null
)
returns table (
  total_reach bigint,
  avg_engagement_rate numeric,
  total_spend numeric,
  roas numeric,
  total_video_views bigint,
  -- Prior period comparison values
  prev_reach bigint,
  prev_engagement_rate numeric,
  prev_spend numeric,
  prev_roas numeric,
  prev_video_views bigint
) as $$
declare
  v_period_days integer;
  v_prev_start date;
  v_prev_end date;
begin
  -- Calculate the prior period of equal length
  v_period_days := p_end_date - p_start_date;
  v_prev_end := p_start_date - 1;
  v_prev_start := v_prev_end - v_period_days;

  return query
  select
    -- Current period
    coalesce(sum(case when r.rollup_date between p_start_date and p_end_date then r.total_reach else 0 end), 0)::bigint as total_reach,
    coalesce(avg(case when r.rollup_date between p_start_date and p_end_date then r.avg_engagement_rate end), 0)::numeric as avg_engagement_rate,
    coalesce(sum(case when r.rollup_date between p_start_date and p_end_date then r.total_spend else 0 end), 0)::numeric as total_spend,
    case
      when sum(case when r.rollup_date between p_start_date and p_end_date then r.total_spend else 0 end) > 0
      then round(
        sum(case when r.rollup_date between p_start_date and p_end_date then r.total_revenue else 0 end) /
        sum(case when r.rollup_date between p_start_date and p_end_date then r.total_spend else 0 end), 1
      )
      else 0
    end::numeric as roas,
    coalesce(sum(case when r.rollup_date between p_start_date and p_end_date then r.total_video_views else 0 end), 0)::bigint as total_video_views,

    -- Prior period
    coalesce(sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_reach else 0 end), 0)::bigint as prev_reach,
    coalesce(avg(case when r.rollup_date between v_prev_start and v_prev_end then r.avg_engagement_rate end), 0)::numeric as prev_engagement_rate,
    coalesce(sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_spend else 0 end), 0)::numeric as prev_spend,
    case
      when sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_spend else 0 end) > 0
      then round(
        sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_revenue else 0 end) /
        sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_spend else 0 end), 1
      )
      else 0
    end::numeric as prev_roas,
    coalesce(sum(case when r.rollup_date between v_prev_start and v_prev_end then r.total_video_views else 0 end), 0)::bigint as prev_video_views

  from public.kpi_daily_rollup r
  where r.org_id = p_org_id
    and r.rollup_date between v_prev_start and p_end_date
    and (p_platform is null and r.platform is null or r.platform = p_platform)
    and (p_channel is null and r.channel is null or r.channel = p_channel);
end;
$$ language plpgsql stable security definer;

-- ===========================================
-- 2. Performance Time Series Query
-- ===========================================
-- Returns daily aggregated metrics for the "Performance Over Time" chart.

create or replace function public.get_performance_timeseries(
  p_org_id uuid,
  p_start_date date,
  p_end_date date,
  p_platform public.sub_platform default null,
  p_channel public.channel_type default null
)
returns table (
  metric_date date,
  total_reach bigint,
  avg_engagement_rate numeric,
  total_video_views bigint,
  total_spend numeric,
  total_revenue numeric
) as $$
begin
  return query
  select
    r.rollup_date as metric_date,
    r.total_reach,
    r.avg_engagement_rate,
    r.total_video_views,
    r.total_spend,
    r.total_revenue
  from public.kpi_daily_rollup r
  where r.org_id = p_org_id
    and r.rollup_date between p_start_date and p_end_date
    and (p_platform is null and r.platform is null or r.platform = p_platform)
    and (p_channel is null and r.channel is null or r.channel = p_channel)
  order by r.rollup_date asc;
end;
$$ language plpgsql stable security definer;

-- ===========================================
-- 3. Spend by Platform (Doughnut Chart)
-- ===========================================

create or replace function public.get_spend_by_platform(
  p_org_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  platform public.sub_platform,
  total_spend numeric
) as $$
begin
  return query
  select
    r.platform,
    sum(r.total_spend)::numeric as total_spend
  from public.kpi_daily_rollup r
  where r.org_id = p_org_id
    and r.rollup_date between p_start_date and p_end_date
    and r.platform is not null
    and r.channel is null  -- Use the per-platform, all-channels rollup
    and r.total_spend > 0
  group by r.platform
  order by total_spend desc;
end;
$$ language plpgsql stable security definer;

-- ===========================================
-- 4. Creative Performance Grid Query
-- ===========================================
-- Returns creatives for the grid, with filtering and sorting.
-- Supports pagination via limit/offset.

create or replace function public.get_creative_grid(
  p_org_id uuid,
  p_platform public.sub_platform default null,
  p_channel public.channel_type default null,
  p_sort_by text default 'engagement_rate',
  p_sort_dir text default 'desc',
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id uuid,
  platform public.sub_platform,
  channel public.channel_type,
  content_type public.content_type,
  title text,
  thumbnail_path text,
  reach bigint,
  video_views bigint,
  likes bigint,
  engagement_rate numeric,
  spend numeric,
  revenue numeric,
  roas numeric,
  published_at timestamptz,
  total_count bigint
) as $$
begin
  return query
  select
    c.id,
    c.platform,
    c.channel,
    c.content_type,
    c.title,
    c.thumbnail_path,
    c.reach,
    c.video_views,
    c.likes,
    c.engagement_rate,
    c.spend,
    c.revenue,
    c.roas,
    c.published_at,
    count(*) over() as total_count
  from public.creatives c
  where c.org_id = p_org_id
    and c.is_active = true
    and (p_platform is null or c.platform = p_platform)
    and (p_channel is null or c.channel = p_channel)
  order by
    case when p_sort_by = 'engagement_rate' and p_sort_dir = 'desc' then c.engagement_rate end desc nulls last,
    case when p_sort_by = 'engagement_rate' and p_sort_dir = 'asc' then c.engagement_rate end asc nulls last,
    case when p_sort_by = 'reach' and p_sort_dir = 'desc' then c.reach end desc nulls last,
    case when p_sort_by = 'reach' and p_sort_dir = 'asc' then c.reach end asc nulls last,
    case when p_sort_by = 'roas' and p_sort_dir = 'desc' then c.roas end desc nulls last,
    case when p_sort_by = 'roas' and p_sort_dir = 'asc' then c.roas end asc nulls last,
    case when p_sort_by = 'video_views' and p_sort_dir = 'desc' then c.video_views end desc nulls last,
    case when p_sort_by = 'video_views' and p_sort_dir = 'asc' then c.video_views end asc nulls last,
    case when p_sort_by = 'spend' and p_sort_dir = 'desc' then c.spend end desc nulls last,
    case when p_sort_by = 'spend' and p_sort_dir = 'asc' then c.spend end asc nulls last
  limit p_limit
  offset p_offset;
end;
$$ language plpgsql stable security definer;

-- ===========================================
-- 5. Update denormalized metrics on creatives
-- ===========================================
-- After daily metrics are synced, update the denormalized columns
-- on the creatives table with the latest snapshot.

create or replace function public.update_creative_denormalized_metrics(
  p_creative_id uuid
)
returns void as $$
begin
  update public.creatives c
  set
    reach = latest.reach,
    impressions = latest.impressions,
    video_views = latest.video_views,
    likes = latest.likes,
    comments = latest.comments,
    shares = latest.shares,
    saves = latest.saves,
    clicks = latest.clicks,
    engagement_rate = latest.engagement_rate,
    spend = latest.spend,
    revenue = latest.revenue,
    roas = latest.roas,
    ctr = latest.ctr,
    cpm = latest.cpm,
    cpc = latest.cpc,
    updated_at = now()
  from (
    select *
    from public.performance_metrics pm
    where pm.creative_id = p_creative_id
    order by pm.metric_date desc
    limit 1
  ) latest
  where c.id = p_creative_id;
end;
$$ language plpgsql security definer;

-- ===========================================
-- 6. Trigger: auto-update creative after metric insert
-- ===========================================

create or replace function public.trg_update_creative_on_metric_insert()
returns trigger as $$
begin
  perform public.update_creative_denormalized_metrics(new.creative_id);
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_metric_insert_update_creative
  after insert on public.performance_metrics
  for each row execute function public.trg_update_creative_on_metric_insert();

-- ===========================================
-- 7. AFI Admin: Top Creatives Across Network
-- ===========================================

create or replace function public.get_top_creatives_network(
  p_platform public.sub_platform default null,
  p_channel public.channel_type default null,
  p_sort_by text default 'engagement_rate',
  p_limit integer default 100
)
returns table (
  id uuid,
  org_id uuid,
  store_name text,
  platform public.sub_platform,
  channel public.channel_type,
  title text,
  thumbnail_path text,
  reach bigint,
  video_views bigint,
  engagement_rate numeric,
  spend numeric,
  roas numeric,
  published_at timestamptz
) as $$
begin
  -- This function is only useful for AFI admins; RLS on creatives
  -- already enforces this, but we add an explicit check
  if not public.is_afi_admin() then
    raise exception 'Access denied: AFI admin role required';
  end if;

  return query
  select
    c.id,
    c.org_id,
    o.name as store_name,
    c.platform,
    c.channel,
    c.title,
    c.thumbnail_path,
    c.reach,
    c.video_views,
    c.engagement_rate,
    c.spend,
    c.roas,
    c.published_at
  from public.creatives c
  join public.organizations o on o.id = c.org_id
  where c.is_active = true
    and (p_platform is null or c.platform = p_platform)
    and (p_channel is null or c.channel = p_channel)
  order by
    case when p_sort_by = 'engagement_rate' then c.engagement_rate end desc nulls last,
    case when p_sort_by = 'reach' then c.reach end desc nulls last,
    case when p_sort_by = 'roas' then c.roas end desc nulls last,
    case when p_sort_by = 'video_views' then c.video_views end desc nulls last
  limit p_limit;
end;
$$ language plpgsql stable security definer;

-- ===========================================
-- 8. Utility: Get connections needing token refresh
-- ===========================================
-- Called by the token-refresh cron Edge Function.

create or replace function public.get_expiring_connections(
  p_buffer_minutes integer default 30
)
returns table (
  connection_id uuid,
  org_id uuid,
  platform public.platform_type,
  token_expires_at timestamptz
) as $$
begin
  return query
  select
    pc.id as connection_id,
    pc.org_id,
    pc.platform,
    pc.token_expires_at
  from public.platform_connections pc
  where pc.status = 'active'
    and pc.token_expires_at is not null
    and pc.token_expires_at <= now() + (p_buffer_minutes || ' minutes')::interval
  order by pc.token_expires_at asc;
end;
$$ language plpgsql stable security definer;

-- Restrict this function to service_role only
revoke execute on function public.get_expiring_connections(integer) from public, anon, authenticated;

-- ===========================================
-- 9. Utility: Get connections due for sync
-- ===========================================
-- Returns connections that haven't been synced within the specified interval.

create or replace function public.get_connections_due_for_sync(
  p_sync_interval_hours integer default 6
)
returns table (
  connection_id uuid,
  org_id uuid,
  platform public.platform_type,
  platform_account_id text,
  last_sync_at timestamptz
) as $$
begin
  return query
  select
    pc.id as connection_id,
    pc.org_id,
    pc.platform,
    pc.platform_account_id,
    pc.last_sync_at
  from public.platform_connections pc
  where pc.status = 'active'
    and (
      pc.last_sync_at is null
      or pc.last_sync_at < now() - (p_sync_interval_hours || ' hours')::interval
    )
  order by pc.last_sync_at asc nulls first;
end;
$$ language plpgsql stable security definer;

-- Restrict to service_role
revoke execute on function public.get_connections_due_for_sync(integer) from public, anon, authenticated;
