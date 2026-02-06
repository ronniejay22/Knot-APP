-- Migration: Create Notification Queue Table
-- Step 1.11: Create Notification Queue Table
--
-- Creates the notification_queue table for scheduling proactive milestone
-- notifications. Each entry represents a scheduled push notification for
-- 14, 7, or 3 days before a milestone.
--
-- Features:
--   - Row Level Security (RLS) enforcing user_id = auth.uid()
--   - CHECK constraint on days_before (14, 7, 3)
--   - CHECK constraint on status ('pending', 'sent', 'failed', 'cancelled')
--   - Foreign key to users with CASCADE delete
--   - Foreign key to partner_milestones with CASCADE delete
--
-- Run this in the Supabase SQL Editor:
--   Dashboard → SQL Editor → New Query → Paste & Run
--
-- Prerequisites:
--   - Step 1.1: Users table created (00002_create_users_table.sql)
--   - Step 1.4: Partner Milestones table created (00005_create_partner_milestones_table.sql)

-- ============================================================
-- 1. Create the notification_queue table
-- ============================================================
CREATE TABLE public.notification_queue (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    milestone_id    UUID NOT NULL REFERENCES public.partner_milestones(id) ON DELETE CASCADE,
    scheduled_for   TIMESTAMPTZ NOT NULL,
    days_before     INTEGER NOT NULL CHECK (days_before IN (14, 7, 3)),
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'cancelled')),
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notification_queue IS 'Scheduled push notifications for upcoming milestones. Notifications fire at 14, 7, and 3 days before each milestone.';
COMMENT ON COLUMN public.notification_queue.id IS 'Auto-generated UUID primary key';
COMMENT ON COLUMN public.notification_queue.user_id IS 'References users(id). CASCADE deletes notifications when user is deleted.';
COMMENT ON COLUMN public.notification_queue.milestone_id IS 'References partner_milestones(id). CASCADE deletes notifications when milestone is deleted.';
COMMENT ON COLUMN public.notification_queue.scheduled_for IS 'Timestamp (with timezone) when the notification should be sent';
COMMENT ON COLUMN public.notification_queue.days_before IS '14 | 7 | 3 — how many days before the milestone this notification fires';
COMMENT ON COLUMN public.notification_queue.status IS 'pending | sent | failed | cancelled — lifecycle status of the notification';
COMMENT ON COLUMN public.notification_queue.sent_at IS 'Timestamp when the notification was actually sent (NULL until sent)';
COMMENT ON COLUMN public.notification_queue.created_at IS 'Timestamp when the notification was scheduled';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own notifications only
CREATE POLICY "notifications_select_own"
    ON public.notification_queue FOR SELECT
    USING (user_id = auth.uid());

-- Users can INSERT notifications for themselves only
CREATE POLICY "notifications_insert_own"
    ON public.notification_queue FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Users can UPDATE their own notifications only
CREATE POLICY "notifications_update_own"
    ON public.notification_queue FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can DELETE their own notifications only
CREATE POLICY "notifications_delete_own"
    ON public.notification_queue FOR DELETE
    USING (user_id = auth.uid());

-- ============================================================
-- 3. Grant permissions to PostgREST roles
-- ============================================================
-- authenticated: Full CRUD on own notifications (enforced by RLS)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_queue TO authenticated;
-- anon: Read-only (RLS returns empty set since auth.uid() is NULL)
GRANT SELECT ON public.notification_queue TO anon;

-- ============================================================
-- 4. Create indexes for fast lookups
-- ============================================================
-- Index on user_id for querying notifications by user
CREATE INDEX idx_notification_queue_user_id
    ON public.notification_queue (user_id);

-- Index on milestone_id for querying notifications by milestone
CREATE INDEX idx_notification_queue_milestone_id
    ON public.notification_queue (milestone_id);

-- Composite index on status + scheduled_for for the notification processing job
-- (find all 'pending' notifications scheduled before NOW)
CREATE INDEX idx_notification_queue_status_scheduled
    ON public.notification_queue (status, scheduled_for)
    WHERE status = 'pending';

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'notification_queue'
ORDER BY ordinal_position;
