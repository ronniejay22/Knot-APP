-- Migration: Create Partner Interests Table
-- Step 1.3: Create Interests Table
--
-- Creates the partner_interests table for storing partner likes and dislikes.
-- Each vault has exactly 5 likes and 5 dislikes (enforced at application layer).
-- An interest cannot appear as both a like AND a dislike for the same vault
-- (enforced by UNIQUE constraint on vault_id + interest_category).
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on interest_type (like, dislike)
--   - CHECK constraint on interest_category (40 predefined values)
--   - UNIQUE constraint on (vault_id, interest_category) prevents duplicates
--   - Foreign key to partner_vaults with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the partner_interests table
-- ============================================================
CREATE TABLE public.partner_interests (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id           UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    interest_type      TEXT NOT NULL CHECK (interest_type IN ('like', 'dislike')),
    interest_category  TEXT NOT NULL CHECK (interest_category IN (
        'Travel', 'Cooking', 'Movies', 'Music', 'Reading',
        'Sports', 'Gaming', 'Art', 'Photography', 'Fitness',
        'Fashion', 'Technology', 'Nature', 'Food', 'Coffee',
        'Wine', 'Dancing', 'Theater', 'Concerts', 'Museums',
        'Shopping', 'Yoga', 'Hiking', 'Beach', 'Pets',
        'Cars', 'DIY', 'Gardening', 'Meditation', 'Podcasts',
        'Baking', 'Camping', 'Cycling', 'Running', 'Swimming',
        'Skiing', 'Surfing', 'Painting', 'Board Games', 'Karaoke'
    )),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Prevent the same interest_category from appearing twice for the same vault.
    -- This also prevents an interest from being both a like AND a dislike.
    UNIQUE (vault_id, interest_category)
);

COMMENT ON TABLE public.partner_interests IS 'Partner interest likes and dislikes. Each vault has exactly 5 likes and 5 dislikes (enforced at API layer).';
COMMENT ON COLUMN public.partner_interests.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_interests.vault_id IS 'References partner_vaults(id). CASCADE deletes interests when vault is deleted.';
COMMENT ON COLUMN public.partner_interests.interest_type IS 'like | dislike';
COMMENT ON COLUMN public.partner_interests.interest_category IS 'Must be from the predefined list of 40 categories';
COMMENT ON COLUMN public.partner_interests.created_at IS 'Timestamp when the interest was recorded';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_interests ENABLE ROW LEVEL SECURITY;

-- Users can SELECT interests for their own vault only
CREATE POLICY "interests_select_own"
    ON public.partner_interests FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT interests for their own vault only
CREATE POLICY "interests_insert_own"
    ON public.partner_interests FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE interests for their own vault only
CREATE POLICY "interests_update_own"
    ON public.partner_interests FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE interests for their own vault only
CREATE POLICY "interests_delete_own"
    ON public.partner_interests FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_interests.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own interests (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_interests TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_interests TO anon;

-- ============================================================
-- 4. Create index on vault_id for fast lookups
-- ============================================================
-- The UNIQUE constraint on (vault_id, interest_category) already creates
-- a composite index. We add a separate index on vault_id alone for
-- queries that filter only by vault_id (e.g., "get all interests for a vault").
CREATE INDEX idx_partner_interests_vault_id
    ON public.partner_interests (vault_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_interests'
ORDER BY ordinal_position;
