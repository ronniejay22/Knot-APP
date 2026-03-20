-- Migration: Add 'plan' recommendation type
-- Extends the recommendation_type CHECK constraint to include 'plan' —
-- a cohesive multi-activity date plan combining 2-3 activities into one
-- evening/day (e.g., "Bake lemon bars + watch Scream 7").
--
-- Plans use content_sections (like ideas) and are not purchasable.
--
-- Prerequisites:
--   - 00020_add_knot_originals.sql (added 'idea' type)

-- ============================================================
-- 1. Update recommendation_type CHECK constraint
-- ============================================================
ALTER TABLE public.recommendations
DROP CONSTRAINT IF EXISTS recommendations_recommendation_type_check;

ALTER TABLE public.recommendations
ADD CONSTRAINT recommendations_recommendation_type_check
    CHECK (recommendation_type IN ('gift', 'experience', 'date', 'idea', 'plan'));
