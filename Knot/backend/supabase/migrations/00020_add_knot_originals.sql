-- Migration: Add Knot Originals (AI-Generated Ideas) Support
-- Step 14.1: Extend recommendations table for in-app AI-generated ideas
--
-- Adds support for a new "idea" recommendation type that stores
-- rich structured content (content_sections JSONB) and has no
-- external URL. These "Knot Originals" are fully AI-generated,
-- personalized recommendations that live entirely in-app.
--
-- Changes:
--   - Add content_sections JSONB column for structured idea content
--   - Add is_idea BOOLEAN column for fast filtering
--   - Update recommendation_type CHECK to include 'idea'
--   - Add composite index for efficient idea queries
--
-- Prerequisites:
--   - Step 1.9: Recommendations table created (00010_create_recommendations_table.sql)

-- ============================================================
-- 1. Add content_sections JSONB column
-- ============================================================
-- Stores structured idea content as a JSON array of section objects.
-- Each section has: type, heading, body (optional), items (optional).
-- NULL for non-idea recommendations (gift, experience, date).
ALTER TABLE public.recommendations
ADD COLUMN content_sections JSONB DEFAULT NULL;

COMMENT ON COLUMN public.recommendations.content_sections IS
    'Structured content sections for AI-generated ideas. JSON array of objects with type/heading/body/items. NULL for linked recommendations.';

-- ============================================================
-- 2. Add is_idea boolean column
-- ============================================================
-- Fast boolean flag for filtering ideas vs linked recommendations.
-- Avoids scanning recommendation_type text for every query.
ALTER TABLE public.recommendations
ADD COLUMN is_idea BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.recommendations.is_idea IS
    'TRUE for AI-generated Knot Original ideas, FALSE for external linked recommendations (gift/experience/date).';

-- ============================================================
-- 3. Update recommendation_type CHECK constraint
-- ============================================================
-- Add 'idea' as a valid recommendation type alongside gift/experience/date.
ALTER TABLE public.recommendations
DROP CONSTRAINT IF EXISTS recommendations_recommendation_type_check;

ALTER TABLE public.recommendations
ADD CONSTRAINT recommendations_recommendation_type_check
    CHECK (recommendation_type IN ('gift', 'experience', 'date', 'idea'));

-- ============================================================
-- 4. Create composite index for idea queries
-- ============================================================
-- Optimizes GET /api/v1/ideas (list user's ideas) which filters
-- by vault_id + is_idea and sorts by created_at DESC.
CREATE INDEX idx_recommendations_is_idea
    ON public.recommendations (vault_id, is_idea, created_at DESC);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'recommendations'
ORDER BY ordinal_position;
