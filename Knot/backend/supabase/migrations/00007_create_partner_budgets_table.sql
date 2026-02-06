-- Migration: Create Partner Budgets Table
-- Step 1.6: Create Budget Tiers Table
--
-- Creates the partner_budgets table for storing partner budget tiers
-- per occasion type (just_because, minor_occasion, major_milestone).
-- Amounts are stored in cents (integers) to avoid floating-point issues.
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on occasion_type (3 valid values)
--   - CHECK constraint enforcing max_amount >= min_amount
--   - CHECK constraint enforcing min_amount >= 0
--   - UNIQUE constraint on (vault_id, occasion_type) — one budget per occasion type per vault
--   - Foreign key to partner_vaults with CASCADE delete
--   - Currency defaults to 'USD'
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the partner_budgets table
-- ============================================================
CREATE TABLE public.partner_budgets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id        UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    occasion_type   TEXT NOT NULL CHECK (occasion_type IN (
        'just_because', 'minor_occasion', 'major_milestone'
    )),
    min_amount      INTEGER NOT NULL CHECK (min_amount >= 0),
    max_amount      INTEGER NOT NULL CHECK (max_amount >= 0),
    currency        TEXT NOT NULL DEFAULT 'USD',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Each vault should have at most one budget per occasion type.
    UNIQUE (vault_id, occasion_type),

    -- Ensure max_amount is always >= min_amount.
    CHECK (max_amount >= min_amount)
);

COMMENT ON TABLE public.partner_budgets IS 'Partner budget tiers by occasion type. Each vault has one budget per occasion type (just_because, minor_occasion, major_milestone). Amounts in cents.';
COMMENT ON COLUMN public.partner_budgets.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_budgets.vault_id IS 'References partner_vaults(id). CASCADE deletes budgets when vault is deleted.';
COMMENT ON COLUMN public.partner_budgets.occasion_type IS 'just_because | minor_occasion | major_milestone';
COMMENT ON COLUMN public.partner_budgets.min_amount IS 'Minimum budget amount in cents (e.g., 2000 = $20.00)';
COMMENT ON COLUMN public.partner_budgets.max_amount IS 'Maximum budget amount in cents (e.g., 5000 = $50.00). Must be >= min_amount.';
COMMENT ON COLUMN public.partner_budgets.currency IS 'ISO 4217 currency code (default USD). Supports international users.';
COMMENT ON COLUMN public.partner_budgets.created_at IS 'Timestamp when the budget was recorded';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_budgets ENABLE ROW LEVEL SECURITY;

-- Users can SELECT budgets for their own vault only
CREATE POLICY "budgets_select_own"
    ON public.partner_budgets FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_budgets.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT budgets for their own vault only
CREATE POLICY "budgets_insert_own"
    ON public.partner_budgets FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_budgets.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE budgets for their own vault only
CREATE POLICY "budgets_update_own"
    ON public.partner_budgets FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_budgets.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_budgets.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE budgets for their own vault only
CREATE POLICY "budgets_delete_own"
    ON public.partner_budgets FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_budgets.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own budgets (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_budgets TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_budgets TO anon;

-- ============================================================
-- 4. Create index on vault_id for fast lookups
-- ============================================================
-- The UNIQUE constraint on (vault_id, occasion_type) already creates
-- a composite index. We add a separate index on vault_id alone for
-- queries that filter only by vault_id (e.g., "get all budgets for a vault").
CREATE INDEX idx_partner_budgets_vault_id
    ON public.partner_budgets (vault_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_budgets'
ORDER BY ordinal_position;
