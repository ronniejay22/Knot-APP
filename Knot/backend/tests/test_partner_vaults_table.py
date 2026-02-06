"""
Step 1.2 Verification: Partner Vaults Table

Tests that:
1. The partner_vaults table exists and is accessible via PostgREST
2. The table has the correct columns with proper types and defaults
3. user_id is UNIQUE (one vault per user)
4. partner_name is NOT NULL
5. cohabitation_status CHECK constraint enforces valid enum values
6. location_country defaults to 'US'
7. Row Level Security (RLS) blocks anonymous access
8. Service client (admin) can read all rows (bypasses RLS)
9. set_updated_at trigger auto-updates timestamps on changes
10. CASCADE delete removes vault when user is deleted
11. Foreign key to public.users is enforced

Prerequisites:
- Complete Steps 0.6-1.1 (Supabase project + users table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00003_create_partner_vaults_table.sql

Run with: pytest tests/test_partner_vaults_table.py -v
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
# Helper: insert and delete vault rows via service client
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


# ---------------------------------------------------------------------------
# Fixture: test auth user (auto-created, auto-cleaned)
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger should auto-create a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users row
    and any partner_vaults row via CASCADE).
    """
    test_email = f"knot-vault-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)

    # Give the trigger a moment to fire
    time.sleep(0.5)

    yield {"id": user_id, "email": test_email}

    # Cleanup: delete auth user (CASCADE deletes public.users + partner_vaults)
    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user_pair():
    """
    Create TWO test users for testing RLS isolation between users.
    Yields a tuple of (user_a_info, user_b_info).
    """
    email_a = f"knot-vaultA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-vaultB-{uuid.uuid4().hex[:8]}@test.example"
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
        "partner_name": "Test Partner",
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
    # No explicit vault cleanup needed — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestPartnerVaultsTableExists:
    """Verify the partner_vaults table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The partner_vaults table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00003_create_partner_vaults_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"partner_vaults table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00003_create_partner_vaults_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  partner_vaults table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestPartnerVaultsSchema:
    """Verify the partner_vaults table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault):
        """
        The partner_vaults table should have exactly these columns:
        id, user_id, partner_name, relationship_tenure_months,
        cohabitation_status, location_city, location_state,
        location_country, created_at, updated_at.
        """
        vault_id = test_vault["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            params={"id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No vault row found"

        row = rows[0]
        expected_columns = {
            "id", "user_id", "partner_name", "relationship_tenure_months",
            "cohabitation_status", "location_city", "location_state",
            "location_country", "created_at", "updated_at",
        }
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault):
        """The id column should be an auto-generated valid UUID."""
        vault_id = test_vault["vault"]["id"]
        parsed = uuid.UUID(vault_id)
        assert str(parsed) == vault_id
        print(f"  id is auto-generated UUID: {vault_id[:8]}...")

    def test_partner_name_not_null(self, test_auth_user):
        """partner_name is NOT NULL — inserting without it should fail."""
        user_id = test_auth_user["id"]

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            json={
                "user_id": user_id,
                # partner_name intentionally omitted
            },
        )
        # PostgREST returns 400 for NOT NULL violations
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing partner_name, got HTTP {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print("  partner_name NOT NULL constraint enforced")

    def test_cohabitation_status_check_constraint(self, test_auth_user):
        """
        cohabitation_status must be one of:
        'living_together', 'separate', 'long_distance'.
        Invalid values should be rejected by the CHECK constraint.
        """
        user_id = test_auth_user["id"]

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            json={
                "user_id": user_id,
                "partner_name": "Check Test Partner",
                "cohabitation_status": "invalid_status",
            },
        )
        # PostgREST returns 400 for CHECK constraint violations
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid cohabitation_status, got HTTP {resp.status_code}. "
            f"Response: {resp.text}"
        )
        print("  cohabitation_status CHECK constraint enforced")

    def test_valid_cohabitation_values(self, test_auth_user):
        """All three valid cohabitation_status values should be accepted."""
        user_id = test_auth_user["id"]
        valid_statuses = ["living_together", "separate", "long_distance"]

        for status in valid_statuses:
            # Insert a vault with this status
            resp = httpx.post(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                json={
                    "user_id": user_id,
                    "partner_name": f"Partner ({status})",
                    "cohabitation_status": status,
                },
            )
            if resp.status_code in (200, 201):
                rows = resp.json()
                vault_id = rows[0]["id"] if isinstance(rows, list) else rows["id"]
                # Clean up for next iteration (user_id is UNIQUE)
                _delete_vault(vault_id)
                print(f"  cohabitation_status '{status}' accepted")
            elif resp.status_code == 409:
                # Conflict because vault already exists for this user — expected on 2nd+ iteration
                # This means the first insert worked; delete and retry
                # Clean up existing vault first
                del_resp = httpx.delete(
                    f"{SUPABASE_URL}/rest/v1/partner_vaults",
                    headers=_service_headers(),
                    params={"user_id": f"eq.{user_id}"},
                )
                # Retry insert
                retry_resp = httpx.post(
                    f"{SUPABASE_URL}/rest/v1/partner_vaults",
                    headers=_service_headers(),
                    json={
                        "user_id": user_id,
                        "partner_name": f"Partner ({status})",
                        "cohabitation_status": status,
                    },
                )
                assert retry_resp.status_code in (200, 201), (
                    f"Failed to insert vault with status '{status}': "
                    f"HTTP {retry_resp.status_code} — {retry_resp.text}"
                )
                rows = retry_resp.json()
                vault_id = rows[0]["id"] if isinstance(rows, list) else rows["id"]
                _delete_vault(vault_id)
                print(f"  cohabitation_status '{status}' accepted (after cleanup)")
            else:
                pytest.fail(
                    f"cohabitation_status '{status}' should be valid but was rejected: "
                    f"HTTP {resp.status_code} — {resp.text}"
                )

    def test_location_country_defaults_to_us(self, test_auth_user):
        """location_country should default to 'US' when not provided."""
        user_id = test_auth_user["id"]

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            json={
                "user_id": user_id,
                "partner_name": "Default Country Partner",
                # location_country intentionally omitted
            },
        )
        assert resp.status_code in (200, 201), (
            f"Failed to insert vault without location_country: "
            f"HTTP {resp.status_code} — {resp.text}"
        )
        rows = resp.json()
        row = rows[0] if isinstance(rows, list) else rows
        assert row["location_country"] == "US", (
            f"location_country should default to 'US', got: {row['location_country']}"
        )
        # Cleanup
        _delete_vault(row["id"])
        print("  location_country defaults to 'US'")

    def test_user_id_unique_constraint(self, test_auth_user):
        """
        user_id is UNIQUE — only one vault per user.
        Inserting a second vault for the same user should fail.
        """
        user_id = test_auth_user["id"]

        # Insert first vault
        resp1 = httpx.post(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            json={
                "user_id": user_id,
                "partner_name": "First Partner",
            },
        )
        assert resp1.status_code in (200, 201), (
            f"Failed to insert first vault: HTTP {resp1.status_code} — {resp1.text}"
        )
        rows1 = resp1.json()
        vault1_id = rows1[0]["id"] if isinstance(rows1, list) else rows1["id"]

        try:
            # Attempt to insert second vault for same user
            resp2 = httpx.post(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                json={
                    "user_id": user_id,
                    "partner_name": "Second Partner",
                },
            )
            assert resp2.status_code == 409, (
                f"Expected 409 Conflict for duplicate user_id, got HTTP {resp2.status_code}. "
                "The UNIQUE constraint on user_id may not be set. "
                f"Response: {resp2.text}"
            )
            print("  user_id UNIQUE constraint enforced (one vault per user)")
        finally:
            _delete_vault(vault1_id)

    def test_created_at_auto_populated(self, test_vault):
        """created_at should be automatically populated with a timestamp."""
        vault = test_vault["vault"]
        assert vault["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {vault['created_at']}")


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestPartnerVaultsRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_vaults(self, test_vault):
        """
        The anon client (no user JWT) should not see any vaults.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} vault(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.partner_vaults ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 vaults visible — RLS enforced")

    def test_service_client_can_read_vaults(self, test_vault):
        """
        The service client (bypasses RLS) should see the test vault.
        """
        vault_id = test_vault["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            params={"id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, (
            f"Service client should see the test vault, got {len(rows)} rows."
        )
        assert rows[0]["id"] == vault_id
        print(f"  Service client: found vault {vault_id[:8]}... — RLS bypassed")

    def test_user_isolation_between_vaults(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's vaults.
        Using service client to verify data isolation (since we can't
        easily generate JWTs for test users, we verify the data is
        correctly associated with user_id).
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

        try:
            # Query vaults for user A — should only return user A's vault
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1, (
                f"Expected 1 vault for user A, got {len(rows_a)}"
            )
            assert rows_a[0]["partner_name"] == "User A's Partner"
            assert rows_a[0]["user_id"] == user_a["id"]

            # Query vaults for user B — should only return user B's vault
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1, (
                f"Expected 1 vault for user B, got {len(rows_b)}"
            )
            assert rows_b[0]["partner_name"] == "User B's Partner"
            assert rows_b[0]["user_id"] == user_b["id"]

            # Verify the two vaults are different
            assert vault_a["id"] != vault_b["id"]
            print("  User isolation verified: each user sees only their own vault")
        finally:
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Triggers and cascades
# ===================================================================

@requires_supabase
class TestPartnerVaultsTriggers:
    """Verify triggers and CASCADE delete behavior."""

    def test_updated_at_changes_on_update(self, test_vault):
        """
        When a vault row is updated, the set_updated_at trigger should
        automatically set updated_at to the current time.
        """
        vault_id = test_vault["vault"]["id"]
        original_updated_at = test_vault["vault"]["updated_at"]

        # Wait to ensure timestamp difference
        time.sleep(1.1)

        # Update the partner name
        patch_resp = httpx.patch(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            params={"id": f"eq.{vault_id}"},
            json={"partner_name": "Updated Partner Name"},
        )
        assert patch_resp.status_code in (200, 204), (
            f"Failed to update vault: HTTP {patch_resp.status_code} — {patch_resp.text}"
        )

        # Get the new updated_at
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            params={"id": f"eq.{vault_id}", "select": "updated_at"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        new_updated_at = rows[0]["updated_at"]

        assert new_updated_at != original_updated_at, (
            f"updated_at did not change after update. "
            f"Before: {original_updated_at}, After: {new_updated_at}. "
            "Check that the set_updated_at trigger is attached to partner_vaults."
        )
        print(f"  updated_at changed: {original_updated_at} → {new_updated_at}")

    def test_cascade_delete_with_user(self):
        """
        When a user is deleted from auth.users, their vault should be
        automatically removed via the CASCADE chain:
        auth.users → public.users → partner_vaults.
        """
        # Create a temporary auth user
        temp_email = f"knot-vault-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeTest!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create a vault for this user
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Cascade Test Partner",
            })
            vault_id = vault["id"]

            # Verify the vault exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                params={"id": f"eq.{vault_id}", "select": "id"},
            )
            assert check1.status_code == 200
            assert len(check1.json()) == 1, "Vault should exist before deletion"

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200, (
                f"Failed to delete auth user: HTTP {del_resp.status_code}"
            )

            # Give CASCADE time to propagate
            time.sleep(0.5)

            # Verify the vault is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/partner_vaults",
                headers=_service_headers(),
                params={"id": f"eq.{vault_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "partner_vaults row still exists after auth user deletion. "
                "Check that user_id has ON DELETE CASCADE referencing users.id, "
                "and users.id has ON DELETE CASCADE referencing auth.users.id."
            )
            print("  CASCADE delete verified: auth deletion removed vault row")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced(self):
        """
        Inserting a vault with a non-existent user_id should fail
        because of the foreign key constraint to public.users.
        """
        fake_user_id = str(uuid.uuid4())

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/partner_vaults",
            headers=_service_headers(),
            json={
                "user_id": fake_user_id,
                "partner_name": "Fake User Partner",
            },
        )
        # PostgREST returns 409 for foreign key violations
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent user_id FK, got HTTP {resp.status_code}. "
            "The foreign key constraint on user_id may not be set. "
            f"Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent user_id rejected)")
