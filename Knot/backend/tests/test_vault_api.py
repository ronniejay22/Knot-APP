"""
Step 3.10 Verification: Vault Submission API Endpoint

Tests the POST /api/v1/vault endpoint that accepts the complete Partner
Vault payload from onboarding and inserts into all relevant tables
(partner_vaults, partner_interests, partner_milestones, partner_vibes,
partner_budgets, partner_love_languages).

Tests cover:
1. Valid payload → 201 with data in all tables
2. Missing required fields → 422
3. Interest count validation (4 instead of 5, 6 instead of 5) → 422
4. Invalid interest categories → 422
5. Interest-dislike overlap → 422
6. Vibe validation (invalid, 0 vibes) → 422
7. Budget validation (wrong count, max < min) → 422
8. Love language validation (same for primary/secondary) → 422
9. Milestone validation (no birthday, custom without budget_tier) → 422
10. No auth token → 401
11. Duplicate vault (second POST) → 409
12. Data integrity verification (all 6 tables populated correctly)

Prerequisites:
- Complete Steps 0.6-0.7 (Supabase project + credentials in .env)
- Run all migrations through 00008 (all partner tables must exist)
- Step 2.5 auth middleware working

Run with: pytest tests/test_vault_api.py -v
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
    """
    Return a complete, valid vault creation payload.

    This payload passes all Pydantic validation rules and mirrors
    what the iOS onboarding flow would submit.
    """
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
                # budget_tier omitted — DB trigger sets major_milestone
            },
            {
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-06-20",
                "recurrence": "yearly",
                # budget_tier omitted — DB trigger sets major_milestone
            },
            {
                "milestone_type": "holiday",
                "milestone_name": "Valentine's Day",
                "milestone_date": "2000-02-14",
                "recurrence": "yearly",
                "budget_tier": "major_milestone",  # explicit override
            },
            {
                "milestone_type": "custom",
                "milestone_name": "First Date",
                "milestone_date": "2024-09-10",
                "recurrence": "one_time",
                "budget_tier": "minor_occasion",  # required for custom
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


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user_with_token():
    """
    Create a test user, sign them in to get a valid access token,
    and yield both the user info and the token.

    Cleanup deletes the auth user (CASCADE removes all data).
    """
    test_email = f"knot-vault-test-{uuid.uuid4().hex[:8]}@test.example"
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
def second_auth_user_with_token():
    """A second test user for isolation tests."""
    test_email = f"knot-vault-test2-{uuid.uuid4().hex[:8]}@test.example"
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


@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


def _auth_headers(token: str) -> dict:
    """Build Authorization headers for API requests."""
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Helper: query table data via service client
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for direct Supabase PostgREST queries (service role)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }


def _query_table(table: str, vault_id: str) -> list[dict]:
    """Query a table for all rows with the given vault_id."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/{table}?vault_id=eq.{vault_id}",
        headers=_service_headers(),
    )
    assert resp.status_code == 200, (
        f"Failed to query {table}: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


# ===================================================================
# 1. Valid payload — 201 response
# ===================================================================

@requires_supabase
class TestValidPayload:
    """Verify POST /api/v1/vault succeeds with a complete, valid payload."""

    def test_valid_payload_returns_201(self, client, test_auth_user_with_token):
        """A valid vault payload should return 201 Created."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201, (
            f"Expected 201, got {resp.status_code}. Response: {resp.text}"
        )
        print(f"  Valid payload → HTTP 201")

    def test_valid_payload_returns_vault_id(self, client, test_auth_user_with_token):
        """The response should include a vault_id UUID."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        data = resp.json()
        assert "vault_id" in data, f"Response missing vault_id. Got: {data}"
        # Verify it looks like a UUID (36 chars with hyphens)
        assert len(data["vault_id"]) == 36, (
            f"vault_id doesn't look like a UUID: {data['vault_id']}"
        )
        print(f"  vault_id: {data['vault_id']}")

    def test_valid_payload_returns_correct_counts(self, client, test_auth_user_with_token):
        """The response should contain correct summary counts."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        data = resp.json()
        assert data["partner_name"] == "Alex"
        assert data["interests_count"] == 5
        assert data["dislikes_count"] == 5
        assert data["milestones_count"] == 4
        assert data["vibes_count"] == 3
        assert data["budgets_count"] == 3
        assert data["love_languages"] == {
            "primary": "quality_time",
            "secondary": "receiving_gifts",
        }
        print(f"  Response counts verified")

    def test_valid_payload_minimal(self, client, test_auth_user_with_token):
        """A minimal payload (only required fields) should succeed."""
        payload = {
            "partner_name": "Jordan",
            # optional fields omitted: tenure, cohabitation, location
            "interests": ["Art", "Photography", "Nature", "Yoga", "Meditation"],
            "dislikes": ["Gaming", "Cars", "Skiing", "Surfing", "Karaoke"],
            "milestones": [
                {
                    "milestone_type": "birthday",
                    "milestone_name": "Birthday",
                    "milestone_date": "2000-07-22",
                    "recurrence": "yearly",
                },
            ],
            "vibes": ["bohemian"],
            "budgets": [
                {"occasion_type": "just_because", "min_amount": 1000, "max_amount": 3000},
                {"occasion_type": "minor_occasion", "min_amount": 3000, "max_amount": 10000},
                {"occasion_type": "major_milestone", "min_amount": 5000, "max_amount": 25000},
            ],
            "love_languages": {
                "primary": "words_of_affirmation",
                "secondary": "acts_of_service",
            },
        }
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201, (
            f"Minimal payload failed: HTTP {resp.status_code}. Response: {resp.text}"
        )
        print(f"  Minimal payload → HTTP 201")


# ===================================================================
# 2. Data integrity — verify all 6 tables
# ===================================================================

@requires_supabase
class TestDataIntegrity:
    """Verify data appears correctly in all database tables after vault creation."""

    def test_vault_table_populated(self, client, test_auth_user_with_token):
        """partner_vaults table should have the correct row."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        # Query vault via service client
        vault_resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults?id=eq.{vault_id}",
            headers=_service_headers(),
        )
        assert vault_resp.status_code == 200
        vaults = vault_resp.json()
        assert len(vaults) == 1
        vault = vaults[0]
        assert vault["partner_name"] == "Alex"
        assert vault["relationship_tenure_months"] == 24
        assert vault["cohabitation_status"] == "living_together"
        assert vault["location_city"] == "San Francisco"
        assert vault["location_state"] == "CA"
        assert vault["location_country"] == "US"
        assert vault["user_id"] == test_auth_user_with_token["id"]
        print(f"  partner_vaults: verified")

    def test_interests_table_populated(self, client, test_auth_user_with_token):
        """partner_interests should have 5 likes and 5 dislikes."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        rows = _query_table("partner_interests", vault_id)
        assert len(rows) == 10, f"Expected 10 interests, got {len(rows)}"

        likes = [r for r in rows if r["interest_type"] == "like"]
        dislikes = [r for r in rows if r["interest_type"] == "dislike"]
        assert len(likes) == 5, f"Expected 5 likes, got {len(likes)}"
        assert len(dislikes) == 5, f"Expected 5 dislikes, got {len(dislikes)}"

        like_categories = {r["interest_category"] for r in likes}
        assert like_categories == {"Travel", "Cooking", "Movies", "Music", "Reading"}

        dislike_categories = {r["interest_category"] for r in dislikes}
        assert dislike_categories == {"Sports", "Gaming", "Cars", "Skiing", "Karaoke"}
        print(f"  partner_interests: 5 likes + 5 dislikes verified")

    def test_milestones_table_populated(self, client, test_auth_user_with_token):
        """partner_milestones should have all milestones with correct budget tiers."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        rows = _query_table("partner_milestones", vault_id)
        assert len(rows) == 4, f"Expected 4 milestones, got {len(rows)}"

        milestones_by_name = {r["milestone_name"]: r for r in rows}

        # Birthday — trigger should set major_milestone
        birthday = milestones_by_name["Birthday"]
        assert birthday["milestone_type"] == "birthday"
        assert birthday["budget_tier"] == "major_milestone"
        assert birthday["recurrence"] == "yearly"

        # Anniversary — trigger should set major_milestone
        anniversary = milestones_by_name["Anniversary"]
        assert anniversary["budget_tier"] == "major_milestone"

        # Valentine's Day — explicit override to major_milestone
        valentines = milestones_by_name["Valentine's Day"]
        assert valentines["milestone_type"] == "holiday"
        assert valentines["budget_tier"] == "major_milestone"

        # Custom — user provided minor_occasion
        first_date = milestones_by_name["First Date"]
        assert first_date["milestone_type"] == "custom"
        assert first_date["budget_tier"] == "minor_occasion"
        assert first_date["recurrence"] == "one_time"
        print(f"  partner_milestones: 4 milestones with correct budget tiers verified")

    def test_vibes_table_populated(self, client, test_auth_user_with_token):
        """partner_vibes should have the selected vibe tags."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        rows = _query_table("partner_vibes", vault_id)
        assert len(rows) == 3
        vibe_tags = {r["vibe_tag"] for r in rows}
        assert vibe_tags == {"quiet_luxury", "minimalist", "romantic"}
        print(f"  partner_vibes: 3 vibes verified")

    def test_budgets_table_populated(self, client, test_auth_user_with_token):
        """partner_budgets should have 3 budget tiers with correct amounts."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        rows = _query_table("partner_budgets", vault_id)
        assert len(rows) == 3

        budgets_by_type = {r["occasion_type"]: r for r in rows}

        jb = budgets_by_type["just_because"]
        assert jb["min_amount"] == 2000
        assert jb["max_amount"] == 5000
        assert jb["currency"] == "USD"

        mo = budgets_by_type["minor_occasion"]
        assert mo["min_amount"] == 5000
        assert mo["max_amount"] == 15000

        mm = budgets_by_type["major_milestone"]
        assert mm["min_amount"] == 10000
        assert mm["max_amount"] == 50000
        print(f"  partner_budgets: 3 tiers verified")

    def test_love_languages_table_populated(self, client, test_auth_user_with_token):
        """partner_love_languages should have primary and secondary entries."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        rows = _query_table("partner_love_languages", vault_id)
        assert len(rows) == 2

        langs_by_priority = {r["priority"]: r for r in rows}

        primary = langs_by_priority[1]
        assert primary["language"] == "quality_time"

        secondary = langs_by_priority[2]
        assert secondary["language"] == "receiving_gifts"
        print(f"  partner_love_languages: primary + secondary verified")


# ===================================================================
# 3. Interest validation errors → 422
# ===================================================================

@requires_supabase
class TestInterestValidation:
    """Verify interest-related validation errors return 422."""

    def test_4_interests_rejected(self, client, test_auth_user_with_token):
        """Sending 4 interests instead of 5 should be rejected."""
        payload = _valid_vault_payload()
        payload["interests"] = ["Travel", "Cooking", "Movies", "Music"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for 4 interests, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  4 interests → HTTP 422")

    def test_6_interests_rejected(self, client, test_auth_user_with_token):
        """Sending 6 interests should be rejected."""
        payload = _valid_vault_payload()
        payload["interests"] = [
            "Travel", "Cooking", "Movies", "Music", "Reading", "Art",
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  6 interests → HTTP 422")

    def test_invalid_interest_category_rejected(self, client, test_auth_user_with_token):
        """An interest not in the predefined list should be rejected."""
        payload = _valid_vault_payload()
        payload["interests"] = ["Travel", "Cooking", "Movies", "Music", "Golf"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        assert "Golf" in resp.text, (
            f"Error message should mention 'Golf'. Got: {resp.text}"
        )
        print(f"  Invalid interest 'Golf' → HTTP 422")

    def test_duplicate_interests_rejected(self, client, test_auth_user_with_token):
        """Duplicate interests should be rejected."""
        payload = _valid_vault_payload()
        payload["interests"] = ["Travel", "Travel", "Movies", "Music", "Reading"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Duplicate interests → HTTP 422")

    def test_4_dislikes_rejected(self, client, test_auth_user_with_token):
        """Sending 4 dislikes instead of 5 should be rejected."""
        payload = _valid_vault_payload()
        payload["dislikes"] = ["Sports", "Gaming", "Cars", "Skiing"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  4 dislikes → HTTP 422")

    def test_interest_dislike_overlap_rejected(self, client, test_auth_user_with_token):
        """An interest that appears in both likes and dislikes should be rejected."""
        payload = _valid_vault_payload()
        payload["interests"] = ["Travel", "Cooking", "Movies", "Music", "Reading"]
        payload["dislikes"] = ["Travel", "Gaming", "Cars", "Skiing", "Karaoke"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        assert "overlap" in resp.text.lower(), (
            f"Error should mention overlap. Got: {resp.text}"
        )
        print(f"  Interest/dislike overlap → HTTP 422")


# ===================================================================
# 4. Vibe validation errors → 422
# ===================================================================

@requires_supabase
class TestVibeValidation:
    """Verify vibe-related validation errors return 422."""

    def test_0_vibes_rejected(self, client, test_auth_user_with_token):
        """An empty vibes list should be rejected."""
        payload = _valid_vault_payload()
        payload["vibes"] = []
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  0 vibes → HTTP 422")

    def test_invalid_vibe_rejected(self, client, test_auth_user_with_token):
        """An invalid vibe tag should be rejected."""
        payload = _valid_vault_payload()
        payload["vibes"] = ["fancy"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        assert "fancy" in resp.text.lower(), (
            f"Error should mention 'fancy'. Got: {resp.text}"
        )
        print(f"  Invalid vibe 'fancy' → HTTP 422")

    def test_9_vibes_rejected(self, client, test_auth_user_with_token):
        """More than 8 vibes should be rejected."""
        payload = _valid_vault_payload()
        payload["vibes"] = [
            "quiet_luxury", "street_urban", "outdoorsy", "vintage",
            "minimalist", "bohemian", "romantic", "adventurous",
            "quiet_luxury",  # 9th — also duplicate
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  9 vibes → HTTP 422")

    def test_duplicate_vibes_rejected(self, client, test_auth_user_with_token):
        """Duplicate vibe tags should be rejected."""
        payload = _valid_vault_payload()
        payload["vibes"] = ["romantic", "romantic"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Duplicate vibes → HTTP 422")


# ===================================================================
# 5. Budget validation errors → 422
# ===================================================================

@requires_supabase
class TestBudgetValidation:
    """Verify budget-related validation errors return 422."""

    def test_2_budgets_rejected(self, client, test_auth_user_with_token):
        """Only 2 budget tiers (instead of 3) should be rejected."""
        payload = _valid_vault_payload()
        payload["budgets"] = [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 15000},
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  2 budgets → HTTP 422")

    def test_max_less_than_min_rejected(self, client, test_auth_user_with_token):
        """A budget where max_amount < min_amount should be rejected."""
        payload = _valid_vault_payload()
        payload["budgets"][0]["min_amount"] = 10000
        payload["budgets"][0]["max_amount"] = 5000  # less than min
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  max < min → HTTP 422")

    def test_negative_min_amount_rejected(self, client, test_auth_user_with_token):
        """A negative min_amount should be rejected."""
        payload = _valid_vault_payload()
        payload["budgets"][0]["min_amount"] = -100
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Negative min → HTTP 422")

    def test_duplicate_occasion_types_rejected(self, client, test_auth_user_with_token):
        """Two budgets with the same occasion_type should be rejected."""
        payload = _valid_vault_payload()
        payload["budgets"] = [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000},
            {"occasion_type": "just_because", "min_amount": 3000, "max_amount": 8000},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 15000},
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Duplicate occasion types → HTTP 422")


# ===================================================================
# 6. Love language validation errors → 422
# ===================================================================

@requires_supabase
class TestLoveLanguageValidation:
    """Verify love language validation errors return 422."""

    def test_same_primary_secondary_rejected(self, client, test_auth_user_with_token):
        """Using the same language for primary and secondary should be rejected."""
        payload = _valid_vault_payload()
        payload["love_languages"] = {
            "primary": "quality_time",
            "secondary": "quality_time",
        }
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Same primary/secondary → HTTP 422")

    def test_invalid_love_language_rejected(self, client, test_auth_user_with_token):
        """An invalid love language should be rejected."""
        payload = _valid_vault_payload()
        payload["love_languages"] = {
            "primary": "telepathy",
            "secondary": "quality_time",
        }
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Invalid love language → HTTP 422")

    def test_missing_secondary_rejected(self, client, test_auth_user_with_token):
        """Missing the secondary love language should be rejected."""
        payload = _valid_vault_payload()
        payload["love_languages"] = {
            "primary": "quality_time",
        }
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing secondary → HTTP 422")


# ===================================================================
# 7. Milestone validation errors → 422
# ===================================================================

@requires_supabase
class TestMilestoneValidation:
    """Verify milestone-related validation errors return 422."""

    def test_no_milestones_rejected(self, client, test_auth_user_with_token):
        """An empty milestones list should be rejected."""
        payload = _valid_vault_payload()
        payload["milestones"] = []
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  0 milestones → HTTP 422")

    def test_no_birthday_rejected(self, client, test_auth_user_with_token):
        """Milestones without a birthday should be rejected."""
        payload = _valid_vault_payload()
        payload["milestones"] = [
            {
                "milestone_type": "holiday",
                "milestone_name": "Christmas",
                "milestone_date": "2000-12-25",
                "recurrence": "yearly",
            },
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        assert "birthday" in resp.text.lower(), (
            f"Error should mention birthday requirement. Got: {resp.text}"
        )
        print(f"  No birthday → HTTP 422")

    def test_custom_without_budget_tier_rejected(self, client, test_auth_user_with_token):
        """A custom milestone without budget_tier should be rejected."""
        payload = _valid_vault_payload()
        payload["milestones"] = [
            {
                "milestone_type": "birthday",
                "milestone_name": "Birthday",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
            },
            {
                "milestone_type": "custom",
                "milestone_name": "First Date",
                "milestone_date": "2024-09-10",
                "recurrence": "one_time",
                # budget_tier intentionally omitted — should fail for custom
            },
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Custom milestone without budget_tier → HTTP 422")

    def test_empty_milestone_name_rejected(self, client, test_auth_user_with_token):
        """A milestone with an empty name should be rejected."""
        payload = _valid_vault_payload()
        payload["milestones"] = [
            {
                "milestone_type": "birthday",
                "milestone_name": "  ",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
            },
        ]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Empty milestone name → HTTP 422")


# ===================================================================
# 8. Missing required fields → 422
# ===================================================================

@requires_supabase
class TestMissingRequiredFields:
    """Verify missing required fields return 422."""

    def test_missing_partner_name_rejected(self, client, test_auth_user_with_token):
        """Missing partner_name should be rejected."""
        payload = _valid_vault_payload()
        del payload["partner_name"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing partner_name → HTTP 422")

    def test_empty_partner_name_rejected(self, client, test_auth_user_with_token):
        """An empty partner_name should be rejected."""
        payload = _valid_vault_payload()
        payload["partner_name"] = "   "
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Empty partner_name → HTTP 422")

    def test_missing_interests_rejected(self, client, test_auth_user_with_token):
        """Missing interests should be rejected."""
        payload = _valid_vault_payload()
        del payload["interests"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing interests → HTTP 422")

    def test_missing_love_languages_rejected(self, client, test_auth_user_with_token):
        """Missing love_languages should be rejected."""
        payload = _valid_vault_payload()
        del payload["love_languages"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing love_languages → HTTP 422")

    def test_missing_vibes_rejected(self, client, test_auth_user_with_token):
        """Missing vibes should be rejected."""
        payload = _valid_vault_payload()
        del payload["vibes"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing vibes → HTTP 422")

    def test_missing_budgets_rejected(self, client, test_auth_user_with_token):
        """Missing budgets should be rejected."""
        payload = _valid_vault_payload()
        del payload["budgets"]
        resp = client.post(
            "/api/v1/vault",
            json=payload,
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422
        print(f"  Missing budgets → HTTP 422")


# ===================================================================
# 9. Authentication — 401
# ===================================================================

@requires_supabase
class TestAuthRequired:
    """Verify the vault endpoint requires authentication."""

    def test_no_token_returns_401(self, client):
        """A request with no auth token should return 401."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
        )
        assert resp.status_code == 401, (
            f"Expected 401 for missing token, got {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print(f"  No token → HTTP 401")

    def test_invalid_token_returns_401(self, client):
        """A request with an invalid token should return 401."""
        resp = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=_auth_headers("invalid_garbage_token_12345"),
        )
        assert resp.status_code == 401
        print(f"  Invalid token → HTTP 401")


# ===================================================================
# 10. Duplicate vault — 409
# ===================================================================

@requires_supabase
class TestDuplicateVault:
    """Verify creating a second vault for the same user returns 409."""

    def test_second_vault_returns_409(self, client, test_auth_user_with_token):
        """A user who already has a vault should get 409 on a second POST."""
        token = test_auth_user_with_token["access_token"]
        headers = _auth_headers(token)

        # First vault creation — should succeed
        resp1 = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=headers,
        )
        assert resp1.status_code == 201, (
            f"First vault creation failed: HTTP {resp1.status_code}. "
            f"Response: {resp1.text}"
        )

        # Second vault creation — should fail with 409
        resp2 = client.post(
            "/api/v1/vault",
            json=_valid_vault_payload(),
            headers=headers,
        )
        assert resp2.status_code == 409, (
            f"Expected 409 for duplicate vault, got {resp2.status_code}. "
            f"Response: {resp2.text}"
        )
        assert "already exists" in resp2.json()["detail"].lower(), (
            f"Error should mention vault already exists. Got: {resp2.json()['detail']}"
        )
        print(f"  Second POST → HTTP 409")
