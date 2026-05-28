-- ============================================================
-- Migration 00024: Add Scheduled Deletion At to Users Table
-- Step 15.5: 60-Day Soft-Delete for Account Deletion
-- ============================================================
--
-- Adds a scheduled_deletion_at timestamptz column to public.users
-- so account deletion becomes a two-phase operation:
--   1. DELETE /api/v1/users/me sets this column to NOW() + 60 days
--      and enqueues a QStash purge job. The Supabase auth user and
--      all CASCADE-linked rows remain intact during the grace window.
--   2. After 60 days, the QStash worker (POST /api/v1/users/process-deletion)
--      verifies the column is still set and runs the hard-delete via
--      the Supabase Admin API, which cascades to every dependent table.
--
-- If the user signs back in within the grace window, POST /api/v1/users/me/restore
-- clears this column. The worker is idempotent against that race: it
-- re-reads the column before deleting.
--
-- The pending-deletion gate (get_active_user_id) returns HTTP 410 Gone
-- on any authenticated request whose user has a non-null value here,
-- forcing the iOS app to surface the restore flow before any other API call.
--
-- Prerequisites:
--   - 00002_create_users_table.sql (users table must exist)
--
-- Notes:
--   - Nullable; existing users default to NULL ("not pending") on ADD COLUMN.
--   - Partial index keeps the column ignorable for normal queries while
--     still letting an admin / debug query find pending rows cheaply.

-- ============================================================
-- 1. Add scheduled_deletion_at column
-- ============================================================
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS scheduled_deletion_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.users.scheduled_deletion_at IS
    'Set when the user requests account deletion. Hard-delete runs via the QStash purge worker once now() passes this timestamp. NULL means the account is active.';

-- ============================================================
-- 2. Partial index for the pending set
-- ============================================================
CREATE INDEX IF NOT EXISTS users_scheduled_deletion_at_idx
    ON public.users (scheduled_deletion_at)
    WHERE scheduled_deletion_at IS NOT NULL;

-- ============================================================
-- 3. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
  AND column_name = 'scheduled_deletion_at';
