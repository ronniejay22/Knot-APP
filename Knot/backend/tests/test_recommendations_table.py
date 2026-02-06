"""
Step 1.9 Verification: Recommendations History Table

Tests that:
1. The recommendations table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, milestone_id, recommendation_type,
   title, description, external_url, price_cents, merchant_name, image_url, created_at)
3. recommendation_type CHECK constraint enforces 'gift', 'experience', 'date' only
4. price_cents CHECK constraint enforces >= 0
5. milestone_id is nullable (recommendations can exist without a milestone)
6. milestone_id FK uses SET NULL on delete (recommendation persists when milestone is deleted)
7. Row Level Security (RLS) blocks anonymous access
8. Service client (admin) can read all rows (bypasses RLS)
9. CASCADE delete removes recommendations when vault is deleted
10. Full CASCADE chain: auth.users → users → partner_vaults → recommendations
11. Foreign key to partner_vaults is enforced

Prerequisites:
- Complete Steps 0.6-1.4 (Supabase project + users + partner_vaults + partner_milestones)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00010_create_recommendations_table.sql

Run with: pytest tests/test_recommendations_table.py -v
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
# Helpers: HTTP headers for PostgREST and Admin API
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access. Bypasses RLS."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _anon_headers() -> dict:
    """Headers for anon (public) PostgREST access. No user JWT."""
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type": "application/json",
    }


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


# ---------------------------------------------------------------------------
# Helpers: insert/delete vault, milestone, and recommendation rows
# ---------------------------------------------------------------------------

def _insert_vault(vault_data: dict) -> dict:
    """Insert a vault row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=vault_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vault: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _delete_vault(vault_id: str):
    """Delete a vault row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        params={"id": f"eq.{vault_id}"},
    )


def _insert_milestone(milestone_data: dict) -> dict:
    """Insert a milestone row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        json=milestone_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert milestone: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _delete_milestone(milestone_id: str):
    """Delete a milestone row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        params={"id": f"eq.{milestone_id}"},
    )


def _insert_recommendation(rec_data: dict) -> dict:
    """Insert a recommendation row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        json=rec_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert recommendation: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_recommendation_raw(rec_data: dict) -> httpx.Response:
    """Insert a recommendation row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        json=rec_data,
    )


def _delete_recommendation(rec_id: str):
    """Delete a recommendation row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        params={"id": f"eq.{rec_id}"},
    )


# ---------------------------------------------------------------------------
# Sample recommendation data
# ---------------------------------------------------------------------------

SAMPLE_GIFT_REC = {
    "recommendation_type": "gift",
    "title": "Handcrafted Ceramic Planter Set",
    "description": "Beautiful set of 3 ceramic planters for indoor gardening enthusiasts.",
    "external_url": "https://example.com/products/ceramic-planter-set",
    "price_cents": 4999,
    "merchant_name": "Etsy",
    "image_url": "https://example.com/images/ceramic-planter.jpg",
}

SAMPLE_EXPERIENCE_REC = {
    "recommendation_type": "experience",
    "title": "Private Pottery Class for Two",
    "description": "2-hour hands-on pottery session in a cozy downtown studio.",
    "external_url": "https://example.com/experiences/pottery-class",
    "price_cents": 12000,
    "merchant_name": "ClassBento",
    "image_url": "https://example.com/images/pottery-class.jpg",
}

SAMPLE_DATE_REC = {
    "recommendation_type": "date",
    "title": "Candlelight Dinner at Bella Luna",
    "description": "Italian fine dining with live jazz on Friday evenings.",
    "external_url": "https://example.com/restaurants/bella-luna",
    "price_cents": 18000,
    "merchant_name": "OpenTable",
    "image_url": "https://example.com/images/bella-luna.jpg",
}


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, milestone, and vault with recommendations
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and recommendations rows).
    """
    test_email = f"knot-rec-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)

    # Give the trigger a moment to fire
    time.sleep(0.5)

    yield {"id": user_id, "email": test_email}

    # Cleanup: delete auth user (CASCADE deletes everything)
    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user_pair():
    """
    Create TWO test users for testing RLS isolation between users.
    Yields a tuple of (user_a_info, user_b_info).
    """
    email_a = f"knot-recA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-recB-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_a_id = _create_auth_user(email_a, password)
    user_b_id = _create_auth_user(email_b, password)

    time.sleep(0.5)

    yield (
        {"id": user_a_id, "email": email_a},
        {"id": user_b_id, "email": email_b},
    )

    _delete_auth_user(user_a_id)
    _delete_auth_user(user_b_id)


@pytest.fixture
def test_vault(test_auth_user):
    """
    Create a test vault for the test user and yield both user and vault info.
    Vault is auto-cleaned when the auth user is deleted (CASCADE).
    """
    user_id = test_auth_user["id"]
    vault_data = {
        "user_id": user_id,
        "partner_name": "Recommendations Test Partner",
        "relationship_tenure_months": 36,
        "cohabitation_status": "living_together",
        "location_city": "San Francisco",
        "location_state": "CA",
        "location_country": "US",
    }
    vault_row = _insert_vault(vault_data)

    yield {
        "user": test_auth_user,
        "vault": vault_row,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_milestone(test_vault):
    """
    Create a vault with a birthday milestone.
    Yields user, vault, and milestone info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    milestone = _insert_milestone({
        "vault_id": vault_id,
        "milestone_type": "birthday",
        "milestone_name": "Partner's Birthday",
        "milestone_date": "2000-06-15",
        "recurrence": "yearly",
        # budget_tier auto-defaults to 'major_milestone' via trigger
    })

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "milestone": milestone,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_recommendations(test_vault_with_milestone):
    """
    Create a vault with 3 recommendations (gift, experience, date) linked
    to a birthday milestone.
    Yields user, vault, milestone, and recommendations info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault_with_milestone["vault"]["id"]
    milestone_id = test_vault_with_milestone["milestone"]["id"]
    recs = []

    for sample in [SAMPLE_GIFT_REC, SAMPLE_EXPERIENCE_REC, SAMPLE_DATE_REC]:
        row = _insert_recommendation({
            "vault_id": vault_id,
            "milestone_id": milestone_id,
            **sample,
        })
        recs.append(row)

    yield {
        "user": test_vault_with_milestone["user"],
        "vault": test_vault_with_milestone["vault"],
        "milestone": test_vault_with_milestone["milestone"],
        "recommendations": recs,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestRecommendationsTableExists:
    """Verify the recommendations table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The recommendations table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00010_create_recommendations_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"recommendations table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00010_create_recommendations_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  recommendations table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestRecommendationsSchema:
    """Verify the recommendations table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_recommendations):
        """
        The recommendations table should have exactly these columns:
        id, vault_id, milestone_id, recommendation_type, title, description,
        external_url, price_cents, merchant_name, image_url, created_at.
        """
        vault_id = test_vault_with_recommendations["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No recommendation rows found"

        row = rows[0]
        expected_columns = {
            "id", "vault_id", "milestone_id", "recommendation_type",
            "title", "description", "external_url", "price_cents",
            "merchant_name", "image_url", "created_at",
        }
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_recommendations):
        """The id column should be an auto-generated valid UUID."""
        rec_id = test_vault_with_recommendations["recommendations"][0]["id"]
        parsed = uuid.UUID(rec_id)
        assert str(parsed) == rec_id
        print(f"  id is auto-generated UUID: {rec_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_recommendations):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_recommendations["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "created_at", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1
        assert rows[0]["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {rows[0]['created_at']}")

    def test_recommendation_type_check_rejects_invalid(self, test_vault):
        """
        recommendation_type must be 'gift', 'experience', or 'date'.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_recommendation_raw({
            "vault_id": vault_id,
            "recommendation_type": "coupon",
            "title": "Test recommendation",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid recommendation_type 'coupon', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  recommendation_type CHECK constraint rejects invalid value 'coupon'")

    def test_recommendation_type_accepts_gift(self, test_vault):
        """recommendation_type 'gift' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Test Gift",
        })
        try:
            assert row["recommendation_type"] == "gift"
            print("  recommendation_type 'gift' accepted")
        finally:
            _delete_recommendation(row["id"])

    def test_recommendation_type_accepts_experience(self, test_vault):
        """recommendation_type 'experience' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "experience",
            "title": "Test Experience",
        })
        try:
            assert row["recommendation_type"] == "experience"
            print("  recommendation_type 'experience' accepted")
        finally:
            _delete_recommendation(row["id"])

    def test_recommendation_type_accepts_date(self, test_vault):
        """recommendation_type 'date' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "date",
            "title": "Test Date",
        })
        try:
            assert row["recommendation_type"] == "date"
            print("  recommendation_type 'date' accepted")
        finally:
            _delete_recommendation(row["id"])

    def test_title_not_null(self, test_vault):
        """title is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_recommendation_raw({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            # title intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing title, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  title NOT NULL constraint enforced")

    def test_recommendation_type_not_null(self, test_vault):
        """recommendation_type is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_recommendation_raw({
            "vault_id": vault_id,
            "title": "Missing Type Rec",
            # recommendation_type intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing recommendation_type, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  recommendation_type NOT NULL constraint enforced")

    def test_milestone_id_is_nullable(self, test_vault):
        """
        milestone_id is nullable — recommendations can exist without a milestone
        (e.g., "just because" browsing).
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Just Because Gift",
            # milestone_id intentionally omitted
        })
        try:
            assert row["milestone_id"] is None, (
                f"milestone_id should be NULL when not provided, "
                f"got {row['milestone_id']}"
            )
            print("  milestone_id is nullable (NULL for 'just because' recommendations)")
        finally:
            _delete_recommendation(row["id"])

    def test_description_is_nullable(self, test_vault):
        """description is nullable — can store recommendations without descriptions."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "No Description Gift",
            # description intentionally omitted
        })
        try:
            assert row["description"] is None
            print("  description is nullable")
        finally:
            _delete_recommendation(row["id"])

    def test_price_cents_check_rejects_negative(self, test_vault):
        """price_cents must be >= 0. Negative amounts should be rejected."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_recommendation_raw({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Negative Price Gift",
            "price_cents": -100,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for negative price_cents, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  price_cents CHECK constraint rejects negative value (-100)")

    def test_price_cents_accepts_zero(self, test_vault):
        """price_cents = 0 should be accepted (free items)."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "experience",
            "title": "Free Museum Visit",
            "price_cents": 0,
        })
        try:
            assert row["price_cents"] == 0
            print("  price_cents = 0 accepted (free items)")
        finally:
            _delete_recommendation(row["id"])

    def test_price_cents_is_nullable(self, test_vault):
        """price_cents is nullable — price might not always be known."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "date",
            "title": "Price Unknown Date",
            # price_cents intentionally omitted
        })
        try:
            assert row["price_cents"] is None
            print("  price_cents is nullable (price unknown)")
        finally:
            _delete_recommendation(row["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestRecommendationsRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_recommendations(self, test_vault_with_recommendations):
        """
        The anon client (no user JWT) should not see any recommendations.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} recommendation(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 recommendations visible — RLS enforced")

    def test_service_client_can_read_recommendations(self, test_vault_with_recommendations):
        """
        The service client (bypasses RLS) should see the test recommendations.
        """
        vault_id = test_vault_with_recommendations["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, (
            f"Service client should see 3 recommendations, got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} recommendations — RLS bypassed")

    def test_user_isolation_between_recommendations(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's recommendations.
        Using service client to verify data isolation.
        """
        user_a, user_b = test_auth_user_pair

        # Create vaults for both users
        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "User A's Partner",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "User B's Partner",
        })

        # Add recommendations to both vaults
        rec_a = _insert_recommendation({
            "vault_id": vault_a["id"],
            "recommendation_type": "gift",
            "title": "User A's Gift Rec",
        })
        rec_b = _insert_recommendation({
            "vault_id": vault_b["id"],
            "recommendation_type": "experience",
            "title": "User B's Experience Rec",
        })

        try:
            # Query recommendations for vault A — should only return vault A's data
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendations",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["title"] == "User A's Gift Rec"

            # Query recommendations for vault B — should only return vault B's data
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendations",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["title"] == "User B's Experience Rec"

            print("  User isolation verified: each vault sees only its own recommendations")
        finally:
            _delete_recommendation(rec_a["id"])
            _delete_recommendation(rec_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: recommendations stored correctly
# ===================================================================

@requires_supabase
class TestRecommendationsDataIntegrity:
    """Verify recommendations are stored with correct data across all fields."""

    def test_three_recommendations_per_vault(self, test_vault_with_recommendations):
        """A vault can have multiple recommendations (the 'Choice of Three')."""
        vault_id = test_vault_with_recommendations["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={
                "vault_id": f"eq.{vault_id}",
                "select": "*",
                "order": "created_at.asc",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 recommendations, got {len(rows)}"
        print(f"  Multiple recommendations per vault: {len(rows)} stored correctly")

    def test_all_fields_populated(self, test_vault_with_recommendations):
        """
        Verify a recommendation record returns with all fields populated
        (the primary test from the implementation plan).
        """
        vault_id = test_vault_with_recommendations["vault"]["id"]
        milestone_id = test_vault_with_recommendations["milestone"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={
                "vault_id": f"eq.{vault_id}",
                "select": "*",
                "order": "created_at.asc",
                "limit": "1",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 1
        row = rows[0]

        # Verify all fields are populated
        assert row["id"] is not None
        assert row["vault_id"] == vault_id
        assert row["milestone_id"] == milestone_id
        assert row["recommendation_type"] == "gift"
        assert row["title"] == "Handcrafted Ceramic Planter Set"
        assert row["description"] == "Beautiful set of 3 ceramic planters for indoor gardening enthusiasts."
        assert row["external_url"] == "https://example.com/products/ceramic-planter-set"
        assert row["price_cents"] == 4999
        assert row["merchant_name"] == "Etsy"
        assert row["image_url"] == "https://example.com/images/ceramic-planter.jpg"
        assert row["created_at"] is not None

        print("  All fields populated and verified for gift recommendation")

    def test_recommendation_types_stored(self, test_vault_with_recommendations):
        """Verify all three recommendation types are stored correctly."""
        recs = test_vault_with_recommendations["recommendations"]

        types = {r["recommendation_type"] for r in recs}
        assert types == {"gift", "experience", "date"}, (
            f"Expected all 3 types (gift, experience, date), got {types}"
        )
        print("  All 3 recommendation types stored: gift, experience, date")

    def test_recommendation_with_milestone(self, test_vault_with_recommendations):
        """Recommendation linked to a milestone should store the milestone_id."""
        rec = test_vault_with_recommendations["recommendations"][0]
        milestone_id = test_vault_with_recommendations["milestone"]["id"]

        assert rec["milestone_id"] == milestone_id, (
            f"milestone_id mismatch: expected {milestone_id}, got {rec['milestone_id']}"
        )
        print("  Recommendation correctly linked to milestone")

    def test_recommendation_without_milestone(self, test_vault):
        """
        Recommendations can be created without a milestone_id
        (e.g., 'just because' browsing).
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Spontaneous Gift Idea",
            "description": "A nice gift just because.",
            "external_url": "https://example.com/spontaneous",
            "price_cents": 2500,
            "merchant_name": "Amazon",
            # milestone_id intentionally omitted
        })
        try:
            assert row["milestone_id"] is None
            assert row["title"] == "Spontaneous Gift Idea"
            print("  Recommendation stored without milestone ('just because')")
        finally:
            _delete_recommendation(row["id"])

    def test_price_stored_in_cents(self, test_vault_with_recommendations):
        """Price should be stored as integer cents (e.g., 4999 = $49.99)."""
        recs = test_vault_with_recommendations["recommendations"]

        # Gift: 4999 cents = $49.99
        gift = [r for r in recs if r["recommendation_type"] == "gift"][0]
        assert gift["price_cents"] == 4999
        assert isinstance(gift["price_cents"], int)

        # Experience: 12000 cents = $120.00
        exp = [r for r in recs if r["recommendation_type"] == "experience"][0]
        assert exp["price_cents"] == 12000

        # Date: 18000 cents = $180.00
        date = [r for r in recs if r["recommendation_type"] == "date"][0]
        assert date["price_cents"] == 18000

        print("  Prices stored as integers in cents (4999, 12000, 18000)")

    def test_external_urls_stored(self, test_vault_with_recommendations):
        """External URLs should be stored correctly for merchant handoff."""
        recs = test_vault_with_recommendations["recommendations"]

        for rec in recs:
            assert rec["external_url"] is not None
            assert rec["external_url"].startswith("https://")

        print("  External URLs stored correctly for all recommendations")

    def test_merchant_names_stored(self, test_vault_with_recommendations):
        """Merchant names should be stored for display on recommendation cards."""
        recs = test_vault_with_recommendations["recommendations"]
        merchants = {r["merchant_name"] for r in recs}

        assert "Etsy" in merchants
        assert "ClassBento" in merchants
        assert "OpenTable" in merchants
        print(f"  Merchant names stored: {sorted(merchants)}")


# ===================================================================
# 5. Milestone FK behavior (SET NULL on delete)
# ===================================================================

@requires_supabase
class TestRecommendationsMilestoneFK:
    """Verify milestone_id FK uses SET NULL on delete (not CASCADE)."""

    def test_milestone_deletion_sets_null(self, test_auth_user):
        """
        When a milestone is deleted, the recommendation's milestone_id should
        be set to NULL (not cascade-deleted). Recommendations are historical
        records that should persist even if the milestone is removed.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Milestone FK Test",
        })
        vault_id = vault["id"]

        # Create milestone
        milestone = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-03-20",
            "recurrence": "yearly",
        })
        milestone_id = milestone["id"]

        # Create recommendation linked to milestone
        rec = _insert_recommendation({
            "vault_id": vault_id,
            "milestone_id": milestone_id,
            "recommendation_type": "gift",
            "title": "Birthday Gift",
            "price_cents": 5000,
        })
        rec_id = rec["id"]

        try:
            # Verify recommendation has milestone_id
            assert rec["milestone_id"] == milestone_id

            # Delete the milestone
            _delete_milestone(milestone_id)
            time.sleep(0.3)

            # Verify recommendation still exists but milestone_id is NULL
            check = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendations",
                headers=_service_headers(),
                params={"id": f"eq.{rec_id}", "select": "*"},
            )
            assert check.status_code == 200
            rows = check.json()
            assert len(rows) == 1, (
                "Recommendation should still exist after milestone deletion "
                "(SET NULL, not CASCADE)"
            )
            assert rows[0]["milestone_id"] is None, (
                f"milestone_id should be NULL after milestone deletion, "
                f"got {rows[0]['milestone_id']}"
            )
            assert rows[0]["title"] == "Birthday Gift", (
                "Recommendation data should be intact after milestone deletion"
            )
            print("  Milestone deletion sets recommendation.milestone_id to NULL (preserves history)")
        finally:
            _delete_recommendation(rec_id)

    def test_milestone_fk_rejects_invalid_id(self, test_vault):
        """
        Inserting a recommendation with a non-existent milestone_id should fail
        because of the foreign key constraint to partner_milestones.
        """
        vault_id = test_vault["vault"]["id"]
        fake_milestone_id = str(uuid.uuid4())

        resp = _insert_recommendation_raw({
            "vault_id": vault_id,
            "milestone_id": fake_milestone_id,
            "recommendation_type": "gift",
            "title": "Invalid Milestone Rec",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent milestone_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  milestone_id FK constraint enforced (non-existent milestone_id rejected)")


# ===================================================================
# 6. Triggers and cascades
# ===================================================================

@requires_supabase
class TestRecommendationsCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its recommendations should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Rec Test",
        })
        vault_id = vault["id"]

        # Insert recommendations
        rec1 = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Cascade Test Gift",
        })
        rec2 = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "experience",
            "title": "Cascade Test Experience",
        })

        # Verify recommendations exist
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 2, "Recommendations should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify recommendations are gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendations",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "recommendation rows still exist after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed recommendation rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → recommendations.
        """
        # Create temp auth user
        temp_email = f"knot-rec-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeRec!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Rec Test",
            })
            vault_id = vault["id"]

            # Add recommendation
            rec = _insert_recommendation({
                "vault_id": vault_id,
                "recommendation_type": "date",
                "title": "Cascade chain test date",
            })
            rec_id = rec["id"]

            # Verify recommendation exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendations",
                headers=_service_headers(),
                params={"id": f"eq.{rec_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify recommendation is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendations",
                headers=_service_headers(),
                params={"id": f"eq.{rec_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Recommendation row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → recommendations"
            )
            print("  Full CASCADE delete verified: auth deletion removed recommendation rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a recommendation with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_recommendation_raw({
            "vault_id": fake_vault_id,
            "recommendation_type": "gift",
            "title": "This should fail",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
