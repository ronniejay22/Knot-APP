"""
Step 1.5 Verification: Partner Vibes Table

Tests that:
1. The partner_vibes table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, vibe_tag, created_at)
3. vibe_tag CHECK constraint enforces 8 valid values
4. UNIQUE(vault_id, vibe_tag) prevents duplicate vibes per vault
5. Row Level Security (RLS) blocks anonymous access
6. Service client (admin) can read all rows (bypasses RLS)
7. CASCADE delete removes vibes when vault is deleted
8. Full CASCADE chain: auth.users → users → partner_vaults → partner_vibes
9. Foreign key to partner_vaults is enforced

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00006_create_partner_vibes_table.sql

Run with: pytest tests/test_partner_vibes_table.py -v
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
# Helpers: insert/delete vault and vibe rows via service client
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


def _insert_vibe(vibe_data: dict) -> dict:
    """Insert a vibe row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vibes",
        headers=_service_headers(),
        json=vibe_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vibe: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_vibe_raw(vibe_data: dict) -> httpx.Response:
    """Insert a vibe row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vibes",
        headers=_service_headers(),
        json=vibe_data,
    )


def _delete_vibe(vibe_id: str):
    """Delete a vibe row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_vibes",
        headers=_service_headers(),
        params={"id": f"eq.{vibe_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with vibes
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and partner_vibes rows).
    """
    test_email = f"knot-vibe-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-vbA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-vbB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Vibe Test Partner",
        "relationship_tenure_months": 18,
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
def test_vault_with_vibes(test_vault):
    """
    Create a vault with sample vibes pre-populated:
    - quiet_luxury
    - minimalist
    - romantic

    Yields user, vault, and vibe info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    vibes = []

    for tag in ["quiet_luxury", "minimalist", "romantic"]:
        row = _insert_vibe({
            "vault_id": vault_id,
            "vibe_tag": tag,
        })
        vibes.append(row)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "vibes": vibes,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerVibesTableExists:
    """Verify the partner_vibes table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_vibes table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00006_create_partner_vibes_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_vibes table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00006_create_partner_vibes_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_vibes table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerVibesSchema:
    """Verify the partner_vibes table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_vibes):
        """
        The partner_vibes table should have exactly these columns:
        id, vault_id, vibe_tag, created_at.
        """
        vault_id = test_vault_with_vibes["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No vibe rows found"

        row = rows[0]
        expected_columns = {"id", "vault_id", "vibe_tag", "created_at"}
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_vibes):
        """The id column should be an auto-generated valid UUID."""
        vibe_id = test_vault_with_vibes["vibes"][0]["id"]
        parsed = uuid.UUID(vibe_id)
        assert str(parsed) == vibe_id
        print(f"  id is auto-generated UUID: {vibe_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_vibes):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_vibes["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
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

    def test_vibe_tag_check_constraint_rejects_invalid(self, test_vault):
        """
        vibe_tag must be one of the 8 valid values.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_vibe_raw({
            "vault_id": vault_id,
            "vibe_tag": "fancy",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid vibe_tag 'fancy', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  vibe_tag CHECK constraint rejects invalid value 'fancy'")

    def test_vibe_tag_accepts_all_valid_values(self, test_vault):
        """All 8 valid vibe_tag values should be accepted."""
        vault_id = test_vault["vault"]["id"]
        valid_vibes = [
            "quiet_luxury", "street_urban", "outdoorsy", "vintage",
            "minimalist", "bohemian", "romantic", "adventurous",
        ]
        inserted_ids = []

        try:
            for tag in valid_vibes:
                row = _insert_vibe({
                    "vault_id": vault_id,
                    "vibe_tag": tag,
                })
                inserted_ids.append(row["id"])
                assert row["vibe_tag"] == tag

            assert len(inserted_ids) == 8, (
                f"Expected 8 vibe tags inserted, got {len(inserted_ids)}"
            )
            print(f"  All 8 valid vibe_tag values accepted")
        finally:
            for vid in inserted_ids:
                _delete_vibe(vid)

    def test_vibe_tag_not_null(self, test_vault):
        """vibe_tag is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_vibe_raw({
            "vault_id": vault_id,
            # vibe_tag intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing vibe_tag, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  vibe_tag NOT NULL constraint enforced")

    def test_unique_constraint_prevents_duplicate_vibe(self, test_vault):
        """
        UNIQUE(vault_id, vibe_tag) should prevent inserting the same
        vibe_tag twice for the same vault.
        """
        vault_id = test_vault["vault"]["id"]

        # Insert first vibe
        row = _insert_vibe({
            "vault_id": vault_id,
            "vibe_tag": "bohemian",
        })

        try:
            # Attempt duplicate insert
            resp = _insert_vibe_raw({
                "vault_id": vault_id,
                "vibe_tag": "bohemian",
            })
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for duplicate vibe_tag 'bohemian', "
                f"got HTTP {resp.status_code}. "
                "UNIQUE(vault_id, vibe_tag) constraint may be missing. "
                f"Response: {resp.text}"
            )
            print("  UNIQUE(vault_id, vibe_tag) prevents duplicate vibes")
        finally:
            _delete_vibe(row["id"])

    def test_same_vibe_allowed_for_different_vaults(self, test_auth_user_pair):
        """
        Different vaults CAN have the same vibe_tag. The UNIQUE constraint
        is scoped to (vault_id, vibe_tag), not global.
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
            vibe_a = _insert_vibe({
                "vault_id": vault_a["id"],
                "vibe_tag": "romantic",
            })
            vibe_b = _insert_vibe({
                "vault_id": vault_b["id"],
                "vibe_tag": "romantic",
            })

            assert vibe_a["vibe_tag"] == "romantic"
            assert vibe_b["vibe_tag"] == "romantic"
            assert vibe_a["vault_id"] != vibe_b["vault_id"]
            print("  Same vibe_tag allowed for different vaults (UNIQUE scoped to vault)")
        finally:
            _delete_vibe(vibe_a["id"])
            _delete_vibe(vibe_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerVibesRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_vibes(self, test_vault_with_vibes):
        """
        The anon client (no user JWT) should not see any vibes.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} vibe(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_vibes ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 vibes visible — RLS enforced")

    def test_service_client_can_read_vibes(self, test_vault_with_vibes):
        """
        The service client (bypasses RLS) should see the test vibes.
        """
        vault_id = test_vault_with_vibes["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, (
            f"Service client should see 3 vibes (quiet_luxury, minimalist, "
            f"romantic), got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} vibes — RLS bypassed")

    def test_user_isolation_between_vibes(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's vibes.
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

        # Add vibes to both vaults
        vibe_a = _insert_vibe({
            "vault_id": vault_a["id"],
            "vibe_tag": "quiet_luxury",
        })
        vibe_b = _insert_vibe({
            "vault_id": vault_b["id"],
            "vibe_tag": "street_urban",
        })

        try:
            # Query vibes for vault A — should only return vault A's vibe
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["vibe_tag"] == "quiet_luxury"

            # Query vibes for vault B — should only return vault B's vibe
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["vibe_tag"] == "street_urban"

            print("  User isolation verified: each vault sees only its own vibes")
        finally:
            _delete_vibe(vibe_a["id"])
            _delete_vibe(vibe_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: vibes stored correctly
# ===================================================================

@requires_supabase
class TestPartnerVibesDataIntegrity:
    """Verify vibes are stored with correct data across all fields."""

    def test_multiple_vibes_per_vault(self, test_vault_with_vibes):
        """
        A vault can have multiple vibes (up to 4, enforced at API layer).
        Verify all 3 test vibes are stored correctly.
        """
        vault_id = test_vault_with_vibes["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 vibes, got {len(rows)}"

        tags = sorted([r["vibe_tag"] for r in rows])
        assert tags == sorted(["quiet_luxury", "minimalist", "romantic"]), (
            f"Expected vibes ['minimalist', 'quiet_luxury', 'romantic'], got {tags}"
        )
        print(f"  3 vibes stored: {tags}")

    def test_vibe_tag_field_values(self, test_vault_with_vibes):
        """Verify each vibe has the correct vibe_tag and vault_id."""
        vault_id = test_vault_with_vibes["vault"]["id"]
        vibes = test_vault_with_vibes["vibes"]

        for vibe in vibes:
            assert vibe["vault_id"] == vault_id, (
                f"Vibe {vibe['id']} has wrong vault_id: "
                f"expected {vault_id}, got {vibe['vault_id']}"
            )
            assert vibe["vibe_tag"] in [
                "quiet_luxury", "minimalist", "romantic",
            ], f"Unexpected vibe_tag: {vibe['vibe_tag']}"

        print("  All vibe fields verified (vault_id, vibe_tag)")

    def test_insert_max_four_vibes(self, test_vault):
        """
        A vault can store up to 4 vibes at the database level.
        (The 1-4 range is enforced at the API layer, but the database
        should accept 4 distinct vibes without issues.)
        """
        vault_id = test_vault["vault"]["id"]
        tags = ["quiet_luxury", "minimalist", "romantic", "adventurous"]
        inserted_ids = []

        try:
            for tag in tags:
                row = _insert_vibe({
                    "vault_id": vault_id,
                    "vibe_tag": tag,
                })
                inserted_ids.append(row["id"])

            assert len(inserted_ids) == 4, (
                f"Expected 4 vibes inserted, got {len(inserted_ids)}"
            )

            # Verify all 4 are retrievable
            resp = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_id}", "select": "*"},
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 4
            print("  4 vibes stored successfully (max for onboarding)")
        finally:
            for vid in inserted_ids:
                _delete_vibe(vid)

    def test_single_vibe_is_valid(self, test_vault):
        """
        A vault with a single vibe should work. Minimum of 1 vibe
        is enforced at the API layer, but the database should accept it.
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_vibe({
            "vault_id": vault_id,
            "vibe_tag": "vintage",
        })

        try:
            resp = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_id}", "select": "*"},
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 1
            assert rows[0]["vibe_tag"] == "vintage"
            print("  Single vibe stored and retrievable")
        finally:
            _delete_vibe(row["id"])


# ===================================================================
# 5. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerVibesCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its vibes should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Vibe Test",
        })
        vault_id = vault["id"]

        # Insert vibes
        vibe1 = _insert_vibe({
            "vault_id": vault_id,
            "vibe_tag": "outdoorsy",
        })
        vibe2 = _insert_vibe({
            "vault_id": vault_id,
            "vibe_tag": "adventurous",
        })

        # Verify vibes exist
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 2, "Vibes should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify vibes are gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vibes",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "partner_vibes rows still exist after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed vibe rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → partner_vibes.
        """
        # Create temp auth user
        temp_email = f"knot-vb-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeVb!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Vibe Test",
            })
            vault_id = vault["id"]

            # Add vibes
            vibe = _insert_vibe({
                "vault_id": vault_id,
                "vibe_tag": "bohemian",
            })
            vibe_id = vibe["id"]

            # Verify vibe exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"id": f"eq.{vibe_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify vibe is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vibes",
                headers=_service_headers(),
                params={"id": f"eq.{vibe_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Vibe row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → partner_vibes"
            )
            print("  Full CASCADE delete verified: auth deletion removed vibe rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a vibe with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_vibe_raw({
            "vault_id": fake_vault_id,
            "vibe_tag": "romantic",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
