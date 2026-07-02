-- Migration: Create Recommendation QA Verdicts Table
-- Step 20.1: Recommendation Quality Cockpit
--
-- Stores the internal reviewer's like/dislike verdicts on generated
-- recommendations, plus the rubric dimensions and free-text reason behind each
-- verdict. This is DEV/QA tooling — it captures the evaluator judging the
-- recommendations (not end-user feedback, which lives in recommendation_feedback).
--
-- The verdicts feed two things:
--   1. Live re-steering: recent likes/dislikes + reasons are injected into the
--      next generation as QA-steering exemplars (unified_generation.py).
--   2. The offline eval harness: a labelled set to calibrate the LLM judge against.
--
-- Written only by the backend service role behind the KNOT_QA_ENABLED flag.
-- Append-only (no updates), so no updated_at trigger.
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run

-- ============================================================
-- 1. Create the rec_qa_verdicts table
-- ============================================================
CREATE TABLE public.rec_qa_verdicts (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    evaluator          TEXT NOT NULL DEFAULT 'qa',
    profile_id         TEXT,
    rec_snapshot       JSONB NOT NULL DEFAULT '{}',
    verdict            TEXT NOT NULL CHECK (verdict IN ('like', 'dislike')),
    reason_dimensions  TEXT[] NOT NULL DEFAULT '{}',
    reason_text        TEXT,
    generation_config  JSONB NOT NULL DEFAULT '{}',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rec_qa_verdicts IS 'Internal QA like/dislike verdicts on generated recommendations (dev tooling, gated by KNOT_QA_ENABLED). Feeds live re-steering and the eval harness. Distinct from end-user recommendation_feedback.';
COMMENT ON COLUMN public.rec_qa_verdicts.evaluator IS 'Who reviewed (free text, defaults to "qa"). Not a users FK — QA is not user-scoped.';
COMMENT ON COLUMN public.rec_qa_verdicts.profile_id IS 'Sample profile id (qa_profiles) or a real vault_id the rec was generated for.';
COMMENT ON COLUMN public.rec_qa_verdicts.rec_snapshot IS 'JSONB snapshot of the recommendation reviewed (title, type, description, personalization_note, matched_* , price, merchant).';
COMMENT ON COLUMN public.rec_qa_verdicts.verdict IS 'like or dislike.';
COMMENT ON COLUMN public.rec_qa_verdicts.reason_dimensions IS 'Rubric dimension ids the evaluator cited (app/services/rec_quality.py), e.g. {grounded, specific}.';
COMMENT ON COLUMN public.rec_qa_verdicts.reason_text IS 'Optional free-text "why" from the reviewer.';
COMMENT ON COLUMN public.rec_qa_verdicts.generation_config IS 'JSONB config the rec was generated with (model, occasion, thinking/effort) — so verdicts can be sliced by config.';

-- Recent-verdicts lookups drive re-steering — index by recency.
CREATE INDEX idx_rec_qa_verdicts_created_at ON public.rec_qa_verdicts (created_at DESC);
CREATE INDEX idx_rec_qa_verdicts_profile ON public.rec_qa_verdicts (profile_id, created_at DESC);

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
-- No user-facing policies: this is dev/QA tooling written and read only by the
-- backend service role (which bypasses RLS). authenticated/anon get no access.
ALTER TABLE public.rec_qa_verdicts ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- 3. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'rec_qa_verdicts'
ORDER BY ordinal_position;
