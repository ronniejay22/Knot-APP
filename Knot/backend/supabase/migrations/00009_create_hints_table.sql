-- Migration: Create Hints Table with Vector Embedding
-- Step 1.8: Create Hints Table with Vector Embedding
--
-- Creates the hints table for storing user-captured hints about their partner
-- (text or voice transcription) with pgvector embeddings for semantic search.
--
-- Features:
--   - Row Level Security (RLS) via subquery to partner_vaults.user_id
--   - CHECK constraint on source ('text_input', 'voice_transcription')
--   - vector(768) column for Vertex AI text-embedding-004 embeddings
--   - HNSW index on hint_embedding for fast cosine similarity search
--   - match_hints() RPC function for semantic similarity queries
--   - Foreign key to partner_vaults with CASCADE delete
--   - is_used boolean to track whether a hint has been used in a recommendation
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 0.6: pgvector extension enabled (00001_enable_pgvector.sql)
--   - Step 1.2: Partner Vaults table created (00003_create_partner_vaults_table.sql)

-- ============================================================
-- 1. Create the hints table
-- ============================================================
CREATE TABLE public.hints (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id        UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    hint_text       TEXT NOT NULL,
    hint_embedding  vector(768),  -- nullable: embedding generated async via Vertex AI
    source          TEXT NOT NULL CHECK (source IN ('text_input', 'voice_transcription')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_used         BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE public.hints IS 'User-captured hints about their partner. Supports text and voice input with vector embeddings for semantic search.';
COMMENT ON COLUMN public.hints.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.hints.vault_id IS 'References partner_vaults(id). CASCADE deletes hints when vault is deleted.';
COMMENT ON COLUMN public.hints.hint_text IS 'The hint text captured by the user (max 500 chars enforced at API layer)';
COMMENT ON COLUMN public.hints.hint_embedding IS '768-dimension vector embedding from Vertex AI text-embedding-004. Nullable if embedding generation fails or is pending.';
COMMENT ON COLUMN public.hints.source IS 'text_input | voice_transcription — how the hint was captured';
COMMENT ON COLUMN public.hints.created_at IS 'Timestamp when the hint was captured';
COMMENT ON COLUMN public.hints.is_used IS 'Whether this hint has been used in a recommendation. Defaults to false.';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.hints ENABLE ROW LEVEL SECURITY;

-- Users can SELECT hints for their own vault only
CREATE POLICY "hints_select_own"
    ON public.hints FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = hints.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can INSERT hints for their own vault only
CREATE POLICY "hints_insert_own"
    ON public.hints FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = hints.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can UPDATE hints for their own vault only
CREATE POLICY "hints_update_own"
    ON public.hints FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = hints.vault_id
        AND partner_vaults.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = hints.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- Users can DELETE hints for their own vault only
CREATE POLICY "hints_delete_own"
    ON public.hints FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = hints.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own hints (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.hints TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.hints TO anon;

-- ============================================================
-- 4. Create index on vault_id for fast lookups
-- ============================================================
CREATE INDEX idx_hints_vault_id
    ON public.hints (vault_id);

-- ============================================================
-- 5. Create HNSW index on hint_embedding for cosine similarity
-- ============================================================
-- HNSW (Hierarchical Navigable Small World) is preferred over IVFFlat because:
--   - No pre-build step required (works on empty tables)
--   - Better recall (accuracy) for nearest-neighbor queries
--   - Incrementally updated as data is inserted
-- vector_cosine_ops uses cosine distance: <=> operator
CREATE INDEX idx_hints_embedding
    ON public.hints
    USING hnsw (hint_embedding vector_cosine_ops);

-- ============================================================
-- 6. Create match_hints() RPC function for similarity search
-- ============================================================
-- This function performs cosine similarity search on hint embeddings.
-- Called via Supabase RPC: POST /rest/v1/rpc/match_hints
--
-- Parameters:
--   query_embedding: 768-dim vector to search against
--   query_vault_id:  UUID of the vault to search within
--   match_threshold: minimum similarity score (0.0 to 1.0, default 0.0)
--   match_count:     maximum number of results (default 10)
--
-- Returns: hints ordered by similarity (most similar first),
--          with a similarity score column (1.0 = identical, 0.0 = orthogonal)
CREATE OR REPLACE FUNCTION match_hints(
    query_embedding vector(768),
    query_vault_id UUID,
    match_threshold FLOAT DEFAULT 0.0,
    match_count INT DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    vault_id UUID,
    hint_text TEXT,
    source TEXT,
    is_used BOOLEAN,
    created_at TIMESTAMPTZ,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        h.id,
        h.vault_id,
        h.hint_text,
        h.source,
        h.is_used,
        h.created_at,
        (1 - (h.hint_embedding <=> query_embedding))::FLOAT AS similarity
    FROM public.hints h
    WHERE h.vault_id = query_vault_id
        AND h.hint_embedding IS NOT NULL
        AND (1 - (h.hint_embedding <=> query_embedding)) >= match_threshold
    ORDER BY h.hint_embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

COMMENT ON FUNCTION match_hints IS 'Semantic similarity search on hint embeddings. Returns hints ordered by cosine similarity to the query vector.';

-- Grant execute to authenticated users and service role
GRANT EXECUTE ON FUNCTION match_hints(vector, UUID, FLOAT, INT) TO authenticated, anon;

-- ============================================================
-- 7. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'hints'
ORDER BY ordinal_position;
