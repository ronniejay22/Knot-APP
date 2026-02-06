-- Migration: Create Recommendation Feedback Table
-- Step 1.10: Create User Feedback Table
--
-- Creates the recommendation_feedback table for storing user feedback on
-- AI-generated recommendations. Each feedback entry is tied to a
-- recommendation and the user who provided it.
--
-- Features:
--   - Row Level Security (RLS) enforcing user_id = auth.uid()
--   - CHECK constraint on action ('selected', 'refreshed', 'saved', 'shared', 'rated')
--   - CHECK constraint on rating (1-5, nullable — only required for 'rated' action)
--   - Foreign key to recommendations with CASCADE delete
--   - Foreign key to users with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.1: Users table created (00002_create_users_table.sql)
--   - Step 1.9: Recommendations table created (00010_create_recommendations_table.sql)

-- ============================================================
-- 1. Create the recommendation_feedback table
-- ============================================================
CREATE TABLE public.recommendation_feedback (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recommendation_id   UUID NOT NULL REFERENCES public.recommendations(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    action              TEXT NOT NULL CHECK (action IN ('selected', 'refreshed', 'saved', 'shared', 'rated')),
    rating              INTEGER CHECK (rating >= 1 AND rating <= 5),
    feedback_text       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.recommendation_feedback IS 'User feedback on AI-generated recommendations. Tracks selections, refreshes, saves, shares, and ratings.';
COMMENT ON COLUMN public.recommendation_feedback.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.recommendation_feedback.recommendation_id IS 'References recommendations(id). CASCADE deletes feedback when recommendation is deleted.';
COMMENT ON COLUMN public.recommendation_feedback.user_id IS 'References users(id). CASCADE deletes feedback when user is deleted.';
COMMENT ON COLUMN public.recommendation_feedback.action IS 'selected | refreshed | saved | shared | rated — the type of feedback action';
COMMENT ON COLUMN public.recommendation_feedback.rating IS '1-5 star rating (nullable, only provided for "rated" action)';
COMMENT ON COLUMN public.recommendation_feedback.feedback_text IS 'Optional text feedback from the user (e.g., "She loved it!")';
COMMENT ON COLUMN public.recommendation_feedback.created_at IS 'Timestamp when the feedback was submitted';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.recommendation_feedback ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own feedback only
CREATE POLICY "feedback_select_own"
    ON public.recommendation_feedback FOR SELECT
    USING (user_id = auth.uid());

-- Users can INSERT feedback for themselves only
CREATE POLICY "feedback_insert_own"
    ON public.recommendation_feedback FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can UPDATE their own feedback only
CREATE POLICY "feedback_update_own"
    ON public.recommendation_feedback FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can DELETE their own feedback only
CREATE POLICY "feedback_delete_own"
    ON public.recommendation_feedback FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own feedback (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.recommendation_feedback TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.recommendation_feedback TO anon;

-- ============================================================
-- 4. Create indexes for fast lookups
-- ============================================================
-- Index on recommendation_id for querying feedback by recommendation
CREATE INDEX idx_feedback_recommendation_id
    ON public.recommendation_feedback (recommendation_id);

-- Index on user_id for querying feedback by user
CREATE INDEX idx_feedback_user_id
    ON public.recommendation_feedback (user_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'recommendation_feedback'
ORDER BY ordinal_position;
