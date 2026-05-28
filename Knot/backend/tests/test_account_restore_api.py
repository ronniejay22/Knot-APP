"""
Step 15.5: Tests for POST /api/v1/users/me/restore

The restore endpoint clears scheduled_deletion_at so a user who tapped
"Delete Account" can come back within the 60-day window. It must
bypass the get_active_user_id gate (pending users need to be able to
call it) while still requiring authentication.

Run with: pytest tests/test_account_restore_api.py -v
"""

import pytest
import time
import uuid
from datetime import datetime, timezone

from tests.test_account_deletion_api import (
    _create_auth_user,
    _delete_auth_user,
    _query_public_user,
    _set_scheduled_deletion,
    _sign_in_user,
    requires_supabase,
)


@pytest.fixture
def client():
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def pending_user(client):
    """Create a test user, force them into pending-deletion state, yield context."""
    email = f"knot-restore-test-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    session = _sign_in_user(email, password)
    _set_scheduled_deletion(user_id, datetime.now(timezone.utc).isoformat())

    yield {"id": user_id, "access_token": session["access_token"]}

    _delete_auth_user(user_id)


@pytest.fixture
def active_user(client):
    """Create a normal (non-pending) test user."""
    email = f"knot-restore-active-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    session = _sign_in_user(email, password)

    yield {"id": user_id, "access_token": session["access_token"]}

    _delete_auth_user(user_id)


@requires_supabase
class TestRestore:
    def test_restore_clears_scheduled_deletion_at(self, client, pending_user):
        resp = client.post(
            "/api/v1/users/me/restore",
            headers={"Authorization": f"Bearer {pending_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "restored"

        time.sleep(0.5)
        row = _query_public_user(pending_user["id"])
        assert row is not None
        assert row["scheduled_deletion_at"] is None

    def test_restore_is_idempotent_on_active_user(self, client, active_user):
        """Calling restore on a non-pending user is a no-op 200."""
        resp = client.post(
            "/api/v1/users/me/restore",
            headers={"Authorization": f"Bearer {active_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "restored"

    def test_restore_requires_auth(self, client):
        resp = client.post("/api/v1/users/me/restore")
        assert resp.status_code == 401

    def test_restore_rejects_invalid_token(self, client):
        resp = client.post(
            "/api/v1/users/me/restore",
            headers={"Authorization": "Bearer invalid_token"},
        )
        assert resp.status_code == 401


@requires_supabase
class TestAccountStatusProbe:
    """GET /api/v1/users/me — used by iOS after sign-in to detect pending state."""

    def test_status_returns_null_for_active(self, client, active_user):
        resp = client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {active_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["user_id"] == active_user["id"]
        assert body["scheduled_deletion_at"] is None

    def test_status_returns_iso_for_pending(self, client, pending_user):
        resp = client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {pending_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body["user_id"] == pending_user["id"]
        assert body["scheduled_deletion_at"] is not None
