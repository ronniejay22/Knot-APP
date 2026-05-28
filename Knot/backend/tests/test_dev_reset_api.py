"""
Step 15.6 Verification: Dev-Only Reset Endpoint

Tests POST /api/v1/users/me/dev-reset — a DEBUG/CI-only escape hatch that
wipes the partner vault and clears scheduled_deletion_at so the iOS app
can re-run the onboarding wizard without signing the user out.

Tests cover:
1. 403 when KNOT_DEV_RESET_ENABLED is unset / false (production safety).
2. 200 happy path when enabled — partner_vaults row removed, CASCADE
   children removed, scheduled_deletion_at cleared.
3. 401 missing / invalid Bearer token.
4. Idempotent second call (no vault to delete still returns 200).
5. Works when the user is currently pending deletion (uses
   get_current_user_id, not get_active_user_id).
6. Module imports + route registration.

Prerequisites:
- Supabase credentials in .env
- Migrations applied through 00024

Run with: pytest tests/test_dev_reset_api.py -v
"""

import pytest
import httpx
import uuid
import time
from datetime import datetime, timezone, timedelta

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Helpers — mirror test_account_deletion_api.py
# ---------------------------------------------------------------------------


def _supabase_configured() -> bool:
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


def _admin_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _service_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }


def _create_auth_user(email: str, password: str) -> str:
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, (
        f"Failed to create test auth user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["id"]


def _delete_auth_user(user_id: str) -> None:
    import warnings
    try:
        resp = httpx.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_admin_headers(),
        )
        if resp.status_code not in (200, 404):
            warnings.warn(
                f"Failed to delete test auth user {user_id}: "
                f"HTTP {resp.status_code} — {resp.text}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}", stacklevel=2
        )


def _sign_in_user(email: str, password: str) -> dict:
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={"email": email, "password": password},
    )
    assert resp.status_code == 200, (
        f"Failed to sign in test user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _query_public_user(user_id: str) -> dict | None:
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/users?select=id,scheduled_deletion_at&id=eq.{user_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200 and resp.json():
        return resp.json()[0]
    return None


def _create_partner_vault(user_id: str) -> str:
    """Insert a minimal partner_vaults row for the user. Returns vault_id."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers={**_service_headers(), "Content-Type": "application/json", "Prefer": "return=representation"},
        json={
            "user_id": user_id,
            "partner_name": "Test Partner",
            "relationship_tenure_months": 12,
            "cohabitation_status": "living_together",
            "location_city": "San Francisco",
            "location_state": "CA",
            "location_country": "US",
        },
    )
    assert resp.status_code == 201, (
        f"Failed to insert partner_vault: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()[0]["id"]


def _query_partner_vault(user_id: str) -> dict | None:
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/partner_vaults?select=id&user_id=eq.{user_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200 and resp.json():
        return resp.json()[0]
    return None


def _count_partner_interests(vault_id: str) -> int:
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/partner_interests?select=id&vault_id=eq.{vault_id}",
        headers=_service_headers(),
    )
    if resp.status_code == 200:
        return len(resp.json())
    return 0


def _insert_interest(vault_id: str, category: str, kind: str = "like") -> None:
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_interests",
        headers={**_service_headers(), "Content-Type": "application/json"},
        json={
            "vault_id": vault_id,
            "interest_type": kind,
            "interest_category": category,
        },
    )
    assert resp.status_code in (201, 200), (
        f"Failed to insert partner_interest: HTTP {resp.status_code} — {resp.text}"
    )


def _set_scheduled_deletion(user_id: str, value) -> None:
    resp = httpx.patch(
        f"{SUPABASE_URL}/rest/v1/users?id=eq.{user_id}",
        headers={**_service_headers(), "Content-Type": "application/json"},
        json={"scheduled_deletion_at": value},
    )
    assert resp.status_code in (200, 204), (
        f"Failed to set scheduled_deletion_at: HTTP {resp.status_code} — {resp.text}"
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def client():
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def test_auth_user(client):
    """Create a test user, sign in, yield credentials. Cleans up via CASCADE."""
    test_email = f"knot-dev-reset-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    yield {
        "id": user_id,
        "email": test_email,
        "access_token": session["access_token"],
    }

    _delete_auth_user(user_id)


@pytest.fixture
def enable_dev_reset(monkeypatch):
    """Force-enable DEV_RESET_ENABLED for the duration of the test."""
    monkeypatch.setattr("app.api.users.DEV_RESET_ENABLED", True)
    yield


@pytest.fixture
def disable_dev_reset(monkeypatch):
    """Force-disable DEV_RESET_ENABLED — simulates production env."""
    monkeypatch.setattr("app.api.users.DEV_RESET_ENABLED", False)
    yield


# ---------------------------------------------------------------------------
# Test: Production safety gate
# ---------------------------------------------------------------------------


@requires_supabase
class TestProductionGate:
    """KNOT_DEV_RESET_ENABLED must be explicitly true. Default is 403."""

    def test_returns_403_when_flag_is_false(self, client, test_auth_user, disable_dev_reset):
        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 403, resp.text
        assert "disabled" in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Test: Happy path
# ---------------------------------------------------------------------------


@requires_supabase
class TestHappyPath:
    """When enabled, dev-reset wipes vault + scheduled_deletion_at."""

    def test_returns_200_with_reset_status(self, client, test_auth_user, enable_dev_reset):
        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data["status"] == "reset"
        assert data["user_id"] == test_auth_user["id"]

    def test_deletes_partner_vault(self, client, test_auth_user, enable_dev_reset):
        user_id = test_auth_user["id"]
        vault_id = _create_partner_vault(user_id)
        time.sleep(0.3)
        assert _query_partner_vault(user_id) is not None, "Vault should exist before reset"

        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        time.sleep(0.3)

        assert _query_partner_vault(user_id) is None, (
            "Vault row should be deleted after dev-reset"
        )
        # Vault was deleted; the FK CASCADE means no interests rows
        # referencing this vault_id can remain.
        assert _count_partner_interests(vault_id) == 0, (
            "CASCADE should have removed all partner_interests rows"
        )

    def test_cascade_removes_child_rows(self, client, test_auth_user, enable_dev_reset):
        """Inserting children and then dev-resetting should remove them via CASCADE."""
        user_id = test_auth_user["id"]
        vault_id = _create_partner_vault(user_id)
        _insert_interest(vault_id, "Travel", kind="like")
        _insert_interest(vault_id, "Cooking", kind="like")
        time.sleep(0.3)
        assert _count_partner_interests(vault_id) == 2

        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200
        time.sleep(0.3)

        assert _count_partner_interests(vault_id) == 0
        assert _query_partner_vault(user_id) is None

    def test_clears_scheduled_deletion_at(self, client, test_auth_user, enable_dev_reset):
        """If the user is in the 60-day grace window, dev-reset clears it."""
        user_id = test_auth_user["id"]
        future = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
        _set_scheduled_deletion(user_id, future)
        time.sleep(0.3)

        before = _query_public_user(user_id)
        assert before is not None
        assert before["scheduled_deletion_at"] is not None

        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        time.sleep(0.3)

        after = _query_public_user(user_id)
        assert after is not None
        assert after["scheduled_deletion_at"] is None, (
            "dev-reset must clear scheduled_deletion_at so the iOS gate releases"
        )

    def test_idempotent_when_no_vault(self, client, test_auth_user, enable_dev_reset):
        """Calling dev-reset twice in a row (no vault to delete) still returns 200."""
        token = test_auth_user["access_token"]
        first = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert first.status_code == 200, first.text

        second = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert second.status_code == 200, second.text
        assert second.json()["status"] == "reset"


# ---------------------------------------------------------------------------
# Test: Auth required
# ---------------------------------------------------------------------------


class TestAuthRequired:
    """Endpoint requires a valid Bearer token even when the dev gate is open."""

    def test_no_auth_header_returns_401(self, client, enable_dev_reset):
        resp = client.post("/api/v1/users/me/dev-reset")
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client, enable_dev_reset):
        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": "Bearer invalid_token_here"},
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Test: Works for pending-deletion users
# ---------------------------------------------------------------------------


@requires_supabase
class TestPendingDeletionUserCanReset:
    """Uses get_current_user_id (not get_active_user_id) so it bypasses the 410 gate."""

    def test_pending_user_can_call_dev_reset(self, client, test_auth_user, enable_dev_reset):
        """A user with scheduled_deletion_at set still gets a 200 (not 410)."""
        user_id = test_auth_user["id"]
        future = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()
        _set_scheduled_deletion(user_id, future)
        time.sleep(0.3)

        # Sanity: any other authed route returns 410 for this user. We don't
        # call one here to keep the test scoped, but the gate is exercised
        # in test_pending_deletion_gate.py.

        resp = client.post(
            "/api/v1/users/me/dev-reset",
            headers={"Authorization": f"Bearer {test_auth_user['access_token']}"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] == "reset"


# ---------------------------------------------------------------------------
# Test: Module imports / route registration
# ---------------------------------------------------------------------------


class TestModuleImports:
    """Wiring sanity checks that don't require Supabase."""

    def test_config_flag_imports(self):
        from app.core.config import DEV_RESET_ENABLED  # noqa: F401

    def test_users_router_has_dev_reset_route(self):
        from app.main import app
        paths = {
            (tuple(sorted(r.methods)) if hasattr(r, "methods") else None, r.path)
            for r in app.routes
            if hasattr(r, "methods")
        }
        assert (("POST",), "/api/v1/users/me/dev-reset") in paths

    def test_existing_routes_still_registered(self):
        """dev-reset must not have shadowed any sibling /me routes."""
        from app.main import app
        paths = {
            (tuple(sorted(r.methods)) if hasattr(r, "methods") else None, r.path)
            for r in app.routes
            if hasattr(r, "methods")
        }
        assert (("DELETE",), "/api/v1/users/me") in paths
        assert (("POST",), "/api/v1/users/me/restore") in paths
        assert (("GET",), "/api/v1/users/me") in paths
