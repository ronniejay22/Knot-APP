-- Migration: Create Milestone Briefings Table
-- Stores Claude-generated contextual briefing narratives that accompany
-- milestone-triggered recommendations. Each briefing synthesizes hints,
-- interests, and vibes into a conversational "friend-like" suggestion.
--
-- One briefing per milestone-per-notification (accompanies all 3 recommendation cards).
--
-- Prerequisites:
--   - 00003_create_partner_vaults_table.sql
--   - 00005_create_partner_milestones_table.sql
--   - 00012_create_notification_queue_table.sql

-- ============================================================
-- 1. Create the milestone_briefings table
-- ============================================================
CREATE TABLE public.milestone_briefings (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vault_id          UUID NOT NULL REFERENCES public.partner_vaults(id) ON DELETE CASCADE,
    milestone_id      UUID NOT NULL REFERENCES public.partner_milestones(id) ON DELETE CASCADE,
    notification_id   UUID REFERENCES public.notification_queue(id) ON DELETE SET NULL,
    briefing_text     TEXT NOT NULL,
    briefing_snippet  TEXT NOT NULL,
    hints_referenced  JSONB DEFAULT '[]'::jsonb,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.milestone_briefings IS 'Claude-generated contextual briefings for upcoming milestones. Displayed above recommendation cards.';
COMMENT ON COLUMN public.milestone_briefings.briefing_text IS 'Full 2-4 sentence conversational briefing referencing hints and interests.';
COMMENT ON COLUMN public.milestone_briefings.briefing_snippet IS 'Condensed version (<100 chars) used as push notification body.';
COMMENT ON COLUMN public.milestone_briefings.hints_referenced IS 'JSON array of hint IDs that were referenced in the briefing.';

-- ============================================================
-- 2. Enable Row Level Security (RLS)
-- ============================================================
ALTER TABLE public.milestone_briefings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "milestone_briefings_select_own"
    ON public.milestone_briefings FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = milestone_briefings.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

CREATE POLICY "milestone_briefings_insert_own"
    ON public.milestone_briefings FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = milestone_briefings.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

CREATE POLICY "milestone_briefings_delete_own"
    ON public.milestone_briefings FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.partner_vaults
        WHERE partner_vaults.id = milestone_briefings.vault_id
        AND partner_vaults.user_id = auth.uid()
    ));

-- ============================================================
-- 3. Grant permissions
-- ============================================================
GRANT SELECT, INSERT, DELETE ON public.milestone_briefings TO authenticated;
GRANT SELECT ON public.milestone_briefings TO anon;

-- ============================================================
-- 4. Create indexes
-- ============================================================
CREATE INDEX idx_milestone_briefings_vault
    ON public.milestone_briefings (vault_id);

CREATE INDEX idx_milestone_briefings_milestone
    ON public.milestone_briefings (milestone_id);

-- ============================================================
-- 5. Verify migration
-- ============================================================
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'milestone_briefings'
ORDER BY ordinal_position;
