-- Migration: Create Partner Love Languages Table
-- Step 1.7: Create Love Languages Table
--
-- Creates the partner_love_languages table for storing a partner's
-- primary and secondary love languages.
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on language (5 valid values)
--   - CHECK constraint on priority (1 = primary, 2 = secondary)
--   - UNIQUE constraint on (vault_id, priority) — one primary and one secondary per vault
--   - UNIQUE constraint on (vault_id, language) — same language cannot be both primary and secondary
--   - Foreign key to partner_vaults with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the partner_love_languages table
-- ============================================================
CREATE TABLE public.partner_love_languages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id        UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    language        TEXT NOT NULL CHECK (language IN (
        'words_of_affirmation', 'acts_of_service', 'receiving_gifts',
        'quality_time', 'physical_touch'
    )),
    priority        INTEGER NOT NULL CHECK (priority IN (1, 2)),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Each vault should have at most one primary (1) and one secondary (2).
    UNIQUE (vault_id, priority),

    -- A language cannot be both primary and secondary for the same vault.
    UNIQUE (vault_id, language)
);

COMMENT ON TABLE public.partner_love_languages IS 'Partner love languages. Each vault has exactly one primary (priority=1) and one secondary (priority=2) love language.';
COMMENT ON COLUMN public.partner_love_languages.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_love_languages.vault_id IS 'References partner_vaults(id). CASCADE deletes love languages when vault is deleted.';
COMMENT ON COLUMN public.partner_love_languages.language IS 'words_of_affirmation | acts_of_service | receiving_gifts | quality_time | physical_touch';
COMMENT ON COLUMN public.partner_love_languages.priority IS '1 = primary love language, 2 = secondary love language';
COMMENT ON COLUMN public.partner_love_languages.created_at IS 'Timestamp when the love language was recorded';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_love_languages ENABLE ROW LEVEL SECURITY;

-- Users can SELECT love languages for their own vault only
CREATE POLICY "love_languages_select_own"
    ON public.partner_love_languages FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_love_languages.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT love languages for their own vault only
CREATE POLICY "love_languages_insert_own"
    ON public.partner_love_languages FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_love_languages.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE love languages for their own vault only
CREATE POLICY "love_languages_update_own"
    ON public.partner_love_languages FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_love_languages.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_love_languages.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE love languages for their own vault only
CREATE POLICY "love_languages_delete_own"
    ON public.partner_love_languages FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_love_languages.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own love languages (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_love_languages TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_love_languages TO anon;

-- ============================================================
-- 4. Create index on vault_id for fast lookups
-- ============================================================
-- The UNIQUE constraints on (vault_id, priority) and (vault_id, language)
-- already create composite indexes. We add a separate index on vault_id
-- alone for queries that filter only by vault_id (e.g., "get all love
-- languages for a vault").
CREATE INDEX idx_partner_love_languages_vault_id
    ON public.partner_love_languages (vault_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_love_languages'
ORDER BY ordinal_position;
