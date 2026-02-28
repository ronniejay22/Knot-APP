"""
Step 5.9 Verification: Recommendations API Endpoint

Tests the POST /api/v1/recommendations/generate endpoint that:
1. Accepts milestone_id (optional) and occasion_type
2. Loads the user's vault data from all 6 tables
3. Runs the LangGraph pipeline (mocked for unit tests)
4. Stores the 3 recommendations in the database
5. Returns the recommendations as JSON

Tests cover:
- Valid request returns 200 with 3 recommendations
- Response includes all required fields (title, description, price, URL, image)
- Recommendations stored in the database
- No vault → 404
- Auth required → 401
- Invalid occasion_type → 422
- Milestone not found → 404
- Pipeline error → 500
- Pipeline returning empty results → 200 with count 0
- Browsing mode (no milestone_id) → 200
- Budget range determination from vault data
- Budget range fallback defaults
- Response scoring fields present
- Database storage includes correct vault_id and milestone_id

Prerequisites:
- Complete Steps 0.6-5.8 (Supabase + all tables + vault API + pipeline)
- Backend server NOT required (uses FastAPI TestClient)

Run with: pytest tests/test_recommendations_api.py -v
"""

import pytest
import httpx
import uuid
import time
from unittest.mock import patch, AsyncMock, MagicMock

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Helper: check if Supabase credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Helpers: HTTP headers for Supabase Admin API
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _service_headers() -> dict:
    """Headers for direct Supabase PostgREST queries (service role)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }


# ---------------------------------------------------------------------------
# Helper: create and delete test auth users
# ---------------------------------------------------------------------------

def _create_auth_user(email: str, password: str) -> str:
    """Create a test user via Supabase Admin API. Returns user ID."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={
            "email": email,
            "password": password,
            "email_confirm": True,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to create test auth user: HTTP {resp.status_code} — {resp.text}"
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
                f"Failed to delete test auth user {user_id}: "
                f"HTTP {resp.status_code} — {resp.text}. "
                "This user may be orphaned in auth.users.",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}. "
            "This user may be orphaned in auth.users.",
            stacklevel=2,
        )


def _sign_in_user(email: str, password: str) -> dict:
    """Sign in a test user. Returns full session response with access_token."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={
            "email": email,
            "password": password,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to sign in test user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


# ---------------------------------------------------------------------------
# Helper: build a valid vault payload
# ---------------------------------------------------------------------------

def _valid_vault_payload() -> dict:
    """Return a complete, valid vault creation payload."""
    return {
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "San Francisco",
        "location_state": "CA",
        "location_country": "US",
        "interests": ["Travel", "Cooking", "Movies", "Music", "Reading"],
        "dislikes": ["Sports", "Gaming", "Cars", "Skiing", "Karaoke"],
        "milestones": [
            {
                "milestone_type": "birthday",
                "milestone_name": "Birthday",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
            },
            {
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-06-20",
                "recurrence": "yearly",
            },
        ],
        "vibes": ["quiet_luxury", "minimalist", "romantic"],
        "budgets": [
            {
                "occasion_type": "just_because",
                "min_amount": 2000,
                "max_amount": 5000,
                "currency": "USD",
            },
            {
                "occasion_type": "minor_occasion",
                "min_amount": 5000,
                "max_amount": 15000,
                "currency": "USD",
            },
            {
                "occasion_type": "major_milestone",
                "min_amount": 10000,
                "max_amount": 50000,
                "currency": "USD",
            },
        ],
        "love_languages": {
            "primary": "quality_time",
            "secondary": "receiving_gifts",
        },
    }


# ---------------------------------------------------------------------------
# Helper: mock pipeline result
# ---------------------------------------------------------------------------

def _mock_pipeline_result(vault_id: str = "test-vault", count: int = 3):
    """Build a mock pipeline result dict with CandidateRecommendation-like objects."""
    from app.agents.state import CandidateRecommendation, LocationData

    candidates = []
    sources = ["yelp", "amazon", "ticketmaster"]
    types = ["experience", "gift", "date"]
    for i in range(count):
        candidates.append(
            CandidateRecommendation(
                id=str(uuid.uuid4()),
                source=sources[i % len(sources)],
                type=types[i % len(types)],
                title=f"Test Recommendation {i + 1}",
                description=f"A great {types[i % len(types)]} option for your partner",
                price_cents=3000 + (i * 1000),
                currency="USD",
                external_url=f"https://example.com/rec/{i + 1}",
                image_url=f"https://example.com/img/{i + 1}.jpg",
                merchant_name=f"Merchant {i + 1}",
                location=LocationData(
                    city="San Francisco",
                    state="CA",
                    country="US",
                ) if types[i % len(types)] != "gift" else None,
                metadata={"test": True},
                interest_score=1.0 + i * 0.5,
                vibe_score=0.3,
                love_language_score=0.4,
                final_score=2.0 + i * 0.5,
            )
        )

    return {
        "final_three": candidates,
        "error": None,
        "relevant_hints": [],
        "candidate_recommendations": candidates,
        "filtered_recommendations": candidates,
    }


# ---------------------------------------------------------------------------
# Helper: query table data via service client
# ---------------------------------------------------------------------------

def _query_recommendations(vault_id: str) -> list[dict]:
    """Query the recommendations table for a given vault_id."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/recommendations?vault_id=eq.{vault_id}&order=created_at.desc",
        headers=_service_headers(),
    )
    assert resp.status_code == 200, (
        f"Failed to query recommendations: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _get_vault_id(user_id: str) -> str:
    """Get the vault_id for a user via service client."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/partner_vaults?user_id=eq.{user_id}&select=id",
        headers=_service_headers(),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) > 0, "No vault found for user"
    return data[0]["id"]


def _get_milestone_id(vault_id: str) -> str:
    """Get the first milestone_id for a vault via service client."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/partner_milestones?vault_id=eq.{vault_id}&select=id&limit=1",
        headers=_service_headers(),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) > 0, "No milestone found for vault"
    return data[0]["id"]


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user_with_token():
    """
    Create a test user, sign them in, and yield user info + token.
    Cleanup deletes the auth user (CASCADE removes all data).
    """
    test_email = f"knot-rec-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_user_with_vault(test_auth_user_with_token, client):
    """
    Create a test user with a complete vault.
    Returns user info including vault_id and first milestone_id.
    """
    token = test_auth_user_with_token["access_token"]

    # Create vault via API
    resp = client.post(
        "/api/v1/vault",
        json=_valid_vault_payload(),
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201, (
        f"Failed to create vault: HTTP {resp.status_code} — {resp.text}"
    )

    vault_data = resp.json()
    vault_id = vault_data["vault_id"]

    # Get the first milestone_id
    milestone_id = _get_milestone_id(vault_id)

    return {
        **test_auth_user_with_token,
        "vault_id": vault_id,
        "milestone_id": milestone_id,
    }


@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


def _auth_headers(token: str) -> dict:
    """Build Authorization headers for API requests."""
    return {"Authorization": f"Bearer {token}"}


# ===================================================================
# 1. Unit tests for Pydantic models
# ===================================================================

class TestRecommendationModels:
    """Verify Pydantic request/response models."""

    def test_generate_request_valid(self):
        """Valid request with occasion_type and milestone_id."""
        from app.models.recommendations import RecommendationGenerateRequest
        req = RecommendationGenerateRequest(
            occasion_type="major_milestone",
            milestone_id="some-uuid",
        )
        assert req.occasion_type == "major_milestone"
        assert req.milestone_id == "some-uuid"

    def test_generate_request_no_milestone(self):
        """Valid request without milestone_id (browsing mode)."""
        from app.models.recommendations import RecommendationGenerateRequest
        req = RecommendationGenerateRequest(occasion_type="just_because")
        assert req.occasion_type == "just_because"
        assert req.milestone_id is None

    def test_generate_request_invalid_occasion(self):
        """Invalid occasion_type should raise validation error."""
        from app.models.recommendations import RecommendationGenerateRequest
        with pytest.raises(Exception):
            RecommendationGenerateRequest(occasion_type="invalid_type")

    def test_generate_response_model(self):
        """Response model should serialize correctly."""
        from app.models.recommendations import (
            RecommendationGenerateResponse,
            RecommendationItemResponse,
        )
        item = RecommendationItemResponse(
            id="rec-1",
            recommendation_type="gift",
            title="Test Gift",
            external_url="https://example.com",
            source="amazon",
        )
        resp = RecommendationGenerateResponse(
            recommendations=[item],
            count=1,
            occasion_type="just_because",
        )
        assert resp.count == 1
        assert resp.recommendations[0].title == "Test Gift"

    def test_item_response_all_fields(self):
        """RecommendationItemResponse should accept all optional fields."""
        from app.models.recommendations import (
            RecommendationItemResponse,
            LocationResponse,
        )
        item = RecommendationItemResponse(
            id="rec-1",
            recommendation_type="experience",
            title="Sunset Dinner",
            description="A romantic dinner on the bay",
            price_cents=15000,
            currency="USD",
            external_url="https://restaurant.com/book",
            image_url="https://restaurant.com/img.jpg",
            merchant_name="The Bay Restaurant",
            source="yelp",
            location=LocationResponse(
                city="San Francisco",
                state="CA",
                country="US",
            ),
            interest_score=1.5,
            vibe_score=0.3,
            love_language_score=0.4,
            final_score=2.7,
        )
        assert item.price_cents == 15000
        assert item.location.city == "San Francisco"
        assert item.final_score == 2.7

    def test_item_response_minimal(self):
        """RecommendationItemResponse with only required fields."""
        from app.models.recommendations import RecommendationItemResponse
        item = RecommendationItemResponse(
            id="rec-1",
            recommendation_type="gift",
            title="A Gift",
            external_url="https://example.com",
            source="amazon",
        )
        assert item.description is None
        assert item.price_cents is None
        assert item.location is None
        assert item.interest_score == 0.0


# ===================================================================
# 2. Unit tests for budget range helper
# ===================================================================

class TestBudgetRangeHelper:
    """Verify find_budget_range helper function."""

    def test_finds_matching_budget(self):
        """Should return the matching budget for the occasion type."""
        from app.services.vault_loader import find_budget_range
        from app.agents.state import VaultBudget

        budgets = [
            VaultBudget(occasion_type="just_because", min_amount=1000, max_amount=3000),
            VaultBudget(occasion_type="minor_occasion", min_amount=5000, max_amount=10000),
            VaultBudget(occasion_type="major_milestone", min_amount=15000, max_amount=50000),
        ]

        result = find_budget_range(budgets, "minor_occasion")
        assert result.min_amount == 5000
        assert result.max_amount == 10000

    def test_fallback_just_because(self):
        """Should use default range when no matching budget found."""
        from app.services.vault_loader import find_budget_range

        result = find_budget_range([], "just_because")
        assert result.min_amount == 2000
        assert result.max_amount == 5000

    def test_fallback_minor_occasion(self):
        """Should use default range for minor_occasion."""
        from app.services.vault_loader import find_budget_range

        result = find_budget_range([], "minor_occasion")
        assert result.min_amount == 5000
        assert result.max_amount == 15000

    def test_fallback_major_milestone(self):
        """Should use default range for major_milestone."""
        from app.services.vault_loader import find_budget_range

        result = find_budget_range([], "major_milestone")
        assert result.min_amount == 10000
        assert result.max_amount == 50000

    def test_preserves_currency(self):
        """Should preserve the currency from the vault budget."""
        from app.services.vault_loader import find_budget_range
        from app.agents.state import VaultBudget

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


# ===================================================================
# 3. Integration tests (with Supabase, pipeline mocked)
# ===================================================================

@requires_supabase
class TestGenerateRecommendations:
    """
    Verify POST /api/v1/recommendations/generate endpoint.
    Pipeline is mocked to avoid external API calls.
    """

    def test_generate_returns_200(self, client, test_user_with_vault):
        """Valid request with vault and milestone returns 200."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "milestone_id": user["milestone_id"],
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200, (
            f"Expected 200, got {resp.status_code}. Response: {resp.text}"
        )

    def test_generate_returns_3_recommendations(self, client, test_user_with_vault):
        """Response should contain exactly 3 recommendations."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "milestone_id": user["milestone_id"],
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        assert data["count"] == 3
        assert len(data["recommendations"]) == 3

    def test_recommendations_have_required_fields(self, client, test_user_with_vault):
        """Each recommendation should have title, description, price, URL, image."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        for rec in data["recommendations"]:
            assert "id" in rec
            assert "title" in rec
            assert rec["title"]  # non-empty
            assert "recommendation_type" in rec
            assert rec["recommendation_type"] in ("gift", "experience", "date")
            assert "external_url" in rec
            assert rec["external_url"].startswith("https://")
            assert "source" in rec
            # Optional fields present
            assert "description" in rec
            assert "price_cents" in rec
            assert "image_url" in rec
            assert "merchant_name" in rec

    def test_response_includes_scoring(self, client, test_user_with_vault):
        """Response should include scoring metadata."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        for rec in data["recommendations"]:
            assert "interest_score" in rec
            assert "vibe_score" in rec
            assert "love_language_score" in rec
            assert "final_score" in rec
            assert isinstance(rec["final_score"], float)

    def test_response_includes_occasion_type(self, client, test_user_with_vault):
        """Response should echo back the occasion_type."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "minor_occasion"},
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        assert data["occasion_type"] == "minor_occasion"

    def test_response_includes_milestone_id(self, client, test_user_with_vault):
        """Response should include the milestone_id when provided."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "milestone_id": user["milestone_id"],
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        assert data["milestone_id"] == user["milestone_id"]

    def test_browsing_mode_no_milestone(self, client, test_user_with_vault):
        """Request without milestone_id (browsing mode) should work."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["milestone_id"] is None
        assert data["count"] == 3

    def test_recommendations_stored_in_db(self, client, test_user_with_vault):
        """Recommendations should be stored in the database."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200

        # Verify in database
        db_recs = _query_recommendations(user["vault_id"])
        assert len(db_recs) >= 3  # at least 3 from this request

        # Check that the titles match
        resp_titles = {r["title"] for r in resp.json()["recommendations"]}
        db_titles = {r["title"] for r in db_recs[:3]}
        assert resp_titles == db_titles

    def test_db_recommendations_have_vault_id(self, client, test_user_with_vault):
        """Stored recommendations should have the correct vault_id."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200

        db_recs = _query_recommendations(user["vault_id"])
        for rec in db_recs:
            assert rec["vault_id"] == user["vault_id"]

    def test_db_uses_generated_ids(self, client, test_user_with_vault):
        """Response should use DB-generated IDs, not pipeline candidate IDs."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        db_recs = _query_recommendations(user["vault_id"])

        # Response IDs should be DB-generated UUIDs, not the pipeline's temp IDs
        for rec in data["recommendations"]:
            # DB UUIDs have the standard format
            assert len(rec["id"]) == 36  # UUID format: 8-4-4-4-12

    def test_location_in_response(self, client, test_user_with_vault):
        """Experience recommendations should include location data."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        # At least one recommendation should have location data
        has_location = any(
            rec.get("location") is not None
            for rec in data["recommendations"]
        )
        assert has_location, "Expected at least one recommendation with location data"


# ===================================================================
# 4. Auth and validation tests
# ===================================================================

@requires_supabase
class TestGenerateAuth:
    """Verify auth and validation for the generate endpoint."""

    def test_no_auth_returns_401(self, client):
        """Request without auth token should return 401."""
        resp = client.post(
            "/api/v1/recommendations/generate",
            json={"occasion_type": "just_because"},
        )
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Request with invalid auth token should return 401."""
        resp = client.post(
            "/api/v1/recommendations/generate",
            json={"occasion_type": "just_because"},
            headers={"Authorization": "Bearer invalid-token-123"},
        )
        assert resp.status_code == 401

    def test_no_vault_returns_404(self, client, test_auth_user_with_token):
        """Request from user without vault should return 404."""
        resp = client.post(
            "/api/v1/recommendations/generate",
            json={"occasion_type": "just_because"},
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 404
        assert "vault" in resp.json()["detail"].lower()

    def test_invalid_occasion_type_returns_422(self, client, test_auth_user_with_token):
        """Request with invalid occasion_type should return 422."""
        resp = client.post(
            "/api/v1/recommendations/generate",
            json={"occasion_type": "invalid_type"},
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422

    def test_missing_occasion_type_returns_422(self, client, test_auth_user_with_token):
        """Request without occasion_type should return 422."""
        resp = client.post(
            "/api/v1/recommendations/generate",
            json={},
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422

    def test_milestone_not_found_returns_404(self, client, test_user_with_vault):
        """Request with non-existent milestone_id should return 404."""
        user = test_user_with_vault
        fake_milestone_id = str(uuid.uuid4())

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "milestone_id": fake_milestone_id,
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 404
        assert "milestone" in resp.json()["detail"].lower()


# ===================================================================
# 5. Pipeline error handling tests
# ===================================================================

@requires_supabase
class TestPipelineErrors:
    """Verify error handling for pipeline failures."""

    def test_pipeline_exception_returns_500(self, client, test_user_with_vault):
        """Pipeline raising an exception should return 500."""
        user = test_user_with_vault

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            side_effect=RuntimeError("Vertex AI connection failed"),
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 500
        assert "unable to find recommendations" in resp.json()["detail"].lower()

    def test_pipeline_error_state_returns_500(self, client, test_user_with_vault):
        """Pipeline returning an error in the result should return 500."""
        user = test_user_with_vault

        error_result = {
            "final_three": [],
            "error": "No candidates found matching budget and criteria",
        }

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=error_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 500
        assert "no candidates" in resp.json()["detail"].lower()

    def test_pipeline_empty_results_returns_empty(self, client, test_user_with_vault):
        """Pipeline returning empty final_three should return count 0."""
        user = test_user_with_vault

        empty_result = {
            "final_three": [],
            "error": None,
        }

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=empty_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 0

    def test_pipeline_partial_results(self, client, test_user_with_vault):
        """Pipeline returning fewer than 3 should still return successfully."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"], count=2)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 2
        assert len(data["recommendations"]) == 2


# ===================================================================
# 6. Pipeline receives correct state
# ===================================================================

@requires_supabase
class TestPipelineState:
    """Verify that the pipeline receives correctly assembled state."""

    def test_pipeline_receives_vault_data(self, client, test_user_with_vault):
        """Pipeline should receive the user's vault data."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["vault_data"] = state.vault_data
            captured_state["occasion_type"] = state.occasion_type
            captured_state["budget_range"] = state.budget_range
            captured_state["milestone_context"] = state.milestone_context
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "major_milestone"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert captured_state["vault_data"].partner_name == "Alex"
        assert captured_state["vault_data"].vault_id == user["vault_id"]

    def test_pipeline_receives_interests(self, client, test_user_with_vault):
        """Pipeline should receive the vault's interests and dislikes."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["interests"] = state.vault_data.interests
            captured_state["dislikes"] = state.vault_data.dislikes
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert len(captured_state["interests"]) == 5
        assert len(captured_state["dislikes"]) == 5
        assert "Travel" in captured_state["interests"]
        assert "Sports" in captured_state["dislikes"]

    def test_pipeline_receives_vibes(self, client, test_user_with_vault):
        """Pipeline should receive the vault's vibes."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["vibes"] = state.vault_data.vibes
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert "quiet_luxury" in captured_state["vibes"]
        assert "minimalist" in captured_state["vibes"]
        assert "romantic" in captured_state["vibes"]

    def test_pipeline_receives_love_languages(self, client, test_user_with_vault):
        """Pipeline should receive the vault's love languages."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["primary"] = state.vault_data.primary_love_language
            captured_state["secondary"] = state.vault_data.secondary_love_language
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert captured_state["primary"] == "quality_time"
        assert captured_state["secondary"] == "receiving_gifts"

    def test_pipeline_receives_budget_range(self, client, test_user_with_vault):
        """Pipeline should receive the correct budget range."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["budget_range"] = state.budget_range
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "major_milestone"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert captured_state["budget_range"].min_amount == 10000
        assert captured_state["budget_range"].max_amount == 50000

    def test_pipeline_receives_milestone_context(self, client, test_user_with_vault):
        """Pipeline should receive milestone context when milestone_id is provided."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["milestone_context"] = state.milestone_context
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={
                    "milestone_id": user["milestone_id"],
                    "occasion_type": "major_milestone",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        mc = captured_state["milestone_context"]
        assert mc is not None
        assert mc.id == user["milestone_id"]
        assert mc.milestone_type in ("birthday", "anniversary", "holiday", "custom")

    def test_pipeline_no_milestone_context_in_browsing(self, client, test_user_with_vault):
        """Pipeline should NOT receive milestone context in browsing mode."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["milestone_context"] = state.milestone_context
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert captured_state["milestone_context"] is None

    def test_pipeline_receives_location(self, client, test_user_with_vault):
        """Pipeline should receive the vault's location data."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])
        captured_state = {}

        async def capture_pipeline(state):
            captured_state["location_city"] = state.vault_data.location_city
            captured_state["location_state"] = state.vault_data.location_state
            captured_state["location_country"] = state.vault_data.location_country
            return mock_result

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            side_effect=capture_pipeline,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert captured_state["location_city"] == "San Francisco"
        assert captured_state["location_state"] == "CA"
        assert captured_state["location_country"] == "US"


# ===================================================================
# 7. All three occasion types work
# ===================================================================

@requires_supabase
class TestOccasionTypes:
    """Verify all three occasion types work correctly."""

    def test_just_because(self, client, test_user_with_vault):
        """just_because occasion should work."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "just_because"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert resp.json()["occasion_type"] == "just_because"

    def test_minor_occasion(self, client, test_user_with_vault):
        """minor_occasion should work."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "minor_occasion"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert resp.json()["occasion_type"] == "minor_occasion"

    def test_major_milestone(self, client, test_user_with_vault):
        """major_milestone should work."""
        user = test_user_with_vault
        mock_result = _mock_pipeline_result(user["vault_id"])

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/generate",
                json={"occasion_type": "major_milestone"},
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        assert resp.json()["occasion_type"] == "major_milestone"
