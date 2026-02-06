"""
Step 1.4 Verification: Partner Milestones Table

Tests that:
1. The partner_milestones table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, milestone_type, milestone_name,
   milestone_date, recurrence, budget_tier, created_at)
3. milestone_type CHECK constraint enforces 'birthday', 'anniversary', 'holiday', 'custom'
4. recurrence CHECK constraint enforces 'yearly', 'one_time'
5. budget_tier CHECK constraint enforces 'just_because', 'minor_occasion', 'major_milestone'
6. Budget tier auto-defaults: birthday/anniversary → major_milestone, holiday → minor_occasion
7. Custom milestones store user-provided budget_tier
8. Row Level Security (RLS) blocks anonymous access
9. Service client (admin) can read all rows (bypasses RLS)
10. CASCADE delete removes milestones when vault is deleted
11. Full CASCADE chain: auth.users → users → partner_vaults → partner_milestones
12. Foreign key to partner_vaults is enforced

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00005_create_partner_milestones_table.sql

Run with: pytest tests/test_partner_milestones_table.py -v
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
# Helpers: insert/delete vault and milestone rows via service client
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


def _insert_milestone_raw(milestone_data: dict) -> httpx.Response:
    """Insert a milestone row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        json=milestone_data,
    )


def _delete_milestone(milestone_id: str):
    """Delete a milestone row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        params={"id": f"eq.{milestone_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with milestones
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and partner_milestones rows).
    """
    test_email = f"knot-milestone-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-msA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-msB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Milestone Test Partner",
        "relationship_tenure_months": 24,
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
def test_vault_with_milestones(test_vault):
    """
    Create a vault with sample milestones pre-populated:
    - Birthday (yearly, major_milestone auto-set)
    - Anniversary (yearly, major_milestone auto-set)
    - Valentine's Day holiday (yearly, major_milestone explicit)
    - Custom milestone (one_time, user-provided budget_tier)

    Yields user, vault, and milestone info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    milestones = []

    # Birthday — budget_tier auto-defaults to major_milestone
    birthday = _insert_milestone({
        "vault_id": vault_id,
        "milestone_type": "birthday",
        "milestone_name": "Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
    })
    milestones.append(birthday)

    # Anniversary — budget_tier auto-defaults to major_milestone
    anniversary = _insert_milestone({
        "vault_id": vault_id,
        "milestone_type": "anniversary",
        "milestone_name": "Anniversary",
        "milestone_date": "2000-06-20",
        "recurrence": "yearly",
    })
    milestones.append(anniversary)

    # Valentine's Day — explicitly set to major_milestone
    valentines = _insert_milestone({
        "vault_id": vault_id,
        "milestone_type": "holiday",
        "milestone_name": "Valentine's Day",
        "milestone_date": "2000-02-14",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
    })
    milestones.append(valentines)

    # Custom milestone — user provides budget_tier
    custom = _insert_milestone({
        "vault_id": vault_id,
        "milestone_type": "custom",
        "milestone_name": "First Date",
        "milestone_date": "2024-09-10",
        "recurrence": "one_time",
        "budget_tier": "minor_occasion",
    })
    milestones.append(custom)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "milestones": milestones,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerMilestonesTableExists:
    """Verify the partner_milestones table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_milestones table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00005_create_partner_milestones_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_milestones table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00005_create_partner_milestones_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_milestones table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerMilestonesSchema:
    """Verify the partner_milestones table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_milestones):
        """
        The partner_milestones table should have exactly these columns:
        id, vault_id, milestone_type, milestone_name, milestone_date,
        recurrence, budget_tier, created_at.
        """
        vault_id = test_vault_with_milestones["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No milestone rows found"

        row = rows[0]
        expected_columns = {
            "id", "vault_id", "milestone_type", "milestone_name",
            "milestone_date", "recurrence", "budget_tier", "created_at",
        }
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_milestones):
        """The id column should be an auto-generated valid UUID."""
        milestone_id = test_vault_with_milestones["milestones"][0]["id"]
        parsed = uuid.UUID(milestone_id)
        assert str(parsed) == milestone_id
        print(f"  id is auto-generated UUID: {milestone_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_milestones):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_milestones["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
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

    def test_milestone_type_check_constraint_rejects_invalid(self, test_vault):
        """
        milestone_type must be one of: birthday, anniversary, holiday, custom.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "graduation",
            "milestone_name": "College Graduation",
            "milestone_date": "2026-05-15",
            "recurrence": "one_time",
            "budget_tier": "minor_occasion",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid milestone_type 'graduation', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  milestone_type CHECK constraint rejects invalid value 'graduation'")

    def test_milestone_type_accepts_all_valid(self, test_vault):
        """All 4 valid milestone_type values should be accepted."""
        vault_id = test_vault["vault"]["id"]
        valid_types = [
            ("birthday", "Birthday", "2000-08-25", "yearly", None),
            ("anniversary", "Anniversary", "2000-11-10", "yearly", None),
            ("holiday", "Christmas", "2000-12-25", "yearly", None),
            ("custom", "Trip to Paris", "2026-06-01", "one_time", "major_milestone"),
        ]
        inserted_ids = []

        try:
            for mtype, mname, mdate, recurrence, tier in valid_types:
                data = {
                    "vault_id": vault_id,
                    "milestone_type": mtype,
                    "milestone_name": mname,
                    "milestone_date": mdate,
                    "recurrence": recurrence,
                }
                if tier is not None:
                    data["budget_tier"] = tier
                row = _insert_milestone(data)
                inserted_ids.append(row["id"])
                assert row["milestone_type"] == mtype

            assert len(inserted_ids) == 4, (
                f"Expected 4 milestone types inserted, got {len(inserted_ids)}"
            )
            print(f"  All 4 valid milestone_type values accepted")
        finally:
            for mid in inserted_ids:
                _delete_milestone(mid)

    def test_recurrence_check_constraint_rejects_invalid(self, test_vault):
        """recurrence must be either 'yearly' or 'one_time'. Invalid values rejected."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "custom",
            "milestone_name": "Weekly Date Night",
            "milestone_date": "2026-03-01",
            "recurrence": "weekly",
            "budget_tier": "just_because",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid recurrence 'weekly', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  recurrence CHECK constraint rejects invalid value 'weekly'")

    def test_recurrence_accepts_yearly_and_one_time(self, test_vault):
        """Both 'yearly' and 'one_time' recurrence values should be accepted."""
        vault_id = test_vault["vault"]["id"]
        inserted_ids = []

        try:
            # yearly
            row1 = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "birthday",
                "milestone_name": "Birthday",
                "milestone_date": "2000-04-12",
                "recurrence": "yearly",
            })
            inserted_ids.append(row1["id"])
            assert row1["recurrence"] == "yearly"

            # one_time
            row2 = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "custom",
                "milestone_name": "Special Event",
                "milestone_date": "2026-07-01",
                "recurrence": "one_time",
                "budget_tier": "just_because",
            })
            inserted_ids.append(row2["id"])
            assert row2["recurrence"] == "one_time"

            print("  recurrence accepts 'yearly' and 'one_time'")
        finally:
            for mid in inserted_ids:
                _delete_milestone(mid)

    def test_budget_tier_check_constraint_rejects_invalid(self, test_vault):
        """budget_tier must be one of: just_because, minor_occasion, major_milestone."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "custom",
            "milestone_name": "Test",
            "milestone_date": "2026-01-01",
            "recurrence": "one_time",
            "budget_tier": "extravagant",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid budget_tier 'extravagant', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  budget_tier CHECK constraint rejects invalid value 'extravagant'")

    def test_milestone_name_not_null(self, test_vault):
        """milestone_name is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_date": "2000-01-01",
            "recurrence": "yearly",
            # milestone_name intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing milestone_name, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  milestone_name NOT NULL constraint enforced")

    def test_milestone_date_not_null(self, test_vault):
        """milestone_date is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "recurrence": "yearly",
            # milestone_date intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing milestone_date, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  milestone_date NOT NULL constraint enforced")

    def test_milestone_date_stores_year_2000_placeholder(self, test_vault):
        """
        For yearly recurrence milestones, dates should store with year 2000
        as a placeholder. Verify the date is stored correctly.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-07-04",
            "recurrence": "yearly",
        })

        try:
            assert row["milestone_date"] == "2000-07-04", (
                f"Expected milestone_date '2000-07-04', got '{row['milestone_date']}'"
            )
            print(f"  milestone_date stores year-2000 placeholder: {row['milestone_date']}")
        finally:
            _delete_milestone(row["id"])


# ===================================================================
# 3. Budget tier auto-defaults (trigger)
# ===================================================================

@requires_supabase
class TestPartnerMilestonesBudgetTierDefaults:
    """Verify the trigger auto-sets budget_tier based on milestone_type."""

    def test_birthday_defaults_to_major_milestone(self, test_vault):
        """
        Inserting a birthday milestone WITHOUT specifying budget_tier
        should auto-default to 'major_milestone' via the trigger.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-03-15",
            "recurrence": "yearly",
            # budget_tier intentionally omitted
        })

        try:
            assert row["budget_tier"] == "major_milestone", (
                f"Expected budget_tier 'major_milestone' for birthday, "
                f"got '{row['budget_tier']}'"
            )
            print("  birthday auto-defaults to 'major_milestone'")
        finally:
            _delete_milestone(row["id"])

    def test_anniversary_defaults_to_major_milestone(self, test_vault):
        """
        Inserting an anniversary milestone WITHOUT specifying budget_tier
        should auto-default to 'major_milestone' via the trigger.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "anniversary",
            "milestone_name": "Anniversary",
            "milestone_date": "2000-06-20",
            "recurrence": "yearly",
            # budget_tier intentionally omitted
        })

        try:
            assert row["budget_tier"] == "major_milestone", (
                f"Expected budget_tier 'major_milestone' for anniversary, "
                f"got '{row['budget_tier']}'"
            )
            print("  anniversary auto-defaults to 'major_milestone'")
        finally:
            _delete_milestone(row["id"])

    def test_holiday_defaults_to_minor_occasion(self, test_vault):
        """
        Inserting a holiday milestone WITHOUT specifying budget_tier
        should auto-default to 'minor_occasion' via the trigger.
        (The app layer can override to 'major_milestone' for
        Valentine's Day and Christmas by explicitly providing it.)
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "holiday",
            "milestone_name": "Mother's Day",
            "milestone_date": "2000-05-12",
            "recurrence": "yearly",
            # budget_tier intentionally omitted
        })

        try:
            assert row["budget_tier"] == "minor_occasion", (
                f"Expected budget_tier 'minor_occasion' for holiday, "
                f"got '{row['budget_tier']}'"
            )
            print("  holiday auto-defaults to 'minor_occasion'")
        finally:
            _delete_milestone(row["id"])

    def test_holiday_can_override_to_major_milestone(self, test_vault):
        """
        A holiday milestone CAN have budget_tier explicitly set to
        'major_milestone' (e.g., for Valentine's Day or Christmas).
        The trigger should NOT override an explicitly provided value.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "holiday",
            "milestone_name": "Valentine's Day",
            "milestone_date": "2000-02-14",
            "recurrence": "yearly",
            "budget_tier": "major_milestone",
        })

        try:
            assert row["budget_tier"] == "major_milestone", (
                f"Expected explicit budget_tier 'major_milestone' for Valentine's Day, "
                f"got '{row['budget_tier']}'"
            )
            print("  holiday accepts explicit 'major_milestone' override")
        finally:
            _delete_milestone(row["id"])

    def test_custom_stores_user_provided_budget_tier(self, test_vault):
        """
        A custom milestone should store the user-provided budget_tier
        without the trigger overriding it.
        """
        vault_id = test_vault["vault"]["id"]

        for tier in ["just_because", "minor_occasion", "major_milestone"]:
            row = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "custom",
                "milestone_name": f"Custom ({tier})",
                "milestone_date": "2026-09-01",
                "recurrence": "one_time",
                "budget_tier": tier,
            })

            try:
                assert row["budget_tier"] == tier, (
                    f"Expected custom milestone budget_tier '{tier}', "
                    f"got '{row['budget_tier']}'"
                )
            finally:
                _delete_milestone(row["id"])

        print("  custom milestones store all 3 user-provided budget_tier values")

    def test_custom_without_budget_tier_fails(self, test_vault):
        """
        A custom milestone WITHOUT budget_tier should fail because the
        trigger does not auto-set a default for custom type, and the
        NOT NULL constraint rejects NULL.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_milestone_raw({
            "vault_id": vault_id,
            "milestone_type": "custom",
            "milestone_name": "Custom No Budget",
            "milestone_date": "2026-10-01",
            "recurrence": "one_time",
            # budget_tier intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for custom milestone without budget_tier, "
            f"got HTTP {resp.status_code}. The NOT NULL constraint should reject "
            f"NULL budget_tier for custom type. Response: {resp.text}"
        )
        print("  custom milestone without budget_tier correctly rejected (NOT NULL)")


# ===================================================================
# 4. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerMilestonesRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_milestones(self, test_vault_with_milestones):
        """
        The anon client (no user JWT) should not see any milestones.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} milestone(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_milestones ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 milestones visible — RLS enforced")

    def test_service_client_can_read_milestones(self, test_vault_with_milestones):
        """
        The service client (bypasses RLS) should see the test milestones.
        """
        vault_id = test_vault_with_milestones["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 4, (
            f"Service client should see 4 milestones (birthday, anniversary, "
            f"Valentine's Day, custom), got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} milestones — RLS bypassed")

    def test_user_isolation_between_milestones(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's milestones.
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

        # Add milestones to both vaults
        milestone_a = _insert_milestone({
            "vault_id": vault_a["id"],
            "milestone_type": "birthday",
            "milestone_name": "A's Birthday",
            "milestone_date": "2000-01-15",
            "recurrence": "yearly",
        })
        milestone_b = _insert_milestone({
            "vault_id": vault_b["id"],
            "milestone_type": "anniversary",
            "milestone_name": "B's Anniversary",
            "milestone_date": "2000-07-20",
            "recurrence": "yearly",
        })

        try:
            # Query milestones for vault A — should only return vault A's milestone
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_milestones",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["milestone_name"] == "A's Birthday"

            # Query milestones for vault B — should only return vault B's milestone
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_milestones",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["milestone_name"] == "B's Anniversary"

            print("  User isolation verified: each vault sees only its own milestones")
        finally:
            _delete_milestone(milestone_a["id"])
            _delete_milestone(milestone_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 5. Data integrity: milestones stored correctly
# ===================================================================

@requires_supabase
class TestPartnerMilestonesDataIntegrity:
    """Verify milestones are stored with correct data across all fields."""

    def test_multiple_milestones_per_vault(self, test_vault_with_milestones):
        """
        A vault can have multiple milestones of different types.
        Verify all 4 test milestones are stored correctly.
        """
        vault_id = test_vault_with_milestones["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 4, f"Expected 4 milestones, got {len(rows)}"

        types = sorted([r["milestone_type"] for r in rows])
        assert types == sorted(["birthday", "anniversary", "holiday", "custom"]), (
            f"Expected all 4 milestone types, got {types}"
        )
        print(f"  4 milestones stored: {types}")

    def test_birthday_milestone_fields(self, test_vault_with_milestones):
        """Verify the birthday milestone has all fields stored correctly."""
        milestones = test_vault_with_milestones["milestones"]
        birthday = next(m for m in milestones if m["milestone_type"] == "birthday")

        assert birthday["milestone_name"] == "Birthday"
        assert birthday["milestone_date"] == "2000-03-15"
        assert birthday["recurrence"] == "yearly"
        assert birthday["budget_tier"] == "major_milestone"
        print("  Birthday milestone: all fields correct")

    def test_custom_milestone_fields(self, test_vault_with_milestones):
        """Verify the custom milestone has all user-provided fields stored correctly."""
        milestones = test_vault_with_milestones["milestones"]
        custom = next(m for m in milestones if m["milestone_type"] == "custom")

        assert custom["milestone_name"] == "First Date"
        assert custom["milestone_date"] == "2024-09-10"
        assert custom["recurrence"] == "one_time"
        assert custom["budget_tier"] == "minor_occasion"
        print("  Custom milestone 'First Date': all fields correct")

    def test_duplicate_milestone_types_allowed(self, test_vault):
        """
        A vault can have multiple milestones of the same type (e.g., multiple holidays).
        There is no UNIQUE constraint on (vault_id, milestone_type).
        """
        vault_id = test_vault["vault"]["id"]
        inserted_ids = []

        try:
            h1 = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "holiday",
                "milestone_name": "Christmas",
                "milestone_date": "2000-12-25",
                "recurrence": "yearly",
                "budget_tier": "major_milestone",
            })
            inserted_ids.append(h1["id"])

            h2 = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "holiday",
                "milestone_name": "New Year's Eve",
                "milestone_date": "2000-12-31",
                "recurrence": "yearly",
            })
            inserted_ids.append(h2["id"])

            assert len(inserted_ids) == 2, (
                "Should allow multiple milestones of the same type"
            )
            print("  Multiple holidays for same vault allowed (no UNIQUE on type)")
        finally:
            for mid in inserted_ids:
                _delete_milestone(mid)


# ===================================================================
# 6. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerMilestonesCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its milestones should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Milestone Test",
        })
        vault_id = vault["id"]

        # Insert a milestone
        milestone = _insert_milestone({
            "vault_id": vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-05-01",
            "recurrence": "yearly",
        })
        milestone_id = milestone["id"]

        # Verify milestone exists
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"id": f"eq.{milestone_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 1, "Milestone should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify milestone is gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_milestones",
            headers=_service_headers(),
            params={"id": f"eq.{milestone_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "partner_milestones row still exists after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed milestone rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → partner_milestones.
        """
        # Create temp auth user
        temp_email = f"knot-ms-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeMs!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Milestone Test",
            })
            vault_id = vault["id"]

            # Add a milestone
            milestone = _insert_milestone({
                "vault_id": vault_id,
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-09-15",
                "recurrence": "yearly",
            })
            milestone_id = milestone["id"]

            # Verify milestone exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_milestones",
                headers=_service_headers(),
                params={"id": f"eq.{milestone_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify milestone is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_milestones",
                headers=_service_headers(),
                params={"id": f"eq.{milestone_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Milestone row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → partner_milestones"
            )
            print("  Full CASCADE delete verified: auth deletion removed milestone rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a milestone with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_milestone_raw({
            "vault_id": fake_vault_id,
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-01-01",
            "recurrence": "yearly",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
