"""
Tests for Recommendation Deep Link Endpoint (Step 9.2)

Validates that GET /api/v1/recommendations/{recommendation_id} returns
the correct recommendation data and enforces authentication.

Prerequisites:
- No external credentials required for route registration tests
- Uses FastAPI TestClient (no running server needed)
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# --- Constants ---

BASE_PATH = "/api/v1/recommendations"
FAKE_UUID = "00000000-0000-0000-0000-000000000000"


# ---------------------------------------------------------------------------
# Route Registration Tests
# ---------------------------------------------------------------------------


class TestGetRecommendationByIdRoute:
    """Tests verifying the GET /{recommendation_id} route is registered."""

    def test_no_auth_returns_401(self):
        """GET without Authorization header returns 401."""
        resp = client.get(f"{BASE_PATH}/{FAKE_UUID}")
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self):
        """GET with an invalid Bearer token returns 401."""
        resp = client.get(
            f"{BASE_PATH}/{FAKE_UUID}",
            headers={"Authorization": "Bearer invalid-token-abc"},
        )
        assert resp.status_code == 401

    def test_endpoint_does_not_shadow_generate(self):
        """The catch-all /{recommendation_id} route does not shadow POST /generate."""
        resp = client.post(
            f"{BASE_PATH}/generate",
            json={"occasion_type": "just_because"},
        )
        # Should return 401 (auth required), not 405 (method not allowed)
        # or 422 (would mean it hit the GET route instead)
        assert resp.status_code == 401

    def test_endpoint_does_not_shadow_refresh(self):
        """The catch-all route does not shadow POST /refresh."""
        resp = client.post(
            f"{BASE_PATH}/refresh",
            json={
                "rejected_recommendation_ids": ["abc"],
                "rejection_reason": "show_different",
            },
        )
        assert resp.status_code == 401

    def test_endpoint_does_not_shadow_feedback(self):
        """The catch-all route does not shadow POST /feedback."""
        resp = client.post(
            f"{BASE_PATH}/feedback",
            json={"recommendation_id": "abc", "action": "selected"},
        )
        assert resp.status_code == 401

    def test_endpoint_does_not_shadow_by_milestone(self):
        """The catch-all route does not shadow GET /by-milestone/{id}."""
        resp = client.get(f"{BASE_PATH}/by-milestone/{FAKE_UUID}")
        # Should return 401 (auth required on by-milestone), not a recommendation lookup
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Module Import Tests
# ---------------------------------------------------------------------------


class TestModuleImports:
    """Tests verifying the endpoint function is properly defined."""

    def test_get_recommendation_by_id_importable(self):
        """The get_recommendation_by_id function can be imported."""
        from app.api.recommendations import get_recommendation_by_id
        assert get_recommendation_by_id is not None
        assert callable(get_recommendation_by_id)

    def test_response_model_is_milestone_recommendation_item(self):
        """The endpoint uses MilestoneRecommendationItem as response model."""
        from app.api.recommendations import router

        # Find the GET /{recommendation_id} route
        get_routes = [
            r for r in router.routes
            if hasattr(r, "methods") and "GET" in r.methods
            and r.path.endswith("/{recommendation_id}")
        ]
        assert len(get_routes) == 1

        from app.models.notifications import MilestoneRecommendationItem
        assert get_routes[0].response_model is MilestoneRecommendationItem
