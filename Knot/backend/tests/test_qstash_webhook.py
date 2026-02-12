"""
Step 7.1 Verification: QStash Webhook Integration

Tests that:
1. The QStash signature verification function correctly validates authentic JWTs
2. The QStash signature verification rejects tampered, expired, or missing signatures
3. The POST /api/v1/notifications/process endpoint authenticates via Upstash-Signature
4. The endpoint rejects requests with invalid or missing signatures (401)
5. The endpoint parses valid payloads and updates notification_queue entries
6. The endpoint returns 404 for non-existent notification IDs
7. The endpoint skips already-processed notifications
8. The publish_to_qstash function constructs correct headers and payload

Prerequisites:
- Complete Steps 0.6, 1.1-1.11 (Supabase + tables including notification_queue)
- PyJWT installed in the virtual environment
- QSTASH_CURRENT_SIGNING_KEY set in .env (for signature tests)

Run with: pytest tests/test_qstash_webhook.py -v
"""

import hashlib
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
import httpx
from fastapi.testclient import TestClient

from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
    QSTASH_CURRENT_SIGNING_KEY,
    QSTASH_NEXT_SIGNING_KEY,
)
from app.main import app
from app.services.qstash import verify_qstash_signature


# ---------------------------------------------------------------------------
# Helper: check if credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Test signing key — used for unit tests that don't need real QStash
# ---------------------------------------------------------------------------

TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"


# ---------------------------------------------------------------------------
# Helpers: generate QStash-style JWT signatures
# ---------------------------------------------------------------------------

def _create_qstash_signature(
    body: bytes,
    url: str,
    signing_key: str = TEST_SIGNING_KEY,
    *,
    expired: bool = False,
    wrong_body: bool = False,
    wrong_url: bool = False,
) -> str:
    """
    Create a QStash-compatible JWT signature for testing.

    QStash JWTs contain these claims:
      - iss: "Upstash"
      - sub: destination URL
      - exp: expiration timestamp
      - nbf: not-before timestamp
      - iat: issued-at timestamp
      - jti: unique message ID
      - body: SHA-256 hash of the request body
    """
    now = int(time.time())

    body_hash = hashlib.sha256(body).hexdigest()
    if wrong_body:
        body_hash = hashlib.sha256(b"tampered_body").hexdigest()

    destination = url
    if wrong_url:
        destination = "https://wrong.example.com/webhook"

    claims = {
        "iss": "Upstash",
        "sub": destination,
        "exp": now - 3600 if expired else now + 3600,
        "nbf": now - 60,
        "iat": now,
        "jti": f"msg_{uuid.uuid4().hex[:16]}",
        "body": body_hash,
    }

    return jwt.encode(claims, signing_key, algorithm="HS256")


# ---------------------------------------------------------------------------
# Helpers: Supabase admin operations (for integration tests)
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _create_auth_user(email: str, password: str) -> str:
    """Create a test user via Supabase Admin API. Returns user ID."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, (
        f"Failed to create auth user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["id"]


def _delete_auth_user(user_id: str):
    """Delete a test user via Supabase Admin API."""
    import warnings
    try:
        resp = httpx.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_admin_headers(),
        )
        if resp.status_code != 200:
            warnings.warn(
                f"Failed to delete auth user {user_id}: HTTP {resp.status_code}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(f"Exception deleting auth user {user_id}: {exc}", stacklevel=2)


def _insert_vault(data: dict) -> dict:
    """Insert a vault row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vault: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_milestone(data: dict) -> dict:
    """Insert a milestone row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert milestone: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_notification(data: dict) -> dict:
    """Insert a notification_queue row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert notification: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _get_notification(notif_id: str) -> dict | None:
    """Fetch a notification_queue row by ID. Returns None if not found."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        params={"id": f"eq.{notif_id}", "select": "*"},
    )
    assert resp.status_code == 200
    rows = resp.json()
    return rows[0] if rows else None


def _future_timestamp(days: int) -> str:
    """Return an ISO 8601 timestamp `days` in the future."""
    dt = datetime.now(timezone.utc) + timedelta(days=days)
    return dt.isoformat()


# ---------------------------------------------------------------------------
# Fixtures: test user, vault, milestone, and notification
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """Create a test auth user. CASCADE cleanup on teardown."""
    email = f"knot-qstash-{uuid.uuid4().hex[:8]}@test.example"
    password = f"QStashTest!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    yield {"id": user_id, "email": email}
    _delete_auth_user(user_id)


@pytest.fixture
def test_pending_notification(test_auth_user):
    """
    Create a vault, milestone, and pending notification for testing.
    Returns all IDs needed for webhook payload construction.
    """
    user_id = test_auth_user["id"]

    vault = _insert_vault({
        "user_id": user_id,
        "partner_name": "QStash Test Partner",
        "relationship_tenure_months": 12,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
    })

    milestone = _insert_milestone({
        "vault_id": vault["id"],
        "milestone_type": "birthday",
        "milestone_name": "Partner's Birthday",
        "milestone_date": "2000-06-15",
        "recurrence": "yearly",
    })

    notification = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone["id"],
        "scheduled_for": _future_timestamp(14),
        "days_before": 14,
    })

    yield {
        "user": test_auth_user,
        "vault": vault,
        "milestone": milestone,
        "notification": notification,
    }
    # CASCADE cleanup via auth user deletion


# ---------------------------------------------------------------------------
# FastAPI test client
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """FastAPI test client for the Knot API."""
    return TestClient(app)


# ===================================================================
# 1. QStash Signature Verification (Unit Tests)
# ===================================================================

class TestQStashSignatureVerification:
    """Unit tests for verify_qstash_signature() — no Supabase needed."""

    def test_valid_signature_accepted(self):
        """A correctly signed JWT with matching body hash should pass."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                claims = verify_qstash_signature(signature, body, url)

        assert claims["iss"] == "Upstash"
        assert claims["sub"] == url
        assert claims["body"] == hashlib.sha256(body).hexdigest()
        print("  Valid QStash signature accepted")

    def test_expired_signature_rejected(self):
        """An expired JWT should be rejected."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url, expired=True)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="expired"):
                    verify_qstash_signature(signature, body, url)

        print("  Expired QStash signature rejected")

    def test_wrong_body_hash_rejected(self):
        """A JWT with a mismatched body hash should be rejected."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url, wrong_body=True)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="Body hash mismatch"):
                    verify_qstash_signature(signature, body, url)

        print("  Mismatched body hash rejected")

    def test_wrong_url_rejected(self):
        """A JWT with a mismatched destination URL should be rejected."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url, wrong_url=True)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="Destination URL mismatch"):
                    verify_qstash_signature(signature, body, url)

        print("  Mismatched destination URL rejected")

    def test_wrong_signing_key_rejected(self):
        """A JWT signed with a different key should be rejected."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url, signing_key="wrong_key")

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="Invalid QStash signature"):
                    verify_qstash_signature(signature, body, url)

        print("  Wrong signing key rejected")

    def test_missing_signature_rejected(self):
        """An empty signature string should be rejected."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="Missing Upstash-Signature"):
                    verify_qstash_signature("", body, url)

        print("  Missing signature rejected")

    def test_no_signing_keys_configured_rejected(self):
        """Verification should fail if no signing keys are configured."""
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", ""):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with pytest.raises(ValueError, match="No QStash signing keys configured"):
                    verify_qstash_signature(signature, body, url)

        print("  No signing keys configured — rejected")

    def test_next_key_rotation_accepted(self):
        """
        When current key fails but next key succeeds, the signature
        should still be accepted (supports key rotation).
        """
        body = b'{"notification_id": "test-123"}'
        url = "https://api.knot.com/api/v1/notifications/process"
        next_key = "next_rotation_key"
        signature = _create_qstash_signature(body, url, signing_key=next_key)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", next_key):
                claims = verify_qstash_signature(signature, body, url)

        assert claims["iss"] == "Upstash"
        print("  Key rotation: next key accepted when current key fails")

    def test_jwt_claims_contain_message_id(self):
        """The decoded JWT should include a jti (message ID) claim."""
        body = b'{"test": true}'
        url = "https://api.knot.com/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                claims = verify_qstash_signature(signature, body, url)

        assert "jti" in claims
        assert claims["jti"].startswith("msg_")
        print(f"  JWT contains message ID: {claims['jti']}")


# ===================================================================
# 2. Webhook Endpoint — Authentication (Unit Tests via TestClient)
# ===================================================================

class TestWebhookAuthentication:
    """Test that the webhook endpoint enforces QStash signature verification."""

    def test_missing_signature_returns_401(self, client):
        """Requests without the Upstash-Signature header should get 401."""
        payload = {
            "notification_id": str(uuid.uuid4()),
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 14,
        }

        resp = client.post(
            "/api/v1/notifications/process",
            json=payload,
        )
        assert resp.status_code == 401, (
            f"Expected 401 for missing signature, got {resp.status_code}: {resp.text}"
        )
        print("  Missing Upstash-Signature header returns 401")

    def test_invalid_signature_returns_401(self, client):
        """Requests with a garbage signature should get 401."""
        payload = {
            "notification_id": str(uuid.uuid4()),
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 14,
        }

        resp = client.post(
            "/api/v1/notifications/process",
            json=payload,
            headers={"Upstash-Signature": "not-a-valid-jwt"},
        )
        assert resp.status_code == 401, (
            f"Expected 401 for invalid signature, got {resp.status_code}: {resp.text}"
        )
        print("  Invalid Upstash-Signature returns 401")

    def test_expired_signature_returns_401(self, client):
        """Requests with an expired QStash JWT should get 401."""
        payload = {
            "notification_id": str(uuid.uuid4()),
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 7,
        }
        body = json.dumps(payload).encode()

        # The TestClient generates a URL like http://testserver/...
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url, expired=True)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                resp = client.post(
                    "/api/v1/notifications/process",
                    content=body,
                    headers={
                        "Upstash-Signature": signature,
                        "Content-Type": "application/json",
                    },
                )
        assert resp.status_code == 401, (
            f"Expected 401 for expired signature, got {resp.status_code}: {resp.text}"
        )
        print("  Expired Upstash-Signature returns 401")


# ===================================================================
# 3. Webhook Endpoint — Payload Processing (Integration Tests)
# ===================================================================

@requires_supabase
class TestWebhookProcessing:
    """
    Integration tests that verify the webhook endpoint correctly
    processes notification_queue entries via Supabase.
    """

    def test_valid_webhook_processes_notification(self, client, test_pending_notification):
        """
        A valid webhook call with a matching notification_queue entry
        should update the status to 'sent' and return 200.
        """
        notif = test_pending_notification["notification"]
        user = test_pending_notification["user"]
        milestone = test_pending_notification["milestone"]

        payload = {
            "notification_id": notif["id"],
            "user_id": user["id"],
            "milestone_id": milestone["id"],
            "days_before": 14,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                resp = client.post(
                    "/api/v1/notifications/process",
                    content=body,
                    headers={
                        "Upstash-Signature": signature,
                        "Content-Type": "application/json",
                    },
                )

        assert resp.status_code == 200, (
            f"Expected 200, got {resp.status_code}: {resp.text}"
        )
        data = resp.json()
        assert data["status"] == "processed"
        assert data["notification_id"] == notif["id"]

        # Verify the database was updated
        updated = _get_notification(notif["id"])
        assert updated is not None
        assert updated["status"] == "sent"
        assert updated["sent_at"] is not None
        print(f"  Valid webhook processed notification {notif['id'][:8]}... → status='sent'")

    def test_nonexistent_notification_returns_404(self, client):
        """
        A webhook call referencing a non-existent notification_id
        should return 404.
        """
        fake_id = str(uuid.uuid4())
        payload = {
            "notification_id": fake_id,
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 7,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                resp = client.post(
                    "/api/v1/notifications/process",
                    content=body,
                    headers={
                        "Upstash-Signature": signature,
                        "Content-Type": "application/json",
                    },
                )

        assert resp.status_code == 404, (
            f"Expected 404 for non-existent notification, got {resp.status_code}: {resp.text}"
        )
        print("  Non-existent notification_id returns 404")

    def test_already_sent_notification_returns_skipped(self, client, test_pending_notification):
        """
        A webhook call for an already-sent notification should return
        status='skipped' instead of processing it again.
        """
        notif = test_pending_notification["notification"]
        user = test_pending_notification["user"]
        milestone = test_pending_notification["milestone"]

        # Manually mark the notification as 'sent'
        httpx.patch(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"id": f"eq.{notif['id']}"},
            json={
                "status": "sent",
                "sent_at": datetime.now(timezone.utc).isoformat(),
            },
        )

        payload = {
            "notification_id": notif["id"],
            "user_id": user["id"],
            "milestone_id": milestone["id"],
            "days_before": 14,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                resp = client.post(
                    "/api/v1/notifications/process",
                    content=body,
                    headers={
                        "Upstash-Signature": signature,
                        "Content-Type": "application/json",
                    },
                )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "skipped"
        assert "already sent" in data["message"]
        print("  Already-sent notification returns skipped")

    def test_cancelled_notification_returns_skipped(self, client, test_pending_notification):
        """
        A webhook call for a cancelled notification should return
        status='skipped' instead of processing it.
        """
        notif = test_pending_notification["notification"]
        user = test_pending_notification["user"]
        milestone = test_pending_notification["milestone"]

        # Manually mark the notification as 'cancelled'
        httpx.patch(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"id": f"eq.{notif['id']}"},
            json={"status": "cancelled"},
        )

        payload = {
            "notification_id": notif["id"],
            "user_id": user["id"],
            "milestone_id": milestone["id"],
            "days_before": 14,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                resp = client.post(
                    "/api/v1/notifications/process",
                    content=body,
                    headers={
                        "Upstash-Signature": signature,
                        "Content-Type": "application/json",
                    },
                )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "skipped"
        assert "already cancelled" in data["message"]
        print("  Cancelled notification returns skipped")


# ===================================================================
# 4. QStash Publish Function (Unit Tests)
# ===================================================================

class TestQStashPublish:
    """Unit tests for publish_to_qstash() — mocked HTTP calls."""

    @pytest.mark.asyncio
    async def test_publish_sends_correct_request(self):
        """publish_to_qstash should POST to the correct QStash URL with auth."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"messageId": "msg_test123"}
        mock_response.raise_for_status = MagicMock()

        with patch("app.services.qstash.UPSTASH_QSTASH_TOKEN", "test_token"):
            with patch("app.services.qstash.UPSTASH_QSTASH_URL", "https://qstash.upstash.io"):
                with patch("httpx.AsyncClient") as mock_client_cls:
                    mock_client = AsyncMock()
                    mock_client.post = AsyncMock(return_value=mock_response)
                    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
                    mock_client.__aexit__ = AsyncMock(return_value=False)
                    mock_client_cls.return_value = mock_client

                    from app.services.qstash import publish_to_qstash

                    result = await publish_to_qstash(
                        destination_url="https://api.knot.com/api/v1/notifications/process",
                        body={"notification_id": "test-123"},
                        delay_seconds=3600,
                    )

                    # Verify the call was made
                    mock_client.post.assert_called_once()
                    call_args = mock_client.post.call_args
                    called_url = call_args[0][0] if call_args[0] else call_args[1].get("url", "")

                    assert "qstash.upstash.io/v2/publish/" in called_url
                    assert "notifications/process" in called_url

                    # Check headers
                    called_headers = call_args[1].get("headers", {})
                    assert called_headers["Authorization"] == "Bearer test_token"
                    assert called_headers["Upstash-Delay"] == "3600s"
                    assert called_headers["Upstash-Retries"] == "3"

                    assert result["messageId"] == "msg_test123"
                    print("  publish_to_qstash sends correct request with auth and delay headers")

    @pytest.mark.asyncio
    async def test_publish_without_delay_omits_header(self):
        """When no delay is specified, the Upstash-Delay header should be absent."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"messageId": "msg_nodelay"}
        mock_response.raise_for_status = MagicMock()

        with patch("app.services.qstash.UPSTASH_QSTASH_TOKEN", "test_token"):
            with patch("app.services.qstash.UPSTASH_QSTASH_URL", "https://qstash.upstash.io"):
                with patch("httpx.AsyncClient") as mock_client_cls:
                    mock_client = AsyncMock()
                    mock_client.post = AsyncMock(return_value=mock_response)
                    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
                    mock_client.__aexit__ = AsyncMock(return_value=False)
                    mock_client_cls.return_value = mock_client

                    from app.services.qstash import publish_to_qstash

                    await publish_to_qstash(
                        destination_url="https://api.knot.com/webhook",
                        body={"test": True},
                    )

                    call_args = mock_client.post.call_args
                    called_headers = call_args[1].get("headers", {})
                    assert "Upstash-Delay" not in called_headers
                    print("  No delay → Upstash-Delay header omitted")

    @pytest.mark.asyncio
    async def test_publish_with_deduplication_id(self):
        """When a deduplication_id is provided, it should be in the headers."""
        mock_response = MagicMock()
        mock_response.json.return_value = {"messageId": "msg_dedup"}
        mock_response.raise_for_status = MagicMock()

        with patch("app.services.qstash.UPSTASH_QSTASH_TOKEN", "test_token"):
            with patch("app.services.qstash.UPSTASH_QSTASH_URL", "https://qstash.upstash.io"):
                with patch("httpx.AsyncClient") as mock_client_cls:
                    mock_client = AsyncMock()
                    mock_client.post = AsyncMock(return_value=mock_response)
                    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
                    mock_client.__aexit__ = AsyncMock(return_value=False)
                    mock_client_cls.return_value = mock_client

                    from app.services.qstash import publish_to_qstash

                    await publish_to_qstash(
                        destination_url="https://api.knot.com/webhook",
                        body={"test": True},
                        deduplication_id="dedup-123",
                    )

                    call_args = mock_client.post.call_args
                    called_headers = call_args[1].get("headers", {})
                    assert called_headers["Upstash-Deduplication-Id"] == "dedup-123"
                    print("  Deduplication ID included in headers")

    @pytest.mark.asyncio
    async def test_publish_raises_without_token(self):
        """publish_to_qstash should raise RuntimeError if token is not configured."""
        with patch("app.services.qstash.UPSTASH_QSTASH_TOKEN", ""):
            from app.services.qstash import publish_to_qstash

            with pytest.raises(RuntimeError, match="UPSTASH_QSTASH_TOKEN not configured"):
                await publish_to_qstash(
                    destination_url="https://api.knot.com/webhook",
                    body={"test": True},
                )
            print("  Missing token raises RuntimeError")


# ===================================================================
# 5. Module Import Verification
# ===================================================================

class TestModuleImports:
    """Verify all new modules import correctly."""

    def test_qstash_service_imports(self):
        """The QStash service module should import without errors."""
        from app.services.qstash import verify_qstash_signature, publish_to_qstash
        assert callable(verify_qstash_signature)
        assert callable(publish_to_qstash)
        print("  app.services.qstash imports successfully")

    def test_notification_models_import(self):
        """The notification models module should import without errors."""
        from app.models.notifications import (
            NotificationProcessRequest,
            NotificationProcessResponse,
        )
        assert NotificationProcessRequest is not None
        assert NotificationProcessResponse is not None
        print("  app.models.notifications imports successfully")

    def test_notifications_router_import(self):
        """The notifications API router should import without errors."""
        from app.api.notifications import router
        assert router is not None
        assert router.prefix == "/api/v1/notifications"
        print("  app.api.notifications router imports successfully")

    def test_config_qstash_variables(self):
        """QStash config variables should be accessible."""
        from app.core.config import (
            UPSTASH_QSTASH_TOKEN,
            UPSTASH_QSTASH_URL,
            QSTASH_CURRENT_SIGNING_KEY,
            QSTASH_NEXT_SIGNING_KEY,
            is_qstash_configured,
            validate_qstash_config,
        )
        assert isinstance(UPSTASH_QSTASH_URL, str)
        assert callable(is_qstash_configured)
        assert callable(validate_qstash_config)
        print("  QStash config variables accessible")

    def test_notifications_router_registered_in_app(self):
        """The notifications router should be registered in the main FastAPI app."""
        from app.main import app

        routes = [route.path for route in app.routes]
        assert "/api/v1/notifications/process" in routes, (
            f"Notifications process route not found in app routes. "
            f"Found: {[r for r in routes if 'notif' in r.lower()]}"
        )
        print("  /api/v1/notifications/process registered in app")
