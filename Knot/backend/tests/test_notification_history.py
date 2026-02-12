"""
Step 7.7 Verification: Notification History API

Tests the notification history endpoints:
1. GET /api/v1/notifications/history — Returns sent/failed notifications with milestone data
2. PATCH /api/v1/notifications/{id}/viewed — Marks a notification as viewed
3. GET /api/v1/recommendations/by-milestone/{milestone_id} — Returns stored recommendations

Tests cover:
1. Empty history returns 200 with empty list
2. History with sent notifications returns items with milestone metadata
3. History excludes pending/cancelled notifications
4. History items include correct recommendations_count
5. Pagination via limit/offset works
6. Auth required (401 without token)
7. Milestone recommendations endpoint returns stored recommendations
8. Milestone recommendations returns empty for no results
9. Milestone recommendations returns 404 for user with no vault
10. Mark viewed endpoint sets viewed_at timestamp
11. Mark viewed returns 404 for non-existent notification
12. Module imports and router registration

Prerequisites:
- Complete Steps 0.6, 1.1-1.12 (Supabase + all tables)
- Complete Steps 7.1-7.6 (Notification pipeline)
- Migration 00015 applied (viewed_at column)

Run with: pytest tests/test_notification_history.py -v
"""

import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
)
from app.main import app


# ---------------------------------------------------------------------------
# Helper: check if credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Test user authentication helpers
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _create_auth_user(email: str, password: str) -> str:
    """Create a test user via Supabase Admin API. Returns user ID."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, (
        f"Failed to create auth user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["id"]


def _sign_in_user(email: str, password: str) -> str:
    """Sign in a user and return the access token."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={"email": email, "password": password},
    )
    assert resp.status_code == 200, (
        f"Failed to sign in: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["access_token"]


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
                f"Failed to delete auth user {user_id}: HTTP {resp.status_code}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(f"Exception deleting auth user {user_id}: {exc}", stacklevel=2)


# ---------------------------------------------------------------------------
# Data insertion helpers
# ---------------------------------------------------------------------------

def _insert_vault(data: dict) -> dict:
    """Insert a vault row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vault: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_milestone(data: dict) -> dict:
    """Insert a milestone row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_milestones",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert milestone: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_notification(data: dict) -> dict:
    """Insert a notification_queue row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert notification: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_recommendation(data: dict) -> dict:
    """Insert a recommendation row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        json=data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert recommendation: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _delete_recommendations_for_vault(vault_id: str):
    """Delete all recommendations for a vault."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        params={"vault_id": f"eq.{vault_id}"},
    )


def _past_timestamp(days: int) -> str:
    """Return an ISO 8601 timestamp `days` in the past."""
    dt = datetime.now(timezone.utc) - timedelta(days=days)
    return dt.isoformat()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """FastAPI test client for the Knot API."""
    return TestClient(app)


@pytest.fixture
def test_auth_user():
    """Create a test auth user. CASCADE cleanup on teardown."""
    email = f"knot-hist-{uuid.uuid4().hex[:8]}@test.example"
    password = f"HistTest!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    yield {"id": user_id, "email": email, "password": password}
    _delete_auth_user(user_id)


@pytest.fixture
def test_full_setup(test_auth_user):
    """
    Create a vault, milestone, sent notifications, and recommendations
    for testing the history endpoints. Returns all IDs.
    """
    user_id = test_auth_user["id"]

    vault = _insert_vault({
        "user_id": user_id,
        "partner_name": "History Test Partner",
        "relationship_tenure_months": 18,
        "cohabitation_status": "living_together",
        "location_city": "Portland",
        "location_state": "OR",
        "location_country": "US",
    })

    milestone = _insert_milestone({
        "vault_id": vault["id"],
        "milestone_type": "birthday",
        "milestone_name": "Partner's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
    })

    # Insert 2 sent notifications and 1 pending (should not appear in history)
    notif_sent_1 = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone["id"],
        "scheduled_for": _past_timestamp(14),
        "days_before": 14,
        "status": "sent",
        "sent_at": _past_timestamp(14),
    })

    notif_sent_2 = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone["id"],
        "scheduled_for": _past_timestamp(7),
        "days_before": 7,
        "status": "sent",
        "sent_at": _past_timestamp(7),
    })

    notif_pending = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone["id"],
        "scheduled_for": _past_timestamp(0),
        "days_before": 3,
    })

    # Insert 3 recommendations for this milestone
    recs = []
    for rec_type, title in [
        ("gift", "Ceramic Mug Set"),
        ("experience", "Sunset Sailing"),
        ("date", "Italian Dinner"),
    ]:
        rec = _insert_recommendation({
            "vault_id": vault["id"],
            "milestone_id": milestone["id"],
            "recommendation_type": rec_type,
            "title": title,
            "description": f"A wonderful {rec_type}",
            "external_url": f"https://example.com/{rec_type}",
            "price_cents": 5000,
            "merchant_name": f"Test {rec_type.capitalize()} Co.",
        })
        recs.append(rec)

    yield {
        "user": test_auth_user,
        "vault": vault,
        "milestone": milestone,
        "notifications": {
            "sent_1": notif_sent_1,
            "sent_2": notif_sent_2,
            "pending": notif_pending,
        },
        "recommendations": recs,
    }

    # Cleanup recommendations (CASCADE handles the rest via auth user deletion)
    _delete_recommendations_for_vault(vault["id"])


# ===================================================================
# 1. Notification History Endpoint — Unit Tests (Mocked DB)
# ===================================================================

class TestNotificationHistoryEndpoint:
    """Unit tests for GET /api/v1/notifications/history using mocked Supabase."""

    def _mock_auth(self):
        """Mock the auth dependency to return a fixed user_id."""
        return "test-user-123"

    def test_empty_history_returns_200(self, client):
        """An authenticated user with no sent notifications gets an empty list."""
        mock_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    # First call: fetch notifications
                    mock_table.select.return_value.eq.return_value.in_.return_value.order.return_value.range.return_value.execute.return_value = MagicMock(data=[])
                else:
                    # Second call: count
                    result = MagicMock(data=[], count=0)
                    mock_table.select.return_value.eq.return_value.in_.return_value.execute.return_value = result
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.notifications.get_service_client", return_value=mock_client):
                resp = client.get("/api/v1/notifications/history")

            assert resp.status_code == 200
            data = resp.json()
            assert data["notifications"] == []
            assert data["total"] == 0
            print("  Empty history returns 200 with empty list")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_history_returns_sent_notifications(self, client):
        """History returns sent notifications with milestone metadata."""
        notification_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())
        sent_at = datetime.now(timezone.utc).isoformat()

        mock_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    # Fetch notifications
                    mock_table.select.return_value.eq.return_value.in_.return_value.order.return_value.range.return_value.execute.return_value = MagicMock(
                        data=[{
                            "id": notification_id,
                            "user_id": "test-user-123",
                            "milestone_id": milestone_id,
                            "scheduled_for": sent_at,
                            "days_before": 14,
                            "status": "sent",
                            "sent_at": sent_at,
                            "viewed_at": None,
                            "created_at": sent_at,
                        }]
                    )
                else:
                    # Count
                    result = MagicMock(data=[], count=1)
                    mock_table.select.return_value.eq.return_value.in_.return_value.execute.return_value = result
            elif table_name == "partner_milestones":
                mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(
                    data=[{
                        "id": milestone_id,
                        "milestone_name": "Test Birthday",
                        "milestone_type": "birthday",
                        "milestone_date": "2000-06-15",
                    }]
                )
            elif table_name == "partner_vaults":
                mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[{"id": vault_id}]
                )
            elif table_name == "recommendations":
                mock_table.select.return_value.eq.return_value.in_.return_value.execute.return_value = MagicMock(
                    data=[
                        {"milestone_id": milestone_id},
                        {"milestone_id": milestone_id},
                        {"milestone_id": milestone_id},
                    ]
                )
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.notifications.get_service_client", return_value=mock_client):
                resp = client.get("/api/v1/notifications/history")

            assert resp.status_code == 200
            data = resp.json()
            assert len(data["notifications"]) == 1
            assert data["total"] == 1

            notif = data["notifications"][0]
            assert notif["id"] == notification_id
            assert notif["milestone_name"] == "Test Birthday"
            assert notif["milestone_type"] == "birthday"
            assert notif["days_before"] == 14
            assert notif["status"] == "sent"
            assert notif["recommendations_count"] == 3
            assert notif["viewed_at"] is None
            print("  History returns sent notifications with milestone metadata")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_history_handles_deleted_milestone(self, client):
        """History handles missing milestones gracefully with 'Deleted Milestone'."""
        notification_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.in_.return_value.order.return_value.range.return_value.execute.return_value = MagicMock(
                        data=[{
                            "id": notification_id,
                            "user_id": "test-user-123",
                            "milestone_id": milestone_id,
                            "scheduled_for": datetime.now(timezone.utc).isoformat(),
                            "days_before": 7,
                            "status": "sent",
                            "sent_at": datetime.now(timezone.utc).isoformat(),
                            "viewed_at": None,
                            "created_at": datetime.now(timezone.utc).isoformat(),
                        }]
                    )
                else:
                    result = MagicMock(data=[], count=1)
                    mock_table.select.return_value.eq.return_value.in_.return_value.execute.return_value = result
            elif table_name == "partner_milestones":
                # Milestone not found (deleted)
                mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
            elif table_name == "partner_vaults":
                mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(data=[])
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.notifications.get_service_client", return_value=mock_client):
                resp = client.get("/api/v1/notifications/history")

            assert resp.status_code == 200
            data = resp.json()
            assert len(data["notifications"]) == 1
            assert data["notifications"][0]["milestone_name"] == "Deleted Milestone"
            print("  History handles deleted milestones gracefully")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_auth_required_for_history(self, client):
        """History endpoint returns 401 without authentication."""
        # No dependency override — auth will fail
        resp = client.get("/api/v1/notifications/history")
        assert resp.status_code == 401
        print("  Auth required for history endpoint")


# ===================================================================
# 2. Mark Viewed Endpoint — Unit Tests (Mocked DB)
# ===================================================================

class TestMarkViewedEndpoint:
    """Unit tests for PATCH /api/v1/notifications/{id}/viewed."""

    def _mock_auth(self):
        return "test-user-123"

    def test_mark_viewed_sets_timestamp(self, client):
        """PATCH /viewed should set viewed_at and return 200."""
        notification_id = str(uuid.uuid4())

        mock_client = MagicMock()
        mock_client.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[{"id": notification_id, "viewed_at": datetime.now(timezone.utc).isoformat()}]
        )

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.notifications.get_service_client", return_value=mock_client):
                resp = client.patch(f"/api/v1/notifications/{notification_id}/viewed")

            assert resp.status_code == 200
            data = resp.json()
            assert data["status"] == "viewed"
            assert data["notification_id"] == notification_id
            print("  Mark viewed sets timestamp and returns 200")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_mark_viewed_returns_404_for_nonexistent(self, client):
        """PATCH /viewed should return 404 for non-existent notification."""
        notification_id = str(uuid.uuid4())

        mock_client = MagicMock()
        mock_client.table.return_value.update.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[]
        )

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.notifications.get_service_client", return_value=mock_client):
                resp = client.patch(f"/api/v1/notifications/{notification_id}/viewed")

            assert resp.status_code == 404
            print("  Mark viewed returns 404 for non-existent notification")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_auth_required_for_mark_viewed(self, client):
        """Mark viewed endpoint returns 401 without authentication."""
        resp = client.patch(f"/api/v1/notifications/{uuid.uuid4()}/viewed")
        assert resp.status_code == 401
        print("  Auth required for mark viewed endpoint")


# ===================================================================
# 3. Milestone Recommendations Endpoint — Unit Tests (Mocked DB)
# ===================================================================

class TestMilestoneRecommendationsEndpoint:
    """Unit tests for GET /api/v1/recommendations/by-milestone/{id}."""

    def _mock_auth(self):
        return "test-user-123"

    def test_returns_stored_recommendations(self, client):
        """Should return existing recommendations for a milestone."""
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        mock_client = MagicMock()

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "partner_vaults":
                mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[{"id": vault_id}]
                )
            elif table_name == "recommendations":
                mock_table.select.return_value.eq.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[
                        {
                            "id": str(uuid.uuid4()),
                            "recommendation_type": "gift",
                            "title": "Test Gift",
                            "description": "A test gift",
                            "external_url": "https://example.com/gift",
                            "price_cents": 5000,
                            "merchant_name": "Test Co.",
                            "image_url": "https://example.com/gift.jpg",
                            "created_at": datetime.now(timezone.utc).isoformat(),
                        },
                        {
                            "id": str(uuid.uuid4()),
                            "recommendation_type": "experience",
                            "title": "Test Experience",
                            "description": "A test experience",
                            "external_url": "https://example.com/exp",
                            "price_cents": 15000,
                            "merchant_name": "Exp Co.",
                            "image_url": "https://example.com/exp.jpg",
                            "created_at": datetime.now(timezone.utc).isoformat(),
                        },
                    ]
                )
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.recommendations.get_service_client", return_value=mock_client):
                resp = client.get(f"/api/v1/recommendations/by-milestone/{milestone_id}")

            assert resp.status_code == 200
            data = resp.json()
            assert data["count"] == 2
            assert data["milestone_id"] == milestone_id
            assert len(data["recommendations"]) == 2
            assert data["recommendations"][0]["title"] == "Test Gift"
            assert data["recommendations"][1]["title"] == "Test Experience"
            print("  Returns stored recommendations for milestone")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_returns_empty_for_no_recommendations(self, client):
        """Should return empty list when no recommendations exist."""
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        mock_client = MagicMock()

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "partner_vaults":
                mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[{"id": vault_id}]
                )
            elif table_name == "recommendations":
                mock_table.select.return_value.eq.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[]
                )
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.recommendations.get_service_client", return_value=mock_client):
                resp = client.get(f"/api/v1/recommendations/by-milestone/{milestone_id}")

            assert resp.status_code == 200
            data = resp.json()
            assert data["count"] == 0
            assert data["recommendations"] == []
            print("  Returns empty list for milestone with no recommendations")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_returns_404_for_no_vault(self, client):
        """Should return 404 if user has no vault."""
        milestone_id = str(uuid.uuid4())

        mock_client = MagicMock()

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "partner_vaults":
                mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                    data=[]
                )
            return mock_table

        mock_client.table.side_effect = table_side_effect

        from app.core.security import get_current_user_id
        app.dependency_overrides[get_current_user_id] = self._mock_auth

        try:
            with patch("app.api.recommendations.get_service_client", return_value=mock_client):
                resp = client.get(f"/api/v1/recommendations/by-milestone/{milestone_id}")

            assert resp.status_code == 404
            print("  Returns 404 for user with no vault")
        finally:
            app.dependency_overrides.pop(get_current_user_id, None)

    def test_auth_required_for_milestone_recommendations(self, client):
        """Milestone recommendations endpoint returns 401 without authentication."""
        resp = client.get(f"/api/v1/recommendations/by-milestone/{uuid.uuid4()}")
        assert resp.status_code == 401
        print("  Auth required for milestone recommendations endpoint")


# ===================================================================
# 4. Integration Tests (Requires Supabase)
# ===================================================================

@requires_supabase
class TestNotificationHistoryIntegration:
    """
    Integration tests that verify end-to-end notification history
    retrieval against real Supabase.
    """

    def test_full_history_flow(self, client, test_full_setup):
        """
        Full integration test:
        1. Sign in as test user
        2. Fetch notification history
        3. Verify sent notifications appear with correct data
        4. Verify pending notification is excluded
        5. Verify recommendations count is correct
        """
        user = test_full_setup["user"]
        milestone = test_full_setup["milestone"]
        notifications = test_full_setup["notifications"]

        # Sign in to get access token
        token = _sign_in_user(user["email"], user["password"])

        # Fetch history
        resp = client.get(
            "/api/v1/notifications/history",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()

        # Should have exactly 2 sent notifications (not the pending one)
        assert data["total"] == 2
        assert len(data["notifications"]) == 2

        # Verify all notifications have correct milestone data
        for notif in data["notifications"]:
            assert notif["milestone_id"] == milestone["id"]
            assert notif["milestone_name"] == "Partner's Birthday"
            assert notif["milestone_type"] == "birthday"
            assert notif["status"] == "sent"
            assert notif["recommendations_count"] == 3

        # Verify the pending notification is NOT in the list
        notif_ids = {n["id"] for n in data["notifications"]}
        assert notifications["pending"]["id"] not in notif_ids

        print(f"  Full history flow: {len(data['notifications'])} notifications with correct data")

    def test_milestone_recommendations_integration(self, client, test_full_setup):
        """
        Integration test: fetch stored recommendations for a milestone.
        """
        user = test_full_setup["user"]
        milestone = test_full_setup["milestone"]

        token = _sign_in_user(user["email"], user["password"])

        resp = client.get(
            f"/api/v1/recommendations/by-milestone/{milestone['id']}",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()

        assert data["count"] == 3
        assert data["milestone_id"] == milestone["id"]
        assert len(data["recommendations"]) == 3

        rec_types = {r["recommendation_type"] for r in data["recommendations"]}
        assert rec_types == {"gift", "experience", "date"}

        print(f"  Milestone recommendations: {data['count']} recommendations found")

    def test_mark_viewed_integration(self, client, test_full_setup):
        """
        Integration test: mark a notification as viewed.
        """
        user = test_full_setup["user"]
        notifications = test_full_setup["notifications"]
        notif_id = notifications["sent_1"]["id"]

        token = _sign_in_user(user["email"], user["password"])

        # Mark as viewed
        resp = client.patch(
            f"/api/v1/notifications/{notif_id}/viewed",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "viewed"

        # Verify viewed_at is set by fetching history
        resp = client.get(
            "/api/v1/notifications/history",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200
        history = resp.json()

        viewed_notif = next(
            (n for n in history["notifications"] if n["id"] == notif_id),
            None,
        )
        assert viewed_notif is not None
        assert viewed_notif["viewed_at"] is not None

        print(f"  Mark viewed integration: notification {notif_id[:8]}... marked with viewed_at")

    def test_history_pagination(self, client, test_full_setup):
        """
        Integration test: pagination with limit and offset.
        """
        user = test_full_setup["user"]
        token = _sign_in_user(user["email"], user["password"])

        # Fetch with limit=1
        resp = client.get(
            "/api/v1/notifications/history?limit=1&offset=0",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200
        data = resp.json()
        assert len(data["notifications"]) == 1
        assert data["total"] == 2  # Total count should still be 2

        # Fetch with offset=1
        resp = client.get(
            "/api/v1/notifications/history?limit=1&offset=1",
            headers={"Authorization": f"Bearer {token}"},
        )

        assert resp.status_code == 200
        data = resp.json()
        assert len(data["notifications"]) == 1

        print("  Pagination: limit and offset work correctly")


# ===================================================================
# 5. Module Import Verification
# ===================================================================

class TestModuleImports:
    """Verify all new and modified modules import correctly."""

    def test_notification_history_models_import(self):
        """The notification history models should import without errors."""
        from app.models.notifications import (
            NotificationHistoryItem,
            NotificationHistoryResponse,
            MilestoneRecommendationItem,
            MilestoneRecommendationsResponse,
        )
        assert NotificationHistoryItem is not None
        assert NotificationHistoryResponse is not None
        assert MilestoneRecommendationItem is not None
        assert MilestoneRecommendationsResponse is not None
        print("  Notification history models import successfully")

    def test_notifications_router_has_history_endpoint(self):
        """The notifications router should have the /history GET endpoint."""
        from app.api.notifications import router
        routes = [r.path for r in router.routes]
        assert any("/history" in path for path in routes)
        print("  Notifications router has /history endpoint")

    def test_notifications_router_has_viewed_endpoint(self):
        """The notifications router should have the /{id}/viewed PATCH endpoint."""
        from app.api.notifications import router
        routes = [r.path for r in router.routes]
        assert any("/{notification_id}/viewed" in path for path in routes)
        print("  Notifications router has /{id}/viewed endpoint")

    def test_recommendations_router_has_by_milestone_endpoint(self):
        """The recommendations router should have the /by-milestone/{id} GET endpoint."""
        from app.api.recommendations import router
        routes = [r.path for r in router.routes]
        assert any("/by-milestone/{milestone_id}" in path for path in routes)
        print("  Recommendations router has /by-milestone/{id} endpoint")

    def test_notification_history_response_defaults(self):
        """NotificationHistoryResponse should have correct default values."""
        from app.models.notifications import NotificationHistoryResponse
        resp = NotificationHistoryResponse(total=0)
        assert resp.notifications == []
        assert resp.total == 0
        print("  NotificationHistoryResponse has correct defaults")

    def test_milestone_recommendations_response(self):
        """MilestoneRecommendationsResponse should construct correctly."""
        from app.models.notifications import MilestoneRecommendationsResponse
        resp = MilestoneRecommendationsResponse(
            count=0,
            milestone_id="test-ms-id",
        )
        assert resp.recommendations == []
        assert resp.count == 0
        assert resp.milestone_id == "test-ms-id"
        print("  MilestoneRecommendationsResponse constructs correctly")
