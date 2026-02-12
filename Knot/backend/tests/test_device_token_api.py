"""
Step 7.4 Verification: Device Token Registration API

Tests the POST /api/v1/users/device-token endpoint that stores
APNs device tokens for push notification delivery.

Tests cover:
1. Valid token registration → 200 with status "registered"
2. Token update (second POST) → 200 with status "updated"
3. Token stored in database (verified via service client)
4. Second token replaces the first in the database
5. Empty device_token → 422
6. Invalid platform → 422
7. Missing device_token field → 422
8. No auth token → 401
9. Invalid auth token → 401
10. Module imports and router registration

Prerequisites:
- Supabase credentials in .env
- Migration 00013 applied (device_token + device_platform columns on users table)

Run with: pytest tests/test_device_token_api.py -v
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
# Helpers: auth user management (same pattern as test_vault_api.py)
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


def _query_user_device_token(user_id: str) -> dict | None:
    """Query the users table directly for device token columns."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/users?select=device_token,device_platform&id=eq.{user_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200 and resp.json():
        return resp.json()[0]
    return None


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
def test_auth_user(client):
    """
    Create a test user, sign them in, and yield context.
    Cleanup deletes the auth user (CASCADE removes all data).
    """
    test_email = f"knot-devtoken-test-{uuid.uuid4().hex[:8]}@test.example"
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
# Test: Valid Device Token Registration
# ---------------------------------------------------------------------------

@requires_supabase
class TestValidRegistration:
    """POST /api/v1/users/device-token with a valid token."""

    def test_register_token_returns_200(self, client, test_auth_user):
        """First registration returns 200 with status 'registered'."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={
                "device_token": "abc123def456" * 4,
                "platform": "ios",
            },
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "registered"
        assert data["device_token"] == "abc123def456" * 4
        assert data["platform"] == "ios"

    def test_register_token_default_platform(self, client, test_auth_user):
        """Platform defaults to 'ios' when not specified."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "testtoken123456"},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200
        assert resp.json()["platform"] == "ios"

    def test_register_android_token(self, client, test_auth_user):
        """Android platform is accepted."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "fcm_token_abc123", "platform": "android"},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200
        assert resp.json()["platform"] == "android"


# ---------------------------------------------------------------------------
# Test: Token Update
# ---------------------------------------------------------------------------

@requires_supabase
class TestTokenUpdate:
    """POST twice with different tokens — second returns 'updated'."""

    def test_second_registration_returns_updated(self, client, test_auth_user):
        """Updating an existing token returns status 'updated'."""
        headers = {"Authorization": f"Bearer {test_auth_user['access_token']}"}

        # First registration
        resp1 = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "first_token_aaa111"},
            headers=headers,
        )
        assert resp1.status_code == 200
        assert resp1.json()["status"] == "registered"

        # Second registration with different token
        resp2 = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "second_token_bbb222"},
            headers=headers,
        )
        assert resp2.status_code == 200
        assert resp2.json()["status"] == "updated"
        assert resp2.json()["device_token"] == "second_token_bbb222"


# ---------------------------------------------------------------------------
# Test: Database Storage
# ---------------------------------------------------------------------------

@requires_supabase
class TestDatabaseStorage:
    """Verify the token is actually stored in the users table."""

    def test_token_stored_in_database(self, client, test_auth_user):
        """Device token and platform are stored in the users table."""
        token = "hex_device_token_" + uuid.uuid4().hex[:32]
        headers = {"Authorization": f"Bearer {test_auth_user['access_token']}"}

        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": token, "platform": "ios"},
            headers=headers,
        )
        assert resp.status_code == 200

        # Query the database directly
        row = _query_user_device_token(test_auth_user["id"])
        assert row is not None
        assert row["device_token"] == token
        assert row["device_platform"] == "ios"

    def test_second_token_replaces_first(self, client, test_auth_user):
        """Only the latest token is stored — no duplicates."""
        headers = {"Authorization": f"Bearer {test_auth_user['access_token']}"}

        # Register first token
        client.post(
            "/api/v1/users/device-token",
            json={"device_token": "old_token_111"},
            headers=headers,
        )

        # Register second token
        client.post(
            "/api/v1/users/device-token",
            json={"device_token": "new_token_222"},
            headers=headers,
        )

        # Verify only the latest token is stored
        row = _query_user_device_token(test_auth_user["id"])
        assert row is not None
        assert row["device_token"] == "new_token_222"

    def test_initial_device_token_is_null(self, client, test_auth_user):
        """Before registration, device_token is NULL."""
        row = _query_user_device_token(test_auth_user["id"])
        assert row is not None
        assert row["device_token"] is None
        assert row["device_platform"] is None


# ---------------------------------------------------------------------------
# Test: Validation Errors
# ---------------------------------------------------------------------------

@requires_supabase
class TestValidationErrors:
    """Invalid payloads return 422."""

    def test_empty_token_returns_422(self, client, test_auth_user):
        """Empty device_token string is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": ""},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 422

    def test_whitespace_only_token_returns_422(self, client, test_auth_user):
        """Whitespace-only device_token is rejected (stripped then empty check)."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "   "},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 422

    def test_invalid_platform_returns_422(self, client, test_auth_user):
        """Invalid platform value is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "valid_token", "platform": "windows"},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 422

    def test_missing_token_field_returns_422(self, client, test_auth_user):
        """Missing device_token field is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"platform": "ios"},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 422

    def test_token_too_long_returns_422(self, client, test_auth_user):
        """Device token exceeding max_length (200) is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "x" * 201},
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Test: Authentication Required
# ---------------------------------------------------------------------------

@requires_supabase
class TestAuthRequired:
    """Endpoint requires valid Bearer token."""

    def test_no_auth_header_returns_401(self, client):
        """Request without Authorization header is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "some_token"},
        )
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Invalid Bearer token is rejected."""
        resp = client.post(
            "/api/v1/users/device-token",
            json={"device_token": "some_token"},
            headers={"Authorization": "Bearer invalid_token_here"},
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Test: Module Imports
# ---------------------------------------------------------------------------

class TestModuleImports:
    """Verify all new modules are importable and registered."""

    def test_users_models_import(self):
        """User models are importable."""
        from app.models.users import DeviceTokenRequest, DeviceTokenResponse
        assert DeviceTokenRequest is not None
        assert DeviceTokenResponse is not None

    def test_users_router_import(self):
        """Users router is importable."""
        from app.api.users import router
        assert router is not None

    def test_users_router_registered_in_app(self):
        """Users router is registered in the FastAPI app."""
        from app.main import app
        routes = [route.path for route in app.routes]
        assert "/api/v1/users/device-token" in routes

    def test_device_token_request_validation(self):
        """DeviceTokenRequest validates and strips whitespace."""
        from app.models.users import DeviceTokenRequest
        req = DeviceTokenRequest(device_token="  abc123  ", platform="ios")
        assert req.device_token == "abc123"
        assert req.platform == "ios"

    def test_device_token_request_default_platform(self):
        """DeviceTokenRequest defaults platform to 'ios'."""
        from app.models.users import DeviceTokenRequest
        req = DeviceTokenRequest(device_token="abc123")
        assert req.platform == "ios"

    def test_device_token_response_model(self):
        """DeviceTokenResponse can be constructed."""
        from app.models.users import DeviceTokenResponse
        resp = DeviceTokenResponse(
            status="registered",
            device_token="abc123",
            platform="ios",
        )
        assert resp.status == "registered"
        assert resp.device_token == "abc123"
        assert resp.platform == "ios"
