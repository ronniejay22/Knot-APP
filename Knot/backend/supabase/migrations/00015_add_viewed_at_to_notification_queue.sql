-- Migration: Add viewed_at column to notification_queue table
-- Step 7.7: Notification History — track when user viewed notification recommendations
--
-- Adds a nullable TIMESTAMPTZ column to record when the user first viewed
-- the recommendations associated with a notification from the history screen.
-- NULL means the user has not yet viewed the recommendations.
--
-- This is a simple ALTER TABLE ADD COLUMN — zero-downtime migration.
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.11: notification_queue table exists (00012_create_notification_queue_table.sql)

-- ============================================================
-- 1. Add the viewed_at column
-- ============================================================
ALTER TABLE public.notification_queue
    ADD COLUMN viewed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.notification_queue.viewed_at
    IS 'Timestamp when the user viewed the recommendations from this notification via the history screen (NULL until viewed)';

-- ============================================================
-- 2. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'notification_queue'
ORDER BY ordinal_position;
