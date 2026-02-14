-- Migration: Add 'handoff' feedback action for merchant handoff tracking
-- Step 9.3: External Merchant Handoff
--
-- The existing CHECK constraint on recommendation_feedback.action (from migration 00011)
-- only allows: 'selected', 'refreshed', 'saved', 'shared', 'rated'.
-- This migration adds 'handoff' for tracking when the user opens a merchant URL.

-- 1. Drop the existing CHECK constraint
ALTER TABLE public.recommendation_feedback
    DROP CONSTRAINT IF EXISTS recommendation_feedback_action_check;

-- 2. Add the new CHECK constraint with 'handoff' included
ALTER TABLE public.recommendation_feedback
    ADD CONSTRAINT recommendation_feedback_action_check
    CHECK (action IN ('selected', 'refreshed', 'saved', 'shared', 'rated', 'handoff'));
