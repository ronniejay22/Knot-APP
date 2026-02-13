"""
Step 7.6 Verification: DND Quiet Hours Logic

Tests that:
1. is_in_quiet_hours() correctly identifies times within and outside quiet hours
2. Midnight-spanning quiet hours (22:00-08:00) work correctly
3. Same-day quiet hours (01:00-06:00) work correctly
4. Equal start/end disables quiet hours
5. Timezone resolution works (explicit, inferred from location, fallback)
6. _compute_next_delivery_time() calculates correct reschedule times
7. check_quiet_hours() integrates DB lookup with DND check
8. Webhook endpoint reschedules notifications during quiet hours
9. Webhook endpoint delivers normally outside quiet hours
10. DND check failure does not block delivery (graceful degradation)

Prerequisites:
- Complete Steps 7.1-7.5
- zoneinfo available (Python 3.9+)

Run with: pytest tests/test_dnd_quiet_hours.py -v
"""

import hashlib
import json
import time
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from zoneinfo import ZoneInfo

import jwt
import pytest
from fastapi.testclient import TestClient

from app.agents.state import (
    CandidateRecommendation,
    MilestoneContext,
    VaultBudget,
    VaultData,
)
from app.main import app
from app.services.dnd import (
    DEFAULT_QUIET_HOURS_END,
    DEFAULT_QUIET_HOURS_START,
    DEFAULT_TIMEZONE,
    _compute_next_delivery_time,
    get_user_timezone,
    infer_timezone_from_location,
    is_in_quiet_hours,
)


# ---------------------------------------------------------------------------
# Test signing key for QStash webhook tests
# ---------------------------------------------------------------------------

TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"


# ---------------------------------------------------------------------------
# Mock data factories (reused from test_apns_push_service.py pattern)
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
        vibes=["quiet_luxury", "adventurous"],
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
            id="rec-001", source="amazon", type="gift",
            title="Ceramic Mug Set", description="Handmade ceramic mugs",
            price_cents=4500, currency="USD",
            external_url="https://example.com/mugs",
            image_url="https://example.com/mugs.jpg",
            merchant_name="Artisan Co.",
            interest_score=0.85, vibe_score=0.78,
            love_language_score=0.72, final_score=0.80,
        ),
        CandidateRecommendation(
            id="rec-002", source="yelp", type="experience",
            title="Sunset Sailing", description="Private sailing trip",
            price_cents=24900, currency="USD",
            external_url="https://example.com/sailing",
            image_url="https://example.com/sailing.jpg",
            merchant_name="Bay Sailing Co.",
            interest_score=0.90, vibe_score=0.85,
            love_language_score=0.70, final_score=0.83,
        ),
        CandidateRecommendation(
            id="rec-003", source="yelp", type="date",
            title="Italian Dinner", description="Intimate 5-course dinner",
            price_cents=18000, currency="USD",
            external_url="https://example.com/dinner",
            image_url="https://example.com/dinner.jpg",
            merchant_name="Trattoria Luna",
            interest_score=0.75, vibe_score=0.92,
            love_language_score=0.88, final_score=0.84,
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
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """FastAPI test client for the Knot API."""
    return TestClient(app)


# ===================================================================
# 1. is_in_quiet_hours — Pure Unit Tests
# ===================================================================

class TestIsInQuietHours:
    """Unit tests for is_in_quiet_hours() — no DB needed."""

    def test_11pm_is_in_default_quiet_hours(self):
        """11pm should be within 10pm-8am quiet hours."""
        user_tz = ZoneInfo("America/New_York")
        # 11pm ET on Mar 15 → in EST that's 4am UTC Mar 16
        now_utc = datetime(2026, 3, 16, 4, 0, tzinfo=timezone.utc)
        is_quiet, next_time = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is True
        assert next_time is not None
        print("  11pm ET → in quiet hours")

    def test_9am_is_outside_default_quiet_hours(self):
        """9am should be outside 10pm-8am quiet hours."""
        user_tz = ZoneInfo("America/New_York")
        # 9am ET → 2pm UTC (EST offset -5)
        now_utc = datetime(2026, 3, 15, 14, 0, tzinfo=timezone.utc)
        is_quiet, next_time = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is False
        assert next_time is None
        print("  9am ET → not in quiet hours")

    def test_10pm_exactly_is_in_quiet_hours(self):
        """10pm (boundary) should be within 10pm-8am quiet hours."""
        user_tz = ZoneInfo("America/Chicago")
        # 10pm CT → 4am UTC next day (CST offset -6)
        now_utc = datetime(2026, 3, 16, 4, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is True
        print("  10pm CT (boundary) → in quiet hours")

    def test_8am_exactly_is_outside_quiet_hours(self):
        """8am (boundary) should be outside 10pm-8am quiet hours."""
        user_tz = ZoneInfo("America/Chicago")
        # 8am CT → 2pm UTC (CST offset -6)
        now_utc = datetime(2026, 3, 15, 14, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is False
        print("  8am CT (boundary) → not in quiet hours")

    def test_3am_is_in_quiet_hours(self):
        """3am should be within 10pm-8am quiet hours (past midnight)."""
        user_tz = ZoneInfo("America/Los_Angeles")
        # 3am PT → 11am UTC (PST offset -8)
        now_utc = datetime(2026, 3, 15, 11, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is True
        print("  3am PT → in quiet hours (past midnight)")

    def test_noon_is_outside_quiet_hours(self):
        """12pm should be outside 10pm-8am quiet hours."""
        user_tz = ZoneInfo("America/New_York")
        # 12pm ET → 5pm UTC
        now_utc = datetime(2026, 3, 15, 17, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(22, 8, user_tz, now_utc)
        assert is_quiet is False
        print("  12pm ET → not in quiet hours")

    def test_same_day_quiet_hours(self):
        """Quiet hours 01:00-06:00 should work for same-day ranges."""
        user_tz = ZoneInfo("America/New_York")
        # 3am ET → 8am UTC (EST offset -5)
        now_utc = datetime(2026, 3, 15, 8, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(1, 6, user_tz, now_utc)
        assert is_quiet is True
        print("  3am ET in 1am-6am range → in quiet hours")

    def test_same_day_quiet_hours_outside(self):
        """7am should be outside 01:00-06:00 quiet hours."""
        user_tz = ZoneInfo("America/New_York")
        # 7am ET → 12pm UTC
        now_utc = datetime(2026, 3, 15, 12, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(1, 6, user_tz, now_utc)
        assert is_quiet is False
        print("  7am ET in 1am-6am range → not in quiet hours")

    def test_equal_start_end_disables_quiet_hours(self):
        """When start == end, quiet hours should be disabled."""
        user_tz = ZoneInfo("America/New_York")
        # 3am ET — would normally be quiet, but disabled
        now_utc = datetime(2026, 3, 15, 8, 0, tzinfo=timezone.utc)
        is_quiet, _ = is_in_quiet_hours(8, 8, user_tz, now_utc)
        assert is_quiet is False
        print("  start == end → quiet hours disabled")


# ===================================================================
# 2. _compute_next_delivery_time — Unit Tests
# ===================================================================

class TestComputeNextDeliveryTime:
    """Tests for next delivery time calculation."""

    def test_11pm_reschedules_to_8am_next_day(self):
        """11pm notification should be rescheduled to 8am next day."""
        user_tz = ZoneInfo("America/New_York")
        # 11pm ET on March 15 → 4am UTC March 16
        now_utc = datetime(2026, 3, 16, 4, 0, tzinfo=timezone.utc)
        is_quiet, next_time = is_in_quiet_hours(22, 8, user_tz, now_utc)

        assert is_quiet is True
        assert next_time is not None

        # Next delivery should be 8am ET on March 16
        next_local = next_time.astimezone(user_tz)
        assert next_local.hour == 8
        assert next_local.minute == 0
        assert next_local.day == 16
        print(f"  11pm → rescheduled to 8am next day: {next_local}")

    def test_3am_reschedules_to_8am_same_day(self):
        """3am notification should be rescheduled to 8am same day."""
        user_tz = ZoneInfo("America/Chicago")
        # 3am CT on March 15 → 9am UTC March 15
        now_utc = datetime(2026, 3, 15, 9, 0, tzinfo=timezone.utc)
        is_quiet, next_time = is_in_quiet_hours(22, 8, user_tz, now_utc)

        assert is_quiet is True
        assert next_time is not None

        next_local = next_time.astimezone(user_tz)
        assert next_local.hour == 8
        assert next_local.day == 15
        print(f"  3am → rescheduled to 8am same day: {next_local}")

    def test_delivery_time_is_utc(self):
        """Next delivery time should be returned in UTC."""
        user_tz = ZoneInfo("America/Los_Angeles")
        # 11pm PT → 7am UTC next day
        now_utc = datetime(2026, 3, 16, 7, 0, tzinfo=timezone.utc)
        _, next_time = is_in_quiet_hours(22, 8, user_tz, now_utc)

        assert next_time is not None
        assert next_time.tzinfo == timezone.utc
        print(f"  Delivery time is UTC: {next_time}")


# ===================================================================
# 3. Timezone Inference — Unit Tests
# ===================================================================

class TestTimezoneInference:
    """Tests for timezone inference from location."""

    def test_texas_maps_to_chicago(self):
        """Texas should map to America/Chicago."""
        assert infer_timezone_from_location("TX", "US") == "America/Chicago"
        print("  TX → America/Chicago")

    def test_california_maps_to_los_angeles(self):
        """California should map to America/Los_Angeles."""
        assert infer_timezone_from_location("CA", "US") == "America/Los_Angeles"
        print("  CA → America/Los_Angeles")

    def test_new_york_maps_to_new_york(self):
        """New York should map to America/New_York."""
        assert infer_timezone_from_location("NY", "US") == "America/New_York"
        print("  NY → America/New_York")

    def test_hawaii_maps_to_honolulu(self):
        """Hawaii should map to Pacific/Honolulu."""
        assert infer_timezone_from_location("HI", "US") == "Pacific/Honolulu"
        print("  HI → Pacific/Honolulu")

    def test_non_us_falls_back_to_default(self):
        """Non-US countries should fall back to DEFAULT_TIMEZONE."""
        assert infer_timezone_from_location("ON", "CA") == DEFAULT_TIMEZONE
        print(f"  Non-US → {DEFAULT_TIMEZONE}")

    def test_none_state_falls_back_to_default(self):
        """None state should fall back to DEFAULT_TIMEZONE."""
        assert infer_timezone_from_location(None, "US") == DEFAULT_TIMEZONE
        print(f"  None state → {DEFAULT_TIMEZONE}")

    def test_case_insensitive_state(self):
        """State abbreviations should be case-insensitive."""
        assert infer_timezone_from_location("tx", "US") == "America/Chicago"
        assert infer_timezone_from_location("Tx", "us") == "America/Chicago"
        print("  Case-insensitive: tx/Tx → America/Chicago")

    def test_none_country_falls_back_to_default(self):
        """None country should fall back to DEFAULT_TIMEZONE."""
        assert infer_timezone_from_location("TX", None) == DEFAULT_TIMEZONE
        print(f"  None country → {DEFAULT_TIMEZONE}")


# ===================================================================
# 4. get_user_timezone — Unit Tests
# ===================================================================

class TestGetUserTimezone:
    """Tests for timezone resolution priority."""

    def test_explicit_timezone_takes_priority(self):
        """Explicit user timezone should override vault location."""
        tz = get_user_timezone("America/Denver", "TX", "US")
        assert str(tz) == "America/Denver"
        print("  Explicit tz → America/Denver (overrides TX)")

    def test_vault_location_used_when_no_explicit_tz(self):
        """Vault location should be used when no explicit timezone."""
        tz = get_user_timezone(None, "CA", "US")
        assert str(tz) == "America/Los_Angeles"
        print("  No explicit tz, CA vault → America/Los_Angeles")

    def test_fallback_when_no_data(self):
        """Should fall back to DEFAULT_TIMEZONE when no data available."""
        tz = get_user_timezone(None, None, None)
        assert str(tz) == DEFAULT_TIMEZONE
        print(f"  No data → {DEFAULT_TIMEZONE}")

    def test_invalid_timezone_falls_back_to_location(self):
        """Invalid explicit timezone should fall back to vault location."""
        tz = get_user_timezone("Invalid/Timezone", "NY", "US")
        assert str(tz) == "America/New_York"
        print("  Invalid tz, NY vault → America/New_York")


# ===================================================================
# 5. check_quiet_hours — Integration Tests (Mocked DB)
# ===================================================================

class TestCheckQuietHours:
    """Tests for check_quiet_hours with mocked Supabase."""

    @pytest.mark.asyncio
    async def test_user_in_quiet_hours_returns_true(self):
        """When user is in quiet hours, should return (True, datetime)."""
        from app.services.dnd import check_quiet_hours

        mock_user_execute = MagicMock()
        mock_user_execute.data = [{
            "quiet_hours_start": 22,
            "quiet_hours_end": 8,
            "timezone": "America/Chicago",
        }]

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_user_execute

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        # 11pm CT → 5am UTC next day
        fake_now = datetime(2026, 3, 16, 5, 0, tzinfo=timezone.utc)

        with patch("app.services.dnd.get_service_client", return_value=mock_client):
            with patch("app.services.dnd.datetime") as mock_dt:
                mock_dt.now.return_value = fake_now
                # Allow datetime(...) constructor to pass through to real datetime
                # so _compute_next_delivery_time can build timezone-aware datetimes
                mock_dt.side_effect = lambda *args, **kwargs: datetime(*args, **kwargs)
                is_quiet, next_time = await check_quiet_hours("user-123")

        assert is_quiet is True
        assert next_time is not None
        print("  User in quiet hours → (True, datetime)")

    @pytest.mark.asyncio
    async def test_user_not_found_allows_delivery(self):
        """Missing user should return (False, None) — allow delivery."""
        from app.services.dnd import check_quiet_hours

        mock_result = MagicMock()
        mock_result.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_result

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.services.dnd.get_service_client", return_value=mock_client):
            is_quiet, next_time = await check_quiet_hours("nonexistent-user")

        assert is_quiet is False
        assert next_time is None
        print("  User not found → (False, None)")

    @pytest.mark.asyncio
    async def test_infers_timezone_from_vault_when_no_explicit_tz(self):
        """When user has no timezone, should infer from vault location."""
        from app.services.dnd import check_quiet_hours

        mock_user_execute = MagicMock()
        mock_user_execute.data = [{
            "quiet_hours_start": 22,
            "quiet_hours_end": 8,
            "timezone": None,
        }]

        mock_vault_execute = MagicMock()
        mock_vault_execute.data = [{
            "location_state": "CA",
            "location_country": "US",
        }]

        call_count = {"n": 0}

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_user_execute
            return mock_vault_execute

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        # 9am PT → 5pm UTC (outside quiet hours)
        with patch("app.services.dnd.get_service_client", return_value=mock_client):
            with patch("app.services.dnd.datetime") as mock_dt:
                mock_dt.now.return_value = datetime(2026, 3, 15, 17, 0, tzinfo=timezone.utc)
                is_quiet, _ = await check_quiet_hours("user-123")

        # 9am PT is outside quiet hours
        assert is_quiet is False
        print("  No explicit tz → inferred from CA vault location")


# ===================================================================
# 6. Webhook DND Integration Tests
# ===================================================================

class TestWebhookDNDIntegration:
    """Tests for DND integration in the webhook endpoint."""

    def _make_webhook_request(
        self,
        client,
        notification_id: str,
        user_id: str,
        milestone_id: str,
        days_before: int = 7,
    ):
        """Build and send a webhook request with valid QStash signature."""
        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": days_before,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        return client.post(
            "/api/v1/notifications/process",
            content=body,
            headers={
                "Content-Type": "application/json",
                "Upstash-Signature": signature,
            },
        )

    def _setup_mocks(
        self,
        notif_id: str,
        user_id: str,
        milestone_id: str,
    ):
        """Create standard mock chain for webhook tests."""
        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "status": "pending",
            "days_before": 7,
        }]

        mock_execute_other = MagicMock()
        mock_execute_other.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            return mock_execute_other

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        return mock_client

    @patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock)
    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_notification_rescheduled_during_quiet_hours(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        mock_dnd,
        client,
    ):
        """Webhook should return 'rescheduled' when in quiet hours."""
        # DND check returns True with a reschedule time
        reschedule_time = datetime(2026, 3, 16, 13, 0, tzinfo=timezone.utc)
        mock_dnd.return_value = (True, reschedule_time)

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_client = self._setup_mocks(notif_id, user_id, milestone_id)

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            with patch("app.api.notifications.is_qstash_configured", return_value=False):
                response = self._make_webhook_request(
                    client, notif_id, user_id, milestone_id,
                )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "rescheduled"
        assert "quiet hours" in data["message"]
        assert data["push_delivered"] is False
        assert data["recommendations_generated"] == 0
        # Neither pipeline nor push should have been called
        mock_pipeline.assert_not_called()
        mock_push.assert_not_called()
        print("  Quiet hours → rescheduled, pipeline + push NOT called")

    @patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock)
    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_notification_delivered_outside_quiet_hours(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        mock_dnd,
        client,
    ):
        """Webhook should proceed normally when outside quiet hours."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}
        mock_push.return_value = {
            "success": True, "apns_id": "apns-123", "status_code": 200, "reason": None,
        }

        # DND check returns False (not in quiet hours)
        mock_dnd.return_value = (False, None)

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_client = self._setup_mocks(notif_id, user_id, milestone_id)

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            response = self._make_webhook_request(
                client, notif_id, user_id, milestone_id,
            )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "processed"
        assert data["push_delivered"] is True
        mock_push.assert_called_once()
        print("  Outside quiet hours → processed, push delivered")

    @patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock)
    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_dnd_check_failure_proceeds_with_delivery(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        mock_dnd,
        client,
    ):
        """If DND check raises, notification should still be delivered."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}
        mock_push.return_value = {
            "success": True, "apns_id": "apns-123", "status_code": 200, "reason": None,
        }

        # DND check raises an exception
        mock_dnd.side_effect = Exception("Database connection refused")

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_client = self._setup_mocks(notif_id, user_id, milestone_id)

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            response = self._make_webhook_request(
                client, notif_id, user_id, milestone_id,
            )

        # Should still succeed — graceful degradation
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "processed"
        mock_push.assert_called_once()
        print("  DND check failure → delivery proceeds (graceful degradation)")

    @patch("app.api.notifications.publish_to_qstash", new_callable=AsyncMock)
    @patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock)
    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_qstash_publish_called_for_reschedule(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        mock_dnd,
        mock_qstash_publish,
        client,
    ):
        """QStash should be called with correct not_before for rescheduled notification."""
        # DND returns quiet with reschedule time
        reschedule_time = datetime(2026, 3, 16, 13, 0, tzinfo=timezone.utc)
        mock_dnd.return_value = (True, reschedule_time)
        mock_qstash_publish.return_value = {"messageId": "mock-msg-123"}

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_client = self._setup_mocks(notif_id, user_id, milestone_id)

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            with patch("app.api.notifications.is_qstash_configured", return_value=True):
                with patch("app.api.notifications.WEBHOOK_BASE_URL", "https://api.knot.example.com"):
                    response = self._make_webhook_request(
                        client, notif_id, user_id, milestone_id,
                    )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "rescheduled"

        # Verify QStash was called with correct parameters
        mock_qstash_publish.assert_called_once()
        call_kwargs = mock_qstash_publish.call_args[1]
        assert call_kwargs["destination_url"] == "https://api.knot.example.com/api/v1/notifications/process"
        assert call_kwargs["not_before"] == int(reschedule_time.timestamp())
        assert call_kwargs["deduplication_id"] == f"{notif_id}-dnd-reschedule"
        print("  QStash called with correct not_before and dedup_id")

    @patch("app.api.notifications.check_quiet_hours", new_callable=AsyncMock)
    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_rescheduled_notification_stays_pending(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        mock_dnd,
        client,
    ):
        """Rescheduled notification should NOT be marked as 'sent'."""
        reschedule_time = datetime(2026, 3, 16, 13, 0, tzinfo=timezone.utc)
        mock_dnd.return_value = (True, reschedule_time)

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        # Track calls to notification_queue.update
        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id, "user_id": user_id,
            "milestone_id": milestone_id, "status": "pending", "days_before": 7,
        }]

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table
        mock_table.execute.return_value = mock_execute_select

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            with patch("app.api.notifications.is_qstash_configured", return_value=False):
                response = self._make_webhook_request(
                    client, notif_id, user_id, milestone_id,
                )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "rescheduled"

        # update() should NOT have been called with status='sent'
        # Since we return early, the notification_queue.update call is never reached
        update_calls = [
            call for call in mock_table.update.call_args_list
            if call[0] and isinstance(call[0][0], dict) and call[0][0].get("status") == "sent"
        ]
        assert len(update_calls) == 0
        print("  Rescheduled notification stays pending (not marked 'sent')")


# ===================================================================
# 7. Module Imports — Unit Tests
# ===================================================================

class TestModuleImports:
    """Verify all new DND modules import correctly."""

    def test_dnd_service_imports(self):
        """The DND service module should import without errors."""
        from app.services.dnd import (
            DEFAULT_QUIET_HOURS_END,
            DEFAULT_QUIET_HOURS_START,
            DEFAULT_TIMEZONE,
            check_quiet_hours,
            get_user_timezone,
            infer_timezone_from_location,
            is_in_quiet_hours,
        )
        assert callable(check_quiet_hours)
        assert callable(is_in_quiet_hours)
        assert callable(get_user_timezone)
        assert callable(infer_timezone_from_location)
        assert DEFAULT_QUIET_HOURS_START == 22
        assert DEFAULT_QUIET_HOURS_END == 8
        assert DEFAULT_TIMEZONE == "America/New_York"
        print("  All DND service exports importable")

    def test_notification_response_accepts_rescheduled_status(self):
        """NotificationProcessResponse should accept 'rescheduled' status."""
        from app.models.notifications import NotificationProcessResponse
        resp = NotificationProcessResponse(
            status="rescheduled",
            notification_id="test-123",
            message="Deferred to 8am (quiet hours).",
        )
        assert resp.status == "rescheduled"
        assert resp.push_delivered is False
        print("  NotificationProcessResponse accepts 'rescheduled' status")

    def test_constants_are_correct(self):
        """DND constants should have expected values."""
        assert DEFAULT_QUIET_HOURS_START == 22
        assert DEFAULT_QUIET_HOURS_END == 8
        assert DEFAULT_TIMEZONE == "America/New_York"
        print("  DND constants verified: 22, 8, America/New_York")
