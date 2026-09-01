"""
Multi-device push delivery.

`users.device_token` was a single column, so registering a device overwrote
whatever was there — a user with two devices only ever received notifications
on whichever they had opened most recently, and nothing errored to say so.
Delivery now fans out over every row in `user_devices`.

These are offline unit tests: the Supabase client and the APNs send are both
mocked, so nothing here touches a network or a database.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.apns import _is_dead_token, deliver_push_notification

DELIVER_KWARGS = dict(
    user_id="user-1",
    notification_id="notif-1",
    milestone_id="ms-1",
    partner_name="Jasmine",
    milestone_name="Jasmine's Birthday",
    days_before=7,
    vibes=[],
    recommendations_count=3,
)


def _client_with_devices(tokens: list[str]):
    """A Supabase client mock whose `user_devices` select returns `tokens`."""
    select_result = MagicMock()
    select_result.data = [{"device_token": t} for t in tokens]

    table = MagicMock()
    table.select.return_value = table
    table.eq.return_value = table
    table.execute.return_value = select_result
    # delete().in_().execute() for pruning
    table.delete.return_value = table
    table.in_.return_value = table
    table.update.return_value = table

    client = MagicMock()
    client.table.return_value = table
    return client, table


def _ok(apns_id="apns-ok"):
    return {"success": True, "apns_id": apns_id, "status_code": 200, "reason": None}


def _fail(status_code=400, reason="BadDeviceToken"):
    return {
        "success": False,
        "apns_id": None,
        "status_code": status_code,
        "reason": reason,
    }


# ===================================================================
# 1. Fan-out
# ===================================================================

class TestFanOut:

    @pytest.mark.asyncio
    async def test_sends_to_every_registered_device(self):
        """The regression: two devices, two pushes — not one."""
        client, _ = _client_with_devices(["tok-phone", "tok-tablet", "tok-sim"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, return_value=_ok(),
            ) as send:
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert send.await_count == 3
        sent_tokens = {call.args[0] for call in send.await_args_list}
        assert sent_tokens == {"tok-phone", "tok-tablet", "tok-sim"}
        assert result["delivered_count"] == 3
        assert result["device_count"] == 3

    @pytest.mark.asyncio
    async def test_every_device_gets_the_same_payload(self):
        client, _ = _client_with_devices(["a", "b"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, return_value=_ok(),
            ) as send:
                await deliver_push_notification(**DELIVER_KWARGS)

        payloads = [call.args[1] for call in send.await_args_list]
        assert payloads[0] == payloads[1]

    @pytest.mark.asyncio
    async def test_one_device_succeeding_is_success(self):
        """A dead tablet must not mark the whole notification undelivered."""
        client, _ = _client_with_devices(["good", "bad"])

        async def outcome(token, _payload):
            return _ok() if token == "good" else _fail()

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is True
        assert result["delivered_count"] == 1
        assert result["device_count"] == 2

    @pytest.mark.asyncio
    async def test_all_devices_failing_is_failure(self):
        client, _ = _client_with_devices(["a", "b"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value=_fail(status_code=503, reason="ServiceUnavailable"),
            ):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is False
        assert result["delivered_count"] == 0
        assert result["reason"] == "ServiceUnavailable"

    @pytest.mark.asyncio
    async def test_one_device_raising_does_not_stop_the_others(self):
        """`gather` collects exceptions rather than cancelling siblings."""
        client, _ = _client_with_devices(["boom", "fine"])

        async def outcome(token, _payload):
            if token == "boom":
                raise RuntimeError("connection reset")
            return _ok()

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is True
        assert result["delivered_count"] == 1

    @pytest.mark.asyncio
    async def test_no_devices_returns_the_unchanged_contract(self):
        """
        The webhook treats `no_device_token` as a permanent failure and cancels
        the notification, so this string must not drift.
        """
        client, _ = _client_with_devices([])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is False
        assert result["reason"] == "no_device_token"
        assert result["device_count"] == 0

    @pytest.mark.asyncio
    async def test_null_tokens_are_ignored(self):
        client, _ = _client_with_devices([])
        client.table.return_value.execute.return_value.data = [
            {"device_token": None}, {"device_token": ""},
        ]

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["reason"] == "no_device_token"

    @pytest.mark.asyncio
    async def test_lookup_failure_is_not_mistaken_for_no_devices(self):
        """
        A database error must stay transient so QStash retries. Reporting
        `no_device_token` would cancel the notification permanently.
        """
        client, table = _client_with_devices(["a"])
        table.execute.side_effect = Exception("connection refused")

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is False
        assert result["reason"].startswith("device_token_lookup_failed")
        assert result["reason"] != "no_device_token"


# ===================================================================
# 2. Pruning
# ===================================================================

class TestDeadTokenPruning:

    @pytest.mark.parametrize(
        "outcome,expected",
        [
            # The only verdict that means the app is gone from the device.
            ({"status_code": 410, "reason": "Unregistered"}, True),
            # NOT dead. APNs returns these for SERVER misconfiguration too — a
            # wrong APNS_USE_SANDBOX or bundle ID makes every push 400. Pruning
            # on them would delete every device row on the first send after a
            # bad deploy, and delivery no longer reads users.device_token, so
            # there would be no way back short of every user relaunching the
            # app on every device.
            ({"status_code": 400, "reason": "BadDeviceToken"}, False),
            ({"status_code": 400, "reason": "DeviceTokenNotForTopic"}, False),
            # Transient — pruning these would unsubscribe users during an outage.
            ({"status_code": 429, "reason": "TooManyRequests"}, False),
            ({"status_code": 503, "reason": "ServiceUnavailable"}, False),
            ({"status_code": 500, "reason": "InternalServerError"}, False),
            ({"status_code": 0, "reason": None}, False),
            # Both halves must match: a 410 with a different reason, or the
            # right reason with the wrong status, is not a confirmed death.
            ({"status_code": 410, "reason": "ExpiredProviderToken"}, False),
            ({"status_code": 400, "reason": "Unregistered"}, False),
        ],
    )
    def test_only_confirmed_death_counts_as_dead(self, outcome, expected):
        assert _is_dead_token(outcome) is expected

    @pytest.mark.asyncio
    async def test_a_misconfigured_sender_does_not_wipe_every_device(self):
        """
        The catastrophic case. A wrong APNs environment 400s every push; if
        that pruned, one bad deploy would unsubscribe the entire user base.
        """
        client, table = _client_with_devices(["phone", "tablet", "laptop"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value=_fail(400, "BadDeviceToken"),
            ):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        table.delete.assert_not_called()
        assert result["pruned_count"] == 0
        assert result["device_count"] == 3

    @pytest.mark.asyncio
    async def test_dead_tokens_are_deleted(self):
        client, table = _client_with_devices(["live", "dead"])

        async def outcome(token, _payload):
            return _ok() if token == "live" else _fail(410, "Unregistered")

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        table.delete.assert_called_once()
        table.in_.assert_called_once_with("device_token", ["dead"])
        assert result["pruned_count"] == 1

    @pytest.mark.asyncio
    async def test_transient_failures_are_not_pruned(self):
        client, table = _client_with_devices(["a"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value=_fail(503, "ServiceUnavailable"),
            ):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        table.delete.assert_not_called()
        assert result["pruned_count"] == 0

    @pytest.mark.asyncio
    async def test_prune_failure_does_not_fail_the_delivery(self):
        """Housekeeping must never sink a push that was actually delivered."""
        client, table = _client_with_devices(["live", "dead"])
        table.delete.side_effect = Exception("delete blew up")

        async def outcome(token, _payload):
            return _ok() if token == "live" else _fail(410, "Unregistered")

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is True
        assert result["pruned_count"] == 0

    @pytest.mark.asyncio
    async def test_partial_transient_failure_still_reports_success(self):
        """
        One device 503s, another takes it. The notification did reach the user,
        so failing here would make QStash re-run the whole delivery and push a
        duplicate to the device that already got it.
        """
        client, _ = _client_with_devices(["ok", "flaky"])

        async def outcome(token, _payload):
            return _ok() if token == "ok" else _fail(503, "ServiceUnavailable")

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is True
        assert result["delivered_count"] == 1
        assert result["failed_count"] == 1
        assert result["device_count"] == 2

    @pytest.mark.asyncio
    async def test_total_failure_surfaces_a_transient_reason_over_a_dead_one(self):
        """
        Nothing landed. The webhook decides retry-vs-cancel from `reason`, so a
        retryable cause must win over an unrecoverable one.
        """
        client, _ = _client_with_devices(["gone", "flaky"])

        async def outcome(token, _payload):
            if token == "gone":
                return _fail(410, "Unregistered")
            return _fail(503, "ServiceUnavailable")

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch("app.services.apns.send_push_notification", side_effect=outcome):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        assert result["success"] is False
        assert result["reason"] == "ServiceUnavailable"
        assert result["pruned_count"] == 1


# ===================================================================
# 3. Caller contract
# ===================================================================

class TestResultContract:
    """`notifications.py` reads `success` and `reason`; neither may drift."""

    @pytest.mark.asyncio
    async def test_success_result_keeps_the_original_keys(self):
        client, _ = _client_with_devices(["a"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, return_value=_ok("apns-xyz"),
            ):
                result = await deliver_push_notification(**DELIVER_KWARGS)

        for key in ("success", "apns_id", "status_code", "reason"):
            assert key in result
        assert result["apns_id"] == "apns-xyz"
        assert result["status_code"] == 200
        assert result["reason"] is None
