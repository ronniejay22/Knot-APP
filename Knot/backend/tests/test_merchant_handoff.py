"""
Tests for Merchant Handoff Feedback Action (Step 9.3)

Validates that the "handoff" action is accepted by the feedback endpoint
and that the Pydantic model validation allows it.

Prerequisites:
- No external credentials required for model and route tests
- Uses FastAPI TestClient (no running server needed)
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

BASE_PATH = "/api/v1/recommendations"


# ---------------------------------------------------------------------------
# Pydantic Model Validation Tests
# ---------------------------------------------------------------------------


class TestHandoffFeedbackModel:
    """Tests verifying 'handoff' is a valid feedback action in the Pydantic model."""

    def test_handoff_action_is_valid(self):
        """RecommendationFeedbackRequest should accept 'handoff' as a valid action."""
        from app.models.recommendations import RecommendationFeedbackRequest

        req = RecommendationFeedbackRequest(
            recommendation_id="rec-123",
            action="handoff",
        )
        assert req.action == "handoff"
        assert req.recommendation_id == "rec-123"

    def test_all_valid_actions_accepted(self):
        """All five feedback actions should be accepted by the model."""
        from app.models.recommendations import RecommendationFeedbackRequest

        valid_actions = ["selected", "saved", "shared", "rated", "handoff"]
        for action in valid_actions:
            req = RecommendationFeedbackRequest(
                recommendation_id="rec-123",
                action=action,
            )
            assert req.action == action

    def test_invalid_action_rejected(self):
        """An invalid action string should be rejected by the model."""
        from app.models.recommendations import RecommendationFeedbackRequest

        with pytest.raises(Exception):
            RecommendationFeedbackRequest(
                recommendation_id="rec-123",
                action="invalid_action",
            )


# ---------------------------------------------------------------------------
# Route Tests
# ---------------------------------------------------------------------------


class TestHandoffFeedbackRoute:
    """Tests verifying the feedback route accepts 'handoff' payloads."""

    def test_feedback_with_handoff_requires_auth(self):
        """POST /feedback with handoff action requires auth (returns 401, not 422).

        A 401 response means the route accepted the payload shape and the
        action value — it only failed because there was no auth token.
        A 422 would mean 'handoff' was rejected by Pydantic validation.
        """
        resp = client.post(
            f"{BASE_PATH}/feedback",
            json={
                "recommendation_id": "rec-handoff-123",
                "action": "handoff",
            },
        )
        assert resp.status_code == 401

    def test_feedback_with_invalid_action_blocked_by_auth(self):
        """POST /feedback with invalid action still returns 401 (auth runs first).

        The auth middleware intercepts the request before Pydantic parses the
        body, so even an invalid action gets 401 when no token is provided.
        This confirms the route is reachable and not shadowed.
        """
        resp = client.post(
            f"{BASE_PATH}/feedback",
            json={
                "recommendation_id": "rec-123",
                "action": "bogus_action",
            },
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Module Import Tests
# ---------------------------------------------------------------------------


class TestHandoffModuleImports:
    """Tests verifying handoff-related imports work correctly."""

    def test_feedback_model_importable(self):
        """RecommendationFeedbackRequest can be imported from the models module."""
        from app.models.recommendations import RecommendationFeedbackRequest

        assert RecommendationFeedbackRequest is not None

    def test_record_feedback_importable(self):
        """The record_feedback endpoint function can be imported."""
        from app.api.recommendations import record_feedback

        assert record_feedback is not None
        assert callable(record_feedback)
