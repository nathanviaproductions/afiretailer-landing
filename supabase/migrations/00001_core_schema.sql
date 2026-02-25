-- ============================================================================
-- AFI Retailer Social Media Dashboard
-- Migration 00001: Core Schema - Extensions, Enums, Organizations, Users
-- ============================================================================
-- This migration sets up the foundational tables for the multi-tenant
-- Ashley Furniture retailer dashboard. Each store (organization) operates
-- as an isolated tenant with its own users and data.
-- ============================================================================

-- ===========================================
-- 1. Required Extensions
-- ===========================================

-- UUID generation for primary keys
create extension if not exists "uuid-ossp" schema extensions;

-- Cryptographic functions for token encryption at rest
create extension if not exists "pgcrypto" schema extensions;

-- pg_cron for scheduled data sync jobs (Supabase has this pre-installed)
-- create extension if not exists "pg_cron";

-- pg_net for making HTTP requests from database functions (Supabase pre-installed)
-- create extension if not exists "pg_net";

-- ===========================================
-- 2. Custom Enum Types
-- ===========================================

-- User roles within the system
create type public.user_role as enum (
  'store_owner',     -- Full access to their store; can manage connections
  'store_manager',   -- Read access to their store's dashboard; no OAuth management
  'afi_admin'        -- AFI corporate admin; read access across ALL stores
);

-- Social media platforms supported
create type public.platform_type as enum (
  'meta',            -- Facebook + Instagram combined OAuth
  'youtube',         -- YouTube via Google OAuth
  'google_business'  -- Google Business Profile via Google OAuth
);

-- Sub-platform identifiers (a single Meta connection yields FB + IG data)
create type public.sub_platform as enum (
  'facebook',
  'instagram',
  'youtube',
  'google_business'
);

-- Content channel classification
create type public.channel_type as enum (
  'paid',            -- Paid ads / promoted content
  'organic'          -- Organic posts / unpromoted content
);

-- Connection health status
create type public.connection_status as enum (
  'active',          -- Token valid, data syncing normally
  'token_expired',   -- Token needs refresh; auto-retry in progress
  'refresh_failed',  -- Refresh attempts exhausted; user must re-authorize
  'disconnected',    -- User manually disconnected
  'pending'          -- OAuth flow initiated but not completed
);

-- Creative content types
create type public.content_type as enum (
  'image',
  'video',
  'carousel',
  'story',
  'reel',
  'text',
  'link',
  'short',           -- YouTube Shorts
  'live',
  'update'           -- Google Business update
);

-- Sync job status
create type public.sync_status as enum (
  'pending',
  'running',
  'completed',
  'failed',
  'rate_limited'
);

-- ===========================================
-- 3. Organizations (Stores)
-- ===========================================
-- Each Ashley Furniture retail licensee location is an "organization."
-- A single licensee group may own multiple stores.

create table public.organizations (
  id             uuid primary key default uuid_generate_v4(),
  name           text not null,                            -- e.g. "Ashley HomeStore - Tampa"
  slug           text not null unique,                     -- URL-safe identifier: "ashley-tampa"
  licensee_group text,                                     -- Groups stores under same owner, e.g. "Southeast Furniture LLC"
  address_line1  text,
  address_line2  text,
  city           text,
  state          text,                                     -- US state abbreviation
  zip            text,
  phone          text,
  timezone       text not null default 'America/New_York', -- Store's local timezone
  is_active      boolean not null default true,
  metadata       jsonb default '{}',                       -- Flexible key-value for future fields
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.organizations is
  'Ashley Furniture retail licensee stores. Each store is an isolated tenant.';

-- ===========================================
-- 4. Users
-- ===========================================
-- Links Supabase Auth users to their organization and role.
-- A user belongs to exactly one organization (store).
-- AFI admins have org_id = NULL (they see everything).

create table public.users (
  id             uuid primary key references auth.users(id) on delete cascade,
  org_id         uuid references public.organizations(id) on delete set null,
  role           public.user_role not null default 'store_manager',
  full_name      text,
  email          text not null,
  avatar_url     text,
  is_active      boolean not null default true,
  last_sign_in   timestamptz,
  metadata       jsonb default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

comment on table public.users is
  'Application user profiles linked to Supabase Auth. Each user belongs to one store or is an AFI admin.';

-- ===========================================
-- 5. Auto-update timestamps trigger
-- ===========================================

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_organizations_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

create trigger trg_users_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- ===========================================
-- 6. Auto-create user profile on signup
-- ===========================================
-- When a user signs up via Supabase Auth, automatically create a row
-- in public.users using metadata from the auth.users record.

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, full_name, role, org_id)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'store_manager'),
    (new.raw_user_meta_data->>'org_id')::uuid
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
