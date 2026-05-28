"""
Step 15.5 Verification: Account Deletion API (60-day soft delete)

Tests the DELETE /api/v1/users/me endpoint that schedules a user's
account for deletion 60 days in the future. The hard-delete runs out
of band via the QStash purge worker (covered in
test_account_deletion_purge_api.py).

Tests cover:
1. Valid delete schedules the account (200 with scheduled_deletion_at)
2. The auth user is NOT removed immediately
3. public.users.scheduled_deletion_at is set ~60 days in the future
4. No auth token → 401, invalid token → 401
5. Module imports and route registration

Prerequisites:
- Supabase credentials in .env
- Migrations applied through 00024

Run with: pytest tests/test_account_deletion_api.py -v
"""

import pytest
import httpx
import uuid
import time
from datetime import datetime, timezone, timedelta

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Helper: check if Supabase credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Helpers: auth user management (same pattern as test_device_token_api.py)
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _service_headers() -> dict:
    """Headers for direct Supabase PostgREST queries (service role)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }


def _create_auth_user(email: str, password: str) -> str:
    """Create a test user via Supabase Admin API. Returns user ID."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={
            "email": email,
            "password": password,
            "email_confirm": True,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to create test auth user: HTTP {resp.status_code} — {resp.text}"
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
        if resp.status_code not in (200, 404):
            warnings.warn(
                f"Failed to delete test auth user {user_id}: "
                f"HTTP {resp.status_code} — {resp.text}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}",
            stacklevel=2,
        )


def _sign_in_user(email: str, password: str) -> dict:
    """Sign in a test user. Returns full session response with access_token."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={
            "email": email,
            "password": password,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to sign in test user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _query_public_user(user_id: str) -> dict | None:
    """Query the public.users table directly for a user row."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/users?select=id,scheduled_deletion_at&id=eq.{user_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200 and resp.json():
        return resp.json()[0]
    return None


def _set_scheduled_deletion(user_id: str, value):
    """Force-set scheduled_deletion_at on a user (helper for purge/gate tests)."""
    resp = httpx.patch(
        f"{SUPABASE_URL}/rest/v1/users?id=eq.{user_id}",
        headers={**_service_headers(), "Content-Type": "application/json"},
        json={"scheduled_deletion_at": value},
    )
    assert resp.status_code in (200, 204), (
        f"Failed to set scheduled_deletion_at: HTTP {resp.status_code} — {resp.text}"
    )


def _check_auth_user_exists(user_id: str) -> bool:
    """Check if an auth user still exists via the Admin API."""
    resp = httpx.get(
        f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
        headers=_admin_headers(),
    )
    return resp.status_code == 200


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def test_auth_user_for_deletion(client):
    """
    Create a test user, sign them in, yield context, and clean up after.
    """
    test_email = f"knot-delete-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "password": test_password,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user(client):
    """
    Create a test user, sign them in, and yield context.
    Auto-deletes on teardown (for auth-required tests).
    """
    test_email = f"knot-auth-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


# ---------------------------------------------------------------------------
# Test: Valid Soft-Delete Scheduling
# ---------------------------------------------------------------------------

@requires_supabase
class TestValidDeletion:
    """DELETE /api/v1/users/me schedules the account; does not purge."""

    def test_delete_returns_200_with_scheduled_status(self, client, test_auth_user_for_deletion):
        """Successful schedule returns 200 with status 'scheduled' and a future date."""
        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["status"] == "scheduled"
        assert "scheduled_deletion_at" in data
        scheduled = datetime.fromisoformat(data["scheduled_deletion_at"].replace("Z", "+00:00"))
        delta = scheduled - datetime.now(timezone.utc)
        # 60 days ± 5 min slack for clock drift / request latency
        assert timedelta(days=60) - timedelta(minutes=5) < delta < timedelta(days=60) + timedelta(minutes=5), (
            f"Scheduled date should be ~60 days out, got delta={delta}"
        )

    def test_auth_user_still_exists_after_schedule(self, client, test_auth_user_for_deletion):
        """After scheduling, auth.users still has the row (hard-delete is deferred)."""
        user_id = test_auth_user_for_deletion["id"]

        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200

        time.sleep(0.5)

        assert _check_auth_user_exists(user_id), (
            "Auth user should still exist during the 60-day grace window"
        )

    def test_public_user_has_scheduled_deletion_at(self, client, test_auth_user_for_deletion):
        """After scheduling, public.users.scheduled_deletion_at is set."""
        user_id = test_auth_user_for_deletion["id"]

        before = _query_public_user(user_id)
        assert before is not None
        assert before.get("scheduled_deletion_at") is None, (
            "Fresh test user should not be pending deletion"
        )

        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200
        time.sleep(0.5)

        after = _query_public_user(user_id)
        assert after is not None, "Public user row should still exist during grace"
        assert after.get("scheduled_deletion_at") is not None, (
            "scheduled_deletion_at should be set after DELETE /me"
        )

    def test_delete_twice_reschedules(self, client, test_auth_user_for_deletion):
        """Calling DELETE /me again refreshes scheduled_deletion_at instead of 410-ing."""
        token = test_auth_user_for_deletion["access_token"]
        user_id = test_auth_user_for_deletion["id"]

        first = client.delete("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"})
        assert first.status_code == 200
        first_at = first.json()["scheduled_deletion_at"]

        time.sleep(1.1)  # ensure timestamp difference exceeds clock resolution

        second = client.delete("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"})
        assert second.status_code == 200, second.text
        second_at = second.json()["scheduled_deletion_at"]

        assert second_at > first_at, "Second delete should push scheduled_deletion_at forward"
        assert _check_auth_user_exists(user_id)


# ---------------------------------------------------------------------------
# Test: Authentication Required
# ---------------------------------------------------------------------------

@requires_supabase
class TestAuthRequired:
    """Endpoint requires valid Bearer token."""

    def test_no_auth_header_returns_401(self, client):
        """Request without Authorization header is rejected."""
        resp = client.delete("/api/v1/users/me")
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Invalid Bearer token is rejected."""
        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": "Bearer invalid_token_here"},
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Test: Module Imports
# ---------------------------------------------------------------------------

class TestModuleImports:
    """Verify the new soft-delete shape is wired up."""

    def test_account_delete_response_import(self):
        from app.models.users import AccountDeleteResponse
        assert AccountDeleteResponse is not None

    def test_account_delete_response_requires_scheduled_at(self):
        """AccountDeleteResponse(scheduled_deletion_at=...) has the new default status."""
        from app.models.users import AccountDeleteResponse
        resp = AccountDeleteResponse(scheduled_deletion_at="2099-01-01T00:00:00+00:00")
        assert resp.status == "scheduled"
        assert resp.scheduled_deletion_at == "2099-01-01T00:00:00+00:00"

    def test_users_router_has_expected_routes(self):
        from app.main import app
        paths = {(tuple(sorted(r.methods)) if hasattr(r, "methods") else None, r.path)
                 for r in app.routes if hasattr(r, "methods")}
        assert (("DELETE",), "/api/v1/users/me") in paths
        assert (("POST",), "/api/v1/users/me/restore") in paths
        assert (("POST",), "/api/v1/users/process-deletion") in paths
        assert (("GET",), "/api/v1/users/me") in paths

    def test_existing_device_token_route_still_registered(self):
        from app.main import app
        routes = [route.path for route in app.routes]
        assert "/api/v1/users/device-token" in routes
