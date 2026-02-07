"""
Step 2.5 Verification: Backend Auth Middleware

Tests that:
1. Protected endpoint returns successfully with a valid Supabase access token
2. Protected endpoint returns 401 with an invalid/expired token
3. Protected endpoint returns 401 with no token
4. The returned user_id matches the authenticated user
5. Malformed Authorization headers are rejected
6. The middleware works as a reusable FastAPI dependency

Prerequisites:
- Complete Steps 0.6-0.7 (Supabase project + credentials in .env)
- Run all migrations through 00002 (users table must exist for auth user creation)

Run with: pytest tests/test_auth_middleware.py -v
"""

import pytest
import httpx
import uuid

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
# Helpers: HTTP headers for Supabase Admin API
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


# ---------------------------------------------------------------------------
# Helper: create and delete test auth users
# ---------------------------------------------------------------------------

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
                f"HTTP {resp.status_code} — {resp.text}. "
                "This user may be orphaned in auth.users.",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}. "
            "This user may be orphaned in auth.users.",
            stacklevel=2,
        )


def _sign_in_user(email: str, password: str) -> dict:
    """
    Sign in a test user via Supabase email/password auth.

    Returns the full session response including access_token and user.
    """
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


# ---------------------------------------------------------------------------
# Fixture: test auth user with valid access token
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user_with_token():
    """
    Create a test user, sign them in to get a valid access token,
    and yield both the user info and the token.

    Cleanup deletes the auth user (CASCADE removes public.users row).
    """
    import time

    test_email = f"knot-auth-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    # Create the user via Admin API
    user_id = _create_auth_user(test_email, test_password)

    # Give the handle_new_user trigger a moment to fire
    time.sleep(0.5)

    # Sign in to get a valid access token (JWT)
    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    # Cleanup: delete auth user (CASCADE deletes public.users row)
    _delete_auth_user(user_id)


# ---------------------------------------------------------------------------
# Fixture: FastAPI test client
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """Create a FastAPI test client using httpx."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


# ===================================================================
# 1. Protected endpoint with valid token
# ===================================================================

@requires_supabase
class TestValidToken:
    """Verify the auth middleware accepts valid Supabase access tokens."""

    def test_valid_token_returns_200(self, client, test_auth_user_with_token):
        """
        A request with a valid Supabase JWT should return 200.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": f"Bearer {test_auth_user_with_token['access_token']}",
            },
        )
        assert resp.status_code == 200, (
            f"Protected endpoint returned {resp.status_code} with valid token. "
            f"Response: {resp.text}"
        )
        print(f"  Valid token → HTTP 200")

    def test_valid_token_returns_correct_user_id(self, client, test_auth_user_with_token):
        """
        The returned user_id should match the authenticated user's ID.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": f"Bearer {test_auth_user_with_token['access_token']}",
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "user_id" in data, (
            f"Response missing 'user_id' field. Got: {data}"
        )
        assert data["user_id"] == test_auth_user_with_token["id"], (
            f"User ID mismatch. Expected: {test_auth_user_with_token['id']}, "
            f"Got: {data['user_id']}"
        )
        print(f"  User ID matches: {data['user_id']}")

    def test_valid_token_returns_json(self, client, test_auth_user_with_token):
        """
        The response should be valid JSON with the expected structure.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": f"Bearer {test_auth_user_with_token['access_token']}",
            },
        )
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, dict), f"Expected dict response, got {type(data)}"
        assert set(data.keys()) == {"user_id"}, (
            f"Unexpected response keys. Expected {{'user_id'}}, got {set(data.keys())}"
        )
        print(f"  Response is valid JSON with correct structure")


# ===================================================================
# 2. Protected endpoint with invalid token
# ===================================================================

@requires_supabase
class TestInvalidToken:
    """Verify the auth middleware rejects invalid tokens with 401."""

    def test_invalid_token_returns_401(self, client):
        """
        A request with a garbage token should return 401.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": "Bearer invalid_garbage_token_12345",
            },
        )
        assert resp.status_code == 401, (
            f"Expected 401 for invalid token, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  Invalid token → HTTP 401")

    def test_invalid_token_returns_error_detail(self, client):
        """
        The 401 response should include a descriptive error message.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": "Bearer invalid_garbage_token_12345",
            },
        )
        assert resp.status_code == 401
        data = resp.json()
        assert "detail" in data, (
            f"401 response missing 'detail' field. Got: {data}"
        )
        print(f"  Error detail: {data['detail']}")

    def test_expired_token_format_returns_401(self, client):
        """
        A JWT-formatted but expired/invalid token should return 401.

        This uses a well-formed but fabricated JWT to test that the
        middleware validates with Supabase, not just checks format.
        """
        # This is a structurally valid JWT but not signed by Supabase
        fake_jwt = (
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IlRlc3QiLCJpYXQiOjE1MTYyMzkwMjJ9."
            "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        )
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": f"Bearer {fake_jwt}",
            },
        )
        assert resp.status_code == 401, (
            f"Expected 401 for fake JWT, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  Fake JWT → HTTP 401")

    def test_empty_bearer_token_returns_401(self, client):
        """
        A request with 'Bearer ' followed by an empty string should return 401.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": "Bearer ",
            },
        )
        # FastAPI's HTTPBearer scheme may reject this at parse level
        assert resp.status_code in (401, 403), (
            f"Expected 401 or 403 for empty bearer, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  Empty Bearer → HTTP {resp.status_code}")


# ===================================================================
# 3. Protected endpoint with no token
# ===================================================================

@requires_supabase
class TestNoToken:
    """Verify the auth middleware rejects requests with no Authorization header."""

    def test_no_auth_header_returns_401(self, client):
        """
        A request with no Authorization header should return 401.
        """
        resp = client.get("/api/v1/me")
        assert resp.status_code == 401, (
            f"Expected 401 for missing auth header, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  No auth header → HTTP 401")

    def test_no_auth_header_returns_descriptive_message(self, client):
        """
        The 401 response for missing token should tell the user what to provide.
        """
        resp = client.get("/api/v1/me")
        assert resp.status_code == 401
        data = resp.json()
        assert "detail" in data, f"401 response missing 'detail'. Got: {data}"
        detail_lower = data["detail"].lower()
        assert "token" in detail_lower or "auth" in detail_lower, (
            f"Error message should mention token/auth. Got: {data['detail']}"
        )
        print(f"  Error message: {data['detail']}")

    def test_no_auth_header_returns_www_authenticate(self, client):
        """
        The 401 response should include a WWW-Authenticate header
        per HTTP standard (RFC 7235).
        """
        resp = client.get("/api/v1/me")
        assert resp.status_code == 401
        assert "www-authenticate" in resp.headers, (
            "401 response missing WWW-Authenticate header. "
            "This is required by RFC 7235 for Bearer auth."
        )
        assert resp.headers["www-authenticate"].lower() == "bearer", (
            f"WWW-Authenticate header should be 'Bearer', "
            f"got: {resp.headers['www-authenticate']}"
        )
        print(f"  WWW-Authenticate: {resp.headers['www-authenticate']}")


# ===================================================================
# 4. Malformed Authorization headers
# ===================================================================

@requires_supabase
class TestMalformedHeaders:
    """Verify the auth middleware handles malformed auth headers gracefully."""

    def test_basic_auth_instead_of_bearer_returns_401(self, client):
        """
        Basic auth (instead of Bearer) should be rejected.
        """
        import base64
        basic_creds = base64.b64encode(b"user:pass").decode()
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": f"Basic {basic_creds}",
            },
        )
        assert resp.status_code == 401, (
            f"Expected 401 for Basic auth, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  Basic auth → HTTP 401")

    def test_raw_token_without_bearer_prefix_returns_401(self, client, test_auth_user_with_token):
        """
        A token without the 'Bearer ' prefix should be rejected.
        """
        resp = client.get(
            "/api/v1/me",
            headers={
                "Authorization": test_auth_user_with_token["access_token"],
            },
        )
        assert resp.status_code == 401, (
            f"Expected 401 for token without Bearer prefix, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  Token without 'Bearer ' prefix → HTTP 401")


# ===================================================================
# 5. Health endpoint remains unprotected
# ===================================================================

@requires_supabase
class TestHealthEndpointUnprotected:
    """Verify the health endpoint does NOT require authentication."""

    def test_health_without_token_returns_200(self, client):
        """
        The /health endpoint should always return 200 regardless of auth.
        """
        resp = client.get("/health")
        assert resp.status_code == 200, (
            f"Health endpoint returned {resp.status_code} without auth. "
            f"Response: {resp.text}"
        )
        data = resp.json()
        assert data == {"status": "ok"}, f"Unexpected health response: {data}"
        print(f"  /health without auth → HTTP 200")

    def test_health_with_token_still_returns_200(self, client, test_auth_user_with_token):
        """
        The /health endpoint should work fine with a token too (it just ignores it).
        """
        resp = client.get(
            "/health",
            headers={
                "Authorization": f"Bearer {test_auth_user_with_token['access_token']}",
            },
        )
        assert resp.status_code == 200
        assert resp.json() == {"status": "ok"}
        print(f"  /health with auth → HTTP 200")
