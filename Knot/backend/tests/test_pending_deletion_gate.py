"""
Step 15.5: Tests for the get_active_user_id pending-deletion gate.

When a user's scheduled_deletion_at is non-null, any route that depends on
get_active_user_id must return HTTP 410 Gone with a body containing the
ISO timestamp. This lets the iOS client surface the PendingDeletionView
before any other API call.

We exercise the gate against an endpoint that uses get_active_user_id —
GET /api/v1/users/me/notification-preferences — because it requires no
extra fixtures beyond the user itself.

Run with: pytest tests/test_pending_deletion_gate.py -v
"""

import pytest
import time
import uuid
from datetime import datetime, timezone

from tests.test_account_deletion_api import (
    _create_auth_user,
    _delete_auth_user,
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
def user_session(client):
    email = f"knot-gate-test-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    session = _sign_in_user(email, password)

    yield {"id": user_id, "access_token": session["access_token"]}

    _delete_auth_user(user_id)


@requires_supabase
class TestPendingDeletionGate:
    def test_active_user_passes_gate(self, client, user_session):
        """Non-pending user can reach an active-gated endpoint."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {user_session['access_token']}"},
        )
        assert resp.status_code == 200, resp.text

    def test_pending_user_is_410(self, client, user_session):
        """A user with scheduled_deletion_at set gets 410 from active-gated routes."""
        scheduled_iso = datetime.now(timezone.utc).isoformat()
        _set_scheduled_deletion(user_session["id"], scheduled_iso)

        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {user_session['access_token']}"},
        )
        assert resp.status_code == 410, resp.text
        body = resp.json()
        assert body["detail"]["code"] == "account_pending_deletion"
        assert body["detail"]["scheduled_deletion_at"] is not None

    def test_pending_user_can_restore_then_continue(self, client, user_session):
        """After restore, the gate clears and the user can call active endpoints again."""
        _set_scheduled_deletion(user_session["id"], datetime.now(timezone.utc).isoformat())

        # Confirm 410 first
        gated = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {user_session['access_token']}"},
        )
        assert gated.status_code == 410

        # Restore
        restore = client.post(
            "/api/v1/users/me/restore",
            headers={"Authorization": f"Bearer {user_session['access_token']}"},
        )
        assert restore.status_code == 200

        time.sleep(0.5)

        # Now the same endpoint should succeed
        ok = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {user_session['access_token']}"},
        )
        assert ok.status_code == 200, ok.text
