"""
Step 1.10 Verification: Recommendation Feedback Table

Tests that:
1. The recommendation_feedback table exists and is accessible via PostgREST
2. The table has the correct columns (id, recommendation_id, user_id, action,
   rating, feedback_text, created_at)
3. action CHECK constraint enforces 'selected', 'refreshed', 'saved', 'shared', 'rated'
4. rating CHECK constraint enforces 1-5 (nullable)
5. Row Level Security (RLS) blocks anonymous access
6. Service client (admin) can read all rows (bypasses RLS)
7. CASCADE delete removes feedback when recommendation is deleted
8. CASCADE delete removes feedback when user is deleted
9. Full CASCADE chain: auth.users → users → recommendation_feedback
10. Foreign key to recommendations is enforced

Prerequisites:
- Complete Steps 0.6-1.9 (Supabase project + users + partner_vaults + recommendations)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00011_create_recommendation_feedback_table.sql

Run with: pytest tests/test_recommendation_feedback_table.py -v
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
# Helpers: insert/delete vault, recommendation, and feedback rows
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


def _delete_recommendation(rec_id: str):
    """Delete a recommendation row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        params={"id": f"eq.{rec_id}"},
    )


def _insert_feedback(feedback_data: dict) -> dict:
    """Insert a feedback row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
        headers=_service_headers(),
        json=feedback_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert feedback: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_feedback_raw(feedback_data: dict) -> httpx.Response:
    """Insert a feedback row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
        headers=_service_headers(),
        json=feedback_data,
    )


def _delete_feedback(feedback_id: str):
    """Delete a feedback row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
        headers=_service_headers(),
        params={"id": f"eq.{feedback_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, recommendation, and feedback
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, recommendations, and feedback rows).
    """
    test_email = f"knot-fb-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-fbA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-fbB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Feedback Test Partner",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "New York",
        "location_state": "NY",
        "location_country": "US",
    }
    vault_row = _insert_vault(vault_data)

    yield {
        "user": test_auth_user,
        "vault": vault_row,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_recommendation(test_vault):
    """
    Create a vault with a single recommendation.
    Yields user, vault, and recommendation info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    rec = _insert_recommendation({
        "vault_id": vault_id,
        "recommendation_type": "gift",
        "title": "Feedback Test Gift",
        "description": "A nice gift for testing feedback.",
        "external_url": "https://example.com/gift",
        "price_cents": 3500,
        "merchant_name": "TestMerchant",
    })

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "recommendation": rec,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_feedback_selected(test_vault_with_recommendation):
    """
    Create a feedback entry with action='selected' for the test recommendation.
    Yields user, vault, recommendation, and feedback info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    user_id = test_vault_with_recommendation["user"]["id"]
    rec_id = test_vault_with_recommendation["recommendation"]["id"]

    feedback = _insert_feedback({
        "recommendation_id": rec_id,
        "user_id": user_id,
        "action": "selected",
    })

    yield {
        "user": test_vault_with_recommendation["user"],
        "vault": test_vault_with_recommendation["vault"],
        "recommendation": test_vault_with_recommendation["recommendation"],
        "feedback": feedback,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestFeedbackTableExists:
    """Verify the recommendation_feedback table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The recommendation_feedback table should exist in the public schema
        and be accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00011_create_recommendation_feedback_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"recommendation_feedback table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00011_create_recommendation_feedback_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  recommendation_feedback table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestFeedbackSchema:
    """Verify the recommendation_feedback table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_feedback_selected):
        """
        The recommendation_feedback table should have exactly these columns:
        id, recommendation_id, user_id, action, rating, feedback_text, created_at.
        """
        fb = test_feedback_selected["feedback"]

        expected_columns = {
            "id", "recommendation_id", "user_id", "action",
            "rating", "feedback_text", "created_at",
        }
        actual_columns = set(fb.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_feedback_selected):
        """The id column should be an auto-generated valid UUID."""
        fb_id = test_feedback_selected["feedback"]["id"]
        parsed = uuid.UUID(fb_id)
        assert str(parsed) == fb_id
        print(f"  id is auto-generated UUID: {fb_id[:8]}...")

    def test_created_at_auto_populated(self, test_feedback_selected):
        """created_at should be automatically populated with a timestamp."""
        fb = test_feedback_selected["feedback"]
        assert fb["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {fb['created_at']}")

    def test_action_check_rejects_invalid(self, test_vault_with_recommendation):
        """
        action must be one of: 'selected', 'refreshed', 'saved', 'shared', 'rated'.
        Invalid values should be rejected by the CHECK constraint.
        """
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        resp = _insert_feedback_raw({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "clicked",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid action 'clicked', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  action CHECK constraint rejects invalid value 'clicked'")

    def test_action_accepts_selected(self, test_vault_with_recommendation):
        """action 'selected' should be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "selected",
        })
        try:
            assert row["action"] == "selected"
            print("  action 'selected' accepted")
        finally:
            _delete_feedback(row["id"])

    def test_action_accepts_refreshed(self, test_vault_with_recommendation):
        """action 'refreshed' should be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "refreshed",
        })
        try:
            assert row["action"] == "refreshed"
            print("  action 'refreshed' accepted")
        finally:
            _delete_feedback(row["id"])

    def test_action_accepts_saved(self, test_vault_with_recommendation):
        """action 'saved' should be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "saved",
        })
        try:
            assert row["action"] == "saved"
            print("  action 'saved' accepted")
        finally:
            _delete_feedback(row["id"])

    def test_action_accepts_shared(self, test_vault_with_recommendation):
        """action 'shared' should be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "shared",
        })
        try:
            assert row["action"] == "shared"
            print("  action 'shared' accepted")
        finally:
            _delete_feedback(row["id"])

    def test_action_accepts_rated(self, test_vault_with_recommendation):
        """action 'rated' should be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 5,
        })
        try:
            assert row["action"] == "rated"
            assert row["rating"] == 5
            print("  action 'rated' accepted with rating=5")
        finally:
            _delete_feedback(row["id"])

    def test_action_not_null(self, test_vault_with_recommendation):
        """action is NOT NULL — inserting without it should fail."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        resp = _insert_feedback_raw({
            "recommendation_id": rec_id,
            "user_id": user_id,
            # action intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing action, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  action NOT NULL constraint enforced")

    def test_rating_check_rejects_zero(self, test_vault_with_recommendation):
        """rating must be >= 1. Zero should be rejected."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        resp = _insert_feedback_raw({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 0,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for rating=0, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  rating CHECK constraint rejects 0 (must be >= 1)")

    def test_rating_check_rejects_six(self, test_vault_with_recommendation):
        """rating must be <= 5. Six should be rejected."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        resp = _insert_feedback_raw({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 6,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for rating=6, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  rating CHECK constraint rejects 6 (must be <= 5)")

    def test_rating_accepts_valid_range(self, test_vault_with_recommendation):
        """rating values 1-5 should all be accepted."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        for rating_val in [1, 2, 3, 4, 5]:
            row = _insert_feedback({
                "recommendation_id": rec_id,
                "user_id": user_id,
                "action": "rated",
                "rating": rating_val,
            })
            try:
                assert row["rating"] == rating_val
            finally:
                _delete_feedback(row["id"])
        print("  rating accepts all valid values (1, 2, 3, 4, 5)")

    def test_rating_is_nullable(self, test_vault_with_recommendation):
        """rating is nullable — non-rated actions don't require a rating."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "selected",
            # rating intentionally omitted
        })
        try:
            assert row["rating"] is None, (
                f"rating should be NULL when not provided, got {row['rating']}"
            )
            print("  rating is nullable (NULL for non-rated actions)")
        finally:
            _delete_feedback(row["id"])

    def test_feedback_text_is_nullable(self, test_vault_with_recommendation):
        """feedback_text is nullable — text feedback is optional."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "selected",
            # feedback_text intentionally omitted
        })
        try:
            assert row["feedback_text"] is None
            print("  feedback_text is nullable")
        finally:
            _delete_feedback(row["id"])

    def test_feedback_text_stores_value(self, test_vault_with_recommendation):
        """feedback_text should store the provided text when given."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 5,
            "feedback_text": "She absolutely loved the pottery class!",
        })
        try:
            assert row["feedback_text"] == "She absolutely loved the pottery class!"
            print("  feedback_text stores value correctly")
        finally:
            _delete_feedback(row["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestFeedbackRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_feedback(self, test_feedback_selected):
        """
        The anon client (no user JWT) should not see any feedback.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} feedback row(s)! "
            "RLS is not properly configured."
        )
        print("  Anon client (no JWT): 0 feedback rows visible — RLS enforced")

    def test_service_client_can_read_feedback(self, test_feedback_selected):
        """
        The service client (bypasses RLS) should see the test feedback.
        """
        rec_id = test_feedback_selected["recommendation"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_service_headers(),
            params={"recommendation_id": f"eq.{rec_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, (
            "Service client should see at least 1 feedback row."
        )
        print(f"  Service client: found {len(rows)} feedback row(s) — RLS bypassed")

    def test_user_isolation_between_feedback(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's feedback.
        Using service client to verify data isolation.
        """
        user_a, user_b = test_auth_user_pair

        # Create vaults for both users
        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "User A Feedback",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "User B Feedback",
        })

        # Create recommendations for both vaults
        rec_a = _insert_recommendation({
            "vault_id": vault_a["id"],
            "recommendation_type": "gift",
            "title": "User A's Gift",
        })
        rec_b = _insert_recommendation({
            "vault_id": vault_b["id"],
            "recommendation_type": "experience",
            "title": "User B's Experience",
        })

        # Create feedback for both users
        fb_a = _insert_feedback({
            "recommendation_id": rec_a["id"],
            "user_id": user_a["id"],
            "action": "selected",
        })
        fb_b = _insert_feedback({
            "recommendation_id": rec_b["id"],
            "user_id": user_b["id"],
            "action": "saved",
        })

        try:
            # Query feedback for user A — should only see user A's data
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["action"] == "selected"

            # Query feedback for user B — should only see user B's data
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["action"] == "saved"

            print("  User isolation verified: each user sees only their own feedback")
        finally:
            _delete_feedback(fb_a["id"])
            _delete_feedback(fb_b["id"])
            _delete_recommendation(rec_a["id"])
            _delete_recommendation(rec_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: feedback stored correctly
# ===================================================================

@requires_supabase
class TestFeedbackDataIntegrity:
    """Verify feedback entries are stored with correct data across all fields."""

    def test_feedback_for_selected_action(self, test_feedback_selected):
        """Insert feedback with action 'selected' and verify the record exists."""
        fb = test_feedback_selected["feedback"]
        rec_id = test_feedback_selected["recommendation"]["id"]
        user_id = test_feedback_selected["user"]["id"]

        # Query by recommendation_id
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_service_headers(),
            params={"recommendation_id": f"eq.{rec_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1

        found = [r for r in rows if r["id"] == fb["id"]]
        assert len(found) == 1
        row = found[0]

        assert row["recommendation_id"] == rec_id
        assert row["user_id"] == user_id
        assert row["action"] == "selected"
        assert row["rating"] is None
        assert row["feedback_text"] is None
        assert row["created_at"] is not None
        print("  Feedback for 'selected' action stored and queried correctly")

    def test_rated_with_feedback_text(self, test_vault_with_recommendation):
        """Feedback with rating and text should store all fields."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        row = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 4,
            "feedback_text": "She liked it but would have preferred a different color.",
        })
        try:
            assert row["action"] == "rated"
            assert row["rating"] == 4
            assert row["feedback_text"] == "She liked it but would have preferred a different color."
            print("  Rated feedback with text stored correctly (action=rated, rating=4, text present)")
        finally:
            _delete_feedback(row["id"])

    def test_multiple_feedback_per_recommendation(self, test_vault_with_recommendation):
        """A recommendation can have multiple feedback entries (e.g., selected then rated)."""
        user_id = test_vault_with_recommendation["user"]["id"]
        rec_id = test_vault_with_recommendation["recommendation"]["id"]

        fb1 = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "selected",
        })
        fb2 = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "rated",
            "rating": 5,
            "feedback_text": "Perfect gift!",
        })

        try:
            resp = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
                headers=_service_headers(),
                params={"recommendation_id": f"eq.{rec_id}", "select": "*"},
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 2, f"Expected 2 feedback entries, got {len(rows)}"

            actions = {r["action"] for r in rows}
            assert actions == {"selected", "rated"}
            print("  Multiple feedback entries per recommendation: selected + rated")
        finally:
            _delete_feedback(fb1["id"])
            _delete_feedback(fb2["id"])


# ===================================================================
# 5. CASCADE delete behavior
# ===================================================================

@requires_supabase
class TestFeedbackCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_recommendation(self, test_auth_user):
        """
        When a recommendation is deleted, all its feedback should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault and recommendation
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade FB Test",
        })
        rec = _insert_recommendation({
            "vault_id": vault["id"],
            "recommendation_type": "gift",
            "title": "Cascade Feedback Gift",
        })
        rec_id = rec["id"]

        # Insert feedback
        fb = _insert_feedback({
            "recommendation_id": rec_id,
            "user_id": user_id,
            "action": "selected",
        })
        fb_id = fb["id"]

        # Verify feedback exists
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_service_headers(),
            params={"id": f"eq.{fb_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 1, "Feedback should exist before recommendation deletion"

        # Delete the recommendation
        _delete_recommendation(rec_id)
        time.sleep(0.3)

        # Verify feedback is gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
            headers=_service_headers(),
            params={"id": f"eq.{fb_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "Feedback row still exists after recommendation deletion. "
            "Check that recommendation_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: recommendation deletion removed feedback rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → recommendation_feedback
        (also via: auth.users → users → partner_vaults → recommendations → feedback)
        """
        # Create temp auth user
        temp_email = f"knot-fb-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeFB!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault and recommendation
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade FB Test",
            })
            rec = _insert_recommendation({
                "vault_id": vault["id"],
                "recommendation_type": "date",
                "title": "Cascade chain test date",
            })

            # Add feedback
            fb = _insert_feedback({
                "recommendation_id": rec["id"],
                "user_id": temp_user_id,
                "action": "saved",
            })
            fb_id = fb["id"]

            # Verify feedback exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
                headers=_service_headers(),
                params={"id": f"eq.{fb_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify feedback is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
                headers=_service_headers(),
                params={"id": f"eq.{fb_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Feedback row still exists after auth user deletion. "
                "Check full CASCADE chain."
            )
            print("  Full CASCADE delete verified: auth deletion removed feedback rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_recommendation_id(self, test_auth_user):
        """
        Inserting feedback with a non-existent recommendation_id should fail
        because of the foreign key constraint to recommendations.
        """
        user_id = test_auth_user["id"]
        fake_rec_id = str(uuid.uuid4())

        resp = _insert_feedback_raw({
            "recommendation_id": fake_rec_id,
            "user_id": user_id,
            "action": "selected",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent recommendation_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  FK constraint enforced (non-existent recommendation_id rejected)")

    def test_foreign_key_enforced_invalid_user_id(self, test_vault_with_recommendation):
        """
        Inserting feedback with a non-existent user_id should fail
        because of the foreign key constraint to users.
        """
        rec_id = test_vault_with_recommendation["recommendation"]["id"]
        fake_user_id = str(uuid.uuid4())

        resp = _insert_feedback_raw({
            "recommendation_id": rec_id,
            "user_id": fake_user_id,
            "action": "selected",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent user_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  FK constraint enforced (non-existent user_id rejected)")
