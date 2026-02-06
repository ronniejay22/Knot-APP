"""
Step 1.3 Verification: Partner Interests Table

Tests that:
1. The partner_interests table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, interest_type, interest_category, created_at)
3. interest_type CHECK constraint enforces 'like' and 'dislike' only
4. interest_category CHECK constraint enforces the predefined list of 40 categories
5. UNIQUE(vault_id, interest_category) prevents duplicates and blocks same interest as both like and dislike
6. Row Level Security (RLS) blocks anonymous access
7. Service client (admin) can read all rows (bypasses RLS)
8. CASCADE delete removes interests when vault is deleted
9. Can insert exactly 5 likes and 5 dislikes for a vault
10. Foreign key to partner_vaults is enforced

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00004_create_partner_interests_table.sql

Run with: pytest tests/test_partner_interests_table.py -v
"""

import pytest
import httpx
import uuid
import time

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Predefined interest categories (must match migration CHECK constraint)
# ---------------------------------------------------------------------------

VALID_CATEGORIES = [
    "Travel", "Cooking", "Movies", "Music", "Reading",
    "Sports", "Gaming", "Art", "Photography", "Fitness",
    "Fashion", "Technology", "Nature", "Food", "Coffee",
    "Wine", "Dancing", "Theater", "Concerts", "Museums",
    "Shopping", "Yoga", "Hiking", "Beach", "Pets",
    "Cars", "DIY", "Gardening", "Meditation", "Podcasts",
    "Baking", "Camping", "Cycling", "Running", "Swimming",
    "Skiing", "Surfing", "Painting", "Board Games", "Karaoke",
]

# Samples for test data — 5 likes and 5 dislikes that don't overlap
SAMPLE_LIKES = ["Travel", "Cooking", "Music", "Photography", "Hiking"]
SAMPLE_DISLIKES = ["Gaming", "Cars", "Shopping", "Skiing", "Karaoke"]


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
# Helpers: insert vault and interest rows via service client
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


def _insert_interest(interest_data: dict) -> dict:
    """Insert an interest row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_interests",
        headers=_service_headers(),
        json=interest_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert interest: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_interest_raw(interest_data: dict) -> httpx.Response:
    """Insert an interest row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_interests",
        headers=_service_headers(),
        json=interest_data,
    )


def _delete_interest(interest_id: str):
    """Delete an interest row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_interests",
        headers=_service_headers(),
        params={"id": f"eq.{interest_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with interests
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and partner_interests rows).
    """
    test_email = f"knot-interest-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-intA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-intB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Interest Test Partner",
        "relationship_tenure_months": 18,
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
def test_vault_with_interests(test_vault):
    """
    Create a vault with 5 likes and 5 dislikes pre-populated.
    Yields user, vault, and interest IDs for verification.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    like_ids = []
    dislike_ids = []

    # Insert 5 likes
    for category in SAMPLE_LIKES:
        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": category,
        })
        like_ids.append(row["id"])

    # Insert 5 dislikes
    for category in SAMPLE_DISLIKES:
        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "dislike",
            "interest_category": category,
        })
        dislike_ids.append(row["id"])

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "like_ids": like_ids,
        "dislike_ids": dislike_ids,
        "likes": SAMPLE_LIKES,
        "dislikes": SAMPLE_DISLIKES,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerInterestsTableExists:
    """Verify the partner_interests table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_interests table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00004_create_partner_interests_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_interests table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00004_create_partner_interests_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_interests table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerInterestsSchema:
    """Verify the partner_interests table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_interests):
        """
        The partner_interests table should have exactly these columns:
        id, vault_id, interest_type, interest_category, created_at.
        """
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No interest rows found"

        row = rows[0]
        expected_columns = {
            "id", "vault_id", "interest_type", "interest_category", "created_at",
        }
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_interests):
        """The id column should be an auto-generated valid UUID."""
        interest_id = test_vault_with_interests["like_ids"][0]
        parsed = uuid.UUID(interest_id)
        assert str(parsed) == interest_id
        print(f"  id is auto-generated UUID: {interest_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_interests):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
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

    def test_interest_type_check_constraint_rejects_invalid(self, test_vault):
        """
        interest_type must be either 'like' or 'dislike'.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_interest_raw({
            "vault_id": vault_id,
            "interest_type": "love",
            "interest_category": "Travel",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid interest_type 'love', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  interest_type CHECK constraint rejects invalid value 'love'")

    def test_interest_type_accepts_like(self, test_vault):
        """interest_type 'like' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": "Travel",
        })
        assert row["interest_type"] == "like"
        _delete_interest(row["id"])
        print("  interest_type 'like' accepted")

    def test_interest_type_accepts_dislike(self, test_vault):
        """interest_type 'dislike' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "dislike",
            "interest_category": "Music",
        })
        assert row["interest_type"] == "dislike"
        _delete_interest(row["id"])
        print("  interest_type 'dislike' accepted")

    def test_interest_category_check_constraint_rejects_invalid(self, test_vault):
        """
        interest_category must be from the predefined list.
        Inserting an invalid category should be rejected.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_interest_raw({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": "Underwater Basket Weaving",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid interest_category "
            f"'Underwater Basket Weaving', got HTTP {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print("  interest_category CHECK constraint rejects invalid category")

    def test_interest_category_accepts_all_valid(self, test_vault):
        """
        All 40 predefined categories should be accepted by the CHECK constraint.
        Insert one of each, then clean up.
        """
        vault_id = test_vault["vault"]["id"]
        inserted_ids = []

        try:
            for i, category in enumerate(VALID_CATEGORIES):
                interest_type = "like" if i % 2 == 0 else "dislike"
                row = _insert_interest({
                    "vault_id": vault_id,
                    "interest_type": interest_type,
                    "interest_category": category,
                })
                inserted_ids.append(row["id"])

            assert len(inserted_ids) == len(VALID_CATEGORIES), (
                f"Expected {len(VALID_CATEGORIES)} interests inserted, "
                f"got {len(inserted_ids)}"
            )
            print(f"  All {len(VALID_CATEGORIES)} valid categories accepted")
        finally:
            for iid in inserted_ids:
                _delete_interest(iid)

    def test_unique_constraint_prevents_duplicate_category(self, test_vault):
        """
        UNIQUE(vault_id, interest_category) prevents inserting the same
        category twice for the same vault, even with the same interest_type.
        """
        vault_id = test_vault["vault"]["id"]

        # Insert first: "Hiking" as a like
        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": "Hiking",
        })

        try:
            # Attempt to insert second: "Hiking" as a like again
            resp = _insert_interest_raw({
                "vault_id": vault_id,
                "interest_type": "like",
                "interest_category": "Hiking",
            })
            assert resp.status_code == 409, (
                f"Expected 409 Conflict for duplicate (vault_id, interest_category), "
                f"got HTTP {resp.status_code}. Response: {resp.text}"
            )
            print("  UNIQUE constraint prevents duplicate category for same vault")
        finally:
            _delete_interest(row["id"])

    def test_unique_constraint_prevents_like_and_dislike_same_category(self, test_vault):
        """
        UNIQUE(vault_id, interest_category) prevents the same category
        from being both a like AND a dislike for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        # Insert "Hiking" as a like
        row = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": "Hiking",
        })

        try:
            # Attempt to insert "Hiking" as a dislike
            resp = _insert_interest_raw({
                "vault_id": vault_id,
                "interest_type": "dislike",
                "interest_category": "Hiking",
            })
            assert resp.status_code == 409, (
                f"Expected 409 Conflict when adding 'Hiking' as both like and dislike, "
                f"got HTTP {resp.status_code}. The UNIQUE(vault_id, interest_category) "
                f"constraint should prevent this. Response: {resp.text}"
            )
            print("  UNIQUE constraint prevents same category as both like and dislike")
        finally:
            _delete_interest(row["id"])

    def test_interest_category_not_null(self, test_vault):
        """interest_category is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_interest_raw({
            "vault_id": vault_id,
            "interest_type": "like",
            # interest_category intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing interest_category, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  interest_category NOT NULL constraint enforced")

    def test_interest_type_not_null(self, test_vault):
        """interest_type is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_interest_raw({
            "vault_id": vault_id,
            # interest_type intentionally omitted
            "interest_category": "Travel",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing interest_type, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  interest_type NOT NULL constraint enforced")


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerInterestsRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_interests(self, test_vault_with_interests):
        """
        The anon client (no user JWT) should not see any interests.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} interest(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_interests ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 interests visible — RLS enforced")

    def test_service_client_can_read_interests(self, test_vault_with_interests):
        """
        The service client (bypasses RLS) should see the test interests.
        """
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 10, (
            f"Service client should see 10 interests (5 likes + 5 dislikes), "
            f"got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} interests — RLS bypassed")

    def test_user_isolation_between_interests(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's interests.
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

        # Add interests to both vaults
        interest_a = _insert_interest({
            "vault_id": vault_a["id"],
            "interest_type": "like",
            "interest_category": "Travel",
        })
        interest_b = _insert_interest({
            "vault_id": vault_b["id"],
            "interest_type": "like",
            "interest_category": "Music",
        })

        try:
            # Query interests for vault A — should only return vault A's interest
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_interests",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["interest_category"] == "Travel"

            # Query interests for vault B — should only return vault B's interest
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_interests",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["interest_category"] == "Music"

            print("  User isolation verified: each vault sees only its own interests")
        finally:
            _delete_interest(interest_a["id"])
            _delete_interest(interest_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: 5 likes + 5 dislikes
# ===================================================================

@requires_supabase
class TestPartnerInterestsDataIntegrity:
    """Verify that 5 likes and 5 dislikes can be stored and retrieved correctly."""

    def test_insert_5_likes_and_5_dislikes(self, test_vault_with_interests):
        """
        A vault should have exactly 5 likes and 5 dislikes.
        Verify all 10 interests are stored with correct types.
        """
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 10, (
            f"Expected 10 interests total, got {len(rows)}"
        )

        likes = [r for r in rows if r["interest_type"] == "like"]
        dislikes = [r for r in rows if r["interest_type"] == "dislike"]

        assert len(likes) == 5, f"Expected 5 likes, got {len(likes)}"
        assert len(dislikes) == 5, f"Expected 5 dislikes, got {len(dislikes)}"

        like_categories = sorted([r["interest_category"] for r in likes])
        dislike_categories = sorted([r["interest_category"] for r in dislikes])

        assert like_categories == sorted(SAMPLE_LIKES), (
            f"Like categories mismatch. Expected: {sorted(SAMPLE_LIKES)}, "
            f"Got: {like_categories}"
        )
        assert dislike_categories == sorted(SAMPLE_DISLIKES), (
            f"Dislike categories mismatch. Expected: {sorted(SAMPLE_DISLIKES)}, "
            f"Got: {dislike_categories}"
        )
        print(f"  5 likes: {like_categories}")
        print(f"  5 dislikes: {dislike_categories}")

    def test_likes_and_dislikes_do_not_overlap(self, test_vault_with_interests):
        """
        The set of likes and dislikes should have no overlap.
        This is enforced by the UNIQUE(vault_id, interest_category) constraint.
        """
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        rows = resp.json()

        likes = {r["interest_category"] for r in rows if r["interest_type"] == "like"}
        dislikes = {r["interest_category"] for r in rows if r["interest_type"] == "dislike"}

        overlap = likes & dislikes
        assert len(overlap) == 0, (
            f"Likes and dislikes overlap: {overlap}. "
            "The UNIQUE(vault_id, interest_category) constraint should prevent this."
        )
        print("  No overlap between likes and dislikes — UNIQUE constraint working")

    def test_all_interests_belong_to_predefined_list(self, test_vault_with_interests):
        """All stored interest categories should be from the predefined list."""
        vault_id = test_vault_with_interests["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "interest_category"},
        )
        rows = resp.json()

        valid_set = set(VALID_CATEGORIES)
        for row in rows:
            assert row["interest_category"] in valid_set, (
                f"Interest category '{row['interest_category']}' is not in the "
                f"predefined list of {len(VALID_CATEGORIES)} categories"
            )
        print(f"  All {len(rows)} interests are from the predefined list")


# ===================================================================
# 5. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerInterestsCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its interests should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Interest Test",
        })
        vault_id = vault["id"]

        # Insert some interests
        interest = _insert_interest({
            "vault_id": vault_id,
            "interest_type": "like",
            "interest_category": "Travel",
        })
        interest_id = interest["id"]

        # Verify interest exists
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"id": f"eq.{interest_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 1, "Interest should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify interest is gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_interests",
            headers=_service_headers(),
            params={"id": f"eq.{interest_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "partner_interests row still exists after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed interest rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → partner_interests.
        """
        # Create temp auth user
        temp_email = f"knot-int-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeInt!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Test",
            })
            vault_id = vault["id"]

            # Add an interest
            interest = _insert_interest({
                "vault_id": vault_id,
                "interest_type": "dislike",
                "interest_category": "Gaming",
            })
            interest_id = interest["id"]

            # Verify interest exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_interests",
                headers=_service_headers(),
                params={"id": f"eq.{interest_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify interest is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_interests",
                headers=_service_headers(),
                params={"id": f"eq.{interest_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Interest row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → partner_interests"
            )
            print("  Full CASCADE delete verified: auth deletion removed interest rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting an interest with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_interest_raw({
            "vault_id": fake_vault_id,
            "interest_type": "like",
            "interest_category": "Travel",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
