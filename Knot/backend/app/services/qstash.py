"""
QStash Service — Upstash QStash integration for scheduled notifications.

Handles publishing messages to QStash for delayed delivery and verifying
incoming webhook signatures to ensure requests originate from QStash.

QStash uses HMAC-SHA256 signature verification. Each webhook request
includes an `Upstash-Signature` header containing a JWT signed with
the current (or next) signing key. We verify this JWT to authenticate
inbound webhook calls.

Step 7.1: Set up QStash scheduler integration.
"""

import hashlib
import logging
from typing import Any

import httpx
import jwt

from app.core.config import (
    QSTASH_CURRENT_SIGNING_KEY,
    QSTASH_NEXT_SIGNING_KEY,
    UPSTASH_QSTASH_TOKEN,
    UPSTASH_QSTASH_URL,
)

logger = logging.getLogger(__name__)


# ===================================================================
# Signature Verification
# ===================================================================

def verify_qstash_signature(
    signature: str,
    body: bytes,
    url: str,
) -> dict:
    """
    Verify that an incoming webhook request is authentically from QStash.

    QStash signs each webhook with a JWT (in the Upstash-Signature header).
    The JWT payload includes:
      - iss: "Upstash"
      - sub: The destination URL
      - exp: Expiration timestamp
      - nbf: Not-before timestamp
      - iat: Issued-at timestamp
      - jti: Unique message ID
      - body: SHA-256 hash of the request body

    We try the current signing key first, then fall back to the next
    signing key (supports key rotation without downtime).

    Args:
        signature: The Upstash-Signature header value (JWT string).
        body: The raw request body bytes.
        url: The destination URL this webhook was sent to.

    Returns:
        dict: The decoded JWT claims on success.

    Raises:
        ValueError: If the signature is invalid, expired, or the body
                    hash does not match.
    """
    if not signature:
        raise ValueError("Missing Upstash-Signature header")

    # Try current key first, then next key (for rotation)
    keys_to_try = []
    if QSTASH_CURRENT_SIGNING_KEY:
        keys_to_try.append(("current", QSTASH_CURRENT_SIGNING_KEY))
    if QSTASH_NEXT_SIGNING_KEY:
        keys_to_try.append(("next", QSTASH_NEXT_SIGNING_KEY))

    if not keys_to_try:
        raise ValueError(
            "No QStash signing keys configured. "
            "Set QSTASH_CURRENT_SIGNING_KEY in your .env file."
        )

    last_error = None
    for key_name, signing_key in keys_to_try:
        try:
            claims = jwt.decode(
                signature,
                signing_key,
                algorithms=["HS256"],
                issuer="Upstash",
                options={
                    "require": ["iss", "sub", "exp", "nbf", "iat", "jti", "body"],
                },
            )

            # Verify the body hash matches
            expected_body_hash = hashlib.sha256(body).hexdigest()
            if claims.get("body") != expected_body_hash:
                raise ValueError(
                    f"Body hash mismatch: expected {expected_body_hash}, "
                    f"got {claims.get('body')}"
                )

            # Verify the destination URL matches
            if claims.get("sub") != url:
                raise ValueError(
                    f"Destination URL mismatch: expected {url}, "
                    f"got {claims.get('sub')}"
                )

            logger.info(
                f"QStash signature verified with {key_name} key "
                f"(message_id={claims.get('jti')})"
            )
            return claims

        except jwt.ExpiredSignatureError:
            last_error = ValueError("QStash signature has expired")
        except jwt.InvalidTokenError as exc:
            last_error = ValueError(f"Invalid QStash signature ({key_name} key): {exc}")
        except ValueError:
            raise
        except Exception as exc:
            last_error = ValueError(f"QStash verification failed ({key_name} key): {exc}")

    raise last_error or ValueError("QStash signature verification failed")


# ===================================================================
# Message Publishing
# ===================================================================

async def publish_to_qstash(
    destination_url: str,
    body: dict[str, Any],
    *,
    delay_seconds: int | None = None,
    deduplication_id: str | None = None,
    retries: int = 3,
) -> dict:
    """
    Publish a message to QStash for delayed or immediate delivery.

    QStash will deliver the message to the destination URL as a POST
    request with the provided JSON body. Optionally schedule delivery
    after a delay.

    Args:
        destination_url: The webhook URL QStash should POST to.
        body: The JSON payload to deliver.
        delay_seconds: Optional delay before delivery (in seconds).
        deduplication_id: Optional ID to prevent duplicate deliveries.
        retries: Number of delivery retries on failure (default 3).

    Returns:
        dict: QStash publish response containing messageId.

    Raises:
        RuntimeError: If QStash credentials are not configured.
        httpx.HTTPStatusError: If the QStash API returns an error.
    """
    if not UPSTASH_QSTASH_TOKEN:
        raise RuntimeError(
            "UPSTASH_QSTASH_TOKEN not configured. "
            "Set it in your .env file."
        )

    headers: dict[str, str] = {
        "Authorization": f"Bearer {UPSTASH_QSTASH_TOKEN}",
        "Content-Type": "application/json",
        "Upstash-Retries": str(retries),
    }

    if delay_seconds is not None and delay_seconds > 0:
        headers["Upstash-Delay"] = f"{delay_seconds}s"

    if deduplication_id:
        headers["Upstash-Deduplication-Id"] = deduplication_id

    publish_url = f"{UPSTASH_QSTASH_URL}/v2/publish/{destination_url}"

    async with httpx.AsyncClient() as client:
        response = await client.post(
            publish_url,
            headers=headers,
            json=body,
            timeout=10.0,
        )
        response.raise_for_status()

    result = response.json()
    logger.info(
        f"Published message to QStash: messageId={result.get('messageId')}, "
        f"destination={destination_url}, delay={delay_seconds}s"
    )
    return result
