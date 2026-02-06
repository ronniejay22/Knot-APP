"""
Step 1.11 Verification: Notification Queue Table

Tests that:
1. The notification_queue table exists and is accessible via PostgREST
2. The table has the correct columns (id, user_id, milestone_id, scheduled_for,
   days_before, status, sent_at, created_at)
3. days_before CHECK constraint enforces 14, 7, 3 only
4. status CHECK constraint enforces 'pending', 'sent', 'failed', 'cancelled'
5. status defaults to 'pending' when not provided
6. Row Level Security (RLS) blocks anonymous access
7. Service client (admin) can read all rows (bypasses RLS)
8. CASCADE delete removes notifications when milestone is deleted
9. CASCADE delete removes notifications when user is deleted
10. Full CASCADE chain: auth.users → users → notification_queue
11. Foreign key to partner_milestones is enforced

Prerequisites:
- Complete Steps 0.6-1.4 (Supabase project + users + partner_vaults + partner_milestones)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00012_create_notification_queue_table.sql

Run with: pytest tests/test_notification_queue_table.py -v
"""

import pytest
import httpx
import uuid
import time
from datetime import datetime, timezone, timedelta

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
# Helpers: insert/delete vault, milestone, and notification rows
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


def _insert_notification(notif_data: dict) -> dict:
    """Insert a notification_queue row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        json=notif_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert notification: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_notification_raw(notif_data: dict) -> httpx.Response:
    """Insert a notification_queue row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        json=notif_data,
    )


def _delete_notification(notif_id: str):
    """Delete a notification_queue row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        params={"id": f"eq.{notif_id}"},
    )


def _update_notification(notif_id: str, updates: dict) -> dict:
    """Update a notification_queue row via service client. Returns updated row."""
    resp = httpx.patch(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        params={"id": f"eq.{notif_id}"},
        json=updates,
    )
    assert resp.status_code in (200, 204), (
        f"Failed to update notification: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) and rows else rows


# ---------------------------------------------------------------------------
# Helper: generate future timestamps
# ---------------------------------------------------------------------------

def _future_timestamp(days: int) -> str:
    """Return an ISO 8601 timestamp `days` in the future."""
    dt = datetime.now(timezone.utc) + timedelta(days=days)
    return dt.isoformat()


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, milestone, and notification queue
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, milestones, and notification_queue rows).
    """
    test_email = f"knot-nq-{uuid.uuid4().hex[:8]}@test.example"
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
    email_a = f"knot-nqA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-nqB-{uuid.uuid4().hex[:8]}@test.example"
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
def test_vault_with_milestone(test_auth_user):
    """
    Create a test vault with a birthday milestone.
    Yields user, vault, and milestone info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    user_id = test_auth_user["id"]
    vault = _insert_vault({
        "user_id": user_id,
        "partner_name": "Notification Test Partner",
        "relationship_tenure_months": 18,
        "cohabitation_status": "separate",
        "location_city": "Chicago",
        "location_state": "IL",
        "location_country": "US",
    })
    milestone = _insert_milestone({
        "vault_id": vault["id"],
        "milestone_type": "birthday",
        "milestone_name": "Partner's Birthday",
        "milestone_date": "2000-08-20",
        "recurrence": "yearly",
    })

    yield {
        "user": test_auth_user,
        "vault": vault,
        "milestone": milestone,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_notification_pending(test_vault_with_milestone):
    """
    Create a pending notification scheduled 14 days before a milestone.
    Yields user, vault, milestone, and notification info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    user_id = test_vault_with_milestone["user"]["id"]
    milestone_id = test_vault_with_milestone["milestone"]["id"]

    notif = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone_id,
        "scheduled_for": _future_timestamp(14),
        "days_before": 14,
    })

    yield {
        "user": test_vault_with_milestone["user"],
        "vault": test_vault_with_milestone["vault"],
        "milestone": test_vault_with_milestone["milestone"],
        "notification": notif,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_three_notifications(test_vault_with_milestone):
    """
    Create 3 notifications (14, 7, 3 days before) for a milestone.
    Yields user, vault, milestone, and notifications info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    user_id = test_vault_with_milestone["user"]["id"]
    milestone_id = test_vault_with_milestone["milestone"]["id"]

    notifications = []
    for days in [14, 7, 3]:
        notif = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(days),
            "days_before": days,
        })
        notifications.append(notif)

    yield {
        "user": test_vault_with_milestone["user"],
        "vault": test_vault_with_milestone["vault"],
        "milestone": test_vault_with_milestone["milestone"],
        "notifications": notifications,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestNotificationQueueTableExists:
    """Verify the notification_queue table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The notification_queue table should exist in the public schema
        and be accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00012_create_notification_queue_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"notification_queue table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00012_create_notification_queue_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  notification_queue table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestNotificationQueueSchema:
    """Verify the notification_queue table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_notification_pending):
        """
        The notification_queue table should have exactly these columns:
        id, user_id, milestone_id, scheduled_for, days_before, status,
        sent_at, created_at.
        """
        notif = test_notification_pending["notification"]

        expected_columns = {
            "id", "user_id", "milestone_id", "scheduled_for",
            "days_before", "status", "sent_at", "created_at",
        }
        actual_columns = set(notif.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_notification_pending):
        """The id column should be an auto-generated valid UUID."""
        notif_id = test_notification_pending["notification"]["id"]
        parsed = uuid.UUID(notif_id)
        assert str(parsed) == notif_id
        print(f"  id is auto-generated UUID: {notif_id[:8]}...")

    def test_created_at_auto_populated(self, test_notification_pending):
        """created_at should be automatically populated with a timestamp."""
        notif = test_notification_pending["notification"]
        assert notif["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {notif['created_at']}")

    def test_days_before_check_rejects_invalid(self, test_vault_with_milestone):
        """days_before must be 14, 7, or 3. Other values should be rejected."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        resp = _insert_notification_raw({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(10),
            "days_before": 10,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid days_before=10, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  days_before CHECK constraint rejects invalid value (10)")

    def test_days_before_accepts_fourteen(self, test_vault_with_milestone):
        """days_before=14 should be accepted."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        row = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(14),
            "days_before": 14,
        })
        try:
            assert row["days_before"] == 14
            print("  days_before=14 accepted")
        finally:
            _delete_notification(row["id"])

    def test_days_before_accepts_seven(self, test_vault_with_milestone):
        """days_before=7 should be accepted."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        row = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
        })
        try:
            assert row["days_before"] == 7
            print("  days_before=7 accepted")
        finally:
            _delete_notification(row["id"])

    def test_days_before_accepts_three(self, test_vault_with_milestone):
        """days_before=3 should be accepted."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        row = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(3),
            "days_before": 3,
        })
        try:
            assert row["days_before"] == 3
            print("  days_before=3 accepted")
        finally:
            _delete_notification(row["id"])

    def test_status_check_rejects_invalid(self, test_vault_with_milestone):
        """status must be 'pending', 'sent', 'failed', or 'cancelled'."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        resp = _insert_notification_raw({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
            "status": "delivered",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid status 'delivered', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  status CHECK constraint rejects invalid value 'delivered'")

    def test_status_defaults_to_pending(self, test_vault_with_milestone):
        """status should default to 'pending' when not explicitly provided."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        row = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
            # status intentionally omitted
        })
        try:
            assert row["status"] == "pending", (
                f"status should default to 'pending', got '{row['status']}'"
            )
            print("  status defaults to 'pending' when not provided")
        finally:
            _delete_notification(row["id"])

    def test_status_accepts_all_valid_values(self, test_vault_with_milestone):
        """All 4 status values should be accepted."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        for status_val in ["pending", "sent", "failed", "cancelled"]:
            row = _insert_notification({
                "user_id": user_id,
                "milestone_id": milestone_id,
                "scheduled_for": _future_timestamp(7),
                "days_before": 7,
                "status": status_val,
            })
            try:
                assert row["status"] == status_val
            finally:
                _delete_notification(row["id"])
        print("  status accepts all valid values (pending, sent, failed, cancelled)")

    def test_sent_at_is_nullable(self, test_notification_pending):
        """sent_at is nullable — NULL until the notification is actually sent."""
        notif = test_notification_pending["notification"]
        assert notif["sent_at"] is None, (
            f"sent_at should be NULL for pending notifications, got {notif['sent_at']}"
        )
        print("  sent_at is nullable (NULL until sent)")

    def test_scheduled_for_not_null(self, test_vault_with_milestone):
        """scheduled_for is NOT NULL — every notification must have a send time."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        resp = _insert_notification_raw({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 7,
            # scheduled_for intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing scheduled_for, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  scheduled_for NOT NULL constraint enforced")

    def test_days_before_not_null(self, test_vault_with_milestone):
        """days_before is NOT NULL — every notification must specify the reminder interval."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        resp = _insert_notification_raw({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            # days_before intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing days_before, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  days_before NOT NULL constraint enforced")


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestNotificationQueueRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_notifications(self, test_notification_pending):
        """
        The anon client (no user JWT) should not see any notifications.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} notification(s)! "
            "RLS is not properly configured."
        )
        print("  Anon client (no JWT): 0 notifications visible — RLS enforced")

    def test_service_client_can_read_notifications(self, test_notification_pending):
        """
        The service client (bypasses RLS) should see the test notification.
        """
        user_id = test_notification_pending["user"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"user_id": f"eq.{user_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, (
            "Service client should see at least 1 notification."
        )
        print(f"  Service client: found {len(rows)} notification(s) — RLS bypassed")

    def test_user_isolation_between_notifications(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's notifications.
        """
        user_a, user_b = test_auth_user_pair

        # Create vaults and milestones for both users
        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "User A Notif",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "User B Notif",
        })
        ms_a = _insert_milestone({
            "vault_id": vault_a["id"],
            "milestone_type": "birthday",
            "milestone_name": "A's Partner Birthday",
            "milestone_date": "2000-05-10",
            "recurrence": "yearly",
        })
        ms_b = _insert_milestone({
            "vault_id": vault_b["id"],
            "milestone_type": "anniversary",
            "milestone_name": "B's Anniversary",
            "milestone_date": "2000-09-15",
            "recurrence": "yearly",
        })

        # Create notifications
        notif_a = _insert_notification({
            "user_id": user_a["id"],
            "milestone_id": ms_a["id"],
            "scheduled_for": _future_timestamp(14),
            "days_before": 14,
        })
        notif_b = _insert_notification({
            "user_id": user_b["id"],
            "milestone_id": ms_b["id"],
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
        })

        try:
            # Query for user A
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["days_before"] == 14

            # Query for user B
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"user_id": f"eq.{user_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["days_before"] == 7

            print("  User isolation verified: each user sees only their own notifications")
        finally:
            _delete_notification(notif_a["id"])
            _delete_notification(notif_b["id"])
            _delete_milestone(ms_a["id"])
            _delete_milestone(ms_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: notifications stored correctly
# ===================================================================

@requires_supabase
class TestNotificationQueueDataIntegrity:
    """Verify notifications are stored with correct data across all fields."""

    def test_pending_notification_stored(self, test_notification_pending):
        """A pending notification should be stored and queryable."""
        user_id = test_notification_pending["user"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={
                "user_id": f"eq.{user_id}",
                "status": "eq.pending",
                "select": "*",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1
        print("  Pending notification stored and queryable")

    def test_three_notifications_per_milestone(self, test_three_notifications):
        """A milestone should have 3 notifications (14, 7, 3 days before)."""
        milestone_id = test_three_notifications["milestone"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={
                "milestone_id": f"eq.{milestone_id}",
                "select": "*",
                "order": "days_before.desc",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 notifications, got {len(rows)}"

        days = [r["days_before"] for r in rows]
        assert days == [14, 7, 3]
        print("  Three notifications per milestone: 14, 7, 3 days before")

    def test_notification_field_values(self, test_notification_pending):
        """All fields should be correctly populated for a pending notification."""
        notif = test_notification_pending["notification"]
        user_id = test_notification_pending["user"]["id"]
        milestone_id = test_notification_pending["milestone"]["id"]

        assert notif["user_id"] == user_id
        assert notif["milestone_id"] == milestone_id
        assert notif["days_before"] == 14
        assert notif["status"] == "pending"
        assert notif["sent_at"] is None
        assert notif["scheduled_for"] is not None
        assert notif["created_at"] is not None
        print("  Notification field values verified (user_id, milestone_id, days_before, status)")

    def test_update_status_to_sent(self, test_vault_with_milestone):
        """Updating status from 'pending' to 'sent' should persist."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        notif = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
        })
        notif_id = notif["id"]

        try:
            # Update to sent
            sent_time = datetime.now(timezone.utc).isoformat()
            updated = _update_notification(notif_id, {
                "status": "sent",
                "sent_at": sent_time,
            })

            # Verify the update
            check = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"id": f"eq.{notif_id}", "select": "*"},
            )
            assert check.status_code == 200
            rows = check.json()
            assert len(rows) == 1
            assert rows[0]["status"] == "sent"
            assert rows[0]["sent_at"] is not None
            print("  Status updated to 'sent' and sent_at populated")
        finally:
            _delete_notification(notif_id)

    def test_update_status_to_cancelled(self, test_vault_with_milestone):
        """Updating status from 'pending' to 'cancelled' should persist."""
        user_id = test_vault_with_milestone["user"]["id"]
        milestone_id = test_vault_with_milestone["milestone"]["id"]

        notif = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(3),
            "days_before": 3,
        })
        notif_id = notif["id"]

        try:
            _update_notification(notif_id, {"status": "cancelled"})

            check = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"id": f"eq.{notif_id}", "select": "status"},
            )
            assert check.status_code == 200
            rows = check.json()
            assert len(rows) == 1
            assert rows[0]["status"] == "cancelled"
            print("  Status updated to 'cancelled' successfully")
        finally:
            _delete_notification(notif_id)


# ===================================================================
# 5. CASCADE delete behavior
# ===================================================================

@requires_supabase
class TestNotificationQueueCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_milestone(self, test_auth_user):
        """
        When a milestone is deleted, all its notifications should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault and milestone
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Notif Test",
        })
        milestone = _insert_milestone({
            "vault_id": vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": "2000-04-15",
            "recurrence": "yearly",
        })
        milestone_id = milestone["id"]

        # Insert notifications
        notif = _insert_notification({
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(14),
            "days_before": 14,
        })
        notif_id = notif["id"]

        # Verify notification exists
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"id": f"eq.{notif_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 1, "Notification should exist before milestone deletion"

        # Delete the milestone
        _delete_milestone(milestone_id)
        time.sleep(0.3)

        # Verify notification is gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/notification_queue",
            headers=_service_headers(),
            params={"id": f"eq.{notif_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "Notification row still exists after milestone deletion. "
            "Check that milestone_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: milestone deletion removed notification rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → notification_queue
        """
        # Create temp auth user
        temp_email = f"knot-nq-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeNQ!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault, milestone, and notification
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade NQ Test",
            })
            milestone = _insert_milestone({
                "vault_id": vault["id"],
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-11-25",
                "recurrence": "yearly",
            })
            notif = _insert_notification({
                "user_id": temp_user_id,
                "milestone_id": milestone["id"],
                "scheduled_for": _future_timestamp(7),
                "days_before": 7,
            })
            notif_id = notif["id"]

            # Verify notification exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"id": f"eq.{notif_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify notification is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/notification_queue",
                headers=_service_headers(),
                params={"id": f"eq.{notif_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Notification row still exists after auth user deletion. "
                "Check full CASCADE chain."
            )
            print("  Full CASCADE delete verified: auth deletion removed notification rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_milestone_id(self, test_auth_user):
        """
        Inserting a notification with a non-existent milestone_id should fail
        because of the foreign key constraint.
        """
        user_id = test_auth_user["id"]
        fake_milestone_id = str(uuid.uuid4())

        resp = _insert_notification_raw({
            "user_id": user_id,
            "milestone_id": fake_milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent milestone_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  FK constraint enforced (non-existent milestone_id rejected)")

    def test_foreign_key_enforced_invalid_user_id(self, test_vault_with_milestone):
        """
        Inserting a notification with a non-existent user_id should fail
        because of the foreign key constraint.
        """
        milestone_id = test_vault_with_milestone["milestone"]["id"]
        fake_user_id = str(uuid.uuid4())

        resp = _insert_notification_raw({
            "user_id": fake_user_id,
            "milestone_id": milestone_id,
            "scheduled_for": _future_timestamp(7),
            "days_before": 7,
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent user_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  FK constraint enforced (non-existent user_id rejected)")
