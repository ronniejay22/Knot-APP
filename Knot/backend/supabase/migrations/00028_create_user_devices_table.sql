-- Migration: One row per device, instead of one token per user
-- August 2026: multi-device push delivery
--
-- `users.device_token` is a single column, so registering a device OVERWRITES
-- whatever was there. Every launch of the app on a second device silently
-- steals notifications from the first: the user keeps receiving pushes, but
-- only ever on whichever device they opened most recently. Nothing errors, so
-- nothing surfaces it.
--
-- This was found in dev when the Simulator's token (80 bytes) replaced a real
-- iPhone's (32 bytes) and pushes stopped arriving on the phone while APNs kept
-- returning 200 — it was delivering, just to the other device.
--
-- `user_devices` makes the token the identity of a device rather than an
-- attribute of a user, so a person can have as many as they like.

CREATE TABLE IF NOT EXISTS public.user_devices (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    -- Globally unique, NOT unique-per-user: a physical device belongs to one
    -- account at a time. If someone signs out and a different user signs in,
    -- the token must MOVE to the new user rather than exist twice, or the
    -- previous account would keep receiving that device's notifications.
    device_token  TEXT NOT NULL UNIQUE,
    platform      TEXT NOT NULL DEFAULT 'ios',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_devices IS
    'Push-notification devices. One row per device token; a user may have many. '
    'Replaces users.device_token, which allowed only one device per account.';

COMMENT ON COLUMN public.user_devices.device_token IS
    'APNs device token, hex-encoded. Globally unique so a device can move '
    'between accounts. Rows are deleted when APNs reports 410 Unregistered.';

-- Delivery fans out by user, so this is the hot path.
CREATE INDEX IF NOT EXISTS idx_user_devices_user_id
    ON public.user_devices (user_id);

-- ============================================================
-- Backfill from the column this replaces
-- ============================================================
-- Non-destructive: users.device_token is left in place. It is still written on
-- registration as a "most recently seen device" convenience, but delivery no
-- longer reads it. ON CONFLICT keeps this migration re-runnable.
INSERT INTO public.user_devices (user_id, device_token, platform)
SELECT id, device_token, COALESCE(device_platform, 'ios')
FROM public.users
WHERE device_token IS NOT NULL AND device_token <> ''
ON CONFLICT (device_token) DO NOTHING;

-- ============================================================
-- RLS
-- ============================================================
-- Everything in `public` is reachable through PostgREST with the anon key that
-- ships inside the iOS app. Device tokens are push-addressable identifiers, so
-- the table denies all client access; the service role bypasses RLS and is the
-- only thing that reads or writes it.
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_devices FROM anon, authenticated;

-- NOTE: run `NOTIFY pgrst, 'reload schema';` after applying, or PostgREST will
-- 404 the new table. `scripts/migrate.py apply` does this automatically.
