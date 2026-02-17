"""
Step 11.4 Verification: Notification Preferences API

Tests the GET and PUT /api/v1/users/me/notification-preferences endpoints
that allow users to control their notification settings (global toggle,
quiet hours, timezone).

Tests cover:
1. GET returns default preferences for new users
2. PUT updates quiet hours successfully
3. PUT updates notifications_enabled to false/true
4. PUT updates timezone to valid IANA string
5. PUT rejects invalid quiet hours (negative, >23)
6. PUT rejects invalid timezone string
7. GET reflects updated preferences after PUT
8. No auth → 401 on both endpoints
9. Invalid auth → 401 on both endpoints
10. Partial update preserves other fields
11. Module imports and route registration
12. Webhook skips notification when notifications_enabled is false

Prerequisites:
- Supabase credentials in .env
- All migrations applied (through 00019)
- Step 2.5 auth middleware working

Run with: pytest tests/test_notification_preferences_api.py -v
"""

import hashlib
import json
import time
import uuid
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
import httpx

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
# Helpers: auth user management
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


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
                f"HTTP {resp.status_code} — {resp.text}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}",
            stacklevel=2,
        )


def _sign_in_user(email: str, password: str) -> dict:
    """Sign in a test user. Returns full session response with access_token."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={
            "email": email,
            "password": password,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to sign in test user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


# ---------------------------------------------------------------------------
# QStash test signing helper
# ---------------------------------------------------------------------------

TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"


def _build_qstash_signature(body: dict, url: str) -> str:
    """Build a valid QStash JWT signature for testing."""
    body_bytes = json.dumps(body).encode()
    body_hash = hashlib.sha256(body_bytes).hexdigest()
    now = int(time.time())

    payload = {
        "iss": "Upstash",
        "sub": url,
        "exp": now + 300,
        "nbf": now - 10,
        "iat": now,
        "jti": str(uuid.uuid4()),
        "body": body_hash,
    }

    return jwt.encode(payload, TEST_SIGNING_KEY, algorithm="HS256")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def test_auth_user():
    """Create a test user, sign in, and yield context. Auto-cleans up."""
    test_email = f"knot-notifpref-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


# ---------------------------------------------------------------------------
# Test: GET Default Preferences
# ---------------------------------------------------------------------------

@requires_supabase
class TestGetDefaultPreferences:
    """GET /api/v1/users/me/notification-preferences returns defaults for new users."""

    def test_get_returns_200(self, client, test_auth_user):
        """Endpoint returns 200 for authenticated users."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200

    def test_default_notifications_enabled(self, client, test_auth_user):
        """notifications_enabled defaults to true."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["notifications_enabled"] is True

    def test_default_quiet_hours(self, client, test_auth_user):
        """quiet_hours_start defaults to 22 and quiet_hours_end defaults to 8."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["quiet_hours_start"] == 22
        assert data["quiet_hours_end"] == 8

    def test_default_timezone_is_null(self, client, test_auth_user):
        """timezone defaults to null (inferred from location)."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        data = resp.json()
        assert data["timezone"] is None


# ---------------------------------------------------------------------------
# Test: PUT Update Preferences
# ---------------------------------------------------------------------------

@requires_supabase
class TestUpdatePreferences:
    """PUT /api/v1/users/me/notification-preferences updates settings."""

    def test_update_quiet_hours(self, client, test_auth_user):
        """Updating quiet hours returns updated values."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"quiet_hours_start": 21, "quiet_hours_end": 7},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["quiet_hours_start"] == 21
        assert data["quiet_hours_end"] == 7

    def test_update_notifications_disabled(self, client, test_auth_user):
        """Disabling notifications returns notifications_enabled=false."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"notifications_enabled": False},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["notifications_enabled"] is False

    def test_update_notifications_reenabled(self, client, test_auth_user):
        """Re-enabling notifications works after disabling."""
        token = test_auth_user["access_token"]
        # Disable
        client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
            json={"notifications_enabled": False},
        )
        # Re-enable
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
            json={"notifications_enabled": True},
        )
        assert resp.status_code == 200
        assert resp.json()["notifications_enabled"] is True

    def test_update_timezone(self, client, test_auth_user):
        """Setting a valid timezone stores and returns it."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"timezone": "America/Chicago"},
        )
        assert resp.status_code == 200
        assert resp.json()["timezone"] == "America/Chicago"

    def test_partial_update_preserves_other_fields(self, client, test_auth_user):
        """Updating only one field preserves other fields."""
        token = test_auth_user["access_token"]
        # First update quiet hours
        client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
            json={"quiet_hours_start": 20, "quiet_hours_end": 6},
        )
        # Then update only notifications_enabled
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
            json={"notifications_enabled": False},
        )
        data = resp.json()
        # quiet hours should be preserved
        assert data["quiet_hours_start"] == 20
        assert data["quiet_hours_end"] == 6
        assert data["notifications_enabled"] is False

    def test_get_reflects_put_changes(self, client, test_auth_user):
        """GET returns updated values after PUT."""
        token = test_auth_user["access_token"]
        client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "notifications_enabled": False,
                "quiet_hours_start": 23,
                "quiet_hours_end": 9,
                "timezone": "America/Los_Angeles",
            },
        )
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {token}"},
        )
        data = resp.json()
        assert data["notifications_enabled"] is False
        assert data["quiet_hours_start"] == 23
        assert data["quiet_hours_end"] == 9
        assert data["timezone"] == "America/Los_Angeles"


# ---------------------------------------------------------------------------
# Test: Validation
# ---------------------------------------------------------------------------

@requires_supabase
class TestValidation:
    """PUT rejects invalid field values."""

    def test_reject_negative_quiet_hours_start(self, client, test_auth_user):
        """Negative quiet_hours_start is rejected."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"quiet_hours_start": -1},
        )
        assert resp.status_code == 422

    def test_reject_quiet_hours_start_above_23(self, client, test_auth_user):
        """quiet_hours_start > 23 is rejected."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"quiet_hours_start": 24},
        )
        assert resp.status_code == 422

    def test_reject_negative_quiet_hours_end(self, client, test_auth_user):
        """Negative quiet_hours_end is rejected."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"quiet_hours_end": -5},
        )
        assert resp.status_code == 422

    def test_reject_quiet_hours_end_above_23(self, client, test_auth_user):
        """quiet_hours_end > 23 is rejected."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"quiet_hours_end": 25},
        )
        assert resp.status_code == 422

    def test_reject_invalid_timezone(self, client, test_auth_user):
        """Invalid timezone string is rejected."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
            json={"timezone": "Not/A/Timezone"},
        )
        assert resp.status_code == 422


# ---------------------------------------------------------------------------
# Test: Authentication Required
# ---------------------------------------------------------------------------

@requires_supabase
class TestAuthRequired:
    """Both endpoints require valid Bearer token."""

    def test_get_no_auth_returns_401(self, client):
        """GET without auth header returns 401."""
        resp = client.get("/api/v1/users/me/notification-preferences")
        assert resp.status_code == 401

    def test_get_invalid_token_returns_401(self, client):
        """GET with invalid token returns 401."""
        resp = client.get(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": "Bearer invalid_token"},
        )
        assert resp.status_code == 401

    def test_put_no_auth_returns_401(self, client):
        """PUT without auth header returns 401."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            json={"notifications_enabled": False},
        )
        assert resp.status_code == 401

    def test_put_invalid_token_returns_401(self, client):
        """PUT with invalid token returns 401."""
        resp = client.put(
            "/api/v1/users/me/notification-preferences",
            headers={"Authorization": "Bearer invalid_token"},
            json={"notifications_enabled": False},
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Test: Module Imports & Route Registration
# ---------------------------------------------------------------------------

class TestModuleImports:
    """Verify all new modules are importable and registered."""

    def test_preferences_response_import(self):
        """NotificationPreferencesResponse is importable."""
        from app.models.users import NotificationPreferencesResponse
        assert NotificationPreferencesResponse is not None

    def test_preferences_request_import(self):
        """NotificationPreferencesRequest is importable."""
        from app.models.users import NotificationPreferencesRequest
        assert NotificationPreferencesRequest is not None

    def test_preferences_response_structure(self):
        """NotificationPreferencesResponse has expected fields."""
        from app.models.users import NotificationPreferencesResponse
        resp = NotificationPreferencesResponse(
            notifications_enabled=True,
            quiet_hours_start=22,
            quiet_hours_end=8,
            timezone=None,
        )
        assert resp.notifications_enabled is True
        assert resp.quiet_hours_start == 22
        assert resp.quiet_hours_end == 8
        assert resp.timezone is None

    def test_preferences_request_partial(self):
        """NotificationPreferencesRequest allows partial payloads."""
        from app.models.users import NotificationPreferencesRequest
        req = NotificationPreferencesRequest(quiet_hours_start=20)
        assert req.quiet_hours_start == 20
        assert req.notifications_enabled is None
        assert req.quiet_hours_end is None

    def test_get_route_registered(self):
        """GET /api/v1/users/me/notification-preferences is registered."""
        from app.main import app
        get_routes = [
            route.path
            for route in app.routes
            if hasattr(route, "methods") and "GET" in route.methods
        ]
        assert "/api/v1/users/me/notification-preferences" in get_routes

    def test_put_route_registered(self):
        """PUT /api/v1/users/me/notification-preferences is registered."""
        from app.main import app
        put_routes = [
            route.path
            for route in app.routes
            if hasattr(route, "methods") and "PUT" in route.methods
        ]
        assert "/api/v1/users/me/notification-preferences" in put_routes

    def test_existing_routes_still_registered(self):
        """Existing user routes are still registered."""
        from app.main import app
        routes = [route.path for route in app.routes]
        assert "/api/v1/users/device-token" in routes
        assert "/api/v1/users/me" in routes
        assert "/api/v1/users/me/export" in routes


# ---------------------------------------------------------------------------
# Test: Webhook Integration — Notifications Disabled Skips Processing
# ---------------------------------------------------------------------------

class TestWebhookNotificationsDisabled:
    """Webhook skips processing when user has notifications disabled."""

    def test_webhook_skips_when_notifications_disabled(self, client):
        """Webhook returns 'skipped' when notifications_enabled is false."""
        test_user_id = str(uuid.uuid4())
        test_notif_id = str(uuid.uuid4())
        test_milestone_id = str(uuid.uuid4())

        webhook_url = "http://testserver/api/v1/notifications/process"
        body_payload = {
            "notification_id": test_notif_id,
            "user_id": test_user_id,
            "milestone_id": test_milestone_id,
            "days_before": 7,
        }
        signature = _build_qstash_signature(body_payload, webhook_url)

        # Mock the DB calls: notification exists + pending, user has notifications disabled
        mock_notif_data = [{
            "id": test_notif_id,
            "user_id": test_user_id,
            "milestone_id": test_milestone_id,
            "scheduled_for": datetime.now(timezone.utc).isoformat(),
            "days_before": 7,
            "status": "pending",
        }]

        mock_user_data = [{
            "quiet_hours_start": 22,
            "quiet_hours_end": 8,
            "timezone": None,
            "notifications_enabled": False,
        }]

        with patch("app.api.notifications.verify_qstash_signature"):
            with patch("app.services.dnd.get_service_client") as mock_dnd_client:
                with patch("app.api.notifications.get_service_client") as mock_notif_client:
                    # Mock notification lookup
                    mock_table = MagicMock()
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=mock_notif_data
                    )
                    # Mock notification status update
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
                    mock_notif_client.return_value.table.return_value = mock_table

                    # Mock DND user lookup (notifications disabled)
                    mock_dnd_table = MagicMock()
                    mock_dnd_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=mock_user_data
                    )
                    mock_dnd_client.return_value.table.return_value = mock_dnd_table

                    resp = client.post(
                        "/api/v1/notifications/process",
                        content=json.dumps(body_payload),
                        headers={
                            "Content-Type": "application/json",
                            "Upstash-Signature": signature,
                        },
                    )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "skipped"
        assert "disabled" in data["message"].lower()

    def test_webhook_processes_when_notifications_enabled(self, client):
        """Webhook processes normally when notifications_enabled is true."""
        test_user_id = str(uuid.uuid4())
        test_notif_id = str(uuid.uuid4())
        test_milestone_id = str(uuid.uuid4())

        webhook_url = "http://testserver/api/v1/notifications/process"
        body_payload = {
            "notification_id": test_notif_id,
            "user_id": test_user_id,
            "milestone_id": test_milestone_id,
            "days_before": 7,
        }
        signature = _build_qstash_signature(body_payload, webhook_url)

        mock_notif_data = [{
            "id": test_notif_id,
            "user_id": test_user_id,
            "milestone_id": test_milestone_id,
            "scheduled_for": datetime.now(timezone.utc).isoformat(),
            "days_before": 7,
            "status": "pending",
        }]

        with patch("app.api.notifications.verify_qstash_signature"):
            with patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock) as mock_dnd:
                # Return: not in quiet hours, no reschedule time, notifications enabled
                mock_dnd.return_value = (False, None, True)
                with patch("app.api.notifications.get_service_client") as mock_notif_client:
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_vault:
                        mock_vault.side_effect = Exception("No vault")

                        # Mock notification lookup + update
                        mock_table = MagicMock()
                        mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                            data=mock_notif_data
                        )
                        mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
                        mock_notif_client.return_value.table.return_value = mock_table

                        resp = client.post(
                            "/api/v1/notifications/process",
                            content=json.dumps(body_payload),
                            headers={
                                "Content-Type": "application/json",
                                "Upstash-Signature": signature,
                            },
                        )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
