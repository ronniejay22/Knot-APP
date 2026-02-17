-- ============================================================
-- Migration 00019: Add Notifications Enabled to Users Table
-- Step 11.4: Notification Preferences
-- ============================================================
--
-- Adds a notifications_enabled boolean column to public.users
-- that acts as a global kill switch for all push notifications.
-- When FALSE, the webhook processor skips delivery entirely.
--
-- Prerequisites:
--   - 00002_create_users_table.sql (users table must exist)
--   - 00014_add_quiet_hours_to_users.sql (quiet hours columns exist)
--
-- Notes:
--   - Defaults to TRUE so existing users continue receiving notifications
--   - The handle_new_user trigger needs no changes (new column has a default)
--   - Existing RLS policies cover updates (users_update_own allows self-update)

-- ============================================================
-- 1. Add notifications_enabled column
-- ============================================================
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN public.users.notifications_enabled IS
    'Global toggle for push notifications. When FALSE, all notifications are skipped during webhook processing.';

-- ============================================================
-- 2. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
ORDER BY ordinal_position;
