-- ============================================================
-- Migration 00013: Add Device Token to Users Table
-- Step 7.4: Push Notification Registration
-- ============================================================
--
-- Adds device_token and device_platform columns to the existing
-- public.users table for storing APNs device tokens. The token
-- is upserted on each app launch after the user grants notification
-- permissions.
--
-- Prerequisites:
--   - 00002_create_users_table.sql (users table must exist)
--
-- Notes:
--   - Both columns are nullable (users who deny permission have NULL)
--   - One device per user for MVP (column on users, not a separate table)
--   - The handle_new_user trigger needs no changes (new columns default to NULL)
--   - Existing RLS policies cover updates (users_update_own allows self-update)

-- ============================================================
-- 1. Add device_token and device_platform columns
-- ============================================================
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS device_token TEXT,
    ADD COLUMN IF NOT EXISTS device_platform TEXT CHECK (device_platform IN ('ios', 'android'));

COMMENT ON COLUMN public.users.device_token IS 'APNs/FCM device token for push notifications. NULL if user has not granted permission.';
COMMENT ON COLUMN public.users.device_platform IS 'Platform of the registered device (ios or android). NULL if no token registered.';

-- ============================================================
-- 2. Create partial index on device_token for push delivery lookups
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_users_device_token
    ON public.users (device_token)
    WHERE device_token IS NOT NULL;

-- ============================================================
-- 3. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
ORDER BY ordinal_position;
