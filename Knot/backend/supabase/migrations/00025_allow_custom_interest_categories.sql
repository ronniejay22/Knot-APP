-- Migration: Allow Custom Interest Categories
--
-- Drops the CHECK constraint on partner_interests.interest_category so users
-- can submit interests/dislikes outside the original 40-item allowlist. The
-- iOS onboarding flow now lets users type a name in the search field and
-- "Add as a new interest" when nothing matches.
--
-- The UNIQUE(vault_id, interest_category) constraint stays in place so a
-- given vault still can't have the same interest twice (or have it be both
-- a like and a dislike).
--
-- Pydantic still validates length and emptiness at the API layer (see
-- backend/app/models/vault.py).
--
-- Run this in the Supabase SQL Editor.

-- ============================================================
-- 1. Drop the existing CHECK constraint
-- ============================================================
-- Postgres auto-names the CHECK constraint based on the column; the name
-- is partner_interests_interest_category_check on this table.
ALTER TABLE public.partner_interests
    DROP CONSTRAINT IF EXISTS partner_interests_interest_category_check;

-- ============================================================
-- 2. Update the column comment
-- ============================================================
COMMENT ON COLUMN public.partner_interests.interest_category IS
    'Free-form interest name. Originally limited to a 40-item allowlist; '
    'as of migration 00025 users can add custom values during onboarding. '
    'Length and non-emptiness are enforced at the API layer.';

-- ============================================================
-- 3. Verify the constraint is gone
-- ============================================================
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.partner_interests'::regclass
ORDER BY conname;
