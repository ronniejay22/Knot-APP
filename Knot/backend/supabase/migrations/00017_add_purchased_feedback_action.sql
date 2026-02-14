-- Migration: Add 'purchased' feedback action for return-to-app purchase tracking
-- Step 9.4: Implement Return-to-App Flow
--
-- The existing CHECK constraint on recommendation_feedback.action allows:
-- 'selected', 'refreshed', 'saved', 'shared', 'rated', 'handoff'.
-- This migration adds 'purchased' for tracking completed purchases.

-- 1. Drop the existing CHECK constraint
ALTER TABLE public.recommendation_feedback
    DROP CONSTRAINT IF EXISTS recommendation_feedback_action_check;

-- 2. Add the new CHECK constraint with 'purchased' included
ALTER TABLE public.recommendation_feedback
    ADD CONSTRAINT recommendation_feedback_action_check
    CHECK (action IN ('selected', 'refreshed', 'saved', 'shared', 'rated', 'handoff', 'purchased'));
