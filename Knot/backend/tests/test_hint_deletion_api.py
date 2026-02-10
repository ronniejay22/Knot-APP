"""
Step 4.6 Verification: Hint Deletion API Endpoint

Tests the DELETE /api/v1/hints/{hint_id} endpoint.

Tests cover:
1. Delete a hint → 204 response
2. Deleted hint no longer appears in GET /api/v1/hints
3. Deleted hint no longer exists in the database
4. Attempt to delete another user's hint → 404
5. Attempt to delete a non-existent hint → 404
6. Auth required → 401 without token
7. No partner vault → 404
8. Double-delete returns 404

Prerequisites:
- Complete Steps 0.6-4.4 (Supabase + all tables + vault API + hint API)
- Backend server NOT required (uses FastAPI TestClient)

Run with: pytest tests/test_hint_deletion_api.py -v
"""

import pytest
import httpx
import uuid
import time
from unittest.mock import patch, AsyncMock

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
# Helpers: auth user management (same pattern as test_hint_submission_api.py)
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


# ---------------------------------------------------------------------------
# Helper: build a valid vault payload
# ---------------------------------------------------------------------------

def _valid_vault_payload() -> dict:
    """Return a complete, valid vault creation payload."""
    return {
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "San Francisco",
        "location_state": "CA",
        "location_country": "US",
        "interests": ["Travel", "Cooking", "Movies", "Music", "Reading"],
        "dislikes": ["Sports", "Gaming", "Cars", "Skiing", "Karaoke"],
        "milestones": [
            {
                "milestone_type": "birthday",
                "milestone_name": "Birthday",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
            },
        ],
        "vibes": ["quiet_luxury", "minimalist"],
        "budgets": [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 15000, "currency": "USD"},
            {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 50000, "currency": "USD"},
        ],
        "love_languages": {"primary": "quality_time", "secondary": "receiving_gifts"},
    }


# ---------------------------------------------------------------------------
# Helper: query hints directly via PostgREST (service role, bypasses RLS)
# ---------------------------------------------------------------------------

def _query_hint_by_id(hint_id: str) -> list[dict]:
    """Query a specific hint by ID directly via PostgREST."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/hints"
        f"?id=eq.{hint_id}"
        f"&select=id,vault_id,hint_text,source,is_used,created_at",
        headers=_service_headers(),
    )
    assert resp.status_code == 200, (
        f"Failed to query hint: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _delete_hints(vault_id: str):
    """Delete all hints for a vault (cleanup)."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/hints?vault_id=eq.{vault_id}",
        headers={
            **_service_headers(),
            "Content-Type": "application/json",
        },
    )


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
def test_auth_user_with_vault(client):
    """
    Create a test user, sign them in, create a vault, and yield context.
    Cleanup deletes the auth user (CASCADE removes all data).
    """
    test_email = f"knot-hintdel-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    # Create a vault via the API
    vault_resp = client.post(
        "/api/v1/vault",
        json=_valid_vault_payload(),
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert vault_resp.status_code == 201, (
        f"Failed to create vault: HTTP {vault_resp.status_code} — {vault_resp.text}"
    )
    vault_id = vault_resp.json()["vault_id"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
        "vault_id": vault_id,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_second_user_with_vault(client):
    """
    Create a second test user with a vault (for cross-user deletion tests).
    """
    test_email = f"knot-hintdel-user2-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    vault_resp = client.post(
        "/api/v1/vault",
        json=_valid_vault_payload(),
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert vault_resp.status_code == 201
    vault_id = vault_resp.json()["vault_id"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
        "vault_id": vault_id,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user_no_vault():
    """Create a test user with NO vault (to test 404 handling)."""
    test_email = f"knot-hintdel-novault-{uuid.uuid4().hex[:8]}@test.example"
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


def _auth_headers(token: str) -> dict:
    """Build Authorization headers for API requests."""
    return {"Authorization": f"Bearer {token}"}


def _create_hint(client, token: str, text: str = "She mentioned a new book") -> dict:
    """Create a hint and return the response JSON."""
    with patch(
        "app.api.hints.generate_embedding",
        new_callable=AsyncMock,
        return_value=None,
    ):
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": text, "source": "text_input"},
            headers=_auth_headers(token),
        )
    assert resp.status_code == 201, (
        f"Failed to create hint: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


# ===================================================================
# 1. Successful deletion — 204 response
# ===================================================================

@requires_supabase
class TestSuccessfulDeletion:
    """Verify DELETE /api/v1/hints/{hint_id} succeeds with valid requests."""

    def test_delete_hint_returns_204(self, client, test_auth_user_with_vault):
        """A valid delete request should return 204 No Content."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)

        resp = client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers=_auth_headers(token),
        )
        assert resp.status_code == 204, (
            f"Expected 204, got {resp.status_code}. Response: {resp.text}"
        )
        print(f"  Delete hint → HTTP 204 (hint_id={hint['id'][:8]}...)")

    def test_deleted_hint_not_in_database(self, client, test_auth_user_with_vault):
        """After deletion, the hint should no longer exist in the database."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)
        hint_id = hint["id"]

        # Verify hint exists before deletion
        rows = _query_hint_by_id(hint_id)
        assert len(rows) == 1, "Hint should exist before deletion"

        # Delete
        resp = client.delete(
            f"/api/v1/hints/{hint_id}",
            headers=_auth_headers(token),
        )
        assert resp.status_code == 204

        # Verify hint is gone from database
        rows = _query_hint_by_id(hint_id)
        assert len(rows) == 0, "Hint should be removed from database after deletion"
        print(f"  Hint removed from database after deletion")

    def test_deleted_hint_not_in_list(self, client, test_auth_user_with_vault):
        """After deletion, the hint should not appear in GET /api/v1/hints."""
        token = test_auth_user_with_vault["access_token"]
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        hint1 = _create_hint(client, token, "First hint - keep this one")
        hint2 = _create_hint(client, token, "Second hint - delete this one")

        # Delete hint2
        resp = client.delete(
            f"/api/v1/hints/{hint2['id']}",
            headers=_auth_headers(token),
        )
        assert resp.status_code == 204

        # List hints — should only have hint1
        list_resp = client.get(
            "/api/v1/hints",
            headers=_auth_headers(token),
        )
        assert list_resp.status_code == 200
        data = list_resp.json()
        hint_ids = [h["id"] for h in data["hints"]]

        assert hint1["id"] in hint_ids, "Non-deleted hint should still appear"
        assert hint2["id"] not in hint_ids, "Deleted hint should not appear in list"
        assert data["total"] == 1
        print("  Deleted hint excluded from GET /api/v1/hints")

    def test_delete_does_not_affect_other_hints(self, client, test_auth_user_with_vault):
        """Deleting one hint should not affect other hints."""
        token = test_auth_user_with_vault["access_token"]
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        hints = [
            _create_hint(client, token, f"Hint number {i}") for i in range(3)
        ]

        # Delete the middle hint
        resp = client.delete(
            f"/api/v1/hints/{hints[1]['id']}",
            headers=_auth_headers(token),
        )
        assert resp.status_code == 204

        # Verify other hints still exist
        for i in [0, 2]:
            rows = _query_hint_by_id(hints[i]["id"])
            assert len(rows) == 1, f"Hint {i} should still exist"

        print("  Other hints unaffected by deletion")


# ===================================================================
# 2. Authorization — cannot delete another user's hint
# ===================================================================

@requires_supabase
class TestCrossUserDeletion:
    """Verify a user cannot delete another user's hints."""

    def test_delete_other_users_hint_returns_404(
        self, client, test_auth_user_with_vault, test_second_user_with_vault
    ):
        """Attempting to delete another user's hint should return 404."""
        # User 1 creates a hint
        user1_token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, user1_token, "User 1's private hint")

        # User 2 tries to delete it
        user2_token = test_second_user_with_vault["access_token"]
        resp = client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers=_auth_headers(user2_token),
        )
        assert resp.status_code == 404, (
            f"Expected 404 when deleting another user's hint, got {resp.status_code}"
        )
        print("  Delete another user's hint → 404")

    def test_other_users_hint_still_exists_after_failed_delete(
        self, client, test_auth_user_with_vault, test_second_user_with_vault
    ):
        """The hint should still exist after a failed cross-user delete attempt."""
        user1_token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, user1_token, "User 1's hint that should persist")

        # User 2 tries to delete
        user2_token = test_second_user_with_vault["access_token"]
        client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers=_auth_headers(user2_token),
        )

        # Verify hint still exists
        rows = _query_hint_by_id(hint["id"])
        assert len(rows) == 1, "Hint should still exist after failed cross-user deletion"
        print("  Hint persists after failed cross-user delete attempt")


# ===================================================================
# 3. Non-existent hint — 404 response
# ===================================================================

@requires_supabase
class TestNonExistentHint:
    """Verify DELETE returns 404 for non-existent hints."""

    def test_delete_nonexistent_hint_returns_404(self, client, test_auth_user_with_vault):
        """Deleting a hint ID that doesn't exist should return 404."""
        token = test_auth_user_with_vault["access_token"]
        fake_id = str(uuid.uuid4())

        resp = client.delete(
            f"/api/v1/hints/{fake_id}",
            headers=_auth_headers(token),
        )
        assert resp.status_code == 404, (
            f"Expected 404 for non-existent hint, got {resp.status_code}"
        )
        print(f"  Non-existent hint ID → 404")

    def test_double_delete_returns_404(self, client, test_auth_user_with_vault):
        """Deleting the same hint twice should return 404 on the second attempt."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)

        # First delete — should succeed
        resp1 = client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers=_auth_headers(token),
        )
        assert resp1.status_code == 204

        # Second delete — should 404
        resp2 = client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers=_auth_headers(token),
        )
        assert resp2.status_code == 404, (
            f"Expected 404 on double-delete, got {resp2.status_code}"
        )
        print("  Double-delete → 204 then 404")


# ===================================================================
# 4. Authentication — 401 responses
# ===================================================================

@requires_supabase
class TestAuthRequired:
    """Verify DELETE /api/v1/hints/{hint_id} requires authentication."""

    def test_no_token_returns_401(self, client, test_auth_user_with_vault):
        """A delete request with no auth token should return 401."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)

        resp = client.delete(f"/api/v1/hints/{hint['id']}")
        assert resp.status_code == 401, (
            f"Expected 401 with no token, got {resp.status_code}"
        )
        print("  No auth token → 401")

    def test_invalid_token_returns_401(self, client, test_auth_user_with_vault):
        """A delete request with an invalid token should return 401."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)

        resp = client.delete(
            f"/api/v1/hints/{hint['id']}",
            headers={"Authorization": "Bearer invalid-token-12345"},
        )
        assert resp.status_code == 401, (
            f"Expected 401 with invalid token, got {resp.status_code}"
        )
        print("  Invalid token → 401")

    def test_hint_persists_after_failed_auth_delete(self, client, test_auth_user_with_vault):
        """The hint should still exist after a failed auth delete attempt."""
        token = test_auth_user_with_vault["access_token"]
        hint = _create_hint(client, token)

        # Try to delete without auth
        client.delete(f"/api/v1/hints/{hint['id']}")

        # Verify hint still exists
        rows = _query_hint_by_id(hint["id"])
        assert len(rows) == 1, "Hint should persist after failed auth delete"
        print("  Hint persists after unauthenticated delete attempt")


# ===================================================================
# 5. No vault — 404 response
# ===================================================================

@requires_supabase
class TestNoVault:
    """Verify DELETE returns 404 when user has no vault."""

    def test_no_vault_returns_404(self, client, test_auth_user_no_vault):
        """A user without a vault should get 404 on delete."""
        fake_id = str(uuid.uuid4())
        resp = client.delete(
            f"/api/v1/hints/{fake_id}",
            headers=_auth_headers(test_auth_user_no_vault["access_token"]),
        )
        assert resp.status_code == 404, (
            f"Expected 404 for user without vault, got {resp.status_code}: {resp.text}"
        )
        detail = resp.json().get("detail", "")
        assert "vault" in detail.lower(), (
            f"Error should mention missing vault. Got: {detail}"
        )
        print("  No vault → 404 with 'vault' in message")
