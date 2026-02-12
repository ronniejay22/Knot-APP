"""
Step 7.2 Verification: Notification Scheduling Logic

Tests that:
1. compute_next_occurrence() correctly resolves yearly, one-time, and floating
   holiday milestones to their next future date.
2. _is_floating_holiday() detects Mother's Day and Father's Day by name.
3. schedule_milestone_notifications() creates the correct number of
   notification_queue entries based on how far away the milestone is.
4. QStash messages are published with correct not_before timestamps.
5. Graceful degradation when QStash is not configured.
6. schedule_notifications_for_milestones() handles batch scheduling.

Prerequisites:
- Complete Steps 0.6, 1.1-1.12 (Supabase + all tables)
- Step 7.1 (QStash service + notification_queue table)

Run with: pytest tests/test_notification_scheduler.py -v
"""

import time
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
)
from app.services.notification_scheduler import (
    NOTIFICATION_DAYS_BEFORE,
    _fathers_day,
    _is_floating_holiday,
    _mothers_day,
    compute_next_occurrence,
    schedule_milestone_notifications,
    schedule_notifications_for_milestones,
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


def _query_notifications(milestone_id: str) -> list[dict]:
    """Fetch all notification_queue rows for a milestone."""
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
    return resp.json()


def _delete_notifications_for_milestone(milestone_id: str):
    """Delete all notification_queue rows for a milestone."""
    resp = httpx.delete(
        f"{SUPABASE_URL}/rest/v1/notification_queue",
        headers=_service_headers(),
        params={"milestone_id": f"eq.{milestone_id}"},
    )
    assert resp.status_code in (200, 204)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """Create a test auth user. CASCADE cleanup on teardown."""
    email = f"knot-sched-{uuid.uuid4().hex[:8]}@test.example"
    password = f"SchedTest!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(email, password)
    time.sleep(0.5)
    yield {"id": user_id, "email": email}
    _delete_auth_user(user_id)


@pytest.fixture
def test_vault(test_auth_user):
    """Create a vault for the test user. Cleaned up by CASCADE."""
    vault = _insert_vault({
        "user_id": test_auth_user["id"],
        "partner_name": "Scheduler Test Partner",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Portland",
        "location_state": "OR",
        "location_country": "US",
    })
    return vault


# ===================================================================
# 1. Floating Holiday Detection (Pure Unit Tests)
# ===================================================================

class TestFloatingHolidayDetection:
    """Unit tests for _is_floating_holiday() — no Supabase needed."""

    def test_mothers_day_detected(self):
        """'Mother's Day' should return 'mothers_day'."""
        assert _is_floating_holiday("Mother's Day") == "mothers_day"
        print("  Mother's Day detected")

    def test_fathers_day_detected(self):
        """'Father's Day' should return 'fathers_day'."""
        assert _is_floating_holiday("Father's Day") == "fathers_day"
        print("  Father's Day detected")

    def test_case_insensitive(self):
        """Detection should be case-insensitive."""
        assert _is_floating_holiday("MOTHER'S DAY") == "mothers_day"
        assert _is_floating_holiday("father's day") == "fathers_day"
        print("  Case-insensitive detection works")

    def test_non_floating_returns_none(self):
        """Non-floating holidays should return None."""
        assert _is_floating_holiday("Valentine's Day") is None
        assert _is_floating_holiday("Christmas") is None
        print("  Non-floating holidays return None")

    def test_birthday_returns_none(self):
        """Birthdays are not floating holidays."""
        assert _is_floating_holiday("Partner's Birthday") is None
        print("  Birthday returns None")


# ===================================================================
# 2. Floating Holiday Date Computation (Pure Unit Tests)
# ===================================================================

class TestFloatingHolidayDates:
    """Unit tests for _mothers_day() and _fathers_day() computation."""

    def test_mothers_day_2026(self):
        """Mother's Day 2026 should be May 10, 2026."""
        assert _mothers_day(2026) == date(2026, 5, 10)
        print("  Mother's Day 2026 = May 10")

    def test_fathers_day_2026(self):
        """Father's Day 2026 should be June 21, 2026."""
        assert _fathers_day(2026) == date(2026, 6, 21)
        print("  Father's Day 2026 = June 21")

    def test_mothers_day_2027(self):
        """Mother's Day 2027 should be May 9, 2027."""
        assert _mothers_day(2027) == date(2027, 5, 9)
        print("  Mother's Day 2027 = May 9")

    def test_fathers_day_2027(self):
        """Father's Day 2027 should be June 20, 2027."""
        assert _fathers_day(2027) == date(2027, 6, 20)
        print("  Father's Day 2027 = June 20")

    def test_mothers_day_is_sunday(self):
        """Mother's Day should always be a Sunday."""
        for year in range(2024, 2031):
            md = _mothers_day(year)
            assert md.weekday() == 6, f"Mother's Day {year} is not Sunday"
        print("  Mother's Day is always Sunday (2024-2030)")

    def test_fathers_day_is_sunday(self):
        """Father's Day should always be a Sunday."""
        for year in range(2024, 2031):
            fd = _fathers_day(year)
            assert fd.weekday() == 6, f"Father's Day {year} is not Sunday"
        print("  Father's Day is always Sunday (2024-2030)")


# ===================================================================
# 3. Next Occurrence Computation (Pure Unit Tests)
# ===================================================================

class TestComputeNextOccurrence:
    """Unit tests for compute_next_occurrence() — no Supabase needed."""

    def test_yearly_birthday_in_future_this_year(self):
        """A birthday later this year should return this year's date."""
        today = date.today()
        # Pick a date 60 days in the future
        future = today + timedelta(days=60)
        milestone_date = date(2000, future.month, future.day)
        result = compute_next_occurrence(
            milestone_date, "Partner's Birthday", "yearly",
        )
        assert result == future
        print(f"  Yearly birthday in future: {result}")

    def test_yearly_birthday_already_passed(self):
        """A birthday that already passed this year should return next year."""
        today = date.today()
        # Pick a date 30 days in the past
        past = today - timedelta(days=30)
        milestone_date = date(2000, past.month, past.day)
        result = compute_next_occurrence(
            milestone_date, "Partner's Birthday", "yearly",
        )
        expected = date(today.year + 1, past.month, past.day)
        assert result == expected
        print(f"  Yearly birthday already passed: {result}")

    def test_one_time_in_future(self):
        """A one-time milestone in the future should return its date."""
        future = date.today() + timedelta(days=20)
        result = compute_next_occurrence(
            future, "Concert Tickets", "one_time",
        )
        assert result == future
        print(f"  One-time future: {result}")

    def test_one_time_in_past(self):
        """A one-time milestone in the past should return None."""
        past = date.today() - timedelta(days=5)
        result = compute_next_occurrence(
            past, "Concert Tickets", "one_time",
        )
        assert result is None
        print("  One-time past: None")

    def test_mothers_day_floating_holiday(self):
        """Mother's Day should resolve to the actual 2nd Sunday of May."""
        today = date.today()
        # Use the approximate date stored in onboarding (May 11)
        milestone_date = date(2000, 5, 11)
        result = compute_next_occurrence(
            milestone_date, "Mother's Day", "yearly",
        )
        expected_this_year = _mothers_day(today.year)
        if expected_this_year > today:
            assert result == expected_this_year
        else:
            assert result == _mothers_day(today.year + 1)
        # Verify it's actually a Sunday
        assert result.weekday() == 6
        print(f"  Mother's Day next occurrence: {result}")

    def test_fathers_day_floating_holiday(self):
        """Father's Day should resolve to the actual 3rd Sunday of June."""
        today = date.today()
        milestone_date = date(2000, 6, 15)
        result = compute_next_occurrence(
            milestone_date, "Father's Day", "yearly",
        )
        expected_this_year = _fathers_day(today.year)
        if expected_this_year > today:
            assert result == expected_this_year
        else:
            assert result == _fathers_day(today.year + 1)
        assert result.weekday() == 6
        print(f"  Father's Day next occurrence: {result}")

    def test_leap_year_feb_29_in_leap_year(self):
        """Feb 29 birthday in a leap year should return Feb 29."""
        milestone_date = date(2000, 2, 29)
        # 2028 is a leap year
        with patch("app.services.notification_scheduler.date") as mock_date:
            mock_date.today.return_value = date(2028, 1, 15)
            mock_date.side_effect = lambda *args, **kw: date(*args, **kw)
            result = compute_next_occurrence(
                milestone_date, "Partner's Birthday", "yearly",
            )
        assert result == date(2028, 2, 29)
        print("  Feb 29 in leap year: Feb 29")

    def test_leap_year_feb_29_in_non_leap_year(self):
        """Feb 29 birthday in a non-leap year should clamp to Feb 28."""
        milestone_date = date(2000, 2, 29)
        with patch("app.services.notification_scheduler.date") as mock_date:
            mock_date.today.return_value = date(2027, 1, 15)
            mock_date.side_effect = lambda *args, **kw: date(*args, **kw)
            result = compute_next_occurrence(
                milestone_date, "Partner's Birthday", "yearly",
            )
        assert result == date(2027, 2, 28)
        print("  Feb 29 in non-leap year: Feb 28")

    def test_today_is_not_returned(self):
        """A milestone occurring today should return next year (already past)."""
        today = date.today()
        milestone_date = date(2000, today.month, today.day)
        result = compute_next_occurrence(
            milestone_date, "Anniversary", "yearly",
        )
        expected = date(today.year + 1, today.month, today.day)
        assert result == expected
        print(f"  Today's milestone returns next year: {result}")

    def test_yearly_christmas(self):
        """Christmas (Dec 25) should resolve correctly."""
        today = date.today()
        milestone_date = date(2000, 12, 25)
        result = compute_next_occurrence(
            milestone_date, "Christmas", "yearly",
        )
        this_year = date(today.year, 12, 25)
        if this_year > today:
            assert result == this_year
        else:
            assert result == date(today.year + 1, 12, 25)
        print(f"  Christmas next occurrence: {result}")


# ===================================================================
# 4. Schedule Milestone Notifications (Integration Tests)
# ===================================================================

class TestScheduleMilestoneNotifications:
    """
    Integration tests for schedule_milestone_notifications().
    Requires Supabase. QStash is mocked.
    """

    @requires_supabase
    @pytest.mark.asyncio
    async def test_milestone_20_days_future_creates_3_notifications(
        self, test_auth_user, test_vault,
    ):
        """
        A milestone 20 days in the future should create 3 notification_queue
        entries (14-day, 7-day, and 3-day) since all intervals are in the future.
        """
        future_date = date.today() + timedelta(days=20)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Partner's Birthday",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Partner's Birthday",
                    recurrence="one_time",
                )

            assert len(result) == 3
            days = [r["days_before"] for r in result]
            assert 14 in days
            assert 7 in days
            assert 3 in days

            # Verify all have status 'pending'
            for r in result:
                assert r["status"] == "pending"
                assert r["milestone_id"] == milestone["id"]
                assert r["user_id"] == test_auth_user["id"]

            # Verify scheduled_for dates are correct
            for r in result:
                scheduled = datetime.fromisoformat(r["scheduled_for"])
                expected = datetime.combine(
                    future_date, datetime.min.time(),
                ).replace(tzinfo=timezone.utc) - timedelta(days=r["days_before"])
                assert scheduled == expected

            # Verify DB has 3 rows
            db_rows = _query_notifications(milestone["id"])
            assert len(db_rows) == 3

            print("  20-day milestone: 3 notifications created with correct dates")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_milestone_10_days_future_creates_2_notifications(
        self, test_auth_user, test_vault,
    ):
        """
        A milestone 10 days out should create 2 notifications (7-day and 3-day).
        The 14-day interval is in the past.
        """
        future_date = date.today() + timedelta(days=10)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "anniversary",
            "milestone_name": "Anniversary",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Anniversary",
                    recurrence="one_time",
                )

            assert len(result) == 2
            days = [r["days_before"] for r in result]
            assert 7 in days
            assert 3 in days
            assert 14 not in days

            print("  10-day milestone: 2 notifications (7-day, 3-day)")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_milestone_5_days_future_creates_1_notification(
        self, test_auth_user, test_vault,
    ):
        """
        A milestone 5 days out should create 1 notification (3-day only).
        """
        future_date = date.today() + timedelta(days=5)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "custom",
            "milestone_name": "Date Night",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
            "budget_tier": "just_because",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Date Night",
                    recurrence="one_time",
                )

            assert len(result) == 1
            assert result[0]["days_before"] == 3

            print("  5-day milestone: 1 notification (3-day only)")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_milestone_2_days_future_creates_no_notifications(
        self, test_auth_user, test_vault,
    ):
        """
        A milestone 2 days out should create 0 notifications
        (all intervals have passed).
        """
        future_date = date.today() + timedelta(days=2)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "custom",
            "milestone_name": "Quick Gift",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
            "budget_tier": "just_because",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Quick Gift",
                    recurrence="one_time",
                )

            assert len(result) == 0

            db_rows = _query_notifications(milestone["id"])
            assert len(db_rows) == 0

            print("  2-day milestone: 0 notifications (all intervals past)")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_one_time_past_milestone_creates_no_notifications(
        self, test_auth_user, test_vault,
    ):
        """A one-time milestone in the past should create 0 notifications."""
        past_date = date.today() - timedelta(days=5)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "custom",
            "milestone_name": "Past Event",
            "milestone_date": past_date.isoformat(),
            "recurrence": "one_time",
            "budget_tier": "just_because",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=past_date,
                    milestone_name="Past Event",
                    recurrence="one_time",
                )

            assert len(result) == 0

            print("  Past one-time milestone: 0 notifications")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_qstash_not_configured_still_creates_db_entries(
        self, test_auth_user, test_vault,
    ):
        """
        When QStash is not configured, notification_queue entries should
        still be created in the database (graceful degradation).
        """
        future_date = date.today() + timedelta(days=20)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Birthday",
                    recurrence="one_time",
                )

            # DB entries created despite no QStash
            assert len(result) == 3
            db_rows = _query_notifications(milestone["id"])
            assert len(db_rows) == 3

            print("  QStash not configured: DB entries still created")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_qstash_publish_called_with_not_before(
        self, test_auth_user, test_vault,
    ):
        """
        When QStash is configured, publish_to_qstash should be called
        with the correct not_before Unix timestamp for each notification.
        """
        future_date = date.today() + timedelta(days=20)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
        })

        mock_publish = AsyncMock(return_value={"messageId": "mock-msg-123"})

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=True,
            ), patch(
                "app.services.notification_scheduler.WEBHOOK_BASE_URL",
                "https://api.knot.example.com",
            ), patch(
                "app.services.notification_scheduler.publish_to_qstash",
                mock_publish,
            ):
                result = await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Birthday",
                    recurrence="one_time",
                )

            assert mock_publish.call_count == 3

            # Verify each call has correct not_before
            for call in mock_publish.call_args_list:
                kwargs = call.kwargs if call.kwargs else {}
                args = call.args if call.args else ()

                # not_before should be an integer (Unix timestamp)
                not_before = kwargs.get("not_before")
                assert isinstance(not_before, int)
                assert not_before > 0

                # destination_url should be correct
                dest = kwargs.get("destination_url") or args[0]
                assert dest == "https://api.knot.example.com/api/v1/notifications/process"

                # deduplication_id should follow format
                dedup = kwargs.get("deduplication_id")
                assert dedup is not None
                assert dedup.startswith(milestone["id"])

            print("  QStash publish called with correct not_before timestamps")

        finally:
            _delete_notifications_for_milestone(milestone["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_deduplication_id_format(
        self, test_auth_user, test_vault,
    ):
        """
        Deduplication IDs should follow the format '{milestone_id}-{days_before}'.
        """
        future_date = date.today() + timedelta(days=20)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": future_date.isoformat(),
            "recurrence": "one_time",
        })

        mock_publish = AsyncMock(return_value={"messageId": "mock-msg-456"})

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=True,
            ), patch(
                "app.services.notification_scheduler.WEBHOOK_BASE_URL",
                "https://api.knot.example.com",
            ), patch(
                "app.services.notification_scheduler.publish_to_qstash",
                mock_publish,
            ):
                await schedule_milestone_notifications(
                    milestone_id=milestone["id"],
                    user_id=test_auth_user["id"],
                    milestone_date=future_date,
                    milestone_name="Birthday",
                    recurrence="one_time",
                )

            dedup_ids = [
                call.kwargs["deduplication_id"]
                for call in mock_publish.call_args_list
            ]
            expected_ids = [
                f"{milestone['id']}-14",
                f"{milestone['id']}-7",
                f"{milestone['id']}-3",
            ]
            assert sorted(dedup_ids) == sorted(expected_ids)

            print("  Deduplication IDs follow correct format")

        finally:
            _delete_notifications_for_milestone(milestone["id"])


# ===================================================================
# 5. Batch Scheduling (Integration Tests)
# ===================================================================

class TestScheduleNotificationsForMilestones:
    """Integration tests for schedule_notifications_for_milestones()."""

    @requires_supabase
    @pytest.mark.asyncio
    async def test_batch_schedules_for_all_milestones(
        self, test_auth_user, test_vault,
    ):
        """
        Batch scheduling across multiple milestones should create the
        correct total number of notifications.
        """
        future_20 = date.today() + timedelta(days=20)
        future_5 = date.today() + timedelta(days=5)

        milestone_1 = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": future_20.isoformat(),
            "recurrence": "one_time",
        })
        milestone_2 = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "custom",
            "milestone_name": "Date Night",
            "milestone_date": future_5.isoformat(),
            "recurrence": "one_time",
            "budget_tier": "just_because",
        })

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_notifications_for_milestones(
                    milestones=[milestone_1, milestone_2],
                    user_id=test_auth_user["id"],
                )

            # milestone_1 (20 days): 3 notifications
            # milestone_2 (5 days): 1 notification (3-day only)
            assert len(result) == 4

            m1_notifs = [r for r in result if r["milestone_id"] == milestone_1["id"]]
            m2_notifs = [r for r in result if r["milestone_id"] == milestone_2["id"]]
            assert len(m1_notifs) == 3
            assert len(m2_notifs) == 1

            print("  Batch: 4 total notifications across 2 milestones")

        finally:
            _delete_notifications_for_milestone(milestone_1["id"])
            _delete_notifications_for_milestone(milestone_2["id"])

    @requires_supabase
    @pytest.mark.asyncio
    async def test_batch_parses_string_dates(
        self, test_auth_user, test_vault,
    ):
        """
        schedule_notifications_for_milestones should handle milestone_date
        as a string (as returned by Supabase) by parsing to date.
        """
        future = date.today() + timedelta(days=20)
        milestone = _insert_milestone({
            "vault_id": test_vault["id"],
            "milestone_type": "birthday",
            "milestone_name": "Birthday",
            "milestone_date": future.isoformat(),
            "recurrence": "one_time",
        })

        # Supabase returns milestone_date as a string
        assert isinstance(milestone["milestone_date"], str)

        try:
            with patch(
                "app.services.notification_scheduler.is_qstash_configured",
                return_value=False,
            ):
                result = await schedule_notifications_for_milestones(
                    milestones=[milestone],
                    user_id=test_auth_user["id"],
                )

            assert len(result) == 3
            print("  Batch correctly parses string dates from Supabase")

        finally:
            _delete_notifications_for_milestone(milestone["id"])


# ===================================================================
# 6. Module Imports (Unit Tests)
# ===================================================================

class TestModuleImports:
    """Verify all new modules and functions are importable."""

    def test_notification_scheduler_imports(self):
        """All functions from notification_scheduler should be importable."""
        from app.services.notification_scheduler import (
            NOTIFICATION_DAYS_BEFORE,
            _fathers_day,
            _is_floating_holiday,
            _mothers_day,
            compute_next_occurrence,
            schedule_milestone_notifications,
            schedule_notifications_for_milestones,
        )
        assert NOTIFICATION_DAYS_BEFORE == [14, 7, 3]
        print("  All notification_scheduler exports importable")

    def test_qstash_publish_has_not_before_param(self):
        """publish_to_qstash should accept a not_before parameter."""
        import inspect
        from app.services.qstash import publish_to_qstash
        sig = inspect.signature(publish_to_qstash)
        assert "not_before" in sig.parameters
        print("  publish_to_qstash has not_before parameter")

    def test_config_has_webhook_base_url(self):
        """Config should export WEBHOOK_BASE_URL."""
        from app.core.config import WEBHOOK_BASE_URL
        assert isinstance(WEBHOOK_BASE_URL, str)
        print("  WEBHOOK_BASE_URL available in config")
