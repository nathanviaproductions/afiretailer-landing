-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00008: Storage Buckets, Realtime, and Cron Jobs
-- ============================================================================
-- Sets up Supabase Storage for creative thumbnails, enables Realtime
-- subscriptions for live dashboard updates, and configures pg_cron
-- scheduled jobs for automated data syncing.
-- ============================================================================

-- ===========================================
-- 1. Storage Bucket: Creative Thumbnails
-- ===========================================
-- Stores thumbnail images downloaded from platform APIs.
-- Public read access (thumbnails are shown in the dashboard).
-- Only service_role can upload (during sync process).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'creative-thumbnails',
  'creative-thumbnails',
  true,                              -- Public read access
  5242880,                           -- 5MB max file size
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do nothing;

-- Storage policy: anyone can read thumbnails (they're public)
create policy "Public read access for thumbnails"
  on storage.objects for select
  using (bucket_id = 'creative-thumbnails');

-- Storage policy: only service_role can upload
-- (service_role bypasses RLS, but we add this for documentation clarity)
create policy "Service role uploads thumbnails"
  on storage.objects for insert
  to service_role
  with check (bucket_id = 'creative-thumbnails');

create policy "Service role updates thumbnails"
  on storage.objects for update
  to service_role
  using (bucket_id = 'creative-thumbnails');

create policy "Service role deletes thumbnails"
  on storage.objects for delete
  to service_role
  using (bucket_id = 'creative-thumbnails');

-- ===========================================
-- 2. Storage Bucket: Organization Logos
-- ===========================================
-- Optional bucket for store logos/branding shown in the dashboard.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'org-assets',
  'org-assets',
  true,
  2097152,                           -- 2MB max
  array['image/jpeg', 'image/png', 'image/svg+xml', 'image/webp']
)
on conflict (id) do nothing;

create policy "Public read for org assets"
  on storage.objects for select
  using (bucket_id = 'org-assets');

create policy "Store owners upload org assets"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'org-assets'
    and (storage.foldername(name))[1] = public.current_user_org_id()::text
  );

-- ===========================================
-- 3. Realtime Configuration
-- ===========================================
-- Enable Supabase Realtime on specific tables so the dashboard can
-- show live updates when new data arrives from sync processes.

-- Note: In Supabase, realtime is enabled per-table via the dashboard or
-- by adding the table to the supabase_realtime publication.

-- We add the key tables that the dashboard subscribes to:
alter publication supabase_realtime add table public.creatives;
alter publication supabase_realtime add table public.kpi_daily_rollup;
alter publication supabase_realtime add table public.platform_connections;

-- ===========================================
-- 4. Cron Jobs (via pg_cron)
-- ===========================================
-- These jobs run on the database server at scheduled intervals.
-- They call Edge Functions via pg_net HTTP requests.
--
-- IMPORTANT: pg_cron and pg_net must be enabled in your Supabase project.
-- Go to Database > Extensions and enable both.
--
-- The SUPABASE_URL and SERVICE_ROLE_KEY below should be replaced with
-- your actual project values, or better yet, use Supabase Vault secrets.

-- Job 1: Refresh expiring OAuth tokens every 15 minutes
-- Calls the token-refresh Edge Function
select cron.schedule(
  'refresh-oauth-tokens',           -- job name
  '*/15 * * * *',                   -- every 15 minutes
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/refresh-tokens',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Job 2: Sync Meta (Facebook + Instagram) data every 4 hours
select cron.schedule(
  'sync-meta-data',
  '0 */4 * * *',                    -- every 4 hours at :00
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/sync-platform-data',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{"platform": "meta"}'::jsonb
  );
  $$
);

-- Job 3: Sync YouTube data every 6 hours
select cron.schedule(
  'sync-youtube-data',
  '30 */6 * * *',                   -- every 6 hours at :30
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/sync-platform-data',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{"platform": "youtube"}'::jsonb
  );
  $$
);

-- Job 4: Sync Google Business Profile data every 12 hours
select cron.schedule(
  'sync-gbp-data',
  '0 6,18 * * *',                   -- twice daily at 6 AM and 6 PM
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/sync-platform-data',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{"platform": "google_business"}'::jsonb
  );
  $$
);

-- Job 5: Compute daily KPI rollups at 2 AM (after all syncs complete)
select cron.schedule(
  'compute-daily-rollups',
  '0 2 * * *',                      -- daily at 2 AM UTC
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/compute-rollups',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- Job 6: Clean up old sync logs (keep 90 days)
select cron.schedule(
  'cleanup-sync-logs',
  '0 3 * * 0',                      -- weekly on Sunday at 3 AM
  $$
  delete from public.sync_log
  where started_at < now() - interval '90 days';
  $$
);
