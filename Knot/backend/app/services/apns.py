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

def build_notification_payload(
    *,
    partner_name: str,
    milestone_name: str,
    days_before: int,
    vibes: list[str],
    recommendations_count: int,
    notification_id: str,
    milestone_id: str,
) -> dict:
    """
    Build the APNs notification payload.

    Title format: "[Partner Name]'s [Milestone] is in [X] days"
    Body format: "I've found [N] [Vibe] options based on their interests.
                  Tap to see them."

    The category "MILESTONE_REMINDER" enables "View" and "Snooze"
    actions defined in the iOS app's UNNotificationCategory registration.

    Custom data keys (notification_id, milestone_id) allow the iOS app
    to deep-link to the recommendations screen on tap.

    Args:
        partner_name: Display name of the partner from the vault.
        milestone_name: Display name of the milestone.
        days_before: Number of days until the milestone (14, 7, or 3).
        vibes: List of vibe tags from the vault.
        recommendations_count: Number of recommendations generated.
        notification_id: UUID of the notification_queue entry.
        milestone_id: UUID of the milestone (for deep-linking).

    Returns:
        dict: APNs-formatted payload ready for JSON serialization.
    """
    title = f"{partner_name}'s {milestone_name} is in {days_before} days"

    # Use the first vibe tag for the body, capitalize it
    vibe_label = vibes[0].replace("_", " ").capitalize() if vibes else "curated"

    body = (
        f"I've found {recommendations_count} {vibe_label} options "
        f"based on their interests. Tap to see them."
    )

    return {
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
    }


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
) -> dict:
    """
    Look up the user's device token and deliver a push notification.

    This is the main entry point called from the notification webhook.
    It handles:
    1. Looking up the device_token from the users table
    2. Building the notification payload
    3. Sending via APNs
    4. Returning the delivery result

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
        dict with delivery result (see send_push_notification).
    """
    from app.db.supabase_client import get_service_client

    client = get_service_client()

    try:
        result = (
            client.table("users")
            .select("device_token, device_platform")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error(
            "Failed to look up device token for user %s: %s",
            user_id[:8], exc,
        )
        return {
            "success": False,
            "apns_id": None,
            "status_code": 0,
            "reason": f"device_token_lookup_failed: {exc}",
        }

    if not result.data or not result.data[0].get("device_token"):
        logger.info(
            "No device token registered for user %s — skipping push delivery",
            user_id[:8],
        )
        return {
            "success": False,
            "apns_id": None,
            "status_code": 0,
            "reason": "no_device_token",
        }

    device_token = result.data[0]["device_token"]

    payload = build_notification_payload(
        partner_name=partner_name,
        milestone_name=milestone_name,
        days_before=days_before,
        vibes=vibes,
        recommendations_count=recommendations_count,
        notification_id=notification_id,
        milestone_id=milestone_id,
    )

    return await send_push_notification(device_token, payload)
