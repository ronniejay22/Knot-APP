-- Migration: Enable pgvector Extension
-- Step 0.6: Set Up Supabase Project
-- This must be run FIRST before any tables using vector columns.
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Or via Supabase CLI:
--   supabase db push

-- Enable the pgvector extension for vector similarity search.
-- Required for hint embeddings (768-dimensional vectors from Vertex AI text-embedding-004).
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- Verify the extension is enabled
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'vector';
