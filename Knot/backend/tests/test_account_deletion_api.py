"""
Step 11.2 Verification: Account Deletion API

Tests the DELETE /api/v1/users/me endpoint that permanently deletes
a user's account and all associated data via Supabase Admin API cascade.

Tests cover:
1. Valid deletion returns 200 with status "deleted"
2. Auth user is removed from auth.users after deletion
3. Public user row is removed via CASCADE
4. No auth token → 401
5. Invalid auth token → 401
6. Module imports and router registration

Prerequisites:
- Supabase credentials in .env
- All migrations applied

Run with: pytest tests/test_account_deletion_api.py -v
"""

import pytest
import httpx
import uuid
import time

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
        if resp.status_code != 200:
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
        f"{SUPABASE_URL}/rest/v1/users?select=id&id=eq.{user_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200 and resp.json():
        return resp.json()[0]
    return None


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
    Create a test user, sign them in, and yield context.
    Does NOT auto-delete — the test itself deletes the user.
    If the test fails before deletion, cleanup attempts manual deletion.
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

    # Cleanup: attempt to delete if test didn't delete the user
    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user(client):
    """
    Create a test user, sign them in, and yield context.
    Auto-deletes on teardown (for auth-required tests that don't delete).
    """
    test_email = f"knot-auth-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


# ---------------------------------------------------------------------------
# Test: Valid Account Deletion
# ---------------------------------------------------------------------------

@requires_supabase
class TestValidDeletion:
    """DELETE /api/v1/users/me with valid authentication."""

    def test_delete_returns_200_with_status(self, client, test_auth_user_for_deletion):
        """Successful deletion returns 200 with status 'deleted'."""
        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "deleted"
        assert "permanently deleted" in data["message"].lower()

    def test_auth_user_removed_after_deletion(self, client, test_auth_user_for_deletion):
        """After deletion, the auth user no longer exists in auth.users."""
        user_id = test_auth_user_for_deletion["id"]

        # Delete the account
        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200

        # Wait for cascade
        time.sleep(0.5)

        # Verify auth user is gone
        exists = _check_auth_user_exists(user_id)
        assert not exists, "Auth user should not exist after account deletion"

    def test_public_user_removed_after_deletion(self, client, test_auth_user_for_deletion):
        """After deletion, the public.users row is removed via CASCADE."""
        user_id = test_auth_user_for_deletion["id"]

        # Verify user exists before deletion
        row_before = _query_public_user(user_id)
        assert row_before is not None, "Public user should exist before deletion"

        # Delete the account
        resp = client.delete(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {test_auth_user_for_deletion['access_token']}"},
        )
        assert resp.status_code == 200

        # Wait for cascade
        time.sleep(0.5)

        # Verify public user row is gone
        row_after = _query_public_user(user_id)
        assert row_after is None, "Public user row should be removed via CASCADE"


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
    """Verify all new modules are importable and registered."""

    def test_account_delete_response_import(self):
        """AccountDeleteResponse is importable."""
        from app.models.users import AccountDeleteResponse
        assert AccountDeleteResponse is not None

    def test_account_delete_response_defaults(self):
        """AccountDeleteResponse has correct default values."""
        from app.models.users import AccountDeleteResponse
        resp = AccountDeleteResponse()
        assert resp.status == "deleted"
        assert "permanently deleted" in resp.message.lower()

    def test_users_router_has_delete_route(self):
        """DELETE /api/v1/users/me route is registered in the app."""
        from app.main import app
        delete_routes = [
            route.path
            for route in app.routes
            if hasattr(route, "methods") and "DELETE" in route.methods
        ]
        assert "/api/v1/users/me" in delete_routes

    def test_existing_device_token_route_still_registered(self):
        """Existing POST /api/v1/users/device-token is still registered."""
        from app.main import app
        routes = [route.path for route in app.routes]
        assert "/api/v1/users/device-token" in routes
