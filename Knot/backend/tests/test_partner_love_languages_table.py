"""
Step 1.7 Verification: Partner Love Languages Table

Tests that:
1. The partner_love_languages table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, language, priority, created_at)
3. language CHECK constraint enforces 5 valid values
4. priority CHECK constraint enforces values 1 and 2 only
5. UNIQUE(vault_id, priority) prevents duplicate priorities per vault
6. UNIQUE(vault_id, language) prevents same language as both primary and secondary
7. Row Level Security (RLS) blocks anonymous access
8. Service client (admin) can read all rows (bypasses RLS)
9. CASCADE delete removes love languages when vault is deleted
10. Full CASCADE chain: auth.users → users → partner_vaults → partner_love_languages
11. Foreign key to partner_vaults is enforced
12. Update primary to a different language succeeds

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00008_create_partner_love_languages_table.sql

Run with: pytest tests/test_partner_love_languages_table.py -v
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
# Helpers: insert/delete vault and love language rows via service client
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


def _insert_love_language(ll_data: dict) -> dict:
    """Insert a love language row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_love_languages",
        headers=_service_headers(),
        json=ll_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert love language: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_love_language_raw(ll_data: dict) -> httpx.Response:
    """Insert a love language row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_love_languages",
        headers=_service_headers(),
        json=ll_data,
    )


def _delete_love_language(ll_id: str):
    """Delete a love language row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_love_languages",
        headers=_service_headers(),
        params={"id": f"eq.{ll_id}"},
    )


def _update_love_language(ll_id: str, updates: dict) -> httpx.Response:
    """Update a love language row via service client. Returns raw response."""
    return httpx.patch(
        f"{SUPABASE_URL}/rest/v1/partner_love_languages",
        headers=_service_headers(),
        params={"id": f"eq.{ll_id}"},
        json=updates,
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with love languages
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and partner_love_languages rows).
    """
    test_email = f"knot-ll-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-llA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-llB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Love Language Test Partner",
        "relationship_tenure_months": 18,
        "cohabitation_status": "living_together",
        "location_city": "Portland",
        "location_state": "OR",
        "location_country": "US",
    }
    vault_row = _insert_vault(vault_data)

    yield {
        "user": test_auth_user,
        "vault": vault_row,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_love_languages(test_vault):
    """
    Create a vault with primary and secondary love languages pre-populated:
    - Primary (priority=1): quality_time
    - Secondary (priority=2): receiving_gifts

    Yields user, vault, and love language info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    love_languages = []

    ll_entries = [
        {"language": "quality_time", "priority": 1},
        {"language": "receiving_gifts", "priority": 2},
    ]

    for entry in ll_entries:
        row = _insert_love_language({
            "vault_id": vault_id,
            **entry,
        })
        love_languages.append(row)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "love_languages": love_languages,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerLoveLanguagesTableExists:
    """Verify the partner_love_languages table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_love_languages table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00008_create_partner_love_languages_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_love_languages table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00008_create_partner_love_languages_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_love_languages table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerLoveLanguagesSchema:
    """Verify the partner_love_languages table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_love_languages):
        """
        The partner_love_languages table should have exactly these columns:
        id, vault_id, language, priority, created_at.
        """
        vault_id = test_vault_with_love_languages["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No love language rows found"

        row = rows[0]
        expected_columns = {"id", "vault_id", "language", "priority", "created_at"}
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_love_languages):
        """The id column should be an auto-generated valid UUID."""
        ll_id = test_vault_with_love_languages["love_languages"][0]["id"]
        parsed = uuid.UUID(ll_id)
        assert str(parsed) == ll_id
        print(f"  id is auto-generated UUID: {ll_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_love_languages):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_love_languages["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
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

    def test_language_check_constraint_rejects_invalid(self, test_vault):
        """
        language must be one of the 5 valid values.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_love_language_raw({
            "vault_id": vault_id,
            "language": "gift_giving",
            "priority": 1,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid language 'gift_giving', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  language CHECK constraint rejects invalid value 'gift_giving'")

    def test_language_accepts_all_valid_values(self, test_vault):
        """All 5 valid language values should be accepted."""
        vault_id = test_vault["vault"]["id"]
        valid_languages = [
            "words_of_affirmation",
            "acts_of_service",
            "receiving_gifts",
            "quality_time",
            "physical_touch",
        ]
        inserted_ids = []

        try:
            # Insert each as primary with different priorities is not possible
            # (only 2 priorities allowed), so we test validity by inserting
            # each language one at a time, verifying, then deleting.
            for lang in valid_languages:
                row = _insert_love_language({
                    "vault_id": vault_id,
                    "language": lang,
                    "priority": 1,
                })
                inserted_ids.append(row["id"])
                assert row["language"] == lang
                # Clean up immediately to free priority=1 for next language
                _delete_love_language(row["id"])
                inserted_ids.pop()

            print("  All 5 valid language values accepted")
        finally:
            for ll_id in inserted_ids:
                _delete_love_language(ll_id)

    def test_priority_check_constraint_rejects_invalid(self, test_vault):
        """
        priority must be 1 (primary) or 2 (secondary).
        Values outside this range should be rejected.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_love_language_raw({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 3,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid priority 3, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  priority CHECK constraint rejects invalid value 3")

    def test_priority_accepts_both_valid_values(self, test_vault):
        """Both valid priority values (1 and 2) should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row1 = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        row2 = _insert_love_language({
            "vault_id": vault_id,
            "language": "acts_of_service",
            "priority": 2,
        })

        try:
            assert row1["priority"] == 1
            assert row2["priority"] == 2
            print("  Both priority values (1=primary, 2=secondary) accepted")
        finally:
            _delete_love_language(row1["id"])
            _delete_love_language(row2["id"])

    def test_priority_zero_rejected(self, test_vault):
        """priority=0 should be rejected by the CHECK constraint."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_love_language_raw({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 0,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid priority 0, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  priority CHECK constraint rejects value 0")

    def test_language_not_null(self, test_vault):
        """language is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_love_language_raw({
            "vault_id": vault_id,
            # language intentionally omitted
            "priority": 1,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing language, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  language NOT NULL constraint enforced")

    def test_priority_not_null(self, test_vault):
        """priority is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_love_language_raw({
            "vault_id": vault_id,
            "language": "quality_time",
            # priority intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing priority, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  priority NOT NULL constraint enforced")

    def test_unique_priority_prevents_duplicate_primary(self, test_vault):
        """
        UNIQUE(vault_id, priority) should prevent inserting two primary (priority=1)
        love languages for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })

        try:
            resp = _insert_love_language_raw({
                "vault_id": vault_id,
                "language": "acts_of_service",
                "priority": 1,  # duplicate priority
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for duplicate priority 1, "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, priority) constraint may be missing. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, priority) prevents duplicate primary love language")
        finally:
            _delete_love_language(row["id"])

    def test_unique_priority_prevents_duplicate_secondary(self, test_vault):
        """
        UNIQUE(vault_id, priority) should prevent inserting two secondary (priority=2)
        love languages for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 2,
        })

        try:
            resp = _insert_love_language_raw({
                "vault_id": vault_id,
                "language": "acts_of_service",
                "priority": 2,  # duplicate priority
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for duplicate priority 2, "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, priority) constraint may be missing. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, priority) prevents duplicate secondary love language")
        finally:
            _delete_love_language(row["id"])

    def test_unique_language_prevents_same_language_both_priorities(self, test_vault):
        """
        UNIQUE(vault_id, language) should prevent the same language from being
        both primary and secondary for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })

        try:
            resp = _insert_love_language_raw({
                "vault_id": vault_id,
                "language": "quality_time",  # same language
                "priority": 2,  # different priority
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for same language 'quality_time' at both priorities, "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, language) constraint may be missing. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, language) prevents same language as both primary and secondary")
        finally:
            _delete_love_language(row["id"])

    def test_same_language_allowed_for_different_vaults(self, test_auth_user_pair):
        """
        Different vaults CAN have the same language. The UNIQUE constraints
        are scoped to (vault_id, ...), not global.
        """
        user_a, user_b = test_auth_user_pair

        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "User A's Partner",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "User B's Partner",
        })

        try:
            ll_a = _insert_love_language({
                "vault_id": vault_a["id"],
                "language": "quality_time",
                "priority": 1,
            })
            ll_b = _insert_love_language({
                "vault_id": vault_b["id"],
                "language": "quality_time",
                "priority": 1,
            })

            assert ll_a["language"] == "quality_time"
            assert ll_b["language"] == "quality_time"
            assert ll_a["vault_id"] != ll_b["vault_id"]
            print("  Same language allowed for different vaults (UNIQUE scoped to vault)")
        finally:
            _delete_love_language(ll_a["id"])
            _delete_love_language(ll_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])

    def test_third_love_language_rejected(self, test_vault):
        """
        A vault should have at most 2 love languages (priority 1 and 2).
        Attempting to insert a third should fail because all valid
        priorities are taken (UNIQUE constraint on priority) and
        no valid priority value remains.
        """
        vault_id = test_vault["vault"]["id"]

        row1 = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        row2 = _insert_love_language({
            "vault_id": vault_id,
            "language": "receiving_gifts",
            "priority": 2,
        })

        try:
            # Attempt a third insert with priority 1 — blocked by UNIQUE(vault_id, priority)
            resp_dup_priority = _insert_love_language_raw({
                "vault_id": vault_id,
                "language": "physical_touch",
                "priority": 1,
            })
            assert resp_dup_priority.status_code in (400, 409), (
                f"Expected 400/409 for third love language (duplicate priority), "
                f"got HTTP {resp_dup_priority.status_code}. Response: {resp_dup_priority.text}"
            )

            # Attempt a third insert with priority 3 — blocked by CHECK(priority IN (1,2))
            resp_bad_priority = _insert_love_language_raw({
                "vault_id": vault_id,
                "language": "physical_touch",
                "priority": 3,
            })
            assert resp_bad_priority.status_code in (400, 409), (
                f"Expected 400/409 for third love language (invalid priority 3), "
                f"got HTTP {resp_bad_priority.status_code}. Response: {resp_bad_priority.text}"
            )

            print("  Third love language correctly rejected (no valid priority slot available)")
        finally:
            _delete_love_language(row1["id"])
            _delete_love_language(row2["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerLoveLanguagesRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_love_languages(self, test_vault_with_love_languages):
        """
        The anon client (no user JWT) should not see any love languages.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} love language(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_love_languages ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 love languages visible — RLS enforced")

    def test_service_client_can_read_love_languages(self, test_vault_with_love_languages):
        """
        The service client (bypasses RLS) should see the test love languages.
        """
        vault_id = test_vault_with_love_languages["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 2, (
            f"Service client should see 2 love languages (primary + secondary), "
            f"got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} love languages — RLS bypassed")

    def test_user_isolation_between_love_languages(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's love languages.
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

        # Add love languages to both vaults
        ll_a = _insert_love_language({
            "vault_id": vault_a["id"],
            "language": "quality_time",
            "priority": 1,
        })
        ll_b = _insert_love_language({
            "vault_id": vault_b["id"],
            "language": "acts_of_service",
            "priority": 1,
        })

        try:
            # Query love languages for vault A — should only return vault A's data
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_love_languages",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["language"] == "quality_time"

            # Query love languages for vault B — should only return vault B's data
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_love_languages",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["language"] == "acts_of_service"

            print("  User isolation verified: each vault sees only its own love languages")
        finally:
            _delete_love_language(ll_a["id"])
            _delete_love_language(ll_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: love languages stored correctly
# ===================================================================

@requires_supabase
class TestPartnerLoveLanguagesDataIntegrity:
    """Verify love languages are stored with correct data across all fields."""

    def test_primary_and_secondary_stored(self, test_vault_with_love_languages):
        """
        A vault should have exactly one primary and one secondary love language.
        """
        vault_id = test_vault_with_love_languages["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={
                "vault_id": f"eq.{vault_id}",
                "select": "*",
                "order": "priority.asc",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 2, f"Expected 2 love languages, got {len(rows)}"

        priorities = [r["priority"] for r in rows]
        assert sorted(priorities) == [1, 2], (
            f"Expected priorities [1, 2], got {sorted(priorities)}"
        )
        print("  Primary (1) and secondary (2) love languages stored correctly")

    def test_love_language_field_values(self, test_vault_with_love_languages):
        """Verify each love language has the correct vault_id and language."""
        vault_id = test_vault_with_love_languages["vault"]["id"]
        love_languages = test_vault_with_love_languages["love_languages"]

        for ll in love_languages:
            assert ll["vault_id"] == vault_id, (
                f"Love language {ll['id']} has wrong vault_id: "
                f"expected {vault_id}, got {ll['vault_id']}"
            )

        languages = {ll["language"] for ll in love_languages}
        assert languages == {"quality_time", "receiving_gifts"}, (
            f"Expected languages {{quality_time, receiving_gifts}}, got {languages}"
        )
        print("  Love language field values verified (vault_id, language)")

    def test_primary_language_correct(self, test_vault_with_love_languages):
        """The primary love language should be 'quality_time' (as set by fixture)."""
        love_languages = test_vault_with_love_languages["love_languages"]
        primary = [ll for ll in love_languages if ll["priority"] == 1]
        assert len(primary) == 1
        assert primary[0]["language"] == "quality_time"
        print("  Primary love language is 'quality_time' (priority=1)")

    def test_secondary_language_correct(self, test_vault_with_love_languages):
        """The secondary love language should be 'receiving_gifts' (as set by fixture)."""
        love_languages = test_vault_with_love_languages["love_languages"]
        secondary = [ll for ll in love_languages if ll["priority"] == 2]
        assert len(secondary) == 1
        assert secondary[0]["language"] == "receiving_gifts"
        print("  Secondary love language is 'receiving_gifts' (priority=2)")

    def test_update_primary_language_succeeds(self, test_vault):
        """
        Updating the primary love language to a different one should succeed.
        This is the primary test case from Step 1.7:
        "Update primary to a different language and confirm success."
        """
        vault_id = test_vault["vault"]["id"]

        # Insert primary and secondary
        row1 = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        row2 = _insert_love_language({
            "vault_id": vault_id,
            "language": "receiving_gifts",
            "priority": 2,
        })

        try:
            # Update primary from quality_time to physical_touch
            resp = _update_love_language(row1["id"], {
                "language": "physical_touch",
            })
            assert resp.status_code == 200, (
                f"Failed to update primary love language: "
                f"HTTP {resp.status_code} — {resp.text}"
            )
            updated_rows = resp.json()
            assert len(updated_rows) == 1
            assert updated_rows[0]["language"] == "physical_touch"
            assert updated_rows[0]["priority"] == 1

            # Verify the update persisted
            check = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_love_languages",
                headers=_service_headers(),
                params={
                    "vault_id": f"eq.{vault_id}",
                    "priority": "eq.1",
                    "select": "*",
                },
            )
            assert check.status_code == 200
            rows = check.json()
            assert len(rows) == 1
            assert rows[0]["language"] == "physical_touch"
            print("  Primary love language updated from 'quality_time' to 'physical_touch'")
        finally:
            _delete_love_language(row1["id"])
            _delete_love_language(row2["id"])

    def test_update_to_same_language_as_other_priority_fails(self, test_vault):
        """
        Updating primary to the same language as secondary should fail
        because of UNIQUE(vault_id, language).
        """
        vault_id = test_vault["vault"]["id"]

        row1 = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        row2 = _insert_love_language({
            "vault_id": vault_id,
            "language": "receiving_gifts",
            "priority": 2,
        })

        try:
            # Try to update primary to match secondary's language
            resp = _update_love_language(row1["id"], {
                "language": "receiving_gifts",
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 when updating primary to same language as secondary, "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, language) should prevent this. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, language) prevents updating primary to same as secondary")
        finally:
            _delete_love_language(row1["id"])
            _delete_love_language(row2["id"])


# ===================================================================
# 5. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerLoveLanguagesCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its love languages should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade LL Test",
        })
        vault_id = vault["id"]

        # Insert love languages
        ll1 = _insert_love_language({
            "vault_id": vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        ll2 = _insert_love_language({
            "vault_id": vault_id,
            "language": "physical_touch",
            "priority": 2,
        })

        # Verify love languages exist
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 2, "Love languages should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify love languages are gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_love_languages",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "partner_love_languages rows still exist after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed love language rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → partner_love_languages.
        """
        # Create temp auth user
        temp_email = f"knot-ll-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeLL!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade LL Test",
            })
            vault_id = vault["id"]

            # Add love languages
            ll = _insert_love_language({
                "vault_id": vault_id,
                "language": "words_of_affirmation",
                "priority": 1,
            })
            ll_id = ll["id"]

            # Verify love language exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_love_languages",
                headers=_service_headers(),
                params={"id": f"eq.{ll_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify love language is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_love_languages",
                headers=_service_headers(),
                params={"id": f"eq.{ll_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Love language row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → partner_love_languages"
            )
            print("  Full CASCADE delete verified: auth deletion removed love language rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a love language with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_love_language_raw({
            "vault_id": fake_vault_id,
            "language": "quality_time",
            "priority": 1,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
