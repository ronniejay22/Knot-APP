-- Migration: Create Partner Milestones Table
-- Step 1.4: Create Milestones Table
--
-- Creates the partner_milestones table for storing partner milestones
-- (birthdays, anniversaries, holidays, custom events).
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on milestone_type (birthday, anniversary, holiday, custom)
--   - CHECK constraint on recurrence (yearly, one_time)
--   - CHECK constraint on budget_tier (just_because, minor_occasion, major_milestone)
--   - Trigger auto-sets budget_tier based on milestone_type when not provided
--   - Foreign key to partner_vaults with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the partner_milestones table
-- ============================================================
CREATE TABLE public.partner_milestones (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id         UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    milestone_type   TEXT NOT NULL CHECK (milestone_type IN ('birthday', 'anniversary', 'holiday', 'custom')),
    milestone_name   TEXT NOT NULL,
    milestone_date   DATE NOT NULL,
    recurrence       TEXT NOT NULL CHECK (recurrence IN ('yearly', 'one_time')),
    budget_tier      TEXT NOT NULL CHECK (budget_tier IN ('just_because', 'minor_occasion', 'major_milestone')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.partner_milestones IS 'Partner milestones — birthdays, anniversaries, holidays, and custom events. Budget tier auto-defaults based on milestone type.';
COMMENT ON COLUMN public.partner_milestones.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.partner_milestones.vault_id IS 'References partner_vaults(id). CASCADE deletes milestones when vault is deleted.';
COMMENT ON COLUMN public.partner_milestones.milestone_type IS 'birthday | anniversary | holiday | custom';
COMMENT ON COLUMN public.partner_milestones.milestone_name IS 'Display name for the milestone (e.g., "Birthday", "Valentine''s Day", "First Date")';
COMMENT ON COLUMN public.partner_milestones.milestone_date IS 'Date of the milestone. For yearly recurrence, use year 2000 as placeholder (e.g., 2000-02-14 for Feb 14).';
COMMENT ON COLUMN public.partner_milestones.recurrence IS 'yearly | one_time';
COMMENT ON COLUMN public.partner_milestones.budget_tier IS 'just_because | minor_occasion | major_milestone. Auto-set by trigger for birthday/anniversary/holiday types.';

-- ============================================================
-- 2. Create trigger function to auto-set budget_tier defaults
-- ============================================================
-- This trigger fires BEFORE INSERT and sets budget_tier based on
-- milestone_type when the caller does not explicitly provide one.
--
-- Defaults:
--   birthday    → major_milestone
--   anniversary → major_milestone
--   holiday     → minor_occasion (app layer overrides to major_milestone
--                  for Valentine's Day and Christmas by setting it explicitly)
--   custom      → must be provided by the user (trigger does not override)
--
-- If budget_tier is already set (not NULL), the trigger does not change it.
-- This allows the app layer to override defaults (e.g., sending
-- 'major_milestone' for Valentine's Day holidays).

CREATE OR REPLACE FUNCTION public.handle_milestone_budget_tier()
RETURNS TRIGGER AS $$
BEGIN
    -- Only set default when budget_tier was not provided
    IF NEW.budget_tier IS NULL THEN
        CASE NEW.milestone_type
            WHEN 'birthday' THEN
                NEW.budget_tier := 'major_milestone';
            WHEN 'anniversary' THEN
                NEW.budget_tier := 'major_milestone';
            WHEN 'holiday' THEN
                NEW.budget_tier := 'minor_occasion';
            ELSE
                -- 'custom' type: budget_tier must be explicitly provided.
                -- Leave NULL so the NOT NULL constraint will reject the insert.
                NULL;
        END CASE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.handle_milestone_budget_tier() IS 'BEFORE INSERT trigger: auto-sets budget_tier based on milestone_type when not provided. birthday/anniversary → major_milestone, holiday → minor_occasion, custom → must be explicit.';

CREATE TRIGGER set_milestone_budget_tier
    BEFORE INSERT ON public.partner_milestones
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_milestone_budget_tier();

-- ============================================================
-- 3. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.partner_milestones ENABLE ROW LEVEL SECURITY;

-- Users can SELECT milestones for their own vault only
CREATE POLICY "milestones_select_own"
    ON public.partner_milestones FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_milestones.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT milestones for their own vault only
CREATE POLICY "milestones_insert_own"
    ON public.partner_milestones FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_milestones.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE milestones for their own vault only
CREATE POLICY "milestones_update_own"
    ON public.partner_milestones FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_milestones.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_milestones.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE milestones for their own vault only
CREATE POLICY "milestones_delete_own"
    ON public.partner_milestones FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = partner_milestones.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 4. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own milestones (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.partner_milestones TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.partner_milestones TO anon;

-- ============================================================
-- 5. Create index on vault_id for fast lookups
-- ============================================================
CREATE INDEX idx_partner_milestones_vault_id
    ON public.partner_milestones (vault_id);

-- ============================================================
-- 6. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'partner_milestones'
ORDER BY ordinal_position;
