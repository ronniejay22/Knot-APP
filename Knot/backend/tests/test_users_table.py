"""
Step 1.1 Verification: Users Table

Tests that:
1. The users table exists and is accessible via PostgREST
2. The table has the correct columns (id, email, created_at, updated_at)
3. Row Level Security (RLS) blocks anonymous access
4. Service client (admin) can read all rows (bypasses RLS)
5. The handle_new_user trigger auto-creates a profile on auth signup
6. The set_updated_at trigger auto-updates timestamps on changes
7. CASCADE delete removes the public.users row when auth user is deleted

Prerequisites:
- Complete Steps 0.6-0.7 (Supabase project + credentials in .env)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00002_create_users_table.sql

Run with: pytest tests/test_users_table.py -v
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
# Fixture: test auth user (auto-created, auto-cleaned)
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger should auto-create a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users row).
    """
    test_email = f"knot-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)

    # Give the trigger a moment to fire
    time.sleep(0.5)

    yield {"id": user_id, "email": test_email}

    # Cleanup: delete auth user (CASCADE deletes public.users row)
    _delete_auth_user(user_id)


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestUsersTableExists:
    """Verify the users table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The users table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00002_create_users_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"users table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00002_create_users_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  users table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestUsersTableSchema:
    """Verify the users table has the correct columns and types."""

    def test_columns_exist(self, test_auth_user):
        """
        The users table should have exactly these columns:
        id (UUID), email (text), created_at (timestamptz), updated_at (timestamptz).
        """
        user_id = test_auth_user["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, (
            "No user row found. The handle_new_user trigger may not have fired. "
            "Check that the trigger was created in the migration."
        )

        row = rows[0]
        expected_columns = {"id", "email", "created_at", "updated_at"}
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_valid_uuid(self, test_auth_user):
        """The id column should store valid UUIDs matching auth.users."""
        user_id = test_auth_user["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "id"},
        )
        assert resp.status_code == 200, f"GET users failed: HTTP {resp.status_code}"
        rows = resp.json()
        assert len(rows) >= 1, "No user row found"

        # Verify it's a valid UUID string
        parsed = uuid.UUID(rows[0]["id"])
        assert str(parsed) == user_id
        print(f"  id is valid UUID: {user_id[:8]}...")

    def test_created_at_auto_populated(self, test_auth_user):
        """created_at should be automatically populated with a timestamp."""
        user_id = test_auth_user["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "created_at"},
        )
        assert resp.status_code == 200, f"GET users failed: HTTP {resp.status_code}"
        rows = resp.json()
        assert len(rows) >= 1, "No user row found"
        assert rows[0]["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {rows[0]['created_at']}")

    def test_email_is_nullable(self, test_auth_user):
        """
        The email column should accept NULL values.
        This is required for Apple Private Relay users who hide their email.
        """
        user_id = test_auth_user["id"]

        # Update email to NULL via service client
        patch_resp = httpx.patch(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}"},
            json={"email": None},
        )
        assert patch_resp.status_code in (200, 204), (
            f"Failed to set email to NULL: HTTP {patch_resp.status_code}"
        )

        # Verify the email is now NULL
        get_resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "email"},
        )
        assert get_resp.status_code == 200, f"GET users failed: HTTP {get_resp.status_code}"
        rows = get_resp.json()
        assert len(rows) >= 1, "No user row found"
        assert rows[0]["email"] is None, (
            f"email should be NULL after setting to null, got: {rows[0]['email']}"
        )
        print("  email column accepts NULL (Apple Private Relay compatible)")


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestUsersTableRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_rows(self, test_auth_user):
        """
        The anon client (no user JWT) should not see any rows.

        With RLS enabled and the policy USING (auth.uid() = id),
        the anon key has no user identity so auth.uid() returns NULL.
        NULL = id is always FALSE, so no rows are visible.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} row(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 rows visible — RLS enforced")

    def test_service_client_can_read_rows(self, test_auth_user):
        """
        The service client (bypasses RLS) should see all rows,
        including the test user's row.
        """
        user_id = test_auth_user["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, (
            f"Service client should see the test user row, got {len(rows)} rows."
        )
        assert rows[0]["id"] == user_id
        print(f"  Service client: found user {user_id[:8]}... — RLS bypassed")


# ===================================================================
# 4. Triggers
# ===================================================================

@requires_supabase
class TestUsersTableTriggers:
    """Verify database triggers work correctly."""

    def test_auto_create_on_auth_signup(self, test_auth_user):
        """
        When a new user is created in auth.users, the handle_new_user
        trigger should auto-insert a row into public.users with the
        same id and email.
        """
        user_id = test_auth_user["id"]
        email = test_auth_user["email"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 1, (
            f"Expected 1 user row after auth signup, got {len(rows)}. "
            "The handle_new_user trigger may not be set up correctly."
        )
        assert rows[0]["id"] == user_id
        assert rows[0]["email"] == email
        print(f"  Trigger auto-created row: id={user_id[:8]}..., email={email}")

    def test_updated_at_changes_on_update(self, test_auth_user):
        """
        When a row is updated, the set_updated_at trigger should
        automatically set updated_at to the current time.
        """
        user_id = test_auth_user["id"]

        # Get the original updated_at
        resp1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "updated_at"},
        )
        assert resp1.status_code == 200, f"GET users failed: HTTP {resp1.status_code}"
        rows1 = resp1.json()
        assert len(rows1) >= 1, "No user row found"
        original_updated_at = rows1[0]["updated_at"]

        # Wait to ensure timestamp difference
        time.sleep(1.1)

        # Update the email
        patch_resp = httpx.patch(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}"},
            json={"email": "updated@knot-test.example"},
        )
        assert patch_resp.status_code in (200, 204), (
            f"Failed to update user row: HTTP {patch_resp.status_code}"
        )

        # Get the new updated_at
        resp2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/users",
            headers=_service_headers(),
            params={"id": f"eq.{user_id}", "select": "updated_at"},
        )
        assert resp2.status_code == 200, f"GET users failed: HTTP {resp2.status_code}"
        rows2 = resp2.json()
        new_updated_at = rows2[0]["updated_at"]

        assert new_updated_at != original_updated_at, (
            f"updated_at did not change after update. "
            f"Before: {original_updated_at}, After: {new_updated_at}. "
            "Check that the set_updated_at trigger is correctly created."
        )
        print(f"  updated_at changed: {original_updated_at} → {new_updated_at}")

    def test_cascade_delete_with_auth_user(self):
        """
        When an auth user is deleted, the public.users row should be
        automatically removed via ON DELETE CASCADE.
        """
        # Create a temporary auth user
        temp_email = f"knot-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeTest!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            # Give the trigger time to create the public.users row
            time.sleep(0.5)

            # Verify the public.users row exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/users",
                headers=_service_headers(),
                params={"id": f"eq.{temp_user_id}", "select": "id"},
            )
            assert check1.status_code == 200, f"GET users failed: HTTP {check1.status_code}"
            assert len(check1.json()) == 1, (
                "public.users row should exist after auth user creation"
            )

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

            # Verify the public.users row is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/users",
                headers=_service_headers(),
                params={"id": f"eq.{temp_user_id}", "select": "id"},
            )
            assert check2.status_code == 200, f"GET users failed: HTTP {check2.status_code}"
            assert len(check2.json()) == 0, (
                "public.users row still exists after auth user deletion. "
                "Check that the id column has ON DELETE CASCADE."
            )
            print(f"  CASCADE delete verified: auth deletion removed public.users row")
        except Exception:
            # Ensure the temp user is cleaned up even if assertions fail
            _delete_auth_user(temp_user_id)
            raise
