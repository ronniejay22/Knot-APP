"""
APNs Push Notification Service — Apple Push Notification delivery.

Handles JWT-based authentication with Apple's APNs HTTP/2 service
and sends push notifications to registered iOS devices.

APNs requires:
1. A .p8 private key from Apple Developer (ES256)
2. Key ID, Team ID, and Bundle ID from the Apple Developer portal
3. HTTP/2 connection to api.push.apple.com (or sandbox)

Step 7.5: Create Push Notification Service (Backend).
"""

import asyncio
import logging
import time
from pathlib import Path

import httpx
import jwt

from app.core.config import (
    APNS_AUTH_KEY_PATH,
    APNS_BUNDLE_ID,
    APNS_KEY_ID,
    APNS_TEAM_ID,
    APNS_USE_SANDBOX,
)

logger = logging.getLogger(__name__)

# APNs endpoints
APNS_PRODUCTION_URL = "https://api.push.apple.com"
APNS_SANDBOX_URL = "https://api.sandbox.push.apple.com"

# Cache the JWT token (valid for ~55 minutes, refresh at 50 min)
_cached_token: str | None = None
_token_generated_at: float = 0
TOKEN_REFRESH_INTERVAL = 50 * 60  # 50 minutes (tokens valid for 60)


# ===================================================================
# Auth Key Loading
# ===================================================================

def _load_auth_key() -> str:
    """
    Load the APNs .p8 private key from disk.

    Returns the key file contents as a string.

    Raises:
        FileNotFoundError: If the key file does not exist.
        RuntimeError: If APNS_AUTH_KEY_PATH is not configured.
    """
    if not APNS_AUTH_KEY_PATH:
        raise RuntimeError(
            "APNS_AUTH_KEY_PATH not configured. "
            "Set it in your .env file."
        )
    key_path = Path(APNS_AUTH_KEY_PATH)
    if not key_path.exists():
        raise FileNotFoundError(
            f"APNs auth key file not found: {APNS_AUTH_KEY_PATH}"
        )
    return key_path.read_text()


# ===================================================================
# JWT Token Generation
# ===================================================================

def _generate_apns_token() -> str:
    """
    Generate (or return cached) JWT for APNs authentication.

    Uses ES256 algorithm as required by Apple. Token includes:
    - iss: Team ID
    - iat: Issued-at timestamp

    The token is cached for 50 minutes (APNs allows up to 60).

    Returns:
        JWT token string for the Authorization header.

    Raises:
        RuntimeError: If APNs credentials are not configured.
        FileNotFoundError: If the .p8 key file is missing.
    """
    global _cached_token, _token_generated_at

    now = time.time()
    if _cached_token and (now - _token_generated_at) < TOKEN_REFRESH_INTERVAL:
        return _cached_token

    auth_key = _load_auth_key()

    token = jwt.encode(
        {"iss": APNS_TEAM_ID, "iat": int(now)},
        auth_key,
        algorithm="ES256",
        headers={"kid": APNS_KEY_ID},
    )

    _cached_token = token
    _token_generated_at = now

    logger.debug("Generated new APNs JWT token (key_id=%s)", APNS_KEY_ID)
    return token


# ===================================================================
# Notification Payload Builder
# ===================================================================

# Friendly cadence phrasing for the notification title. The scheduler only
# fires at 14/7/3 days before; the fallback covers any future cadence.
_DAYS_PHRASE = {
    14: "is two weeks away",
    7: "is next week",
    3: "is in 3 days",
}

# Fallback body when no personalized briefing snippet was generated.
FALLBACK_BODY = "Have you gotten them anything yet? Tap for a few ideas we picked out."


def build_notification_payload(
    *,
    partner_name: str,
    milestone_name: str,
    days_before: int,
    notification_id: str,
    milestone_id: str,
    briefing_snippet: str | None = None,
    occasion_category: str | None = None,
) -> dict:
    """
    Build the APNs notification payload.

    Title format: "[Partner Name]'s [Milestone] is next week" (friendly
    phrasing per cadence via _DAYS_PHRASE).
    Body: Uses the briefing snippet if available (personalized, hint-aware),
          otherwise a friendly generic nudge (FALLBACK_BODY).

    The category "MILESTONE_REMINDER" enables "View" and "Snooze"
    actions defined in the iOS app's UNNotificationCategory registration.

    Custom data keys allow the iOS app to deep-link to the recommendations
    screen on tap. `notification_id` / `milestone_id` identify what to fetch
    and mark viewed; `milestone_name` / `partner_name` / `days_before` let the
    tap-through render its header immediately from the payload, with no
    milestone lookup on the critical path (the header used to cost a full
    `GET /api/v1/milestones` round-trip before anything appeared).

    Args:
        partner_name: Display name of the partner from the vault.
        milestone_name: Display name of the milestone.
        days_before: Number of days until the milestone (14, 7, or 3).
        notification_id: UUID of the notification_queue entry.
        milestone_id: UUID of the milestone (for deep-linking).
        briefing_snippet: Optional condensed briefing for the notification body.
        occasion_category: Stable occasion key, so the tap-through can pick the
            entry modal's copy and illustration without a lookup. Omitted from
            the payload when absent, which the client reads as "default".

    Returns:
        dict: APNs-formatted payload ready for JSON serialization.
    """
    days_phrase = _DAYS_PHRASE.get(days_before, f"is in {days_before} days")
    title = f"{partner_name}'s {milestone_name} {days_phrase}"

    body = briefing_snippet if briefing_snippet else FALLBACK_BODY

    payload = {
        "aps": {
            "alert": {
                "title": title,
                "body": body,
            },
            "sound": "default",
            "category": "MILESTONE_REMINDER",
        },
        "notification_id": notification_id,
        "milestone_id": milestone_id,
        # Display payload — lets the tap-through render its header with zero
        # network calls (see the docstring).
        "milestone_name": milestone_name,
        "partner_name": partner_name,
        "days_before": days_before,
    }

    # Only sent when known. APNs payloads are size-capped (4KB), so there is no
    # value in shipping a null the client would treat the same as absent.
    if occasion_category:
        payload["occasion_category"] = occasion_category

    return payload


# ===================================================================
# Push Notification Delivery
# ===================================================================

async def send_push_notification(
    device_token: str,
    payload: dict,
) -> dict:
    """
    Send a push notification to a single device via APNs.

    Establishes an HTTP/2 connection to Apple's APNs server and
    sends the notification payload. Uses JWT bearer token auth.

    Args:
        device_token: Hex-encoded APNs device token from the users table.
        payload: The notification payload dict (from build_notification_payload).

    Returns:
        dict with keys:
        - success (bool): Whether the notification was accepted.
        - apns_id (str | None): The APNs-assigned notification ID.
        - status_code (int): HTTP status code from APNs.
        - reason (str | None): Error reason if failed.

    Raises:
        RuntimeError: If APNs is not configured.
    """
    if not APNS_KEY_ID or not APNS_TEAM_ID:
        raise RuntimeError(
            "APNs credentials not configured. "
            "Set APNS_KEY_ID, APNS_TEAM_ID, APNS_AUTH_KEY_PATH, "
            "and APNS_BUNDLE_ID in your .env file."
        )

    token = _generate_apns_token()
    base_url = APNS_SANDBOX_URL if APNS_USE_SANDBOX else APNS_PRODUCTION_URL
    url = f"{base_url}/3/device/{device_token}"

    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }

    async with httpx.AsyncClient(http2=True) as client:
        response = await client.post(
            url,
            json=payload,
            headers=headers,
            timeout=10.0,
        )

    apns_id = response.headers.get("apns-id")

    if response.status_code == 200:
        logger.info(
            "Push notification delivered: apns_id=%s, device=%s...",
            apns_id,
            device_token[:16],
        )
        return {
            "success": True,
            "apns_id": apns_id,
            "status_code": 200,
            "reason": None,
        }

    # Parse error response
    reason = None
    try:
        error_body = response.json()
        reason = error_body.get("reason")
    except Exception:
        reason = response.text or f"HTTP {response.status_code}"

    logger.warning(
        "APNs delivery failed: status=%d, reason=%s, device=%s..., apns_id=%s",
        response.status_code,
        reason,
        device_token[:16],
        apns_id,
    )

    return {
        "success": False,
        "apns_id": apns_id,
        "status_code": response.status_code,
        "reason": reason,
    }


# ===================================================================
# High-Level Delivery (DB Lookup + Send)
# ===================================================================

async def deliver_push_notification(
    *,
    user_id: str,
    notification_id: str,
    milestone_id: str,
    partner_name: str,
    milestone_name: str,
    days_before: int,
    vibes: list[str],
    recommendations_count: int,
    briefing_snippet: str | None = None,
    occasion_category: str | None = None,
) -> dict:
    """
    Look up the user's device token and deliver a push notification.

    Note: `vibes` and `recommendations_count` are retained for caller-signature
    stability but no longer influence the payload copy — the fallback body is
    the friendly generic nudge in `FALLBACK_BODY`.

    This is the main entry point called from the notification webhook.
    It handles:
    1. Looking up every registered device for the user (`user_devices`)
    2. Building the notification payload
    3. Sending to all of them concurrently
    4. Pruning tokens APNs reports as dead
    5. Returning an aggregate delivery result

    Delivery fans out because a user may have several devices — a phone and a
    tablet, or a real device and a Simulator during development. This used to
    read `users.device_token`, a single column that each registration
    overwrote, so only the most recently opened device ever got a
    notification and the others failed silently.

    Gracefully handles missing device tokens (returns success=False
    with reason "no_device_token" instead of raising).

    Args:
        user_id: UUID of the user to notify.
        notification_id: UUID of the notification_queue entry.
        milestone_id: UUID of the milestone.
        partner_name: Partner's display name (for notification title).
        milestone_name: Milestone display name (for notification title).
        days_before: Days until the milestone.
        vibes: Vibe tags from the vault (for notification body).
        recommendations_count: Number of recommendations generated.

    Returns:
        dict with the same keys `send_push_notification` returns, so callers
        are unaffected — `success` is True when *any* device took delivery.
        Adds `device_count`, `delivered_count` and `pruned_count`.
    """
    from app.db.supabase_client import get_service_client

    client = get_service_client()

    try:
        result = (
            client.table("user_devices")
            .select("device_token")
            .eq("user_id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error(
            "Failed to look up devices for user %s: %s",
            user_id[:8], exc,
        )
        return {
            "success": False,
            "apns_id": None,
            "status_code": 0,
            "reason": f"device_token_lookup_failed: {exc}",
            "device_count": 0,
            "delivered_count": 0,
            "failed_count": 0,
            "pruned_count": 0,
        }

    tokens = [
        row["device_token"] for row in (result.data or []) if row.get("device_token")
    ]

    if not tokens:
        logger.info(
            "No device registered for user %s — skipping push delivery",
            user_id[:8],
        )
        return {
            "success": False,
            "apns_id": None,
            "status_code": 0,
            "reason": "no_device_token",
            "device_count": 0,
            "delivered_count": 0,
            "failed_count": 0,
            "pruned_count": 0,
        }

    payload = build_notification_payload(
        partner_name=partner_name,
        milestone_name=milestone_name,
        days_before=days_before,
        notification_id=notification_id,
        milestone_id=milestone_id,
        briefing_snippet=briefing_snippet,
        occasion_category=occasion_category,
    )

    # Concurrent, and never raises: one unreachable device must not stop the
    # others from being notified.
    results = await asyncio.gather(
        *(send_push_notification(token, payload) for token in tokens),
        return_exceptions=True,
    )

    delivered: list[dict] = []
    failures: list[dict] = []
    dead_tokens: list[str] = []

    for token, outcome in zip(tokens, results):
        if isinstance(outcome, BaseException):
            logger.warning(
                "Push to device %s... raised: %s", token[:16], outcome
            )
            failures.append({"reason": f"exception: {outcome}", "status_code": 0})
            continue
        if outcome.get("success"):
            delivered.append(outcome)
        else:
            failures.append(outcome)
            if _is_dead_token(outcome):
                dead_tokens.append(token)

    pruned = _prune_dead_tokens(client, dead_tokens)

    # Failures that are neither "device is gone" nor "we delivered" — an APNs
    # 503, a throttle, a timeout. These are the ones a retry could fix.
    transient = [
        f for f in failures
        if not _is_dead_token(f) and f.get("status_code") != 200
    ]

    if delivered:
        if transient:
            # Deliberately still a success: the notification reached the user.
            # Returning failure would make the webhook 500 and QStash re-run
            # the whole delivery, which would push a DUPLICATE to every device
            # that already took it. A missed reminder on a second device is a
            # better outcome than a doubled one on the first. Logged loudly
            # because it is otherwise invisible.
            logger.warning(
                "Push for user %s reached %d/%d devices; %d transient "
                "failure(s) not retried: %s",
                user_id[:8], len(delivered), len(tokens), len(transient),
                [f.get("reason") for f in transient],
            )
        first = delivered[0]
        return {
            "success": True,
            "apns_id": first.get("apns_id"),
            "status_code": 200,
            "reason": None,
            "device_count": len(tokens),
            "delivered_count": len(delivered),
            "failed_count": len(failures),
            "pruned_count": pruned,
        }

    # Nothing landed. Surface a transient reason in preference to a terminal
    # one, so the webhook retries when a retry could actually help.
    worst = (transient or failures or [{}])[0]
    return {
        "success": False,
        "apns_id": worst.get("apns_id"),
        "status_code": worst.get("status_code", 0),
        "reason": worst.get("reason") or "push_not_delivered",
        "device_count": len(tokens),
        "delivered_count": 0,
        "failed_count": len(failures),
        "pruned_count": pruned,
    }


#: The only APNs verdict that means a device is genuinely gone: 410
#: `Unregistered`, i.e. the app was deleted from that device.
#:
#: Deliberately nothing else. `BadDeviceToken` and `DeviceTokenNotForTopic` are
#: tempting — they sound terminal — but APNs returns them for *server*
#: misconfiguration too: a wrong `APNS_USE_SANDBOX`, or a bundle ID that does
#: not match the token's app. In that state every push 400s, so treating them
#: as dead would delete every row in `user_devices` on the first send after a
#: bad deploy. There is no way back from that: delivery no longer reads
#: `users.device_token`, so every user would have to relaunch the app on every
#: device, and until they did, `no_device_token` would make the webhook cancel
#: their notifications permanently rather than retry.
#:
#: A pruning rule has to be safe when the *sender* is what is broken.
_DEAD_TOKEN_STATUS = 410
_DEAD_TOKEN_REASON = "Unregistered"


def _is_dead_token(outcome: dict) -> bool:
    return (
        outcome.get("status_code") == _DEAD_TOKEN_STATUS
        and outcome.get("reason") == _DEAD_TOKEN_REASON
    )


def _prune_dead_tokens(client, tokens: list[str]) -> int:
    """Delete devices APNs has told us are gone. Best-effort."""
    if not tokens:
        return 0
    try:
        client.table("user_devices").delete().in_("device_token", tokens).execute()
    except Exception as exc:
        logger.warning("Failed to prune %d dead device token(s): %s", len(tokens), exc)
        return 0
    logger.info("Pruned %d dead device token(s)", len(tokens))
    return len(tokens)
