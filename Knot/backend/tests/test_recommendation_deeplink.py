"""
Tests for Recommendation Deep Link Endpoint (Step 9.2)

Validates that GET /api/v1/recommendations/{recommendation_id} returns
the correct recommendation data and enforces authentication.

Prerequisites:
- No external credentials required for route registration tests
- Uses FastAPI TestClient (no running server needed)
"""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# --- Constants ---

BASE_PATH = "/api/v1/recommendations"
FAKE_UUID = "00000000-0000-0000-0000-000000000000"
VAULT_ID = "11111111-1111-1111-1111-111111111111"


def _stored_row(**overrides) -> dict:
    """A stored `recommendations` row as `/{id}` reads it back."""
    row = {
        "id": FAKE_UUID,
        "vault_id": VAULT_ID,
        "recommendation_type": "gift",
        "title": "Hand-thrown Mug",
        "description": "A speckled stoneware mug.",
        "external_url": "https://example.com/mug",
        "price_cents": 4200,
        "merchant_name": "Clay Co.",
        "image_url": "https://example.com/mug.jpg",
        "created_at": "2026-09-20T00:00:00+00:00",
    }
    row.update(overrides)
    return row


def _mock_supabase(rec_row: dict) -> MagicMock:
    """A service client whose vault and recommendation lookups both hit."""
    mock_client = MagicMock()

    def table_side_effect(table_name: str):
        table = MagicMock()
        if table_name == "partner_vaults":
            table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"id": VAULT_ID}]
            )
        elif table_name == "recommendations":
            table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[rec_row]
            )
        return table

    mock_client.table.side_effect = table_side_effect
    return mock_client


@pytest.fixture
def auth_override():
    from app.core.security import get_active_user_id

    app.dependency_overrides[get_active_user_id] = lambda: "test-user-123"
    yield
    app.dependency_overrides.pop(get_active_user_id, None)


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
# Field mapping
# ---------------------------------------------------------------------------


class TestGetRecommendationByIdFields:
    """
    `/{id}` builds its item inline rather than through `_stored_rows_to_items`,
    so a column added to the shared mapper is NOT automatically served here.
    """

    def test_serves_the_stored_headline(self, auth_override):
        mock_client = _mock_supabase(_stored_row(headline="Small Luxuries"))

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get(f"{BASE_PATH}/{FAKE_UUID}")

        assert resp.status_code == 200
        assert resp.json()["headline"] == "Small Luxuries"

    def test_legacy_row_without_a_headline_serves_null(self, auth_override):
        mock_client = _mock_supabase(_stored_row())

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get(f"{BASE_PATH}/{FAKE_UUID}")

        assert resp.status_code == 200
        assert resp.json()["headline"] is None


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
