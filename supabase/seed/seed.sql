-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Seed Data: Demo organizations, connections, creatives, and metrics
-- ============================================================================
-- This seed file populates the database with realistic demo data matching
-- the existing dashboard.js mock data. Run after migrations complete.
-- Usage: supabase db reset  (runs migrations + seed automatically)
-- ============================================================================

-- ===========================================
-- 1. Organizations (3 demo stores)
-- ===========================================

insert into public.organizations (id, name, slug, licensee_group, city, state, zip, timezone) values
  ('a1000000-0000-0000-0000-000000000001', 'Ashley HomeStore - Tampa', 'ashley-tampa', 'Southeast Furniture LLC', 'Tampa', 'FL', '33607', 'America/New_York'),
  ('a1000000-0000-0000-0000-000000000002', 'Ashley HomeStore - Orlando', 'ashley-orlando', 'Southeast Furniture LLC', 'Orlando', 'FL', '32801', 'America/New_York'),
  ('a1000000-0000-0000-0000-000000000003', 'Ashley HomeStore - Jacksonville', 'ashley-jacksonville', 'Northeast FL Furniture Inc', 'Jacksonville', 'FL', '32202', 'America/New_York');

-- ===========================================
-- 2. Platform Connections (Tampa store)
-- ===========================================
-- Note: access_token_encrypted / refresh_token_encrypted are left NULL
-- in seed data. Real tokens are stored encrypted via Edge Functions.

insert into public.platform_connections (id, org_id, platform, status, platform_account_id, platform_account_name, connected_at) values
  ('c1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'meta', 'active', 'meta-act-12345', 'Ashley HomeStore Tampa', now() - interval '60 days'),
  ('c1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'youtube', 'active', 'UC_yt_ashley_tampa', 'Ashley HomeStore Tampa', now() - interval '45 days');
  -- Google Business Profile is intentionally NOT connected (matches dashboard.html)

-- ===========================================
-- 3. Campaigns
-- ===========================================

insert into public.campaigns (id, org_id, platform, platform_campaign_id, name, channel, status, budget_daily, start_date, end_date) values
  ('d1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'meta', 'camp_memorial_day', 'Memorial Day Sale 2025', 'paid', 'completed', 50.00, '2025-05-15', '2025-06-01'),
  ('d1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'meta', 'camp_spring_mattress', 'Spring Mattress Event', 'paid', 'active', 75.00, '2025-03-01', '2025-04-30'),
  ('d1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', 'meta', 'camp_outdoor_patio', 'Outdoor Patio Collection', 'paid', 'active', 40.00, '2025-04-01', '2025-06-30');

-- ===========================================
-- 4. Creatives (matches dashboard.js demo data)
-- ===========================================

insert into public.creatives (id, org_id, campaign_id, connection_id, platform, platform_content_id, channel, content_type, title, reach, video_views, likes, engagement_rate, spend, revenue, roas, published_at) values
  -- Facebook Paid
  ('e1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'facebook', 'fb_post_001', 'paid', 'image', 'Memorial Day Sale - Living Room Sets 40% Off', 34200, 12800, 1420, 6.8, 450.00, 3150.00, 7.0, now() - interval '20 days'),
  ('e1000000-0000-0000-0000-000000000004', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'facebook', 'fb_post_004', 'paid', 'video', 'Spring Mattress Event - Save Up To $500', 28100, 9300, 890, 4.2, 620.00, 2850.00, 4.6, now() - interval '35 days'),
  ('e1000000-0000-0000-0000-000000000006', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-000000000001', 'facebook', 'fb_post_006', 'paid', 'carousel', 'Outdoor Patio Furniture - Summer Ready', 22300, 7800, 670, 3.9, 380.00, 1560.00, 4.1, now() - interval '10 days'),
  ('e1000000-0000-0000-0000-00000000000b', 'a1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'facebook', 'fb_post_011', 'paid', 'video', 'Recliner Comfort Test - 30 Day Guarantee', 16700, 5900, 430, 3.4, 310.00, 2200.00, 7.1, now() - interval '25 days'),

  -- Facebook Organic
  ('e1000000-0000-0000-0000-00000000000a', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000001', 'facebook', 'fb_post_010', 'organic', 'image', 'Ashley HomeStore Grand Opening Event', 31200, 4100, 2890, 11.2, 0.00, 0.00, 0.0, now() - interval '5 days'),

  -- Instagram Organic
  ('e1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000001', 'instagram', 'ig_post_002', 'organic', 'reel', 'New Arrivals: Modern Farmhouse Collection', 18900, 8400, 2310, 8.2, 0.00, 0.00, 0.0, now() - interval '12 days'),
  ('e1000000-0000-0000-0000-000000000005', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000001', 'instagram', 'ig_post_005', 'organic', 'video', 'Behind the Scenes: Store Redesign Tour', 12400, 5600, 1890, 9.4, 0.00, 0.00, 0.0, now() - interval '8 days'),
  ('e1000000-0000-0000-0000-00000000000c', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000001', 'instagram', 'ig_post_012', 'organic', 'carousel', 'Interior Design Tips: Small Space Solutions', 21500, 9800, 3200, 10.1, 0.00, 0.00, 0.0, now() - interval '3 days'),

  -- Instagram Paid
  ('e1000000-0000-0000-0000-000000000008', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000001', 'instagram', 'ig_post_008', 'paid', 'image', 'Flash Sale: Dining Sets Starting at $499', 19800, 6100, 1120, 5.6, 520.00, 3900.00, 7.5, now() - interval '15 days'),

  -- YouTube Organic
  ('e1000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000002', 'youtube', 'yt_vid_003', 'organic', 'video', 'Customer Testimonial - The Johnson Family', 8700, 6200, 340, 5.1, 0.00, 0.00, 0.0, now() - interval '30 days'),
  ('e1000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000002', 'youtube', 'yt_vid_007', 'organic', 'video', 'How To Style Your Bedroom On A Budget', 15600, 11200, 890, 7.3, 0.00, 0.00, 0.0, now() - interval '18 days'),

  -- YouTube Paid
  ('e1000000-0000-0000-0000-000000000009', 'a1000000-0000-0000-0000-000000000001', null, 'c1000000-0000-0000-0000-000000000002', 'youtube', 'yt_vid_009', 'paid', 'video', 'Kids Room Makeover Challenge', 9400, 7800, 560, 6.1, 275.00, 980.00, 3.6, now() - interval '22 days');

-- ===========================================
-- 5. Performance Metrics (30 days of daily snapshots)
-- ===========================================
-- Generate realistic daily metrics for each creative.
-- We use generate_series to create 30 days of data with slight daily variation.

-- Helper function for seed data only
create or replace function _seed_metrics()
returns void as $$
declare
  rec record;
  d date;
  day_offset integer;
  growth_factor numeric;
begin
  for rec in select * from public.creatives where org_id = 'a1000000-0000-0000-0000-000000000001' loop
    for day_offset in 0..29 loop
      d := current_date - day_offset;
      -- Simulate gradual growth: newer data has higher cumulative values
      growth_factor := (30.0 - day_offset) / 30.0;

      insert into public.performance_metrics (
        creative_id, org_id, platform, channel, metric_date,
        reach, impressions, video_views, likes, comments, shares, saves, clicks,
        engagement_rate, spend, revenue, roas, ctr, cpm, cpc, conversions
      ) values (
        rec.id,
        rec.org_id,
        rec.platform,
        rec.channel,
        d,
        -- Daily values are a fraction of the cumulative total
        greatest(0, (rec.reach * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.reach * 1.3 * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.video_views * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.likes * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.likes * 0.1 * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.likes * 0.05 * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.likes * 0.03 * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        greatest(0, (rec.reach * 0.02 * growth_factor / 30 * (0.8 + random() * 0.4))::bigint),
        rec.engagement_rate * (0.85 + random() * 0.3),
        rec.spend / 30 * (0.8 + random() * 0.4),
        rec.revenue / 30 * (0.8 + random() * 0.4),
        case when rec.spend > 0 then rec.roas * (0.85 + random() * 0.3) else 0 end,
        case when rec.reach > 0 then (random() * 3 + 1)::numeric(6,3) else 0 end,
        case when rec.spend > 0 then (rec.spend / 30 / greatest(1, rec.reach * 1.3 / 30) * 1000)::numeric(10,2) else 0 end,
        case when rec.spend > 0 then (rec.spend / 30 / greatest(1, rec.reach * 0.02 / 30))::numeric(10,2) else 0 end,
        case when rec.spend > 0 then greatest(0, (rec.revenue / 150 * growth_factor * (0.8 + random() * 0.4))::integer) else 0 end
      )
      on conflict (creative_id, metric_date) do nothing;
    end loop;
  end loop;
end;
$$ language plpgsql;

-- Run the seed function
select _seed_metrics();

-- Clean up the temporary function
drop function _seed_metrics();

-- ===========================================
-- 6. Compute KPI rollups for seeded data
-- ===========================================

-- Compute rollups for each day of seeded data
do $$
declare
  d date;
begin
  for d in select generate_series(current_date - 29, current_date, '1 day')::date loop
    perform public.compute_daily_rollup('a1000000-0000-0000-0000-000000000001', d);
  end loop;
end $$;
