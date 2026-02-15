-- Migration: Create User Preferences Weights Table
-- Step 10.2: Create Feedback Analysis Job
--
-- Creates the user_preferences_weights table for storing learned preference
-- weights derived from recommendation feedback analysis. Each user has at
-- most one row containing JSONB weight multipliers for vibes, interests,
-- recommendation types, and love languages.
--
-- The weekly feedback analysis job computes these weights by analyzing:
--   - Which vibes correlate with high ratings vs. refreshes
--   - Which interests correlate with selections vs. rejections
--   - Which recommendation types (gift/experience/date) get higher ratings
--   - Which love languages correlate with positive feedback
--
-- Weight values are multipliers centered around 1.0:
--   - 1.0 = neutral (no adjustment)
--   - >1.0 = boost (user prefers this dimension)
--   - <1.0 = penalty (user dislikes this dimension)
--   - Range clamped to [0.5, 2.0] to prevent extreme swings
--
-- Prerequisites:
--   - Step 1.1: Users table created (00002_create_users_table.sql)
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run

-- ============================================================
-- 1. Create the user_preferences_weights table
-- ============================================================
CREATE TABLE public.user_preferences_weights (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    vibe_weights          JSONB NOT NULL DEFAULT '{}',
    interest_weights      JSONB NOT NULL DEFAULT '{}',
    type_weights          JSONB NOT NULL DEFAULT '{}',
    love_language_weights JSONB NOT NULL DEFAULT '{}',
    feedback_count        INTEGER NOT NULL DEFAULT 0,
    last_analyzed_at      TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_preferences_weights IS 'Learned preference weights per user, computed by the weekly feedback analysis job. Used by the matching node to personalize recommendation scoring.';
COMMENT ON COLUMN public.user_preferences_weights.user_id IS 'References users(id). UNIQUE ensures one weights row per user. CASCADE deletes weights when user is deleted.';
COMMENT ON COLUMN public.user_preferences_weights.vibe_weights IS 'JSONB map of vibe_tag -> weight multiplier (e.g., {"romantic": 1.4, "adventurous": 0.7}). Default 1.0 for unlisted vibes.';
COMMENT ON COLUMN public.user_preferences_weights.interest_weights IS 'JSONB map of interest_category -> weight multiplier (e.g., {"Cooking": 1.3, "Gaming": 0.8}).';
COMMENT ON COLUMN public.user_preferences_weights.type_weights IS 'JSONB map of recommendation_type -> weight multiplier (e.g., {"gift": 1.2, "experience": 0.9, "date": 1.0}).';
COMMENT ON COLUMN public.user_preferences_weights.love_language_weights IS 'JSONB map of love_language -> weight multiplier (e.g., {"quality_time": 1.3}).';
COMMENT ON COLUMN public.user_preferences_weights.feedback_count IS 'Total number of feedback entries analyzed to compute these weights. Used for confidence tracking.';
COMMENT ON COLUMN public.user_preferences_weights.last_analyzed_at IS 'Timestamp of the last analysis run that updated these weights.';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.user_preferences_weights ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own weights only
CREATE POLICY "weights_select_own"
    ON public.user_preferences_weights FOR SELECT
    USING (user_id = auth.uid());

-- No user-facing INSERT/UPDATE/DELETE policies.
-- Only the service role (backend feedback analysis job) writes to this table.
-- The service client bypasses RLS.

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Read-only (users can see their own weights via RLS)
GRANT SELECT ON public.user_preferences_weights TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.user_preferences_weights TO anon;
-- service_role implicitly has full access (bypasses RLS)

-- ============================================================
-- 4. Reuse handle_updated_at trigger for updated_at column
-- ============================================================
CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.user_preferences_weights
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'user_preferences_weights'
ORDER BY ordinal_position;
