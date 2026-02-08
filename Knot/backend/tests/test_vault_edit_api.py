"""
Step 3.12 Verification: Vault Edit Functionality (GET + PUT)

Tests the GET /api/v1/vault and PUT /api/v1/vault endpoints that allow
users to retrieve and update their Partner Vault data.

Tests cover:
1. GET /api/v1/vault:
   - Returns full vault data from all 6 tables
   - Returns 404 when no vault exists
   - Returns 401 without auth
   - All interests, dislikes, milestones, vibes, budgets, love languages present

2. PUT /api/v1/vault:
   - Updates partner name and verifies persistence
   - Updates interests (swap one) and verifies change
   - Updates vibes and verifies change
   - Updates budgets and verifies change
   - Updates love languages and verifies change
   - Updates milestones (add/remove) and verifies change
   - Returns 404 when no vault exists
   - Returns 401 without auth
   - Returns 422 for invalid payload (same validation as POST)
   - Vault ID is preserved after update (not recreated)

Prerequisites:
- Complete Steps 0.6-0.7 (Supabase project + credentials in .env)
- Run all migrations through 00008
- Step 2.5 auth middleware working
- Step 3.10 POST /api/v1/vault working

Run with: pytest tests/test_vault_edit_api.py -v
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
# Helpers: HTTP headers
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


def _auth_headers(token: str) -> dict:
    """Build Authorization headers for API requests."""
    return {"Authorization": f"Bearer {token}"}


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
# Helper: build valid vault payloads
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
            {
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-06-20",
                "recurrence": "yearly",
            },
        ],
        "vibes": ["quiet_luxury", "minimalist", "romantic"],
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


def _updated_vault_payload() -> dict:
    """Return a valid vault payload with different data for update testing."""
    return {
        "partner_name": "Jordan",
        "relationship_tenure_months": 36,
        "cohabitation_status": "separate",
        "location_city": "New York",
        "location_state": "NY",
        "location_country": "US",
        "interests": ["Photography", "Hiking", "Art", "Coffee", "Yoga"],
        "dislikes": ["Fashion", "Technology", "Shopping", "Surfing", "Camping"],
        "milestones": [
            {
                "milestone_type": "birthday",
                "milestone_name": "Jordan's Birthday",
                "milestone_date": "2000-07-22",
                "recurrence": "yearly",
            },
            {
                "milestone_type": "holiday",
                "milestone_name": "Valentine's Day",
                "milestone_date": "2000-02-14",
                "recurrence": "yearly",
                "budget_tier": "major_milestone",
            },
            {
                "milestone_type": "custom",
                "milestone_name": "First Date",
                "milestone_date": "2024-09-10",
                "recurrence": "one_time",
                "budget_tier": "minor_occasion",
            },
        ],
        "vibes": ["bohemian", "adventurous"],
        "budgets": [
            {
                "occasion_type": "just_because",
                "min_amount": 3000,
                "max_amount": 8000,
                "currency": "USD",
            },
            {
                "occasion_type": "minor_occasion",
                "min_amount": 8000,
                "max_amount": 20000,
                "currency": "USD",
            },
            {
                "occasion_type": "major_milestone",
                "min_amount": 15000,
                "max_amount": 75000,
                "currency": "USD",
            },
        ],
        "love_languages": {
            "primary": "acts_of_service",
            "secondary": "physical_touch",
        },
    }


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user_with_token():
    """Create a test user, sign them in, and yield user info + token."""
    test_email = f"knot-edit-test-{uuid.uuid4().hex[:8]}@test.example"
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
def test_auth_user_with_vault(client, test_auth_user_with_token):
    """
    Create a test user WITH a vault already created.
    Yields both user info and the vault creation response.
    """
    resp = client.post(
        "/api/v1/vault",
        json=_valid_vault_payload(),
        headers=_auth_headers(test_auth_user_with_token["access_token"]),
    )
    assert resp.status_code == 201, (
        f"Failed to create vault: HTTP {resp.status_code} — {resp.text}"
    )

    yield {
        **test_auth_user_with_token,
        "vault": resp.json(),
    }


@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


# ===================================================================
# GET /api/v1/vault — Retrieve Vault
# ===================================================================

@requires_supabase
class TestGetVault:
    """Verify GET /api/v1/vault returns the full vault data."""

    def test_get_vault_returns_200(self, client, test_auth_user_with_vault):
        """GET with valid auth and existing vault returns 200."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 200, (
            f"Expected 200, got {resp.status_code}. Response: {resp.text}"
        )
        print("  GET vault → HTTP 200")

    def test_get_vault_returns_partner_name(self, client, test_auth_user_with_vault):
        """GET response includes the partner name."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert data["partner_name"] == "Alex"
        print(f"  Partner name: {data['partner_name']}")

    def test_get_vault_returns_basic_info(self, client, test_auth_user_with_vault):
        """GET response includes all basic info fields."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert data["relationship_tenure_months"] == 24
        assert data["cohabitation_status"] == "living_together"
        assert data["location_city"] == "San Francisco"
        assert data["location_state"] == "CA"
        assert data["location_country"] == "US"
        print("  Basic info fields verified")

    def test_get_vault_returns_vault_id(self, client, test_auth_user_with_vault):
        """GET response includes the vault_id matching creation response."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert data["vault_id"] == test_auth_user_with_vault["vault"]["vault_id"]
        print(f"  Vault ID matches: {data['vault_id']}")

    def test_get_vault_returns_interests(self, client, test_auth_user_with_vault):
        """GET response includes 5 interests (likes)."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert len(data["interests"]) == 5
        assert set(data["interests"]) == {"Travel", "Cooking", "Movies", "Music", "Reading"}
        print(f"  Interests: {data['interests']}")

    def test_get_vault_returns_dislikes(self, client, test_auth_user_with_vault):
        """GET response includes 5 dislikes."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert len(data["dislikes"]) == 5
        assert set(data["dislikes"]) == {"Sports", "Gaming", "Cars", "Skiing", "Karaoke"}
        print(f"  Dislikes: {data['dislikes']}")

    def test_get_vault_returns_milestones(self, client, test_auth_user_with_vault):
        """GET response includes milestones with all fields."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        milestones = data["milestones"]
        assert len(milestones) == 2
        types = {m["milestone_type"] for m in milestones}
        assert "birthday" in types
        assert "anniversary" in types
        # Each milestone should have all fields
        for m in milestones:
            assert "id" in m
            assert "milestone_name" in m
            assert "milestone_date" in m
            assert "recurrence" in m
        print(f"  Milestones: {len(milestones)} ({types})")

    def test_get_vault_returns_vibes(self, client, test_auth_user_with_vault):
        """GET response includes vibe tags."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert set(data["vibes"]) == {"quiet_luxury", "minimalist", "romantic"}
        print(f"  Vibes: {data['vibes']}")

    def test_get_vault_returns_budgets(self, client, test_auth_user_with_vault):
        """GET response includes 3 budget tiers with amounts."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        budgets = data["budgets"]
        assert len(budgets) == 3
        occasion_types = {b["occasion_type"] for b in budgets}
        assert occasion_types == {"just_because", "minor_occasion", "major_milestone"}
        # Check amounts for just_because
        jb = next(b for b in budgets if b["occasion_type"] == "just_because")
        assert jb["min_amount"] == 2000
        assert jb["max_amount"] == 5000
        assert jb["currency"] == "USD"
        print(f"  Budgets: {len(budgets)} tiers verified")

    def test_get_vault_returns_love_languages(self, client, test_auth_user_with_vault):
        """GET response includes primary and secondary love languages."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        love_languages = data["love_languages"]
        assert len(love_languages) == 2
        primary = next(ll for ll in love_languages if ll["priority"] == 1)
        secondary = next(ll for ll in love_languages if ll["priority"] == 2)
        assert primary["language"] == "quality_time"
        assert secondary["language"] == "receiving_gifts"
        print(f"  Love languages: primary={primary['language']}, secondary={secondary['language']}")

    def test_get_vault_returns_404_no_vault(self, client, test_auth_user_with_token):
        """GET returns 404 when the user has no vault."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 404
        assert "detail" in resp.json()
        print("  No vault → HTTP 404")

    def test_get_vault_returns_401_no_auth(self, client):
        """GET returns 401 without authentication."""
        resp = client.get("/api/v1/vault")
        assert resp.status_code == 401
        print("  No auth → HTTP 401")

    def test_get_vault_returns_401_invalid_token(self, client):
        """GET returns 401 with an invalid token."""
        resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers("invalid-token-12345"),
        )
        assert resp.status_code == 401
        print("  Invalid token → HTTP 401")


# ===================================================================
# PUT /api/v1/vault — Update Vault
# ===================================================================

@requires_supabase
class TestUpdateVault:
    """Verify PUT /api/v1/vault updates vault data correctly."""

    def test_update_vault_returns_200(self, client, test_auth_user_with_vault):
        """PUT with valid auth and payload returns 200."""
        resp = client.put(
            "/api/v1/vault",
            json=_updated_vault_payload(),
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 200, (
            f"Expected 200, got {resp.status_code}. Response: {resp.text}"
        )
        print("  PUT vault → HTTP 200")

    def test_update_partner_name_persists(self, client, test_auth_user_with_vault):
        """Updating partner name is reflected in subsequent GET."""
        updated = _updated_vault_payload()
        resp = client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 200

        # Verify via GET
        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        assert data["partner_name"] == "Jordan"
        print(f"  Name updated: Alex → {data['partner_name']}")

    def test_update_basic_info_persists(self, client, test_auth_user_with_vault):
        """Updating basic info fields is reflected in subsequent GET."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        assert data["relationship_tenure_months"] == 36
        assert data["cohabitation_status"] == "separate"
        assert data["location_city"] == "New York"
        assert data["location_state"] == "NY"
        print("  Basic info updated and persisted")

    def test_update_interests_persists(self, client, test_auth_user_with_vault):
        """Updating interests replaces old ones with new ones."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        assert set(data["interests"]) == {"Photography", "Hiking", "Art", "Coffee", "Yoga"}
        assert len(data["interests"]) == 5
        print(f"  Interests updated: {data['interests']}")

    def test_update_dislikes_persists(self, client, test_auth_user_with_vault):
        """Updating dislikes replaces old ones with new ones."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        assert set(data["dislikes"]) == {"Fashion", "Technology", "Shopping", "Surfing", "Camping"}
        assert len(data["dislikes"]) == 5
        print(f"  Dislikes updated: {data['dislikes']}")

    def test_update_milestones_persists(self, client, test_auth_user_with_vault):
        """Updating milestones replaces old ones (different count OK)."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        # Updated payload has 3 milestones (was 2)
        assert len(data["milestones"]) == 3
        types = {m["milestone_type"] for m in data["milestones"]}
        assert types == {"birthday", "holiday", "custom"}
        # Verify birthday name changed
        birthday = next(m for m in data["milestones"] if m["milestone_type"] == "birthday")
        assert birthday["milestone_name"] == "Jordan's Birthday"
        print(f"  Milestones updated: {len(data['milestones'])} ({types})")

    def test_update_vibes_persists(self, client, test_auth_user_with_vault):
        """Updating vibes replaces old ones with new ones."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        assert set(data["vibes"]) == {"bohemian", "adventurous"}
        print(f"  Vibes updated: {data['vibes']}")

    def test_update_budgets_persists(self, client, test_auth_user_with_vault):
        """Updating budgets replaces old amounts with new ones."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        jb = next(b for b in data["budgets"] if b["occasion_type"] == "just_because")
        assert jb["min_amount"] == 3000
        assert jb["max_amount"] == 8000
        mm = next(b for b in data["budgets"] if b["occasion_type"] == "major_milestone")
        assert mm["min_amount"] == 15000
        assert mm["max_amount"] == 75000
        print("  Budgets updated and persisted")

    def test_update_love_languages_persists(self, client, test_auth_user_with_vault):
        """Updating love languages replaces old selections."""
        updated = _updated_vault_payload()
        client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )

        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = get_resp.json()
        primary = next(ll for ll in data["love_languages"] if ll["priority"] == 1)
        secondary = next(ll for ll in data["love_languages"] if ll["priority"] == 2)
        assert primary["language"] == "acts_of_service"
        assert secondary["language"] == "physical_touch"
        print(f"  Love languages updated: {primary['language']}, {secondary['language']}")

    def test_update_preserves_vault_id(self, client, test_auth_user_with_vault):
        """PUT does not change the vault_id (updates in place, not recreates)."""
        original_vault_id = test_auth_user_with_vault["vault"]["vault_id"]

        resp = client.put(
            "/api/v1/vault",
            json=_updated_vault_payload(),
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.json()["vault_id"] == original_vault_id

        # Also verify via GET
        get_resp = client.get(
            "/api/v1/vault",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert get_resp.json()["vault_id"] == original_vault_id
        print(f"  Vault ID preserved: {original_vault_id}")

    def test_update_response_has_summary(self, client, test_auth_user_with_vault):
        """PUT response includes updated summary counts."""
        updated = _updated_vault_payload()
        resp = client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        data = resp.json()
        assert data["partner_name"] == "Jordan"
        assert data["interests_count"] == 5
        assert data["dislikes_count"] == 5
        assert data["milestones_count"] == 3
        assert data["vibes_count"] == 2
        assert data["budgets_count"] == 3
        assert data["love_languages"]["primary"] == "acts_of_service"
        assert data["love_languages"]["secondary"] == "physical_touch"
        print("  Update response summary verified")

    def test_update_returns_404_no_vault(self, client, test_auth_user_with_token):
        """PUT returns 404 when the user has no vault to update."""
        resp = client.put(
            "/api/v1/vault",
            json=_updated_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 404
        assert "detail" in resp.json()
        print("  No vault → HTTP 404")

    def test_update_returns_401_no_auth(self, client):
        """PUT returns 401 without authentication."""
        resp = client.put(
            "/api/v1/vault",
            json=_updated_vault_payload(),
        )
        assert resp.status_code == 401
        print("  No auth → HTTP 401")

    def test_update_returns_401_invalid_token(self, client):
        """PUT returns 401 with an invalid token."""
        resp = client.put(
            "/api/v1/vault",
            json=_updated_vault_payload(),
            headers=_auth_headers("invalid-token-12345"),
        )
        assert resp.status_code == 401
        print("  Invalid token → HTTP 401")

    def test_update_validates_interests_count(self, client, test_auth_user_with_vault):
        """PUT validates that exactly 5 interests are required (same as POST)."""
        updated = _updated_vault_payload()
        updated["interests"] = ["Travel", "Cooking"]  # only 2
        resp = client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422
        print("  Invalid interests count → HTTP 422")

    def test_update_validates_interest_dislike_overlap(self, client, test_auth_user_with_vault):
        """PUT validates that interests and dislikes don't overlap (same as POST)."""
        updated = _updated_vault_payload()
        updated["interests"] = ["Travel", "Cooking", "Movies", "Music", "Reading"]
        updated["dislikes"] = ["Travel", "Gaming", "Cars", "Skiing", "Karaoke"]  # Travel overlaps
        resp = client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422
        print("  Interest/dislike overlap → HTTP 422")

    def test_update_validates_empty_name(self, client, test_auth_user_with_vault):
        """PUT validates that partner_name is not empty (same as POST)."""
        updated = _updated_vault_payload()
        updated["partner_name"] = "   "  # whitespace only
        resp = client.put(
            "/api/v1/vault",
            json=updated,
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422
        print("  Empty name → HTTP 422")

    def test_multiple_updates_work(self, client, test_auth_user_with_vault):
        """Multiple sequential updates all succeed."""
        token = test_auth_user_with_vault["access_token"]

        # First update
        updated1 = _updated_vault_payload()
        resp1 = client.put("/api/v1/vault", json=updated1, headers=_auth_headers(token))
        assert resp1.status_code == 200

        # Second update — change back to original
        original = _valid_vault_payload()
        resp2 = client.put("/api/v1/vault", json=original, headers=_auth_headers(token))
        assert resp2.status_code == 200

        # Verify final state matches original
        get_resp = client.get("/api/v1/vault", headers=_auth_headers(token))
        data = get_resp.json()
        assert data["partner_name"] == "Alex"
        assert set(data["interests"]) == {"Travel", "Cooking", "Movies", "Music", "Reading"}
        print("  Multiple sequential updates work correctly")

    def test_update_single_field_change(self, client, test_auth_user_with_vault):
        """Updating just one field (name) while keeping everything else the same."""
        token = test_auth_user_with_vault["access_token"]
        payload = _valid_vault_payload()
        payload["partner_name"] = "Updated Name Only"

        resp = client.put("/api/v1/vault", json=payload, headers=_auth_headers(token))
        assert resp.status_code == 200

        get_resp = client.get("/api/v1/vault", headers=_auth_headers(token))
        data = get_resp.json()
        assert data["partner_name"] == "Updated Name Only"
        # Everything else unchanged
        assert set(data["interests"]) == {"Travel", "Cooking", "Movies", "Music", "Reading"}
        assert set(data["vibes"]) == {"quiet_luxury", "minimalist", "romantic"}
        print("  Single field update: name changed, rest preserved")
