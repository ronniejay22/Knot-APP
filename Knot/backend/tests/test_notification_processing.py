"""
Step 7.3 Verification: Notification Processing with Recommendation Generation

Tests that:
1. The vault_loader service correctly loads vault data and milestone context
2. The find_budget_range helper returns correct results with fallbacks
3. Processing a pending notification generates recommendations via the pipeline
4. Generated recommendations are stored in the database with correct milestone_id
5. Pipeline failure does not prevent the notification from being marked as 'sent'
6. Pipeline returning empty results still marks notification as 'sent'
7. Pipeline error state still marks notification as 'sent'
8. Vault not found still marks notification as 'sent' (graceful degradation)
9. The response includes the recommendations_generated count

Prerequisites:
- Complete Steps 0.6, 1.1-1.11 (Supabase + tables including notification_queue)
- Complete Steps 7.1 and 7.2 (QStash webhook and scheduling)
- PyJWT installed in the virtual environment

Run with: pytest tests/test_notification_processing.py -v
"""

import hashlib
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
import httpx
from fastapi.testclient import TestClient

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    VaultBudget,
    VaultData,
)
from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
)
from app.main import app
from app.services.vault_loader import (
    find_budget_range,
    load_milestone_context,
    load_vault_data,
)


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
# Test signing key — used for unit tests
# ---------------------------------------------------------------------------

TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"


# ---------------------------------------------------------------------------
# Mock data factories
# ---------------------------------------------------------------------------

def _mock_vault_data(vault_id: str = "vault-123") -> VaultData:
    """Create a mock VaultData for testing."""
    return VaultData(
        vault_id=vault_id,
        partner_name="Test Partner",
        relationship_tenure_months=24,
        cohabitation_status="living_together",
        location_city="Austin",
        location_state="TX",
        location_country="US",
        interests=["cooking", "hiking", "music", "photography", "travel"],
        dislikes=["sports", "gaming", "fishing", "hunting", "cars"],
        vibes=["cozy", "adventurous"],
        primary_love_language="quality_time",
        secondary_love_language="acts_of_service",
        budgets=[
            VaultBudget(occasion_type="just_because", min_amount=2000, max_amount=5000),
            VaultBudget(occasion_type="minor_occasion", min_amount=5000, max_amount=15000),
            VaultBudget(occasion_type="major_milestone", min_amount=10000, max_amount=50000),
        ],
    )


def _mock_candidates() -> list[CandidateRecommendation]:
    """Create 3 mock recommendation candidates."""
    return [
        CandidateRecommendation(
            id="rec-001",
            source="amazon",
            type="gift",
            title="Ceramic Mug Set",
            description="Handmade ceramic mugs",
            price_cents=4500,
            currency="USD",
            external_url="https://example.com/mugs",
            image_url="https://example.com/mugs.jpg",
            merchant_name="Artisan Co.",
            interest_score=0.85,
            vibe_score=0.78,
            love_language_score=0.72,
            final_score=0.80,
        ),
        CandidateRecommendation(
            id="rec-002",
            source="yelp",
            type="experience",
            title="Sunset Sailing",
            description="Private sailing trip",
            price_cents=24900,
            currency="USD",
            external_url="https://example.com/sailing",
            image_url="https://example.com/sailing.jpg",
            merchant_name="Bay Sailing Co.",
            interest_score=0.90,
            vibe_score=0.85,
            love_language_score=0.70,
            final_score=0.83,
        ),
        CandidateRecommendation(
            id="rec-003",
            source="yelp",
            type="date",
            title="Italian Dinner",
            description="Intimate 5-course dinner",
            price_cents=18000,
            currency="USD",
            external_url="https://example.com/dinner",
            image_url="https://example.com/dinner.jpg",
            merchant_name="Trattoria Luna",
            interest_score=0.75,
            vibe_score=0.92,
            love_language_score=0.88,
            final_score=0.84,
        ),
    ]


# ---------------------------------------------------------------------------
# Helpers: QStash signature generation
# ---------------------------------------------------------------------------

def _create_qstash_signature(
    body: bytes,
    url: str,
    signing_key: str = TEST_SIGNING_KEY,
) -> str:
    """Create a QStash-compatible JWT signature for testing."""
    now = int(time.time())
    body_hash = hashlib.sha256(body).hexdigest()

    claims = {
        "iss": "Upstash",
        "sub": url,
        "exp": now + 3600,
        "nbf": now - 60,
        "iat": now,
        "jti": f"msg_{uuid.uuid4().hex[:16]}",
        "body": body_hash,
    }

    return jwt.encode(claims, signing_key, algorithm="HS256")


# ---------------------------------------------------------------------------
# Helpers: Supabase admin operations (for integration tests)
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


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
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, (
        f"Failed to create auth user: HTTP {resp.status_code} — {resp.text}"
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
                f"Failed to delete auth user {user_id}: HTTP {resp.status_code}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(f"Exception deleting auth user {user_id}: {exc}", stacklevel=2)


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


def _get_notification(notif_id: str) -> dict | None:
    """Fetch a notification_queue row by ID. Returns None if not found."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        params={"id": f"eq.{notif_id}", "select": "*"},
    )
    assert resp.status_code == 200
    rows = resp.json()
    return rows[0] if rows else None


def _get_recommendations_for_milestone(milestone_id: str) -> list[dict]:
    """Fetch all recommendations linked to a milestone."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        params={"milestone_id": f"eq.{milestone_id}", "select": "*"},
    )
    assert resp.status_code == 200
    return resp.json()


def _delete_recommendations_for_milestone(milestone_id: str):
    """Delete all recommendations linked to a milestone."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        params={"milestone_id": f"eq.{milestone_id}"},
    )


def _future_timestamp(days: int) -> str:
    """Return an ISO 8601 timestamp `days` in the future."""
    dt = datetime.now(timezone.utc) + timedelta(days=days)
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
    email = f"knot-notif-proc-{uuid.uuid4().hex[:8]}@test.example"
    password = f"NotifTest!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    yield {"id": user_id, "email": email}
    _delete_auth_user(user_id)


@pytest.fixture
def test_full_setup(test_auth_user):
    """
    Create a vault, milestone, and pending notification for testing.
    Returns all IDs needed for webhook payload construction.
    """
    user_id = test_auth_user["id"]

    vault = _insert_vault({
        "user_id": user_id,
        "partner_name": "Notification Test Partner",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
    })

    milestone = _insert_milestone({
        "vault_id": vault["id"],
        "milestone_type": "birthday",
        "milestone_name": "Partner's Birthday",
        "milestone_date": "2000-06-15",
        "recurrence": "yearly",
    })

    notification = _insert_notification({
        "user_id": user_id,
        "milestone_id": milestone["id"],
        "scheduled_for": _future_timestamp(14),
        "days_before": 14,
    })

    yield {
        "user": test_auth_user,
        "vault": vault,
        "milestone": milestone,
        "notification": notification,
    }

    # Clean up recommendations created during test
    _delete_recommendations_for_milestone(milestone["id"])
    # CASCADE cleanup via auth user deletion handles the rest


# ===================================================================
# 1. Vault Loader Unit Tests
# ===================================================================

class TestVaultLoader:
    """Unit tests for the vault_loader service functions."""

    def test_find_budget_range_matches_occasion(self):
        """Should return the matching budget for the occasion type."""
        budgets = [
            VaultBudget(occasion_type="just_because", min_amount=1000, max_amount=3000),
            VaultBudget(occasion_type="minor_occasion", min_amount=5000, max_amount=10000),
            VaultBudget(occasion_type="major_milestone", min_amount=15000, max_amount=50000),
        ]

        result = find_budget_range(budgets, "minor_occasion")
        assert result.min_amount == 5000
        assert result.max_amount == 10000
        print("  find_budget_range returns matching budget")

    def test_find_budget_range_uses_fallback(self):
        """Should use default range when no matching budget found."""
        result = find_budget_range([], "just_because")
        assert result.min_amount == 2000
        assert result.max_amount == 5000
        print("  find_budget_range uses fallback defaults")

    def test_find_budget_range_fallback_major_milestone(self):
        """Should use correct fallback for major_milestone."""
        result = find_budget_range([], "major_milestone")
        assert result.min_amount == 10000
        assert result.max_amount == 50000
        print("  find_budget_range fallback for major_milestone correct")

    def test_find_budget_range_preserves_currency(self):
        """Should preserve the currency from the vault budget."""
        budgets = [
            VaultBudget(
                occasion_type="just_because",
                min_amount=2000,
                max_amount=5000,
                currency="GBP",
            ),
        ]

        result = find_budget_range(budgets, "just_because")
        assert result.currency == "GBP"
        print("  find_budget_range preserves currency")

    def test_find_budget_range_unknown_occasion_uses_generic_fallback(self):
        """Should use generic fallback for unknown occasion types."""
        result = find_budget_range([], "unknown_type")
        assert result.min_amount == 2000
        assert result.max_amount == 10000
        print("  find_budget_range uses generic fallback for unknown occasion")


# ===================================================================
# 2. Notification Processing with Recommendations (Unit Tests)
# ===================================================================

class TestNotificationRecommendationGeneration:
    """
    Unit tests for the enhanced notification processing endpoint.
    Uses mocks for QStash signature, vault loading, and pipeline.
    """

    def _build_signed_request(self, payload: dict) -> tuple[bytes, str]:
        """Build a signed QStash webhook request."""
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)
        return body, signature

    def _mock_notification_lookup(self, mock_client, notification_id: str, status: str = "pending"):
        """Configure mock Supabase client for notification lookup."""
        mock_table = MagicMock()
        mock_select = MagicMock()
        mock_eq = MagicMock()
        mock_execute = MagicMock()

        mock_execute.execute.return_value = MagicMock(
            data=[{
                "id": notification_id,
                "status": status,
                "user_id": "user-123",
                "milestone_id": "milestone-123",
                "days_before": 14,
            }]
        )

        mock_client.table.return_value = mock_table
        mock_table.select.return_value = mock_select
        mock_select.eq.return_value = mock_eq
        mock_eq.execute = mock_execute.execute

        return mock_client

    def test_processing_generates_recommendations(self, client):
        """
        A valid webhook call should generate 3 recommendations
        and include recommendations_generated=3 in the response.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 14,
        }
        body, signature = self._build_signed_request(payload)

        mock_vault_data = _mock_vault_data(vault_id)
        mock_milestone_ctx = MilestoneContext(
            id=milestone_id,
            milestone_type="birthday",
            milestone_name="Partner's Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
        )
        mock_candidates = _mock_candidates()

        # Build the chain of mock Supabase calls
        mock_db_client = MagicMock()

        # Call 1: notification_queue.select → returns pending notification
        notif_select_result = MagicMock()
        notif_select_result.data = [{
            "id": notification_id,
            "status": "pending",
        }]

        # Call 2: recommendations.insert → returns stored rows
        rec_insert_result = MagicMock()
        rec_insert_result.data = [{"id": f"db-rec-{i}"} for i in range(3)]

        # Call 3: notification_queue.update → returns updated row
        notif_update_result = MagicMock()
        notif_update_result.data = [{"id": notification_id, "status": "sent"}]

        # Configure the mock table calls
        call_count = {"n": 0}
        original_table = mock_db_client.table

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    # First call: select for lookup
                    mock_table.select.return_value.eq.return_value.execute.return_value = notif_select_result
                else:
                    # Second call: update for status change
                    mock_table.update.return_value.eq.return_value.execute.return_value = notif_update_result
            elif table_name == "recommendations":
                mock_table.insert.return_value.execute.return_value = rec_insert_result
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (mock_vault_data, vault_id)
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = mock_milestone_ctx
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.return_value = {
                                    "final_three": mock_candidates,
                                    "error": None,
                                }
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 3
        print("  Processing generates 3 recommendations")

    def test_pipeline_failure_still_marks_sent(self, client):
        """
        If the recommendation pipeline raises an exception, the notification
        should still be marked as 'sent' with recommendations_generated=0.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 7,
        }
        body, signature = self._build_signed_request(payload)

        mock_vault_data = _mock_vault_data(vault_id)
        mock_milestone_ctx = MilestoneContext(
            id=milestone_id,
            milestone_type="birthday",
            milestone_name="Partner's Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
        )

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (mock_vault_data, vault_id)
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = mock_milestone_ctx
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.side_effect = RuntimeError("Pipeline crashed")
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 0
        print("  Pipeline failure still marks notification as sent")

    def test_pipeline_empty_results_still_marks_sent(self, client):
        """
        If the pipeline returns empty final_three, the notification
        should still be marked as 'sent' with recommendations_generated=0.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 3,
        }
        body, signature = self._build_signed_request(payload)

        mock_vault_data = _mock_vault_data(vault_id)
        mock_milestone_ctx = MilestoneContext(
            id=milestone_id,
            milestone_type="birthday",
            milestone_name="Partner's Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
        )

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (mock_vault_data, vault_id)
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = mock_milestone_ctx
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.return_value = {
                                    "final_three": [],
                                    "error": None,
                                }
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 0
        print("  Empty pipeline results still marks notification as sent")

    def test_pipeline_error_state_still_marks_sent(self, client):
        """
        If the pipeline returns an error in the result dict, the notification
        should still be marked as 'sent' with recommendations_generated=0.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 14,
        }
        body, signature = self._build_signed_request(payload)

        mock_vault_data = _mock_vault_data(vault_id)
        mock_milestone_ctx = MilestoneContext(
            id=milestone_id,
            milestone_type="birthday",
            milestone_name="Partner's Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
        )

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (mock_vault_data, vault_id)
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = mock_milestone_ctx
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.return_value = {
                                    "final_three": [],
                                    "error": "No candidates found after filtering",
                                }
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 0
        print("  Pipeline error state still marks notification as sent")

    def test_vault_not_found_still_marks_sent(self, client):
        """
        If load_vault_data raises ValueError (no vault), the notification
        should still be marked as 'sent' with recommendations_generated=0.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 14,
        }
        body, signature = self._build_signed_request(payload)

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.side_effect = ValueError("No partner vault found")
                        resp = client.post(
                            "/api/v1/notifications/process",
                            content=body,
                            headers={
                                "Upstash-Signature": signature,
                                "Content-Type": "application/json",
                            },
                        )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 0
        print("  Vault not found still marks notification as sent")

    def test_milestone_not_found_still_marks_sent(self, client):
        """
        If load_milestone_context returns None (milestone deleted), the
        notification should still be marked as 'sent'.
        """
        notification_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())
        vault_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": 7,
        }
        body, signature = self._build_signed_request(payload)

        mock_vault_data = _mock_vault_data(vault_id)

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (mock_vault_data, vault_id)
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = None
                            resp = client.post(
                                "/api/v1/notifications/process",
                                content=body,
                                headers={
                                    "Upstash-Signature": signature,
                                    "Content-Type": "application/json",
                                },
                            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 0
        print("  Milestone not found still marks notification as sent")

    def test_response_includes_recommendations_count(self, client):
        """
        The JSON response should always include the recommendations_generated field.
        """
        notification_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 14,
        }
        body, signature = self._build_signed_request(payload)

        mock_db_client = MagicMock()
        call_count = {"n": 0}

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                call_count["n"] += 1
                if call_count["n"] == 1:
                    mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "pending"}]
                    )
                else:
                    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
                        data=[{"id": notification_id, "status": "sent"}]
                    )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.side_effect = ValueError("No vault")
                        resp = client.post(
                            "/api/v1/notifications/process",
                            content=body,
                            headers={
                                "Upstash-Signature": signature,
                                "Content-Type": "application/json",
                            },
                        )

        assert resp.status_code == 200
        data = resp.json()
        assert "recommendations_generated" in data
        assert isinstance(data["recommendations_generated"], int)
        print("  Response always includes recommendations_generated field")

    def test_skipped_notification_has_zero_recommendations(self, client):
        """
        When a notification is already processed (skipped), the response
        should include recommendations_generated=0.
        """
        notification_id = str(uuid.uuid4())

        payload = {
            "notification_id": notification_id,
            "user_id": str(uuid.uuid4()),
            "milestone_id": str(uuid.uuid4()),
            "days_before": 14,
        }
        body, signature = self._build_signed_request(payload)

        mock_db_client = MagicMock()

        def table_side_effect(table_name):
            mock_table = MagicMock()
            if table_name == "notification_queue":
                mock_table.select.return_value.eq.return_value.execute.return_value = MagicMock(
                    data=[{"id": notification_id, "status": "sent"}]
                )
            return mock_table

        mock_db_client.table.side_effect = table_side_effect

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.get_service_client", return_value=mock_db_client):
                    resp = client.post(
                        "/api/v1/notifications/process",
                        content=body,
                        headers={
                            "Upstash-Signature": signature,
                            "Content-Type": "application/json",
                        },
                    )

        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "skipped"
        assert data["recommendations_generated"] == 0
        print("  Skipped notification has recommendations_generated=0")


# ===================================================================
# 3. Integration Tests (Requires Supabase)
# ===================================================================

@requires_supabase
class TestNotificationRecommendationIntegration:
    """
    Integration tests that verify end-to-end notification processing
    with recommendation generation against real Supabase.
    """

    def test_full_processing_stores_recommendations(self, client, test_full_setup):
        """
        Processing a notification with a mocked pipeline should store
        the recommendations in the database and update notification status.
        """
        notif = test_full_setup["notification"]
        user = test_full_setup["user"]
        milestone = test_full_setup["milestone"]

        payload = {
            "notification_id": notif["id"],
            "user_id": user["id"],
            "milestone_id": milestone["id"],
            "days_before": 14,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        mock_candidates = _mock_candidates()

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock) as mock_dnd:
                    mock_dnd.return_value = (False, None, True)
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (
                            _mock_vault_data(test_full_setup["vault"]["id"]),
                            test_full_setup["vault"]["id"],
                        )
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = MilestoneContext(
                                id=milestone["id"],
                                milestone_type="birthday",
                                milestone_name="Partner's Birthday",
                                milestone_date="2000-06-15",
                                recurrence="yearly",
                                budget_tier="major_milestone",
                            )
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.return_value = {
                                    "final_three": mock_candidates,
                                    "error": None,
                                }
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["status"] == "processed"
        assert data["recommendations_generated"] == 3

        # Verify notification status updated in DB
        updated = _get_notification(notif["id"])
        assert updated is not None
        assert updated["status"] == "sent"
        assert updated["sent_at"] is not None

        # Verify recommendations stored in DB
        recs = _get_recommendations_for_milestone(milestone["id"])
        assert len(recs) == 3

        rec_types = {r["recommendation_type"] for r in recs}
        assert rec_types == {"gift", "experience", "date"}

        print(f"  Full processing stored 3 recommendations for milestone {milestone['id'][:8]}...")

    def test_recommendations_linked_to_correct_milestone(self, client, test_full_setup):
        """
        Generated recommendations should be linked to the correct
        milestone_id and vault_id in the database.
        """
        notif = test_full_setup["notification"]
        user = test_full_setup["user"]
        milestone = test_full_setup["milestone"]
        vault = test_full_setup["vault"]

        payload = {
            "notification_id": notif["id"],
            "user_id": user["id"],
            "milestone_id": milestone["id"],
            "days_before": 7,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        mock_candidates = _mock_candidates()

        with patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY):
            with patch("app.services.qstash.QSTASH_NEXT_SIGNING_KEY", ""):
                with patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock) as mock_dnd:
                    mock_dnd.return_value = (False, None, True)
                    with patch("app.api.notifications.load_vault_data", new_callable=AsyncMock) as mock_load:
                        mock_load.return_value = (
                            _mock_vault_data(vault["id"]),
                            vault["id"],
                        )
                        with patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock) as mock_ms:
                            mock_ms.return_value = MilestoneContext(
                                id=milestone["id"],
                                milestone_type="birthday",
                                milestone_name="Partner's Birthday",
                                milestone_date="2000-06-15",
                                recurrence="yearly",
                                budget_tier="major_milestone",
                            )
                            with patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock) as mock_pipeline:
                                mock_pipeline.return_value = {
                                    "final_three": mock_candidates,
                                    "error": None,
                                }
                                resp = client.post(
                                    "/api/v1/notifications/process",
                                    content=body,
                                    headers={
                                        "Upstash-Signature": signature,
                                        "Content-Type": "application/json",
                                    },
                                )

        assert resp.status_code == 200

        recs = _get_recommendations_for_milestone(milestone["id"])
        assert len(recs) >= 3

        for rec in recs:
            assert rec["milestone_id"] == milestone["id"]
            assert rec["vault_id"] == vault["id"]

        print(f"  Recommendations correctly linked to milestone {milestone['id'][:8]}... and vault {vault['id'][:8]}...")


# ===================================================================
# 4. Module Import Verification
# ===================================================================

class TestModuleImports:
    """Verify all new and modified modules import correctly."""

    def test_vault_loader_imports(self):
        """The vault_loader module should import without errors."""
        from app.services.vault_loader import (
            load_vault_data,
            load_milestone_context,
            find_budget_range,
        )
        assert callable(load_vault_data)
        assert callable(load_milestone_context)
        assert callable(find_budget_range)
        print("  app.services.vault_loader imports successfully")

    def test_notifications_imports_pipeline(self):
        """The notifications module should import pipeline dependencies."""
        from app.api.notifications import router
        assert router is not None
        assert router.prefix == "/api/v1/notifications"
        print("  app.api.notifications imports pipeline dependencies")

    def test_notification_response_has_recommendations_field(self):
        """The NotificationProcessResponse should have recommendations_generated."""
        from app.models.notifications import NotificationProcessResponse

        resp = NotificationProcessResponse(
            status="processed",
            notification_id="test-id",
            message="Test",
        )
        assert resp.recommendations_generated == 0

        resp_with_recs = NotificationProcessResponse(
            status="processed",
            notification_id="test-id",
            message="Test",
            recommendations_generated=3,
        )
        assert resp_with_recs.recommendations_generated == 3
        print("  NotificationProcessResponse has recommendations_generated field")
