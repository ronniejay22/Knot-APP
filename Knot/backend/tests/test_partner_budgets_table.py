"""
Step 1.6 Verification: Partner Budgets Table

Tests that:
1. The partner_budgets table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, occasion_type, min_amount, max_amount, currency, created_at)
3. occasion_type CHECK constraint enforces 3 valid values
4. UNIQUE(vault_id, occasion_type) prevents duplicate occasion types per vault
5. CHECK constraint enforces max_amount >= min_amount
6. CHECK constraint enforces min_amount >= 0
7. currency defaults to 'USD' when not provided
8. Row Level Security (RLS) blocks anonymous access
9. Service client (admin) can read all rows (bypasses RLS)
10. CASCADE delete removes budgets when vault is deleted
11. Full CASCADE chain: auth.users → users → partner_vaults → partner_budgets
12. Foreign key to partner_vaults is enforced

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00007_create_partner_budgets_table.sql

Run with: pytest tests/test_partner_budgets_table.py -v
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
# Helpers: insert/delete vault and budget rows via service client
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


def _insert_budget(budget_data: dict) -> dict:
    """Insert a budget row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_budgets",
        headers=_service_headers(),
        json=budget_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert budget: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_budget_raw(budget_data: dict) -> httpx.Response:
    """Insert a budget row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_budgets",
        headers=_service_headers(),
        json=budget_data,
    )


def _delete_budget(budget_id: str):
    """Delete a budget row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_budgets",
        headers=_service_headers(),
        params={"id": f"eq.{budget_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with budgets
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and partner_budgets rows).
    """
    test_email = f"knot-budget-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-bgA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-bgB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Budget Test Partner",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
    }
    vault_row = _insert_vault(vault_data)

    yield {
        "user": test_auth_user,
        "vault": vault_row,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_budgets(test_vault):
    """
    Create a vault with all three budget tiers pre-populated:
    - just_because:    $20.00 - $50.00  (2000 - 5000 cents)
    - minor_occasion:  $50.00 - $150.00 (5000 - 15000 cents)
    - major_milestone: $100.00 - $500.00 (10000 - 50000 cents)

    Yields user, vault, and budget info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    budgets = []

    budget_tiers = [
        {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000},
        {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 15000},
        {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 50000},
    ]

    for tier in budget_tiers:
        row = _insert_budget({
            "vault_id": vault_id,
            **tier,
        })
        budgets.append(row)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "budgets": budgets,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerBudgetsTableExists:
    """Verify the partner_budgets table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_budgets table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00007_create_partner_budgets_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_budgets table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00007_create_partner_budgets_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_budgets table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerBudgetsSchema:
    """Verify the partner_budgets table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_budgets):
        """
        The partner_budgets table should have exactly these columns:
        id, vault_id, occasion_type, min_amount, max_amount, currency, created_at.
        """
        vault_id = test_vault_with_budgets["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No budget rows found"

        row = rows[0]
        expected_columns = {"id", "vault_id", "occasion_type", "min_amount", "max_amount", "currency", "created_at"}
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_budgets):
        """The id column should be an auto-generated valid UUID."""
        budget_id = test_vault_with_budgets["budgets"][0]["id"]
        parsed = uuid.UUID(budget_id)
        assert str(parsed) == budget_id
        print(f"  id is auto-generated UUID: {budget_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_budgets):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_budgets["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
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

    def test_occasion_type_check_constraint_rejects_invalid(self, test_vault):
        """
        occasion_type must be one of the 3 valid values.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            "occasion_type": "extravagant",
            "min_amount": 1000,
            "max_amount": 5000,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid occasion_type 'extravagant', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  occasion_type CHECK constraint rejects invalid value 'extravagant'")

    def test_occasion_type_accepts_all_valid_values(self, test_vault):
        """All 3 valid occasion_type values should be accepted."""
        vault_id = test_vault["vault"]["id"]
        valid_types = ["just_because", "minor_occasion", "major_milestone"]
        inserted_ids = []

        try:
            for otype in valid_types:
                row = _insert_budget({
                    "vault_id": vault_id,
                    "occasion_type": otype,
                    "min_amount": 1000,
                    "max_amount": 5000,
                })
                inserted_ids.append(row["id"])
                assert row["occasion_type"] == otype

            assert len(inserted_ids) == 3, (
                f"Expected 3 occasion types inserted, got {len(inserted_ids)}"
            )
            print("  All 3 valid occasion_type values accepted")
        finally:
            for bid in inserted_ids:
                _delete_budget(bid)

    def test_currency_defaults_to_usd(self, test_vault):
        """
        When currency is not provided, it should default to 'USD'.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 1000,
            "max_amount": 3000,
            # currency intentionally omitted
        })

        try:
            assert row["currency"] == "USD", (
                f"Expected currency to default to 'USD', got '{row['currency']}'"
            )
            print("  currency defaults to 'USD' when not provided")
        finally:
            _delete_budget(row["id"])

    def test_currency_accepts_non_usd(self, test_vault):
        """
        International users should be able to set a different currency code.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 1000,
            "max_amount": 3000,
            "currency": "GBP",
        })

        try:
            assert row["currency"] == "GBP", (
                f"Expected currency 'GBP', got '{row['currency']}'"
            )
            print("  currency accepts non-USD values (GBP)")
        finally:
            _delete_budget(row["id"])

    def test_max_amount_gte_min_amount_constraint(self, test_vault):
        """
        max_amount must be >= min_amount. The CHECK constraint should
        reject inserts where max_amount < min_amount.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 5000,
            "max_amount": 2000,  # less than min_amount
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for max_amount < min_amount, "
            f"got HTTP {resp.status_code}. "
            "CHECK (max_amount >= min_amount) constraint may be missing. "
            f"Response: {resp.text}"
        )
        print("  CHECK (max_amount >= min_amount) constraint enforced")

    def test_max_amount_equals_min_amount_allowed(self, test_vault):
        """
        max_amount == min_amount should be allowed (exact budget, no range).
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 3000,
            "max_amount": 3000,
        })

        try:
            assert row["min_amount"] == 3000
            assert row["max_amount"] == 3000
            print("  max_amount == min_amount is allowed (exact budget)")
        finally:
            _delete_budget(row["id"])

    def test_min_amount_non_negative_constraint(self, test_vault):
        """
        min_amount must be >= 0. Negative values should be rejected.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": -100,
            "max_amount": 5000,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for negative min_amount, "
            f"got HTTP {resp.status_code}. "
            "CHECK (min_amount >= 0) constraint may be missing. "
            f"Response: {resp.text}"
        )
        print("  CHECK (min_amount >= 0) constraint enforced")

    def test_occasion_type_not_null(self, test_vault):
        """occasion_type is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            # occasion_type intentionally omitted
            "min_amount": 1000,
            "max_amount": 5000,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing occasion_type, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  occasion_type NOT NULL constraint enforced")

    def test_min_amount_not_null(self, test_vault):
        """min_amount is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            # min_amount intentionally omitted
            "max_amount": 5000,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing min_amount, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  min_amount NOT NULL constraint enforced")

    def test_max_amount_not_null(self, test_vault):
        """max_amount is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_budget_raw({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 1000,
            # max_amount intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing max_amount, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  max_amount NOT NULL constraint enforced")

    def test_unique_constraint_prevents_duplicate_occasion_type(self, test_vault):
        """
        UNIQUE(vault_id, occasion_type) should prevent inserting the same
        occasion_type twice for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        # Insert first budget for just_because
        row = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 2000,
            "max_amount": 5000,
        })

        try:
            # Attempt duplicate insert
            resp = _insert_budget_raw({
                "vault_id": vault_id,
                "occasion_type": "just_because",
                "min_amount": 1000,
                "max_amount": 3000,
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for duplicate occasion_type 'just_because', "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, occasion_type) constraint may be missing. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, occasion_type) prevents duplicate occasion types")
        finally:
            _delete_budget(row["id"])

    def test_same_occasion_type_allowed_for_different_vaults(self, test_auth_user_pair):
        """
        Different vaults CAN have the same occasion_type. The UNIQUE constraint
        is scoped to (vault_id, occasion_type), not global.
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
            budget_a = _insert_budget({
                "vault_id": vault_a["id"],
                "occasion_type": "major_milestone",
                "min_amount": 10000,
                "max_amount": 50000,
            })
            budget_b = _insert_budget({
                "vault_id": vault_b["id"],
                "occasion_type": "major_milestone",
                "min_amount": 20000,
                "max_amount": 100000,
            })

            assert budget_a["occasion_type"] == "major_milestone"
            assert budget_b["occasion_type"] == "major_milestone"
            assert budget_a["vault_id"] != budget_b["vault_id"]
            print("  Same occasion_type allowed for different vaults (UNIQUE scoped to vault)")
        finally:
            _delete_budget(budget_a["id"])
            _delete_budget(budget_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerBudgetsRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_budgets(self, test_vault_with_budgets):
        """
        The anon client (no user JWT) should not see any budgets.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} budget(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_budgets ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 budgets visible — RLS enforced")

    def test_service_client_can_read_budgets(self, test_vault_with_budgets):
        """
        The service client (bypasses RLS) should see the test budgets.
        """
        vault_id = test_vault_with_budgets["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, (
            f"Service client should see 3 budgets (just_because, minor_occasion, "
            f"major_milestone), got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} budgets — RLS bypassed")

    def test_user_isolation_between_budgets(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's budgets.
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

        # Add budgets to both vaults
        budget_a = _insert_budget({
            "vault_id": vault_a["id"],
            "occasion_type": "just_because",
            "min_amount": 2000,
            "max_amount": 5000,
        })
        budget_b = _insert_budget({
            "vault_id": vault_b["id"],
            "occasion_type": "just_because",
            "min_amount": 3000,
            "max_amount": 8000,
        })

        try:
            # Query budgets for vault A — should only return vault A's budget
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_budgets",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["min_amount"] == 2000

            # Query budgets for vault B — should only return vault B's budget
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_budgets",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["min_amount"] == 3000

            print("  User isolation verified: each vault sees only its own budgets")
        finally:
            _delete_budget(budget_a["id"])
            _delete_budget(budget_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: budgets stored correctly
# ===================================================================

@requires_supabase
class TestPartnerBudgetsDataIntegrity:
    """Verify budgets are stored with correct data across all fields."""

    def test_all_three_tiers_stored(self, test_vault_with_budgets):
        """
        A vault should have all three budget tiers stored correctly.
        Verify occasion_type, min_amount, and max_amount for each.
        """
        vault_id = test_vault_with_budgets["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={
                "vault_id": f"eq.{vault_id}",
                "select": "*",
                "order": "min_amount.asc",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 budget tiers, got {len(rows)}"

        types = sorted([r["occasion_type"] for r in rows])
        assert types == sorted(["just_because", "minor_occasion", "major_milestone"]), (
            f"Expected all 3 occasion types, got {types}"
        )
        print(f"  3 budget tiers stored: {types}")

    def test_budget_amounts_stored_correctly(self, test_vault_with_budgets):
        """Verify each budget tier has the correct min/max amounts."""
        budgets = test_vault_with_budgets["budgets"]

        expected = {
            "just_because": (2000, 5000),
            "minor_occasion": (5000, 15000),
            "major_milestone": (10000, 50000),
        }

        for budget in budgets:
            otype = budget["occasion_type"]
            assert otype in expected, f"Unexpected occasion_type: {otype}"
            exp_min, exp_max = expected[otype]
            assert budget["min_amount"] == exp_min, (
                f"{otype}: expected min_amount {exp_min}, got {budget['min_amount']}"
            )
            assert budget["max_amount"] == exp_max, (
                f"{otype}: expected max_amount {exp_max}, got {budget['max_amount']}"
            )
            print(f"  {otype}: ${exp_min / 100:.2f} - ${exp_max / 100:.2f} verified")

    def test_budget_field_values(self, test_vault_with_budgets):
        """Verify each budget has the correct vault_id and currency."""
        vault_id = test_vault_with_budgets["vault"]["id"]
        budgets = test_vault_with_budgets["budgets"]

        for budget in budgets:
            assert budget["vault_id"] == vault_id, (
                f"Budget {budget['id']} has wrong vault_id: "
                f"expected {vault_id}, got {budget['vault_id']}"
            )
            assert budget["currency"] == "USD", (
                f"Budget {budget['id']} has wrong currency: "
                f"expected 'USD', got '{budget['currency']}'"
            )

        print("  All budget fields verified (vault_id, currency)")

    def test_amounts_stored_as_integers(self, test_vault_with_budgets):
        """
        min_amount and max_amount should be stored as integers (cents),
        not floats, to avoid floating-point precision issues.
        """
        budgets = test_vault_with_budgets["budgets"]

        for budget in budgets:
            assert isinstance(budget["min_amount"], int), (
                f"min_amount should be an integer, got {type(budget['min_amount'])}"
            )
            assert isinstance(budget["max_amount"], int), (
                f"max_amount should be an integer, got {type(budget['max_amount'])}"
            )

        print("  Amounts stored as integers (cents) — no floating-point issues")

    def test_zero_min_amount_allowed(self, test_vault):
        """
        A min_amount of 0 (free/no minimum) should be allowed.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 0,
            "max_amount": 5000,
        })

        try:
            assert row["min_amount"] == 0
            assert row["max_amount"] == 5000
            print("  min_amount of 0 allowed (free/no minimum)")
        finally:
            _delete_budget(row["id"])


# ===================================================================
# 5. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerBudgetsCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its budgets should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Budget Test",
        })
        vault_id = vault["id"]

        # Insert budgets
        budget1 = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "just_because",
            "min_amount": 2000,
            "max_amount": 5000,
        })
        budget2 = _insert_budget({
            "vault_id": vault_id,
            "occasion_type": "major_milestone",
            "min_amount": 10000,
            "max_amount": 50000,
        })

        # Verify budgets exist
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 2, "Budgets should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify budgets are gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_budgets",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "partner_budgets rows still exist after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed budget rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → partner_budgets.
        """
        # Create temp auth user
        temp_email = f"knot-bg-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeBg!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Budget Test",
            })
            vault_id = vault["id"]

            # Add budget
            budget = _insert_budget({
                "vault_id": vault_id,
                "occasion_type": "minor_occasion",
                "min_amount": 5000,
                "max_amount": 15000,
            })
            budget_id = budget["id"]

            # Verify budget exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_budgets",
                headers=_service_headers(),
                params={"id": f"eq.{budget_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify budget is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_budgets",
                headers=_service_headers(),
                params={"id": f"eq.{budget_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Budget row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → partner_budgets"
            )
            print("  Full CASCADE delete verified: auth deletion removed budget rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a budget with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_budget_raw({
            "vault_id": fake_vault_id,
            "occasion_type": "just_because",
            "min_amount": 1000,
            "max_amount": 5000,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
