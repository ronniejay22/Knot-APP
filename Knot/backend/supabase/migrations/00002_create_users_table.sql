-- Migration: Create Users Table
-- Step 1.1: Create Users Table
--
-- Creates the public.users table linked to auth.users with:
--   - Row Level Security (RLS) so users can only access their own row
--   - Trigger to auto-update updated_at on row changes
--   - Trigger to auto-create a profile row when a user signs up via auth
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 0.6: Supabase project created and pgvector enabled
--   - Step 0.7: Auth with Apple Sign-In configured

-- ============================================================
-- 1. Create the users table
-- ============================================================
CREATE TABLE public.users (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.users IS 'Application user profiles linked to Supabase auth.users';
COMMENT ON COLUMN public.users.id IS 'References auth.users(id), set during Apple Sign-In';
COMMENT ON COLUMN public.users.email IS 'User email (nullable for Apple Private Relay users)';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own row only
CREATE POLICY "users_select_own"
    ON public.users FOR SELECT
    USING (auth.uid() = id);

-- Users can UPDATE their own row only
CREATE POLICY "users_update_own"
    ON public.users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Users can INSERT their own row (for initial profile creation)
CREATE POLICY "users_insert_own"
    ON public.users FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================================
-- 3. Auto-update updated_at timestamp
--    (Reusable trigger function for future tables)
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();

-- ============================================================
-- 4. Auto-create user profile on auth signup
--    (Fires when a new row is inserted into auth.users)
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- 5. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own row (enforced by RLS)
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.users TO anon;

-- ============================================================
-- 6. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
ORDER BY ordinal_position;
