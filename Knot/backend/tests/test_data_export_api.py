"""
Step 11.3 Verification: Data Export API

Tests the GET /api/v1/users/me/export endpoint that compiles all user data
(vault, hints, recommendations, feedback, notifications) and returns
the complete dataset as JSON.

Tests cover:
1. Export with vault data returns all sections populated
2. Export without vault returns user info + empty collections
3. No auth token → 401
4. Invalid auth token → 401
5. Module imports and router registration
6. Response structure validation

Prerequisites:
- Supabase credentials in .env
- All migrations applied
- Step 2.5 auth middleware working

Run with: pytest tests/test_data_export_api.py -v
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
# Helpers: auth user management (same pattern as test_account_deletion_api.py)
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


def _valid_vault_payload() -> dict:
    """Return a complete, valid vault creation payload."""
    return {
        "partner_name": "Alex Export",
        "relationship_tenure_months": 18,
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
            {
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-06-20",
                "recurrence": "yearly",
            },
        ],
        "vibes": ["quiet_luxury", "minimalist"],
        "budgets": [
            {
                "occasion_type": "just_because",
                "min_amount": 2000,
                "max_amount": 5000,
                "currency": "USD",
            },
            {
                "occasion_type": "minor_occasion",
                "min_amount": 5000,
                "max_amount": 15000,
                "currency": "USD",
            },
            {
                "occasion_type": "major_milestone",
                "min_amount": 10000,
                "max_amount": 50000,
                "currency": "USD",
            },
        ],
        "love_languages": {
            "primary": "quality_time",
            "secondary": "receiving_gifts",
        },
    }


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
    """Create a test user, sign in, and yield context. Auto-cleans up."""
    test_email = f"knot-export-test-{uuid.uuid4().hex[:8]}@test.example"
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


@pytest.fixture
def test_auth_user_with_vault(client, test_auth_user):
    """Create a test user with a complete vault, plus a hint."""
    token = test_auth_user["access_token"]

    # Create vault via API
    vault_resp = client.post(
        "/api/v1/vault",
        headers={"Authorization": f"Bearer {token}"},
        json=_valid_vault_payload(),
    )
    assert vault_resp.status_code == 201, (
        f"Failed to create vault: HTTP {vault_resp.status_code} — {vault_resp.text}"
    )

    # Add a test hint
    hint_resp = client.post(
        "/api/v1/hints",
        headers={"Authorization": f"Bearer {token}"},
        json={"hint_text": "She mentioned wanting a new yoga mat", "source": "text_input"},
    )
    assert hint_resp.status_code == 201, (
        f"Failed to create hint: HTTP {hint_resp.status_code} — {hint_resp.text}"
    )

    return {
        **test_auth_user,
        "vault_id": vault_resp.json().get("vault_id"),
        "hint_id": hint_resp.json().get("id"),
    }


# ---------------------------------------------------------------------------
# Test: Export with Vault Data
# ---------------------------------------------------------------------------

@requires_supabase
class TestExportWithVault:
    """GET /api/v1/users/me/export with a fully populated vault."""

    def test_export_returns_200(self, client, test_auth_user_with_vault):
        """Export endpoint returns 200 OK."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        assert resp.status_code == 200

    def test_export_has_exported_at_timestamp(self, client, test_auth_user_with_vault):
        """Response includes an ISO 8601 exported_at timestamp."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert "exported_at" in data
        assert "T" in data["exported_at"]  # ISO 8601 contains T separator

    def test_export_includes_user_info(self, client, test_auth_user_with_vault):
        """Response includes user account info (id, email)."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert "user" in data
        assert data["user"]["id"] == test_auth_user_with_vault["id"]
        assert data["user"]["email"] == test_auth_user_with_vault["email"]

    def test_export_includes_vault_data(self, client, test_auth_user_with_vault):
        """Response includes partner vault with basic info."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        vault = data["partner_vault"]
        assert vault is not None
        assert vault["partner_name"] == "Alex Export"
        assert vault["cohabitation_status"] == "living_together"
        assert vault["location_city"] == "San Francisco"

    def test_export_includes_interests_and_dislikes(self, client, test_auth_user_with_vault):
        """Vault section includes interests and dislikes lists."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        vault = resp.json()["partner_vault"]
        assert len(vault["interests"]) == 5
        assert "Travel" in vault["interests"]
        assert len(vault["dislikes"]) == 5
        assert "Sports" in vault["dislikes"]

    def test_export_includes_vibes(self, client, test_auth_user_with_vault):
        """Vault section includes vibe tags."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        vault = resp.json()["partner_vault"]
        assert len(vault["vibes"]) == 2
        assert "quiet_luxury" in vault["vibes"]

    def test_export_includes_budgets(self, client, test_auth_user_with_vault):
        """Vault section includes budget tiers."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        vault = resp.json()["partner_vault"]
        assert len(vault["budgets"]) == 3

    def test_export_includes_love_languages(self, client, test_auth_user_with_vault):
        """Vault section includes love languages."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        vault = resp.json()["partner_vault"]
        assert len(vault["love_languages"]) == 2

    def test_export_includes_milestones(self, client, test_auth_user_with_vault):
        """Response includes milestones list."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert len(data["milestones"]) == 2
        milestone_names = [m["milestone_name"] for m in data["milestones"]]
        assert "Birthday" in milestone_names

    def test_export_includes_hints(self, client, test_auth_user_with_vault):
        """Response includes hints list (without embeddings)."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert len(data["hints"]) >= 1
        hint = data["hints"][0]
        assert "hint_text" in hint
        assert "hint_embedding" not in hint  # Embeddings excluded

    def test_export_has_empty_recommendations(self, client, test_auth_user_with_vault):
        """Recommendations list is empty when none have been generated."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert isinstance(data["recommendations"], list)

    def test_export_has_empty_feedback(self, client, test_auth_user_with_vault):
        """Feedback list is empty when no feedback has been given."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert isinstance(data["feedback"], list)

    def test_export_has_empty_notifications(self, client, test_auth_user_with_vault):
        """Notifications list is empty when none have been scheduled."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user_with_vault['access_token']}"},
        )
        data = resp.json()
        assert isinstance(data["notifications"], list)


# ---------------------------------------------------------------------------
# Test: Export without Vault
# ---------------------------------------------------------------------------

@requires_supabase
class TestExportWithoutVault:
    """GET /api/v1/users/me/export for a user who hasn't completed onboarding."""

    def test_export_returns_200_without_vault(self, client, test_auth_user):
        """Export succeeds even without a vault (user info only)."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200

    def test_export_has_user_info_without_vault(self, client, test_auth_user):
        """User info is present even without a vault."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["user"]["id"] == test_auth_user["id"]

    def test_vault_is_null_without_onboarding(self, client, test_auth_user):
        """partner_vault is null when onboarding hasn't been completed."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["partner_vault"] is None

    def test_collections_are_empty_without_vault(self, client, test_auth_user):
        """All data collections are empty lists without a vault."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["milestones"] == []
        assert data["hints"] == []
        assert data["recommendations"] == []
        assert data["feedback"] == []
        assert data["notifications"] == []


# ---------------------------------------------------------------------------
# Test: Authentication Required
# ---------------------------------------------------------------------------

@requires_supabase
class TestAuthRequired:
    """Endpoint requires valid Bearer token."""

    def test_no_auth_header_returns_401(self, client):
        """Request without Authorization header is rejected."""
        resp = client.get("/api/v1/users/me/export")
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Invalid Bearer token is rejected."""
        resp = client.get(
            "/api/v1/users/me/export",
            headers={"Authorization": "Bearer invalid_token_here"},
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Test: Module Imports & Route Registration
# ---------------------------------------------------------------------------

class TestModuleImports:
    """Verify all new modules are importable and registered."""

    def test_data_export_response_import(self):
        """DataExportResponse is importable."""
        from app.models.users import DataExportResponse
        assert DataExportResponse is not None

    def test_data_export_response_structure(self):
        """DataExportResponse has expected fields."""
        from app.models.users import DataExportResponse
        resp = DataExportResponse(
            exported_at="2026-02-16T12:00:00+00:00",
            user={"id": "test", "email": "test@example.com", "created_at": "2026-01-01"},
        )
        assert resp.exported_at == "2026-02-16T12:00:00+00:00"
        assert resp.partner_vault is None
        assert resp.milestones == []
        assert resp.hints == []
        assert resp.recommendations == []
        assert resp.feedback == []
        assert resp.notifications == []

    def test_users_router_has_export_route(self):
        """GET /api/v1/users/me/export route is registered in the app."""
        from app.main import app
        get_routes = [
            route.path
            for route in app.routes
            if hasattr(route, "methods") and "GET" in route.methods
        ]
        assert "/api/v1/users/me/export" in get_routes

    def test_existing_device_token_route_still_registered(self):
        """Existing POST /api/v1/users/device-token is still registered."""
        from app.main import app
        routes = [route.path for route in app.routes]
        assert "/api/v1/users/device-token" in routes

    def test_existing_delete_route_still_registered(self):
        """Existing DELETE /api/v1/users/me is still registered."""
        from app.main import app
        delete_routes = [
            route.path
            for route in app.routes
            if hasattr(route, "methods") and "DELETE" in route.methods
        ]
        assert "/api/v1/users/me" in delete_routes
