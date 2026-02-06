-- Migration: Create Recommendations History Table
-- Step 1.9: Create Recommendations History Table
--
-- Creates the recommendations table for storing AI-generated gift, experience,
-- and date recommendations. Each recommendation is tied to a partner vault
-- and optionally linked to a milestone (birthday, anniversary, etc.).
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on recommendation_type ('gift', 'experience', 'date')
--   - CHECK constraint on price_cents (>= 0, amounts in cents)
--   - Nullable milestone_id FK (recommendations can exist without a milestone)
--   - Foreign key to partner_vaults with CASCADE delete
--   - Foreign key to partner_milestones with SET NULL on delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)
--   - Step 1.4: Partner Milestones table created (00005_create_partner_milestones_table.sql)

-- ============================================================
-- 1. Create the recommendations table
-- ============================================================
CREATE TABLE public.recommendations (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id             UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    milestone_id         UUID REFERENCES public.partner_milestones(id) ON DELETE SET NULL,
    recommendation_type  TEXT NOT NULL CHECK (recommendation_type IN ('gift', 'experience', 'date')),
    title                TEXT NOT NULL,
    description          TEXT,
    external_url         TEXT,
    price_cents          INTEGER CHECK (price_cents >= 0),
    merchant_name        TEXT,
    image_url            TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.recommendations IS 'AI-generated recommendations (gifts, experiences, dates). Linked to partner vaults and optionally to milestones.';
COMMENT ON COLUMN public.recommendations.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.recommendations.vault_id IS 'References partner_vaults(id). CASCADE deletes recommendations when vault is deleted.';
COMMENT ON COLUMN public.recommendations.milestone_id IS 'Optional reference to partner_milestones(id). SET NULL when milestone is deleted (recommendation persists for history).';
COMMENT ON COLUMN public.recommendations.recommendation_type IS 'gift | experience | date — the category of this recommendation';
COMMENT ON COLUMN public.recommendations.title IS 'Display title for the recommendation (e.g., "Ceramic Pottery Class for Two")';
COMMENT ON COLUMN public.recommendations.description IS 'Short description of the recommendation (optional, shown on card)';
COMMENT ON COLUMN public.recommendations.external_url IS 'URL to the merchant/booking page for the recommendation';
COMMENT ON COLUMN public.recommendations.price_cents IS 'Price in cents (e.g., 4999 = $49.99). NULL if price is unknown. Must be >= 0.';
COMMENT ON COLUMN public.recommendations.merchant_name IS 'Name of the merchant or venue (e.g., "Amazon", "Yelp", "Ticketmaster")';
COMMENT ON COLUMN public.recommendations.image_url IS 'URL to the hero image displayed on the recommendation card';
COMMENT ON COLUMN public.recommendations.created_at IS 'Timestamp when the recommendation was generated';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;

-- Users can SELECT recommendations for their own vault only
CREATE POLICY "recommendations_select_own"
    ON public.recommendations FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = recommendations.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT recommendations for their own vault only
CREATE POLICY "recommendations_insert_own"
    ON public.recommendations FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = recommendations.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE recommendations for their own vault only
CREATE POLICY "recommendations_update_own"
    ON public.recommendations FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = recommendations.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = recommendations.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE recommendations for their own vault only
CREATE POLICY "recommendations_delete_own"
    ON public.recommendations FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = recommendations.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own recommendations (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.recommendations TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.recommendations TO anon;

-- ============================================================
-- 4. Create indexes for fast lookups
-- ============================================================
-- Index on vault_id for querying recommendations by vault
CREATE INDEX idx_recommendations_vault_id
    ON public.recommendations (vault_id);

-- Index on milestone_id for querying recommendations by milestone
CREATE INDEX idx_recommendations_milestone_id
    ON public.recommendations (milestone_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'recommendations'
ORDER BY ordinal_position;
