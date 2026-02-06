-- Migration: Create Partner Vibes Table
-- Step 1.5: Create Aesthetic Vibes Table
--
-- Creates the partner_vibes table for storing partner aesthetic vibe tags
-- (quiet_luxury, street_urban, outdoorsy, vintage, minimalist, bohemian,
-- romantic, adventurous).
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on vibe_tag (8 valid values)
--   - UNIQUE constraint on (vault_id, vibe_tag) prevents duplicate vibes
--   - Foreign key to partner_vaults with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the partner_vibes table
-- ============================================================
CREATE TABLE public.partner_vibes (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id    UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    vibe_tag    TEXT NOT NULL CHECK (vibe_tag IN (
        'quiet_luxury', 'street_urban', 'outdoorsy', 'vintage',
        'minimalist', 'bohemian', 'romantic', 'adventurous'
    )),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Prevent the same vibe_tag from appearing twice for the same vault.
    UNIQUE (vault_id, vibe_tag)
);

COMMENT ON TABLE public.partner_vibes IS 'Partner aesthetic vibe tags. Each vault can have 1-4 vibes (enforced at API layer). UNIQUE constraint prevents duplicate vibes per vault.';
COMMENT ON COLUMN public.partner_vibes.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_vibes.vault_id IS 'References partner_vaults(id). CASCADE deletes vibes when vault is deleted.';
COMMENT ON COLUMN public.partner_vibes.vibe_tag IS 'quiet_luxury | street_urban | outdoorsy | vintage | minimalist | bohemian | romantic | adventurous';
COMMENT ON COLUMN public.partner_vibes.created_at IS 'Timestamp when the vibe was recorded';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_vibes ENABLE ROW LEVEL SECURITY;

-- Users can SELECT vibes for their own vault only
CREATE POLICY "vibes_select_own"
    ON public.partner_vibes FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_vibes.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT vibes for their own vault only
CREATE POLICY "vibes_insert_own"
    ON public.partner_vibes FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_vibes.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE vibes for their own vault only
CREATE POLICY "vibes_update_own"
    ON public.partner_vibes FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_vibes.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_vibes.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE vibes for their own vault only
CREATE POLICY "vibes_delete_own"
    ON public.partner_vibes FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_vibes.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own vibes (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_vibes TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_vibes TO anon;

-- ============================================================
-- 4. Create index on vault_id for fast lookups
-- ============================================================
-- The UNIQUE constraint on (vault_id, vibe_tag) already creates
-- a composite index. We add a separate index on vault_id alone for
-- queries that filter only by vault_id (e.g., "get all vibes for a vault").
CREATE INDEX idx_partner_vibes_vault_id
    ON public.partner_vibes (vault_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_vibes'
ORDER BY ordinal_position;
