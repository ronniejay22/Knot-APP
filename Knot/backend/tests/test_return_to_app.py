"""
Tests for Return-to-App Purchase Tracking (Step 9.4)

Validates that the "purchased" action is accepted by the feedback endpoint
and that the Pydantic model validation allows it alongside rating and feedback_text.

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


class TestPurchasedFeedbackModel:
    """Tests verifying 'purchased' is a valid feedback action in the Pydantic model."""

    def test_purchased_action_is_valid(self):
        """RecommendationFeedbackRequest should accept 'purchased' as a valid action."""
        from app.models.recommendations import RecommendationFeedbackRequest

        req = RecommendationFeedbackRequest(
            recommendation_id="rec-123",
            action="purchased",
        )
        assert req.action == "purchased"
        assert req.recommendation_id == "rec-123"

    def test_purchased_with_rating(self):
        """'purchased' action should accept an optional rating (1-5)."""
        from app.models.recommendations import RecommendationFeedbackRequest

        req = RecommendationFeedbackRequest(
            recommendation_id="rec-123",
            action="purchased",
            rating=5,
        )
        assert req.action == "purchased"
        assert req.rating == 5

    def test_purchased_with_feedback_text(self):
        """'purchased' action should accept optional feedback_text."""
        from app.models.recommendations import RecommendationFeedbackRequest

        req = RecommendationFeedbackRequest(
            recommendation_id="rec-123",
            action="purchased",
            feedback_text="She loved it!",
        )
        assert req.action == "purchased"
        assert req.feedback_text == "She loved it!"

    def test_purchased_with_invalid_rating_rejected(self):
        """Rating value of 6 should be rejected by the validator."""
        from app.models.recommendations import RecommendationFeedbackRequest

        with pytest.raises(Exception):
            RecommendationFeedbackRequest(
                recommendation_id="rec-123",
                action="purchased",
                rating=6,
            )

    def test_all_valid_actions_accepted_including_purchased(self):
        """All six feedback actions should be accepted by the model."""
        from app.models.recommendations import RecommendationFeedbackRequest

        valid_actions = ["selected", "saved", "shared", "rated", "handoff", "purchased"]
        for action in valid_actions:
            req = RecommendationFeedbackRequest(
                recommendation_id="rec-123",
                action=action,
            )
            assert req.action == action


# ---------------------------------------------------------------------------
# Route Tests
# ---------------------------------------------------------------------------


class TestPurchasedFeedbackRoute:
    """Tests verifying the feedback route accepts 'purchased' payloads."""

    def test_feedback_with_purchased_requires_auth(self):
        """POST /feedback with purchased action requires auth (returns 401, not 422).

        A 401 response means the route accepted the payload shape and the
        action value — it only failed because there was no auth token.
        A 422 would mean 'purchased' was rejected by Pydantic validation.
        """
        resp = client.post(
            f"{BASE_PATH}/feedback",
            json={
                "recommendation_id": "rec-purchased-123",
                "action": "purchased",
            },
        )
        assert resp.status_code == 401

    def test_purchased_with_rating_requires_auth(self):
        """POST /feedback with purchased action and rating requires auth (returns 401).

        Confirms the payload with both action and rating fields is accepted
        structurally, and only fails on authentication.
        """
        resp = client.post(
            f"{BASE_PATH}/feedback",
            json={
                "recommendation_id": "rec-purchased-456",
                "action": "purchased",
                "rating": 4,
                "feedback_text": "Great recommendation!",
            },
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Module Import Tests
# ---------------------------------------------------------------------------


class TestPurchasedModuleImports:
    """Tests verifying purchased-related imports work correctly."""

    def test_feedback_model_importable(self):
        """RecommendationFeedbackRequest can be imported and includes 'purchased'."""
        from app.models.recommendations import RecommendationFeedbackRequest

        assert RecommendationFeedbackRequest is not None
        # Verify 'purchased' is accepted without exception
        req = RecommendationFeedbackRequest(
            recommendation_id="test",
            action="purchased",
        )
        assert req is not None
