-- Migration: Add 'disliked' feedback action for the Spotlight deck's 👎 vote
-- June 12, 2026: Spotlight recommendation experience
--
-- The Spotlight deck lets the user pass on a recommendation (👎). Unlike a
-- 'refreshed' (which rejects the whole set), a 'disliked' is a per-item negative
-- signal. The weekly feedback-analysis job weights it slightly more negatively
-- than 'refreshed'.
--
-- The existing CHECK constraint on recommendation_feedback.action allows:
-- 'selected', 'refreshed', 'saved', 'shared', 'rated', 'handoff', 'purchased'.
-- This migration adds 'disliked'.

-- 1. Drop the existing CHECK constraint
ALTER TABLE public.recommendation_feedback
    DROP CONSTRAINT IF EXISTS recommendation_feedback_action_check;

-- 2. Add the new CHECK constraint with 'disliked' included
ALTER TABLE public.recommendation_feedback
    ADD CONSTRAINT recommendation_feedback_action_check
    CHECK (action IN ('selected', 'refreshed', 'saved', 'shared', 'rated', 'handoff', 'purchased', 'disliked'));
