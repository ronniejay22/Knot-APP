-- Migration: Create Partner Vaults Table
-- Step 1.2: Create Partner Vault Table
--
-- Creates the partner_vaults table for storing partner profile data.
-- Each user has exactly one vault (user_id is UNIQUE).
--
-- Features:
--   - Row Level Security (RLS) so users can only access their own vault
--   - CHECK constraint on cohabitation_status enum values
--   - Reuses handle_updated_at() trigger from Step 1.1
--   - Foreign key to public.users with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.1: Users table created (00002_create_users_table.sql)

-- ============================================================
-- 1. Create the partner_vaults table
-- ============================================================
CREATE TABLE public.partner_vaults (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    partner_name                TEXT NOT NULL,
    relationship_tenure_months  INTEGER,
    cohabitation_status         TEXT CHECK (cohabitation_status IN ('living_together', 'separate', 'long_distance')),
    location_city               TEXT,
    location_state              TEXT,
    location_country            TEXT DEFAULT 'US',
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.partner_vaults IS 'Partner profile vaults — one per user. Stores partner basic info and location.';
COMMENT ON COLUMN public.partner_vaults.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_vaults.user_id IS 'References public.users(id). UNIQUE ensures one vault per user.';
COMMENT ON COLUMN public.partner_vaults.partner_name IS 'Partner display name (required)';
COMMENT ON COLUMN public.partner_vaults.relationship_tenure_months IS 'How long in the relationship, in months';
COMMENT ON COLUMN public.partner_vaults.cohabitation_status IS 'living_together | separate | long_distance';
COMMENT ON COLUMN public.partner_vaults.location_city IS 'City where the partner lives (used for location-aware recommendations)';
COMMENT ON COLUMN public.partner_vaults.location_state IS 'State/province where the partner lives';
COMMENT ON COLUMN public.partner_vaults.location_country IS 'Country code (default US). Supports international users.';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_vaults ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own vault only
CREATE POLICY "vaults_select_own"
    ON public.partner_vaults FOR SELECT
    USING (auth.uid() = user_id);

-- Users can INSERT their own vault only
CREATE POLICY "vaults_insert_own"
    ON public.partner_vaults FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can UPDATE their own vault only
CREATE POLICY "vaults_update_own"
    ON public.partner_vaults FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can DELETE their own vault only
CREATE POLICY "vaults_delete_own"
    ON public.partner_vaults FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================
-- 3. Reuse handle_updated_at trigger from Step 1.1
-- ============================================================
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.partner_vaults
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================
-- 4. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own vault (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_vaults TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_vaults TO anon;

-- ============================================================
-- 5. Create index on user_id for fast lookups
-- ============================================================
-- Note: UNIQUE constraint already creates an implicit unique index on user_id.
-- No additional index needed.

-- ============================================================
-- 6. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_vaults'
ORDER BY ordinal_position;
