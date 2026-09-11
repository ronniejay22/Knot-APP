"""
The "your picks are ready" push.

A generation run takes ~20-30s. If the user leaves the app during it, iOS
grants only ~30s of background execution and then suspends the app — taking
the in-flight request, and any chance of scheduling a local notification, with
it. So completion is announced by a real remote push fired from the backend
once the picks are stored, which reaches the user even if iOS suspended or
killed the app.

These are offline unit tests: the Supabase client, the APNs send, and the
pipeline are all mocked, so nothing here touches a network or a database.
"""

import inspect
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.recommendations import (
    _notify_recommendations_ready,
    generate_recommendations,
    refresh_recommendations,
)
from app.services.apns import (
    RECOMMENDATIONS_READY_CATEGORY,
    build_recommendations_ready_payload,
    deliver_recommendations_ready,
)


def _client_with_devices(tokens: list[str]):
    """A Supabase client mock whose `user_devices` select returns `tokens`."""
    select_result = MagicMock()
    select_result.data = [{"device_token": t} for t in tokens]

    table = MagicMock()
    table.select.return_value = table
    table.eq.return_value = table
    table.execute.return_value = select_result
    table.delete.return_value = table
    table.in_.return_value = table

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
# 1. Payload
# ===================================================================

class TestPayload:

    def test_title_category_and_sound(self):
        payload = build_recommendations_ready_payload(partner_name="Jas", count=3)
        aps = payload["aps"]

        assert aps["alert"]["title"] == "Your picks are ready ✨"
        assert aps["category"] == RECOMMENDATIONS_READY_CATEGORY
        assert aps["sound"] == "default"

    def test_body_names_the_partner_and_the_count(self):
        payload = build_recommendations_ready_payload(partner_name="Jas", count=3)
        assert payload["aps"]["alert"]["body"] == "Tap to see 3 ideas we picked for Jas."

    def test_body_falls_back_when_partner_name_is_missing(self):
        for missing in (None, ""):
            body = build_recommendations_ready_payload(
                partner_name=missing, count=3,
            )["aps"]["alert"]["body"]
            assert body == "Tap to see 3 ideas we picked out."
            assert "None" not in body

    def test_singular_when_only_one_idea(self):
        body = build_recommendations_ready_payload(
            partner_name="Jas", count=1,
        )["aps"]["alert"]["body"]
        assert "1 idea we picked" in body
        assert "ideas" not in body

    def test_zero_count_does_not_leak_into_the_copy(self):
        """
        The endpoints only push on a successful run, which always carries picks
        — but "0 ideas" would be worse than saying nothing.
        """
        body = build_recommendations_ready_payload(
            partner_name="Jas", count=0,
        )["aps"]["alert"]["body"]
        assert "0" not in body
        assert body == "Tap to see your personalized recommendations."

    def test_carries_no_milestone_id(self):
        """
        Load-bearing. `AppDelegate.didReceive` routes any push carrying a
        `milestone_id` into `MilestoneRecommendationsCoverView`, a full-screen
        cover — which on a tap would stack a duplicate cover over the
        recommendations the user is already looking at. Without one the
        delegate ignores the tap and the app just resumes where it was.
        """
        payload = build_recommendations_ready_payload(partner_name="Jas", count=3)

        assert "milestone_id" not in payload
        assert "notification_id" not in payload
        # Only the `aps` envelope — no custom top-level keys at all.
        assert set(payload) == {"aps"}


# ===================================================================
# 2. Delivery — shares the fan-out/prune core with milestone pushes
# ===================================================================

class TestDelivery:

    @pytest.mark.asyncio
    async def test_sends_to_every_registered_device(self):
        client, _ = _client_with_devices(["tok-phone", "tok-tablet"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, return_value=_ok(),
            ) as send:
                result = await deliver_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        assert send.await_count == 2
        assert result["success"] is True
        assert result["device_count"] == 2
        assert result["delivered_count"] == 2

    @pytest.mark.asyncio
    async def test_sends_the_ready_payload_not_the_milestone_one(self):
        client, _ = _client_with_devices(["tok-1"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, return_value=_ok(),
            ) as send:
                await deliver_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        _token, payload = send.await_args.args
        assert payload["aps"]["category"] == RECOMMENDATIONS_READY_CATEGORY

    @pytest.mark.asyncio
    async def test_one_failing_device_does_not_stop_the_others(self):
        client, _ = _client_with_devices(["tok-dead", "tok-live"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock, side_effect=[_fail(), _ok()],
            ):
                result = await deliver_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        assert result["success"] is True
        assert result["delivered_count"] == 1
        assert result["failed_count"] == 1

    @pytest.mark.asyncio
    async def test_no_registered_device_reports_no_device_token(self):
        client, _ = _client_with_devices([])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            result = await deliver_recommendations_ready(
                user_id="user-1", partner_name="Jas", count=3,
            )

        assert result["success"] is False
        assert result["reason"] == "no_device_token"

    @pytest.mark.asyncio
    async def test_prunes_only_on_410_unregistered(self):
        """
        Inherited from the shared `_deliver_payload`. A misconfigured sender
        400s every push, so pruning on anything broader would delete every row
        in `user_devices` on the first send after a bad deploy.
        """
        client, table = _client_with_devices(["tok-1"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value=_fail(400, "BadDeviceToken"),
            ):
                result = await deliver_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        assert result["pruned_count"] == 0
        table.delete.assert_not_called()

    @pytest.mark.asyncio
    async def test_prunes_a_device_apns_reports_as_gone(self):
        client, table = _client_with_devices(["tok-gone"])

        with patch("app.db.supabase_client.get_service_client", return_value=client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value=_fail(410, "Unregistered"),
            ):
                result = await deliver_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        assert result["pruned_count"] == 1
        table.delete.assert_called_once()


# ===================================================================
# 3. The guards around firing it
# ===================================================================

def _users_client(notifications_enabled):
    """A Supabase client mock whose `users` select returns one row."""
    result = MagicMock()
    result.data = (
        [] if notifications_enabled is None
        else [{"notifications_enabled": notifications_enabled}]
    )

    table = MagicMock()
    table.select.return_value = table
    table.eq.return_value = table
    table.limit.return_value = table
    table.execute.return_value = result

    client = MagicMock()
    client.table.return_value = table
    return client


class TestNotifyGuards:

    @pytest.mark.asyncio
    async def test_skipped_when_apns_is_not_configured(self):
        """Local dev without APNs credentials must not attempt a delivery."""
        with patch("app.api.recommendations.is_apns_configured", return_value=False):
            with patch(
                "app.api.recommendations.deliver_recommendations_ready",
                new_callable=AsyncMock,
            ) as deliver:
                await _notify_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )

        deliver.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_skipped_when_the_run_produced_nothing(self):
        """
        A run can finish empty — the pipeline returning no candidates only logs
        a warning and still answers 200 with an empty list. Announcing "your
        picks are ready" would walk the user back to an empty screen.
        """
        with patch("app.api.recommendations.is_apns_configured", return_value=True):
            with patch(
                "app.api.recommendations.deliver_recommendations_ready",
                new_callable=AsyncMock,
            ) as deliver:
                await _notify_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=0,
                )

        deliver.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_skipped_when_the_user_turned_notifications_off(self):
        with patch("app.api.recommendations.is_apns_configured", return_value=True):
            with patch(
                "app.api.recommendations.get_service_client",
                return_value=_users_client(False),
            ):
                with patch(
                    "app.api.recommendations.deliver_recommendations_ready",
                    new_callable=AsyncMock,
                ) as deliver:
                    await _notify_recommendations_ready(
                        user_id="user-1", partner_name="Jas", count=3,
                    )

        deliver.assert_not_awaited()

    @pytest.mark.asyncio
    @pytest.mark.parametrize("enabled", [True, None])
    async def test_sent_when_enabled_or_unknown(self, enabled):
        """`None` is the absent-row case — only an explicit False suppresses."""
        with patch("app.api.recommendations.is_apns_configured", return_value=True):
            with patch(
                "app.api.recommendations.get_service_client",
                return_value=_users_client(enabled),
            ):
                with patch(
                    "app.api.recommendations.deliver_recommendations_ready",
                    new_callable=AsyncMock, return_value=_ok(),
                ) as deliver:
                    await _notify_recommendations_ready(
                        user_id="user-1", partner_name="Jas", count=3,
                    )

        deliver.assert_awaited_once_with(
            user_id="user-1", partner_name="Jas", count=3,
        )

    @pytest.mark.asyncio
    async def test_a_delivery_failure_never_raises(self):
        """
        It runs on `BackgroundTasks` after the response is sent, but an
        exception escaping here would still surface as a server-side error for
        something the user already received successfully.
        """
        with patch("app.api.recommendations.is_apns_configured", return_value=True):
            with patch(
                "app.api.recommendations.get_service_client",
                return_value=_users_client(True),
            ):
                with patch(
                    "app.api.recommendations.deliver_recommendations_ready",
                    new_callable=AsyncMock, side_effect=RuntimeError("APNs down"),
                ):
                    await _notify_recommendations_ready(
                        user_id="user-1", partner_name="Jas", count=3,
                    )

    @pytest.mark.asyncio
    async def test_a_lookup_failure_never_raises(self):
        broken = MagicMock()
        broken.table.side_effect = RuntimeError("no database")

        with patch("app.api.recommendations.is_apns_configured", return_value=True):
            with patch(
                "app.api.recommendations.get_service_client", return_value=broken,
            ):
                await _notify_recommendations_ready(
                    user_id="user-1", partner_name="Jas", count=3,
                )


# ===================================================================
# 4. Both generation endpoints queue it
# ===================================================================

class TestEndpointsQueueThePush:

    @pytest.mark.parametrize(
        "handler", [generate_recommendations, refresh_recommendations],
    )
    def test_handler_accepts_background_tasks(self, handler):
        """
        The push must be queued, not awaited: generation already costs the
        client ~20-30s and nothing may be added to that wait.
        """
        from fastapi import BackgroundTasks

        params = inspect.signature(handler).parameters
        annotations = [p.annotation for p in params.values()]
        assert BackgroundTasks in annotations, (
            f"{handler.__name__} no longer declares a BackgroundTasks parameter — "
            "the recommendations-ready push cannot be queued."
        )

    @pytest.mark.asyncio
    async def test_generate_queues_the_push_with_partner_and_count(self):
        """
        Drives the real handler with the pipeline and database mocked, so this
        proves the wiring rather than the signature.
        """
        from fastapi import BackgroundTasks

        from app.agents.state import CandidateRecommendation, VaultBudget, VaultData
        from app.models.recommendations import RecommendationGenerateRequest

        vault = VaultData(
            vault_id="vault-1",
            partner_name="Jas",
            interests=["Cooking"],
            dislikes=["Gaming"],
            vibes=["romantic"],
            primary_love_language="quality_time",
            secondary_love_language="receiving_gifts",
            budgets=[
                VaultBudget(
                    occasion_type="just_because", min_amount=5000, max_amount=15000,
                )
            ],
        )
        candidates = [
            CandidateRecommendation(
                id=str(uuid.uuid4()),
                source="claude_search",
                type="gift",
                title=f"Pick {i}",
                external_url="https://example.com/thing",
            )
            for i in range(3)
        ]

        background_tasks = BackgroundTasks()

        with patch(
            "app.api.recommendations.load_vault_data",
            new_callable=AsyncMock, return_value=(vault, "vault-1"),
        ), patch(
            "app.api.recommendations.load_learned_weights",
            new_callable=AsyncMock, return_value=None,
        ), patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value={"final_three": candidates, "error": None},
        ), patch(
            "app.api.recommendations.get_service_client", return_value=MagicMock(),
        ):
            await generate_recommendations(
                payload=RecommendationGenerateRequest(occasion_type="just_because"),
                background_tasks=background_tasks,
                user_id="user-1",
            )

        queued = [
            t for t in background_tasks.tasks
            if t.func is _notify_recommendations_ready
        ]
        assert len(queued) == 1, "generate did not queue the recommendations-ready push"
        assert queued[0].kwargs == {
            "user_id": "user-1", "partner_name": "Jas", "count": 3,
        }


# ===================================================================
# 5. No double-notify with the milestone reminder
# ===================================================================

def test_milestone_webhook_does_not_send_a_recommendations_ready_push():
    """
    The QStash webhook runs `run_recommendation_pipeline` directly rather than
    calling `/generate`, so it keeps sending only its own milestone reminder.
    If it ever started calling the endpoint, a user would get two pushes.
    """
    import app.api.notifications as notifications

    assert not hasattr(notifications, "deliver_recommendations_ready")
    assert not hasattr(notifications, "_notify_recommendations_ready")
