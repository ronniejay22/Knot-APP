-- Migration: Add occasion_category to partner_milestones
-- August 2026: Occasion entry modal + expanded milestone catalog
--
-- Until now there was no stable key identifying WHICH occasion a milestone is.
-- `milestone_type` only distinguishes birthday / anniversary / holiday / custom,
-- and every holiday is stored as a free-text `milestone_name` — the iOS
-- `HolidayOption.id` ("valentines_day", "christmas", …) was discarded at write
-- time. The only categorisation in the codebase was
-- `notification_scheduler._is_floating_holiday()`, an unanchored substring match
-- on the display name, which:
--   * misfires (a milestone named "Grandmother's Birthday" resolves to the
--     2nd Sunday of May), and
--   * breaks silently when a user renames the milestone, since
--     MilestoneUpdateRequest allows editing `milestone_name`.
--
-- `occasion_category` is that missing key. It drives:
--   * the per-occasion entry modal copy + illustration on push tap-through, and
--   * date computation for holidays that are not fixed in the Gregorian
--     calendar (Thanksgiving, Easter, Hanukkah, Diwali, Lunar New Year, Eid).
--
-- Deliberately NULLABLE and UNCONSTRAINED:
--   * Nullable so existing rows stay valid with no backfill — the resolver in
--     app/services/occasion_category.py falls back to name matching for them.
--   * No CHECK constraint, because the catalogue is expected to grow and a
--     constrained column would need a migration every time. Migration 00025 had
--     to drop exactly this kind of CHECK from partner_interests.interest_category
--     for the same reason; not repeating it here.

ALTER TABLE public.partner_milestones
    ADD COLUMN IF NOT EXISTS occasion_category TEXT;

COMMENT ON COLUMN public.partner_milestones.occasion_category IS
    'Stable occasion key (e.g. birthday, valentines_day, thanksgiving, new_home). '
    'Drives entry-modal copy/illustration and non-Gregorian holiday date math. '
    'NULL for rows created before this migration — resolved by name fallback.';

-- NOTE: run `NOTIFY pgrst, 'reload schema';` in the Supabase SQL Editor after
-- applying, or PostgREST will 500 on the new column (see progress.md note #150).
