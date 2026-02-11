"""
Step 5.10 Verification: Refresh (Re-roll) API Endpoint

Tests the POST /api/v1/recommendations/refresh endpoint that:
1. Accepts rejected_recommendation_ids (array of UUIDs) and rejection_reason
2. Stores feedback with action='refreshed' for each rejected recommendation
3. Re-runs the pipeline with exclusion filters based on rejection_reason
4. Returns 3 new recommendations

Rejection reasons and their effects:
- too_expensive: Exclude recommendations at or above the rejected price tier
- too_cheap: Exclude recommendations at or below the rejected price tier
- not_their_style: Exclude the vibe category of rejected recommendations
- already_have_similar: Exclude same merchant and product category
- show_different: Exclude only the exact same items

Tests cover:
- Valid refresh request returns 200 with 3 new recommendations
- Feedback stored with action='refreshed' in the database
- too_expensive exclusion produces lower-priced results
- too_cheap exclusion produces higher-priced results
- not_their_style exclusion removes matching vibe categories
- already_have_similar exclusion removes same merchant+type combos
- show_different only excludes exact items
- Auth required → 401
- No vault → 404
- Invalid rejection_reason → 422
- Empty rejected_recommendation_ids → 422
- Non-existent recommendation IDs → 404
- Pipeline error → 500
- Pydantic model validation

Prerequisites:
- Complete Steps 0.6-5.9 (Supabase + all tables + vault API + pipeline + generate)
- Backend server NOT required (uses FastAPI TestClient)

Run with: pytest tests/test_refresh_api.py -v
"""

import pytest
import httpx
import uuid
import time
from unittest.mock import patch, AsyncMock

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
# Helpers: HTTP headers
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
        "Prefer": "return=representation",
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
                f"HTTP {resp.status_code} — {resp.text}.",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}.",
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
# Helper: vault payload and queries
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


def _query_feedback(rec_id: str) -> list[dict]:
    """Query feedback for a recommendation."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/recommendation_feedback?recommendation_id=eq.{rec_id}",
        headers=_service_headers(),
    )
    assert resp.status_code == 200
    return resp.json()


def _query_recommendations(vault_id: str) -> list[dict]:
    """Query recommendations for a vault."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/recommendations?vault_id=eq.{vault_id}&order=created_at.desc",
        headers=_service_headers(),
    )
    assert resp.status_code == 200
    return resp.json()


# ---------------------------------------------------------------------------
# Helper: mock pipeline result with configurable candidates
# ---------------------------------------------------------------------------

def _mock_pipeline_result_with_prices(
    prices: list[int],
    types: list[str] | None = None,
    vibes: list[str] | None = None,
    merchants: list[str] | None = None,
):
    """Build a mock pipeline result with candidates at specified prices."""
    from app.agents.state import CandidateRecommendation, LocationData

    if types is None:
        types = ["gift", "experience", "date"]
    if vibes is None:
        vibes = ["quiet_luxury", "minimalist", "romantic"]
    if merchants is None:
        merchants = [f"Merchant {i + 1}" for i in range(len(prices))]

    candidates = []
    for i, price in enumerate(prices):
        candidates.append(
            CandidateRecommendation(
                id=str(uuid.uuid4()),
                source="yelp" if i % 2 == 0 else "amazon",
                type=types[i % len(types)],
                title=f"Recommendation {i + 1} at ${price // 100}",
                description=f"A {vibes[i % len(vibes)]} option",
                price_cents=price,
                currency="USD",
                external_url=f"https://example.com/rec/{i + 1}",
                image_url=f"https://example.com/img/{i + 1}.jpg",
                merchant_name=merchants[i % len(merchants)],
                location=LocationData(
                    city="San Francisco", state="CA", country="US",
                ) if types[i % len(types)] != "gift" else None,
                metadata={
                    "matched_vibe": vibes[i % len(vibes)],
                    "catalog": "stub",
                },
                interest_score=1.0,
                vibe_score=0.3,
                love_language_score=0.4,
                final_score=2.0 + i * 0.1,
            )
        )

    return {
        "final_three": candidates[:3],
        "error": None,
        "relevant_hints": [],
        "candidate_recommendations": candidates,
        "filtered_recommendations": candidates,
    }


def _mock_pipeline_result(count: int = 3):
    """Build a standard mock pipeline result."""
    return _mock_pipeline_result_with_prices(
        prices=[3000 + i * 1000 for i in range(max(count, 9))],
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user_with_token():
    """Create a test user, sign them in, yield user info + token."""
    test_email = f"knot-refresh-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_user_with_vault_and_recs(test_auth_user_with_token, client):
    """
    Create a test user with vault and initial recommendations.
    Returns user info including vault_id and recommendation IDs.
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

    # Generate initial recommendations (mocked)
    mock_result = _mock_pipeline_result()

    with patch(
        "app.api.recommendations.run_recommendation_pipeline",
        new_callable=AsyncMock,
        return_value=mock_result,
    ):
        gen_resp = client.post(
            "/api/v1/recommendations/generate",
            json={"occasion_type": "just_because"},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert gen_resp.status_code == 200
    gen_data = gen_resp.json()
    rec_ids = [r["id"] for r in gen_data["recommendations"]]

    return {
        **test_auth_user_with_token,
        "vault_id": vault_id,
        "recommendation_ids": rec_ids,
        "recommendations": gen_data["recommendations"],
    }


@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ===================================================================
# 1. Pydantic model tests
# ===================================================================

class TestRefreshModels:
    """Verify Pydantic request/response models for refresh endpoint."""

    def test_refresh_request_valid(self):
        """Valid request with rejected IDs and reason."""
        from app.models.recommendations import RecommendationRefreshRequest
        req = RecommendationRefreshRequest(
            rejected_recommendation_ids=["id-1", "id-2"],
            rejection_reason="too_expensive",
        )
        assert len(req.rejected_recommendation_ids) == 2
        assert req.rejection_reason == "too_expensive"

    def test_refresh_request_all_reasons(self):
        """All 5 rejection reasons should be valid."""
        from app.models.recommendations import RecommendationRefreshRequest
        for reason in [
            "too_expensive", "too_cheap", "not_their_style",
            "already_have_similar", "show_different",
        ]:
            req = RecommendationRefreshRequest(
                rejected_recommendation_ids=["id-1"],
                rejection_reason=reason,
            )
            assert req.rejection_reason == reason

    def test_refresh_request_invalid_reason(self):
        """Invalid rejection_reason should raise validation error."""
        from app.models.recommendations import RecommendationRefreshRequest
        with pytest.raises(Exception):
            RecommendationRefreshRequest(
                rejected_recommendation_ids=["id-1"],
                rejection_reason="invalid_reason",
            )

    def test_refresh_request_empty_ids_rejected(self):
        """Empty rejected_recommendation_ids should be rejected."""
        from app.models.recommendations import RecommendationRefreshRequest
        with pytest.raises(Exception):
            RecommendationRefreshRequest(
                rejected_recommendation_ids=[],
                rejection_reason="too_expensive",
            )

    def test_refresh_response_model(self):
        """Response model should serialize correctly."""
        from app.models.recommendations import (
            RecommendationRefreshResponse,
            RecommendationItemResponse,
        )
        item = RecommendationItemResponse(
            id="rec-1",
            recommendation_type="gift",
            title="New Gift",
            external_url="https://example.com",
            source="amazon",
        )
        resp = RecommendationRefreshResponse(
            recommendations=[item],
            count=1,
            rejection_reason="too_expensive",
        )
        assert resp.count == 1
        assert resp.rejection_reason == "too_expensive"


# ===================================================================
# 2. Exclusion filter unit tests
# ===================================================================

class TestExclusionFilters:
    """Unit tests for the _apply_exclusion_filters helper."""

    def _make_candidates(self, prices, types=None, vibes=None, merchants=None):
        """Helper to create CandidateRecommendation objects."""
        from app.agents.state import CandidateRecommendation

        if types is None:
            types = ["gift"] * len(prices)
        if vibes is None:
            vibes = ["quiet_luxury"] * len(prices)
        if merchants is None:
            merchants = [f"Merchant {i}" for i in range(len(prices))]

        candidates = []
        for i, price in enumerate(prices):
            candidates.append(
                CandidateRecommendation(
                    id=str(uuid.uuid4()),
                    source="amazon",
                    type=types[i],
                    title=f"Item {i + 1}",
                    price_cents=price,
                    external_url=f"https://example.com/{i}",
                    merchant_name=merchants[i],
                    metadata={"matched_vibe": vibes[i]},
                    final_score=2.0,
                )
            )
        return candidates

    def test_show_different_excludes_exact_items(self):
        """show_different should only exclude exact title matches."""
        from app.api.recommendations import _apply_exclusion_filters
        from app.agents.state import BudgetRange

        candidates = self._make_candidates([3000, 4000, 5000, 6000, 7000])
        rejected = [{"title": "Item 1", "price_cents": 3000}]
        budget = BudgetRange(min_amount=2000, max_amount=8000)

        result = _apply_exclusion_filters(
            candidates, rejected, "show_different", budget,
        )
        titles = [c.title for c in result]
        assert "Item 1" not in titles
        assert len(result) == 4

    def test_too_expensive_excludes_high_tier(self):
        """too_expensive should exclude items at or above rejected price tier."""
        from app.api.recommendations import _apply_exclusion_filters
        from app.agents.state import BudgetRange

        # Budget 2000-8000, third = 2000
        # low: 2000-4000, mid: 4000-6000, high: 6000-8000
        candidates = self._make_candidates([2500, 3500, 5000, 7000, 7500])
        # Rejected item at 7000 = "high" tier
        rejected = [{"title": "Expensive Item", "price_cents": 7000}]
        budget = BudgetRange(min_amount=2000, max_amount=8000)

        result = _apply_exclusion_filters(
            candidates, rejected, "too_expensive", budget,
        )
        # Should keep only low and mid tier items (< high)
        for c in result:
            assert c.price_cents < 6000, (
                f"Expected only low/mid tier, got {c.price_cents}"
            )

    def test_too_cheap_excludes_low_tier(self):
        """too_cheap should exclude items at or below rejected price tier."""
        from app.api.recommendations import _apply_exclusion_filters
        from app.agents.state import BudgetRange

        # Budget 2000-8000, third = 2000
        # low: 2000-4000, mid: 4000-6000, high: 6000-8000
        candidates = self._make_candidates([2500, 3500, 5000, 7000, 7500])
        # Rejected item at 2500 = "low" tier
        rejected = [{"title": "Cheap Item", "price_cents": 2500}]
        budget = BudgetRange(min_amount=2000, max_amount=8000)

        result = _apply_exclusion_filters(
            candidates, rejected, "too_cheap", budget,
        )
        # Should keep only mid and high tier items (> low)
        for c in result:
            assert c.price_cents >= 4000, (
                f"Expected only mid/high tier, got {c.price_cents}"
            )

    def test_not_their_style_excludes_vibe(self):
        """not_their_style should exclude candidates with the same vibe."""
        from app.api.recommendations import _apply_exclusion_filters
        from app.agents.state import BudgetRange

        candidates = self._make_candidates(
            [3000, 4000, 5000, 6000],
            vibes=["romantic", "romantic", "minimalist", "quiet_luxury"],
        )
        # Reject a romantic item
        rejected = [{"title": "Item 1", "price_cents": 3000}]
        budget = BudgetRange(min_amount=2000, max_amount=8000)

        result = _apply_exclusion_filters(
            candidates, rejected, "not_their_style", budget,
        )
        # Should exclude Item 1 (exact match) and Item 2 (same vibe "romantic")
        for c in result:
            vibe = c.metadata.get("matched_vibe", "")
            assert vibe != "romantic", f"Expected no romantic items, got '{c.title}'"

    def test_already_have_similar_excludes_merchant_and_type(self):
        """already_have_similar should exclude same merchant+type combos."""
        from app.api.recommendations import _apply_exclusion_filters
        from app.agents.state import BudgetRange

        candidates = self._make_candidates(
            [3000, 4000, 5000, 6000],
            types=["gift", "gift", "experience", "gift"],
            merchants=["Amazon", "Amazon", "Amazon", "Etsy"],
        )
        # Reject an Amazon gift
        rejected = [{
            "title": "Item 1",
            "price_cents": 3000,
            "merchant_name": "Amazon",
            "recommendation_type": "gift",
        }]
        budget = BudgetRange(min_amount=2000, max_amount=8000)

        result = _apply_exclusion_filters(
            candidates, rejected, "already_have_similar", budget,
        )
        # Should exclude Item 1 (exact), Item 2 (same merchant+type: Amazon+gift),
        # Item 4 (Etsy+gift) should stay
        # Item 3 (Amazon+experience) should stay (different type)
        for c in result:
            if c.merchant_name and c.merchant_name.lower() == "amazon":
                assert c.type != "gift", (
                    f"Expected no Amazon gifts, got '{c.title}'"
                )

    def test_price_tier_classification(self):
        """Verify price tier classification logic."""
        from app.api.recommendations import _classify_price_tier
        from app.agents.state import BudgetRange

        budget = BudgetRange(min_amount=3000, max_amount=9000)
        # Range = 6000, third = 2000
        # low: 3000-5000, mid: 5000-7000, high: 7000-9000

        assert _classify_price_tier(3500, budget) == "low"
        assert _classify_price_tier(6000, budget) == "mid"
        assert _classify_price_tier(8000, budget) == "high"
        assert _classify_price_tier(None, budget) == "mid"


# ===================================================================
# 3. Integration tests: refresh endpoint
# ===================================================================

@requires_supabase
class TestRefreshEndpoint:
    """Verify POST /api/v1/recommendations/refresh endpoint."""

    def test_refresh_returns_200(self, client, test_user_with_vault_and_recs):
        """Valid refresh request returns 200."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200, (
            f"Expected 200, got {resp.status_code}. Response: {resp.text}"
        )

    def test_refresh_returns_3_recommendations(self, client, test_user_with_vault_and_recs):
        """Refresh should return 3 new recommendations."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        assert data["count"] == 3
        assert len(data["recommendations"]) == 3

    def test_refresh_echoes_rejection_reason(self, client, test_user_with_vault_and_recs):
        """Response should echo back the rejection_reason."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "not_their_style",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        assert data["rejection_reason"] == "not_their_style"

    def test_refresh_stores_feedback(self, client, test_user_with_vault_and_recs):
        """Refresh should store feedback with action='refreshed'."""
        user = test_user_with_vault_and_recs
        rec_id = user["recommendation_ids"][0]
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": [rec_id],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200

        # Verify feedback was stored
        feedback = _query_feedback(rec_id)
        assert len(feedback) >= 1
        refreshed = [f for f in feedback if f["action"] == "refreshed"]
        assert len(refreshed) >= 1
        assert refreshed[0]["feedback_text"] == "show_different"

    def test_refresh_stores_new_recommendations(self, client, test_user_with_vault_and_recs):
        """Refresh should store the new recommendations in the database."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200
        data = resp.json()

        # Original 3 + new 3 = at least 6
        db_recs = _query_recommendations(user["vault_id"])
        assert len(db_recs) >= 6

    def test_recommendations_have_required_fields(self, client, test_user_with_vault_and_recs):
        """Each refreshed recommendation should have required fields."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result(9)

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        data = resp.json()
        for rec in data["recommendations"]:
            assert "id" in rec
            assert "title" in rec
            assert rec["title"]
            assert "recommendation_type" in rec
            assert rec["recommendation_type"] in ("gift", "experience", "date")
            assert "external_url" in rec
            assert "source" in rec


# ===================================================================
# 4. Auth and validation tests
# ===================================================================

@requires_supabase
class TestRefreshAuth:
    """Verify auth and validation for the refresh endpoint."""

    def test_no_auth_returns_401(self, client):
        """Request without auth token should return 401."""
        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": ["some-id"],
                "rejection_reason": "too_expensive",
            },
        )
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Request with invalid auth token should return 401."""
        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": ["some-id"],
                "rejection_reason": "too_expensive",
            },
            headers={"Authorization": "Bearer invalid-token"},
        )
        assert resp.status_code == 401

    def test_no_vault_returns_404(self, client, test_auth_user_with_token):
        """Request from user without vault should return 404."""
        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": ["some-id"],
                "rejection_reason": "too_expensive",
            },
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 404
        assert "vault" in resp.json()["detail"].lower()

    def test_invalid_rejection_reason_returns_422(self, client, test_auth_user_with_token):
        """Request with invalid rejection_reason should return 422."""
        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": ["some-id"],
                "rejection_reason": "invalid_reason",
            },
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422

    def test_empty_rejected_ids_returns_422(self, client, test_auth_user_with_token):
        """Request with empty rejected_recommendation_ids should return 422."""
        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": [],
                "rejection_reason": "too_expensive",
            },
            headers=_auth_headers(test_auth_user_with_token["access_token"]),
        )
        assert resp.status_code == 422

    def test_nonexistent_rec_ids_returns_404(self, client, test_user_with_vault_and_recs):
        """Request with non-existent recommendation IDs should return 404."""
        user = test_user_with_vault_and_recs
        fake_ids = [str(uuid.uuid4())]

        resp = client.post(
            "/api/v1/recommendations/refresh",
            json={
                "rejected_recommendation_ids": fake_ids,
                "rejection_reason": "too_expensive",
            },
            headers=_auth_headers(user["access_token"]),
        )
        assert resp.status_code == 404


# ===================================================================
# 5. Pipeline error handling for refresh
# ===================================================================

@requires_supabase
class TestRefreshPipelineErrors:
    """Verify error handling for pipeline failures during refresh."""

    def test_pipeline_exception_returns_500(self, client, test_user_with_vault_and_recs):
        """Pipeline raising an exception should return 500."""
        user = test_user_with_vault_and_recs

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            side_effect=RuntimeError("Vertex AI connection failed"),
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 500

    def test_pipeline_error_state_returns_500(self, client, test_user_with_vault_and_recs):
        """Pipeline returning error state should return 500."""
        user = test_user_with_vault_and_recs

        error_result = {
            "final_three": [],
            "error": "No candidates found",
        }

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=error_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": "show_different",
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 500


# ===================================================================
# 6. All 5 rejection reasons work
# ===================================================================

@requires_supabase
class TestAllRejectionReasons:
    """Verify all 5 rejection reasons work end-to-end."""

    @pytest.mark.parametrize("reason", [
        "too_expensive",
        "too_cheap",
        "not_their_style",
        "already_have_similar",
        "show_different",
    ])
    def test_rejection_reason_accepted(
        self, client, test_user_with_vault_and_recs, reason,
    ):
        """Each rejection reason should be accepted and return 200."""
        user = test_user_with_vault_and_recs
        mock_result = _mock_pipeline_result_with_prices(
            prices=[2500, 3000, 3500, 5000, 6000, 7000, 7500, 8000, 9000],
            types=["gift", "experience", "date", "gift", "experience",
                   "date", "gift", "experience", "date"],
            vibes=["quiet_luxury", "minimalist", "romantic",
                   "quiet_luxury", "minimalist", "romantic",
                   "quiet_luxury", "minimalist", "romantic"],
            merchants=["A", "B", "C", "D", "E", "F", "G", "H", "I"],
        )

        with patch(
            "app.api.recommendations.run_recommendation_pipeline",
            new_callable=AsyncMock,
            return_value=mock_result,
        ):
            resp = client.post(
                "/api/v1/recommendations/refresh",
                json={
                    "rejected_recommendation_ids": user["recommendation_ids"][:1],
                    "rejection_reason": reason,
                },
                headers=_auth_headers(user["access_token"]),
            )

        assert resp.status_code == 200, (
            f"Reason '{reason}' failed: {resp.status_code} — {resp.text}"
        )
        data = resp.json()
        assert data["count"] >= 1
        assert data["rejection_reason"] == reason
