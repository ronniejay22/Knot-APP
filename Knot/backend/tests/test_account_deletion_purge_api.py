"""
Step 15.5: Tests for the QStash purge worker

POST /api/v1/users/process-deletion is the webhook QStash calls 60 days
after a user requested deletion. It must:

  * Reject calls with no/invalid/expired Upstash-Signature.
  * No-op when scheduled_deletion_at has been cleared (user restored).
  * No-op when scheduled_deletion_at was pushed into the future
    (user re-scheduled and a stale message arrived first).
  * Otherwise hard-delete the auth user via Supabase Admin API.

Run with: pytest tests/test_account_deletion_purge_api.py -v
"""

import hashlib
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import jwt
import httpx
import pytest

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
from tests.test_account_deletion_api import (
    _check_auth_user_exists,
    _create_auth_user,
    _delete_auth_user,
    _query_public_user,
    _set_scheduled_deletion,
    _sign_in_user,
    requires_supabase,
)


TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"
WORKER_URL = "http://testserver/api/v1/users/process-deletion"


def _qstash_signature(body: bytes, url: str = WORKER_URL, *, expired: bool = False) -> str:
    """Build a JWT QStash would have signed for this body+url."""
    now = int(time.time())
    claims = {
        "iss": "Upstash",
        "sub": url,
        "exp": now - 3600 if expired else now + 3600,
        "nbf": now - 60,
        "iat": now,
        "jti": f"msg_{uuid.uuid4().hex[:16]}",
        "body": hashlib.sha256(body).hexdigest(),
    }
    return jwt.encode(claims, TEST_SIGNING_KEY, algorithm="HS256")


@pytest.fixture
def client():
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def due_user(client):
    """A user whose scheduled_deletion_at is in the past — the purge should run."""
    email = f"knot-purge-due-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    _set_scheduled_deletion(
        user_id, (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    )
    yield {"id": user_id}
    _delete_auth_user(user_id)


@pytest.fixture
def restored_user(client):
    """A user whose scheduled_deletion_at is null — purge must noop."""
    email = f"knot-purge-restored-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    # Leave scheduled_deletion_at NULL (default)
    yield {"id": user_id}
    _delete_auth_user(user_id)


@pytest.fixture
def future_user(client):
    """A user whose scheduled_deletion_at is still in the future."""
    email = f"knot-purge-future-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    _set_scheduled_deletion(
        user_id, (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
    )
    yield {"id": user_id}
    _delete_auth_user(user_id)


class TestSignature:
    """Signature verification is independent of any user state."""

    def test_missing_signature_returns_401(self, client):
        resp = client.post(
            "/api/v1/users/process-deletion",
            json={"user_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 401

    def test_invalid_signature_returns_401(self, client):
        resp = client.post(
            "/api/v1/users/process-deletion",
            json={"user_id": str(uuid.uuid4())},
            headers={"Upstash-Signature": "not-a-jwt"},
        )
        assert resp.status_code == 401

    def test_expired_signature_returns_401(self, client):
        body = json.dumps({"user_id": str(uuid.uuid4())}).encode()
        signature = _qstash_signature(body, expired=True)

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY), \
             patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
            resp = client.post(
                "/api/v1/users/process-deletion",
                content=body,
                headers={
                    "Upstash-Signature": signature,
                    "Content-Type": "application/json",
                },
            )
        assert resp.status_code == 401


@requires_supabase
class TestPurgeBehavior:
    """End-to-end behavior with a real Supabase project."""

    def _send(self, client, payload: dict):
        body = json.dumps(payload).encode()
        signature = _qstash_signature(body)
        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY), \
             patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
            return client.post(
                "/api/v1/users/process-deletion",
                content=body,
                headers={
                    "Upstash-Signature": signature,
                    "Content-Type": "application/json",
                },
            )

    def test_due_user_is_hard_deleted(self, client, due_user):
        resp = self._send(client, {"user_id": due_user["id"]})
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "deleted"

        time.sleep(0.5)
        assert not _check_auth_user_exists(due_user["id"])
        assert _query_public_user(due_user["id"]) is None

    def test_restored_user_is_skipped(self, client, restored_user):
        resp = self._send(client, {"user_id": restored_user["id"]})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["status"] == "skipped"
        assert body["reason"] == "restored"

        time.sleep(0.5)
        assert _check_auth_user_exists(restored_user["id"])

    def test_future_scheduled_user_is_skipped(self, client, future_user):
        resp = self._send(client, {"user_id": future_user["id"]})
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["status"] == "skipped"
        assert body["reason"] == "rescheduled"

        time.sleep(0.5)
        assert _check_auth_user_exists(future_user["id"])

    def test_already_gone_user_returns_deleted(self, client):
        """An auth user that no longer exists is treated as success (idempotent replay)."""
        random_id = str(uuid.uuid4())
        resp = self._send(client, {"user_id": random_id})
        # 404 from admin API is mapped to 200 'deleted' for idempotency
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "deleted"


class TestPayload:
    """Bad payload shapes."""

    def test_missing_user_id_returns_422(self, client):
        body = json.dumps({}).encode()
        signature = _qstash_signature(body)
        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY), \
             patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
            resp = client.post(
                "/api/v1/users/process-deletion",
                content=body,
                headers={
                    "Upstash-Signature": signature,
                    "Content-Type": "application/json",
                },
            )
        assert resp.status_code == 422
