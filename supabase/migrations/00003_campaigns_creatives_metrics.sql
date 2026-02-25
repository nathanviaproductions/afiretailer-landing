-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00003: Campaigns, Creatives, and Performance Metrics
-- ============================================================================
-- Core content and metrics tables. Creatives represent individual posts,
-- ads, or videos. Performance metrics are daily snapshots enabling
-- time-series trend analysis. Campaigns group related creatives.
-- ============================================================================

-- ===========================================
-- 1. Campaigns
-- ===========================================
-- Optional grouping of creatives into campaigns. Maps to ad campaigns
-- on paid platforms or manual groupings for organic content.

create table public.campaigns (
  id               uuid primary key default uuid_generate_v4(),
  org_id           uuid not null references public.organizations(id) on delete cascade,
  platform         public.platform_type not null,
  platform_campaign_id text,          -- Native campaign ID from the platform API
  name             text not null,
  description      text,
  channel          public.channel_type not null default 'paid',
  status           text default 'active',  -- active, paused, completed, archived
  budget_total     numeric(12,2),     -- Total campaign budget in USD
  budget_daily     numeric(12,2),     -- Daily budget cap in USD
  start_date       date,
  end_date         date,
  metadata         jsonb default '{}',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  -- Prevent duplicate imports of the same platform campaign
  unique (org_id, platform, platform_campaign_id)
);

comment on table public.campaigns is
  'Campaigns group related creatives. Maps to ad campaigns on paid platforms.';

-- ===========================================
-- 2. Creatives (Content)
-- ===========================================
-- Individual pieces of content: a Facebook post, Instagram reel, YouTube
-- video, etc. This is the core entity displayed in the Creative
-- Performance grid on the dashboard.

create table public.creatives (
  id                  uuid primary key default uuid_generate_v4(),
  org_id              uuid not null references public.organizations(id) on delete cascade,
  campaign_id         uuid references public.campaigns(id) on delete set null,
  connection_id       uuid references public.platform_connections(id) on delete set null,

  -- Platform identification
  platform            public.sub_platform not null,   -- facebook, instagram, youtube, google_business
  platform_content_id text,                            -- Native post/ad/video ID from platform API
  channel             public.channel_type not null,    -- paid or organic
  content_type        public.content_type not null default 'image',

  -- Content details
  title               text,                            -- Post text, ad headline, or video title
  description         text,                            -- Extended description / body text
  permalink           text,                            -- Direct link to the content on the platform
  thumbnail_path      text,                            -- Path in Supabase Storage bucket

  -- Denormalized latest metrics (updated by the daily sync process)
  -- Kept here for fast single-query reads on the creative grid
  reach               bigint not null default 0,
  impressions         bigint not null default 0,
  video_views         bigint not null default 0,
  likes               bigint not null default 0,
  comments            bigint not null default 0,
  shares              bigint not null default 0,
  saves               bigint not null default 0,
  clicks              bigint not null default 0,
  engagement_rate     numeric(6,3) not null default 0, -- Percentage: 4.7 = 4.7%
  spend               numeric(12,2) not null default 0,
  revenue             numeric(12,2) not null default 0,
  roas                numeric(8,2) not null default 0, -- spend > 0 ? revenue / spend : 0
  ctr                 numeric(6,3) not null default 0, -- click-through rate %
  cpm                 numeric(10,2) not null default 0, -- cost per 1000 impressions
  cpc                 numeric(10,2) not null default 0, -- cost per click

  -- Content lifecycle
  published_at        timestamptz,
  is_active           boolean not null default true,
  metadata            jsonb default '{}',              -- Platform-specific extra fields
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- Prevent duplicate imports
  unique (org_id, platform, platform_content_id)
);

comment on table public.creatives is
  'Individual social media posts, ads, and videos. Core entity for the Creative Performance grid.';

-- ===========================================
-- 3. Performance Metrics (Daily Snapshots)
-- ===========================================
-- One row per creative per day. This is the time-series data that powers
-- the "Performance Over Time" chart and enables trend analysis.
-- New snapshots are inserted daily by the sync process.

create table public.performance_metrics (
  id              uuid primary key default uuid_generate_v4(),
  creative_id     uuid not null references public.creatives(id) on delete cascade,
  org_id          uuid not null references public.organizations(id) on delete cascade,
  platform        public.sub_platform not null,
  channel         public.channel_type not null,
  metric_date     date not null,       -- The day this snapshot represents

  -- Engagement metrics (cumulative totals as of metric_date)
  reach           bigint not null default 0,
  impressions     bigint not null default 0,
  video_views     bigint not null default 0,
  likes           bigint not null default 0,
  comments        bigint not null default 0,
  shares          bigint not null default 0,
  saves           bigint not null default 0,
  clicks          bigint not null default 0,
  engagement_rate numeric(6,3) not null default 0,

  -- Paid metrics
  spend           numeric(12,2) not null default 0,
  revenue         numeric(12,2) not null default 0,
  roas            numeric(8,2) not null default 0,
  ctr             numeric(6,3) not null default 0,
  cpm             numeric(10,2) not null default 0,
  cpc             numeric(10,2) not null default 0,
  conversions     integer not null default 0,
  cost_per_conversion numeric(10,2) not null default 0,

  -- Platform-specific extended metrics stored as JSON
  -- e.g. YouTube: watch_time_minutes, avg_view_duration, subscriber_change
  -- e.g. Meta: frequency, estimated_ad_recall_lift
  -- e.g. GBP: direction_requests, phone_calls, website_visits
  extended_metrics jsonb default '{}',

  created_at      timestamptz not null default now(),

  -- One snapshot per creative per day
  unique (creative_id, metric_date)
);

comment on table public.performance_metrics is
  'Daily performance snapshots per creative. Powers time-series charts and trend analysis.';

-- ===========================================
-- 4. Triggers
-- ===========================================

create trigger trg_campaigns_updated_at
  before update on public.campaigns
  for each row execute function public.set_updated_at();

create trigger trg_creatives_updated_at
  before update on public.creatives
  for each row execute function public.set_updated_at();
