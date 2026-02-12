-- ============================================================
-- Migration 00014: Add Quiet Hours and Timezone to Users Table
-- Step 7.6: DND Respect Logic
-- ============================================================
--
-- Adds quiet_hours_start, quiet_hours_end, and timezone columns
-- to the existing public.users table. These enable the backend to
-- check whether a notification is being delivered during the user's
-- quiet hours and reschedule it accordingly.
--
-- Prerequisites:
--   - 00002_create_users_table.sql (users table must exist)
--
-- Notes:
--   - quiet_hours_start/end are integers representing hour-of-day (0-23)
--   - Defaults: 22 (10pm) start, 8 (8am) end
--   - timezone is nullable; when NULL, the system infers from
--     partner_vaults.location_state/location_country
--   - The handle_new_user trigger needs no changes (new columns have defaults/NULL)
--   - Existing RLS policies cover updates (users_update_own allows self-update)

-- ============================================================
-- 1. Add quiet hours and timezone columns
-- ============================================================
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS quiet_hours_start INTEGER NOT NULL DEFAULT 22
        CHECK (quiet_hours_start >= 0 AND quiet_hours_start <= 23),
    ADD COLUMN IF NOT EXISTS quiet_hours_end INTEGER NOT NULL DEFAULT 8
        CHECK (quiet_hours_end >= 0 AND quiet_hours_end <= 23),
    ADD COLUMN IF NOT EXISTS timezone TEXT;

COMMENT ON COLUMN public.users.quiet_hours_start IS
    'Hour-of-day (0-23) when quiet hours begin. Default 22 (10pm). Notifications during quiet hours are rescheduled.';
COMMENT ON COLUMN public.users.quiet_hours_end IS
    'Hour-of-day (0-23) when quiet hours end. Default 8 (8am). Rescheduled notifications deliver at this time.';
COMMENT ON COLUMN public.users.timezone IS
    'IANA timezone string (e.g., America/Chicago). NULL means infer from partner_vaults location.';

-- ============================================================
-- 2. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
ORDER BY ordinal_position;
