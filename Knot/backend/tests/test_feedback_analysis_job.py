"""
Tests for Feedback Analysis Job (Step 10.2)

Validates that:
1. Scoring functions correctly convert feedback actions to numeric scores
2. Weight computation produces correct multipliers with damping
3. Vibe keyword matching detects correct vibes from recommendation text
4. Love language matching detects correct love languages from recommendation text/type
5. Pydantic models serialize/deserialize correctly
6. API endpoint is accessible and handles various payloads
7. The user_preferences_weights table exists and has correct schema (requires Supabase)
8. Full analysis flow: seed feedback → run job → verify weights (requires Supabase)

Prerequisites:
- Unit/model/route tests: No external credentials required
- Integration tests: Supabase credentials in .env

Run with: pytest tests/test_feedback_analysis_job.py -v
"""

import pytest
import httpx
import uuid
import time

from fastapi.testclient import TestClient

from app.main import app
from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
from app.services.feedback_analysis import (
    _clamp,
    _compute_weight_from_scores,
    _match_recommendation_love_languages,
    _match_recommendation_vibes,
    _score_from_feedback,
    DEFAULT_WEIGHT,
    MAX_WEIGHT,
    MIN_WEIGHT,
)

test_client = TestClient(app)


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
# Helpers: HTTP headers for PostgREST and Admin API
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access. Bypasses RLS."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _anon_headers() -> dict:
    """Headers for anon (public) PostgREST access. No user JWT."""
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type": "application/json",
    }


def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
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
                f"HTTP {resp.status_code} — {resp.text}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}",
            stacklevel=2,
        )


# ---------------------------------------------------------------------------
# Helpers: insert/delete DB rows
# ---------------------------------------------------------------------------

def _insert_vault(vault_data: dict) -> dict:
    """Insert a vault row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=vault_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vault: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_vibes(vault_id: str, vibes: list[str]) -> list[dict]:
    """Insert vibe rows for a vault."""
    rows = [{"vault_id": vault_id, "vibe_tag": v} for v in vibes]
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vibes",
        headers=_service_headers(),
        json=rows,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vibes: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _insert_interests(vault_id: str, likes: list[str], dislikes: list[str] | None = None) -> list[dict]:
    """Insert interest rows for a vault."""
    rows = [{"vault_id": vault_id, "interest_type": "like", "interest_category": c} for c in likes]
    if dislikes:
        rows += [{"vault_id": vault_id, "interest_type": "dislike", "interest_category": c} for c in dislikes]
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_interests",
        headers=_service_headers(),
        json=rows,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert interests: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _insert_recommendation(rec_data: dict) -> dict:
    """Insert a recommendation row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendations",
        headers=_service_headers(),
        json=rec_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert recommendation: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_feedback(feedback_data: dict) -> dict:
    """Insert a feedback row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/recommendation_feedback",
        headers=_service_headers(),
        json=feedback_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert feedback: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_weights(weights_data: dict) -> dict:
    """Insert a weights row via service client. Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
        headers=_service_headers(),
        json=weights_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert weights: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_weights_raw(weights_data: dict) -> httpx.Response:
    """Insert a weights row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
        headers=_service_headers(),
        json=weights_data,
    )


def _get_weights_for_user(user_id: str) -> dict | None:
    """Query user_preferences_weights for a specific user. Returns the row or None."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
        headers=_service_headers(),
        params={"user_id": f"eq.{user_id}", "select": "*"},
    )
    assert resp.status_code == 200
    rows = resp.json()
    return rows[0] if rows else None


def _delete_weights(weights_id: str):
    """Delete a weights row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
        headers=_service_headers(),
        params={"id": f"eq.{weights_id}"},
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """Create a test user in auth.users. Cleanup via CASCADE."""
    test_email = f"knot-fba-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)
    yield {"id": user_id, "email": test_email}
    _delete_auth_user(user_id)


@pytest.fixture
def test_vault_with_vibes(test_auth_user):
    """Create a vault with romantic and adventurous vibes."""
    user_id = test_auth_user["id"]
    vault = _insert_vault({
        "user_id": user_id,
        "partner_name": "Feedback Analysis Partner",
        "relationship_tenure_months": 24,
        "location_city": "New York",
        "location_state": "NY",
        "location_country": "US",
    })
    _insert_vibes(vault["id"], ["romantic", "adventurous"])
    _insert_interests(vault["id"], ["Cooking", "Reading", "Travel"])

    yield {
        "user": test_auth_user,
        "vault": vault,
        "vibes": ["romantic", "adventurous"],
        "interests": ["Cooking", "Reading", "Travel"],
    }


@pytest.fixture
def test_seeded_feedback(test_vault_with_vibes):
    """
    Create a vault with recommendations and feedback seeded for analysis.

    Seeds:
    - 3 romantic recommendations rated 5 stars each
    - 3 adventurous recommendations rated 2 stars each
    - 1 experience recommendation selected (no rating)
    - Total: 7 feedback entries (above MIN_FEEDBACK_FOR_ADJUSTMENT threshold)
    """
    user_id = test_vault_with_vibes["user"]["id"]
    vault_id = test_vault_with_vibes["vault"]["id"]

    # Romantic recommendations — user loves these
    romantic_recs = []
    for i, (title, desc) in enumerate([
        ("Candlelit Sunset Dinner for Two", "A romantic evening with stargazing on the rooftop."),
        ("Couples Cruise on the River", "A romantic sunset cruise with champagne."),
        ("Stargazing Picnic Experience", "A romantic outdoor experience under the stars."),
    ]):
        rec = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "date" if i % 2 == 0 else "experience",
            "title": title,
            "description": desc,
            "external_url": f"https://example.com/romantic-{i}",
            "price_cents": 15000 + i * 1000,
            "merchant_name": f"Romantic Merchant {i}",
        })
        romantic_recs.append(rec)
        _insert_feedback({
            "recommendation_id": rec["id"],
            "user_id": user_id,
            "action": "rated",
            "rating": 5,
            "feedback_text": "She absolutely loved it!",
        })

    # Adventurous recommendations — user doesn't like these
    adventurous_recs = []
    for i, (title, desc) in enumerate([
        ("Extreme Skydiving Adventure", "An adventurous thrill-seeking skydiving experience."),
        ("White Water Rafting Expedition", "An extreme adventure rafting down rapids."),
        ("Escape Room Challenge Night", "An adventurous escape room with puzzles."),
    ]):
        rec = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "experience",
            "title": title,
            "description": desc,
            "external_url": f"https://example.com/adventurous-{i}",
            "price_cents": 12000 + i * 500,
            "merchant_name": f"Adventure Co {i}",
        })
        adventurous_recs.append(rec)
        _insert_feedback({
            "recommendation_id": rec["id"],
            "user_id": user_id,
            "action": "rated",
            "rating": 2,
            "feedback_text": "Not really her style.",
        })

    # One extra selected experience (cooking-related)
    cooking_rec = _insert_recommendation({
        "vault_id": vault_id,
        "recommendation_type": "experience",
        "title": "Cooking Class — Italian Cuisine",
        "description": "Learn to cook authentic Italian dishes together.",
        "external_url": "https://example.com/cooking-class",
        "price_cents": 10000,
        "merchant_name": "Chef's Table Studio",
    })
    _insert_feedback({
        "recommendation_id": cooking_rec["id"],
        "user_id": user_id,
        "action": "selected",
    })

    yield {
        "user": test_vault_with_vibes["user"],
        "vault": test_vault_with_vibes["vault"],
        "vibes": test_vault_with_vibes["vibes"],
        "interests": test_vault_with_vibes["interests"],
        "romantic_recs": romantic_recs,
        "adventurous_recs": adventurous_recs,
        "cooking_rec": cooking_rec,
        "feedback_count": 7,
    }


# ===================================================================
# 1. Unit tests: _score_from_feedback
# ===================================================================

class TestScoreFromFeedback:
    """Verify the scoring function maps actions to correct numeric scores."""

    def test_rated_5_returns_positive_one(self):
        """A 5-star rating should return +1.0 (maximum positive signal)."""
        assert _score_from_feedback("rated", 5) == 1.0

    def test_rated_4_returns_half(self):
        """A 4-star rating should return +0.5."""
        assert _score_from_feedback("rated", 4) == 0.5

    def test_rated_3_returns_zero(self):
        """A 3-star rating should return 0.0 (neutral)."""
        assert _score_from_feedback("rated", 3) == 0.0

    def test_rated_2_returns_negative_half(self):
        """A 2-star rating should return -0.5."""
        assert _score_from_feedback("rated", 2) == -0.5

    def test_rated_1_returns_negative_one(self):
        """A 1-star rating should return -1.0 (maximum negative signal)."""
        assert _score_from_feedback("rated", 1) == -1.0

    def test_selected_returns_positive(self):
        """Selecting a recommendation is a mild positive signal (+0.3)."""
        assert _score_from_feedback("selected", None) == 0.3

    def test_purchased_returns_strong_positive(self):
        """Purchasing is a strong positive signal (+0.5)."""
        assert _score_from_feedback("purchased", None) == 0.5

    def test_saved_returns_mild_positive(self):
        """Saving is a mild positive signal (+0.2)."""
        assert _score_from_feedback("saved", None) == 0.2

    def test_shared_returns_positive(self):
        """Sharing is a mild positive signal (+0.3)."""
        assert _score_from_feedback("shared", None) == 0.3

    def test_handoff_returns_weak_positive(self):
        """Merchant handoff is a weak positive signal (+0.1)."""
        assert _score_from_feedback("handoff", None) == 0.1

    def test_refreshed_returns_negative(self):
        """Refreshing (rejecting) is a negative signal (-0.5)."""
        assert _score_from_feedback("refreshed", None) == -0.5

    def test_unknown_action_returns_zero(self):
        """Unknown actions should return 0.0 (neutral)."""
        assert _score_from_feedback("unknown_action", None) == 0.0


# ===================================================================
# 2. Unit tests: _compute_weight_from_scores
# ===================================================================

class TestComputeWeightFromScores:
    """Verify weight computation with damping formula."""

    def test_empty_scores_returns_default(self):
        """No scores should return the default weight (1.0)."""
        assert _compute_weight_from_scores([]) == DEFAULT_WEIGHT

    def test_all_positive_scores_produce_weight_above_one(self):
        """Consistently positive feedback should produce weight > 1.0."""
        result = _compute_weight_from_scores([1.0, 1.0, 1.0, 1.0, 1.0])
        assert result > 1.0
        print(f"  All positive (5x 1.0): weight = {result:.3f}")

    def test_all_negative_scores_produce_weight_below_one(self):
        """Consistently negative feedback should produce weight < 1.0."""
        result = _compute_weight_from_scores([-1.0, -1.0, -1.0, -1.0, -1.0])
        assert result < 1.0
        print(f"  All negative (5x -1.0): weight = {result:.3f}")

    def test_mixed_scores_near_neutral(self):
        """Mixed positive and negative feedback should stay near 1.0."""
        result = _compute_weight_from_scores([1.0, -1.0, 0.5, -0.5])
        assert 0.9 < result < 1.1
        print(f"  Mixed scores: weight = {result:.3f}")

    def test_weight_clamped_high(self):
        """Even extreme positive data should not exceed MAX_WEIGHT."""
        result = _compute_weight_from_scores([1.0] * 100)
        assert result <= MAX_WEIGHT
        print(f"  100x positive: weight = {result:.3f} (max={MAX_WEIGHT})")

    def test_weight_clamped_low(self):
        """Even extreme negative data should not go below MIN_WEIGHT."""
        result = _compute_weight_from_scores([-1.0] * 100)
        assert result >= MIN_WEIGHT
        print(f"  100x negative: weight = {result:.3f} (min={MIN_WEIGHT})")

    def test_single_score_damped(self):
        """A single score should be heavily damped toward 1.0."""
        result = _compute_weight_from_scores([1.0])
        # With n=1, damping = 1/(1+2) = 0.33, so weight ≈ 1.33
        assert 1.0 < result < 1.5
        print(f"  Single positive: weight = {result:.3f}")

    def test_more_samples_stronger_effect(self):
        """More samples should produce a stronger adjustment from 1.0."""
        result_small = _compute_weight_from_scores([1.0, 1.0])
        result_large = _compute_weight_from_scores([1.0] * 20)
        assert result_large > result_small
        print(f"  2 samples: {result_small:.3f}, 20 samples: {result_large:.3f}")


# ===================================================================
# 3. Unit tests: _clamp
# ===================================================================

class TestClamp:
    """Verify clamping function bounds weights to [MIN_WEIGHT, MAX_WEIGHT]."""

    def test_clamp_below_minimum(self):
        """Values below MIN_WEIGHT should be clamped to MIN_WEIGHT."""
        assert _clamp(0.3) == MIN_WEIGHT

    def test_clamp_above_maximum(self):
        """Values above MAX_WEIGHT should be clamped to MAX_WEIGHT."""
        assert _clamp(2.5) == MAX_WEIGHT

    def test_clamp_within_range(self):
        """Values within range should be unchanged."""
        assert _clamp(1.2) == 1.2

    def test_clamp_at_boundaries(self):
        """Values exactly at the boundaries should be unchanged."""
        assert _clamp(MIN_WEIGHT) == MIN_WEIGHT
        assert _clamp(MAX_WEIGHT) == MAX_WEIGHT


# ===================================================================
# 4. Unit tests: _match_recommendation_vibes
# ===================================================================

class TestMatchRecommendationVibes:
    """Verify vibe keyword matching against recommendation text."""

    def test_romantic_keywords_detected(self):
        """Romantic keywords in title should match the romantic vibe."""
        matched = _match_recommendation_vibes(
            "Candlelit Sunset Dinner",
            "A romantic evening for couples.",
            ["romantic", "adventurous"],
        )
        assert "romantic" in matched
        print(f"  Matched vibes: {matched}")

    def test_adventurous_keywords_detected(self):
        """Adventurous keywords in title should match the adventurous vibe."""
        matched = _match_recommendation_vibes(
            "Extreme Skydiving Adventure",
            "A thrill-seeking skydiving experience.",
            ["romantic", "adventurous"],
        )
        assert "adventurous" in matched
        print(f"  Matched vibes: {matched}")

    def test_no_match_returns_empty(self):
        """Text with no vibe keywords should return empty list."""
        matched = _match_recommendation_vibes(
            "Generic Product",
            "A regular item with no special vibes.",
            ["romantic", "adventurous"],
        )
        assert matched == []

    def test_only_vault_vibes_checked(self):
        """Only vibes in the vault should be checked (not all 8 vibes)."""
        matched = _match_recommendation_vibes(
            "Luxury Spa Day",
            "An exclusive upscale spa experience.",
            ["romantic"],  # vault only has romantic, not quiet_luxury
        )
        assert "quiet_luxury" not in matched
        assert "romantic" not in matched  # no romantic keywords in this text

    def test_description_none_handled(self):
        """None description should not cause errors."""
        matched = _match_recommendation_vibes(
            "Romantic Cruise",
            None,
            ["romantic"],
        )
        assert "romantic" in matched

    def test_multiple_vibes_can_match(self):
        """A recommendation can match multiple vibes simultaneously."""
        matched = _match_recommendation_vibes(
            "Romantic Adventure Cruise",
            "A couples adventure on a sunset cruise with extreme thrills.",
            ["romantic", "adventurous"],
        )
        assert "romantic" in matched
        assert "adventurous" in matched


# ===================================================================
# 5. Unit tests: _match_recommendation_love_languages
# ===================================================================

class TestMatchRecommendationLoveLanguages:
    """Verify love language matching based on type and keywords."""

    def test_gift_type_maps_to_receiving_gifts(self):
        """Gift-type recommendations should match receiving_gifts."""
        matched = _match_recommendation_love_languages(
            "Handmade Ceramic Mug", "A beautiful gift.", "gift",
        )
        assert "receiving_gifts" in matched

    def test_experience_type_maps_to_quality_time(self):
        """Experience-type recommendations should match quality_time."""
        matched = _match_recommendation_love_languages(
            "Cooking Class", "A fun experience.", "experience",
        )
        assert "quality_time" in matched

    def test_date_type_maps_to_quality_time(self):
        """Date-type recommendations should match quality_time."""
        matched = _match_recommendation_love_languages(
            "Italian Dinner", "A romantic date.", "date",
        )
        assert "quality_time" in matched

    def test_physical_touch_keywords(self):
        """Keywords like 'couples massage' should match physical_touch."""
        matched = _match_recommendation_love_languages(
            "Couples Massage Package", "A spa day together.", "experience",
        )
        assert "physical_touch" in matched

    def test_words_of_affirmation_keywords(self):
        """Keywords like 'personalized' should match words_of_affirmation."""
        matched = _match_recommendation_love_languages(
            "Personalized Engraved Journal", "A custom sentimental gift.", "gift",
        )
        assert "words_of_affirmation" in matched

    def test_acts_of_service_keywords(self):
        """Keywords like 'practical tool kit' should match acts_of_service."""
        matched = _match_recommendation_love_languages(
            "Home Repair Tool Kit", "A practical organizer for the home.", "gift",
        )
        assert "acts_of_service" in matched


# ===================================================================
# 6. Pydantic model tests
# ===================================================================

class TestPydanticModels:
    """Verify Pydantic models for feedback analysis."""

    def test_user_preferences_weights_model(self):
        """UserPreferencesWeights should serialize all fields."""
        from app.models.feedback_analysis import UserPreferencesWeights

        w = UserPreferencesWeights(
            user_id="test-user-123",
            vibe_weights={"romantic": 1.4, "adventurous": 0.7},
            interest_weights={"Cooking": 1.3},
            type_weights={"gift": 1.2, "experience": 0.9},
            love_language_weights={"quality_time": 1.1},
            feedback_count=10,
        )
        assert w.user_id == "test-user-123"
        assert w.vibe_weights["romantic"] == 1.4
        assert w.feedback_count == 10

    def test_user_preferences_weights_defaults(self):
        """UserPreferencesWeights should have sensible defaults."""
        from app.models.feedback_analysis import UserPreferencesWeights

        w = UserPreferencesWeights(user_id="test")
        assert w.vibe_weights == {}
        assert w.interest_weights == {}
        assert w.type_weights == {}
        assert w.love_language_weights == {}
        assert w.feedback_count == 0

    def test_feedback_analysis_request_optional_user_id(self):
        """FeedbackAnalysisRequest should accept optional user_id."""
        from app.models.feedback_analysis import FeedbackAnalysisRequest

        req_none = FeedbackAnalysisRequest()
        assert req_none.user_id is None

        req_with = FeedbackAnalysisRequest(user_id="user-123")
        assert req_with.user_id == "user-123"

    def test_feedback_analysis_response_model(self):
        """FeedbackAnalysisResponse should have all required fields."""
        from app.models.feedback_analysis import FeedbackAnalysisResponse

        resp = FeedbackAnalysisResponse(
            status="completed",
            users_analyzed=5,
            message="Analyzed 5 users.",
        )
        assert resp.status == "completed"
        assert resp.users_analyzed == 5
        assert resp.message == "Analyzed 5 users."


# ===================================================================
# 7. API route tests (FastAPI TestClient, no Supabase needed for structure)
# ===================================================================

class TestFeedbackAnalyzeEndpoint:
    """Verify the /api/v1/feedback/analyze endpoint is registered and accepts requests."""

    def test_endpoint_exists(self):
        """POST /api/v1/feedback/analyze should not return 404 (route exists)."""
        resp = test_client.post("/api/v1/feedback/analyze")
        assert resp.status_code != 404, (
            "Endpoint /api/v1/feedback/analyze not found. "
            "Check that feedback_router is registered in main.py."
        )
        print(f"  Endpoint exists — status: {resp.status_code}")

    def test_endpoint_accepts_empty_body(self):
        """POST with empty body should not return 422 (body is optional)."""
        resp = test_client.post("/api/v1/feedback/analyze")
        assert resp.status_code != 422, (
            "Endpoint rejected empty body with 422. Body should be optional."
        )

    def test_endpoint_accepts_user_id_body(self):
        """POST with user_id in body should not return 422."""
        resp = test_client.post(
            "/api/v1/feedback/analyze",
            json={"user_id": "test-user-123"},
        )
        assert resp.status_code != 422, (
            "Endpoint rejected user_id body with 422."
        )


# ===================================================================
# 8. Module import tests
# ===================================================================

class TestModuleImports:
    """Verify all new modules are importable and accessible."""

    def test_feedback_analysis_service_imports(self):
        """The feedback analysis service module should be importable."""
        from app.services import feedback_analysis
        assert hasattr(feedback_analysis, "run_feedback_analysis")
        assert hasattr(feedback_analysis, "analyze_user_feedback")
        assert hasattr(feedback_analysis, "upsert_user_weights")

    def test_feedback_analysis_models_import(self):
        """The feedback analysis models module should be importable."""
        from app.models import feedback_analysis
        assert hasattr(feedback_analysis, "UserPreferencesWeights")
        assert hasattr(feedback_analysis, "FeedbackAnalysisRequest")
        assert hasattr(feedback_analysis, "FeedbackAnalysisResponse")

    def test_feedback_router_imports(self):
        """The feedback API router should be importable."""
        from app.api.feedback import router
        assert router is not None

    def test_feedback_router_registered_in_app(self):
        """The feedback router should be registered in the FastAPI app."""
        routes = [route.path for route in app.routes]
        assert "/api/v1/feedback/analyze" in routes, (
            f"Feedback endpoint not in app routes. Found: {routes}"
        )

    def test_vibe_keywords_exported(self):
        """VIBE_KEYWORDS should be accessible from the service module."""
        from app.services.feedback_analysis import VIBE_KEYWORDS
        assert isinstance(VIBE_KEYWORDS, dict)
        assert "romantic" in VIBE_KEYWORDS
        assert "adventurous" in VIBE_KEYWORDS
        assert len(VIBE_KEYWORDS) == 8

    def test_scoring_constants_exported(self):
        """MIN_WEIGHT, MAX_WEIGHT, DEFAULT_WEIGHT should be accessible."""
        assert MIN_WEIGHT == 0.5
        assert MAX_WEIGHT == 2.0
        assert DEFAULT_WEIGHT == 1.0


# ===================================================================
# 9. Integration tests: Table schema (requires Supabase)
# ===================================================================

@requires_supabase
class TestWeightsTableExists:
    """Verify the user_preferences_weights table exists and is accessible."""

    def test_table_is_accessible(self):
        """The user_preferences_weights table should be accessible via PostgREST."""
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"user_preferences_weights table not accessible (HTTP {resp.status_code}). "
            "Run the migration: "
            "backend/supabase/migrations/00018_create_user_preferences_weights_table.sql"
        )
        print("  user_preferences_weights table exists and is accessible")


@requires_supabase
class TestWeightsTableSchema:
    """Verify the table has the correct columns and constraints."""

    def test_columns_exist(self, test_auth_user):
        """The table should have all expected columns."""
        user_id = test_auth_user["id"]
        row = _insert_weights({
            "user_id": user_id,
            "vibe_weights": {"romantic": 1.4},
            "interest_weights": {"Cooking": 1.2},
            "type_weights": {"gift": 1.1},
            "love_language_weights": {"quality_time": 1.3},
            "feedback_count": 5,
        })
        try:
            expected_columns = {
                "id", "user_id", "vibe_weights", "interest_weights",
                "type_weights", "love_language_weights", "feedback_count",
                "last_analyzed_at", "created_at", "updated_at",
            }
            actual_columns = set(row.keys())
            assert expected_columns.issubset(actual_columns), (
                f"Missing columns: {expected_columns - actual_columns}"
            )
            print(f"  All columns present: {sorted(actual_columns)}")
        finally:
            _delete_weights(row["id"])

    def test_unique_constraint_on_user_id(self, test_auth_user):
        """Inserting two rows for the same user_id should fail."""
        user_id = test_auth_user["id"]
        row1 = _insert_weights({"user_id": user_id, "feedback_count": 1})
        try:
            resp = _insert_weights_raw({"user_id": user_id, "feedback_count": 2})
            assert resp.status_code in (400, 409), (
                f"Expected 400/409 for duplicate user_id, "
                f"got HTTP {resp.status_code}. Response: {resp.text}"
            )
            print("  UNIQUE constraint on user_id enforced")
        finally:
            _delete_weights(row1["id"])

    def test_jsonb_columns_store_and_retrieve(self, test_auth_user):
        """JSONB columns should correctly store and retrieve weight maps."""
        user_id = test_auth_user["id"]
        vibe_w = {"romantic": 1.4, "adventurous": 0.7}
        row = _insert_weights({
            "user_id": user_id,
            "vibe_weights": vibe_w,
        })
        try:
            assert row["vibe_weights"] == vibe_w
            print(f"  JSONB roundtrip: {row['vibe_weights']}")
        finally:
            _delete_weights(row["id"])

    def test_defaults_applied(self, test_auth_user):
        """Default values should be applied for optional columns."""
        user_id = test_auth_user["id"]
        row = _insert_weights({"user_id": user_id})
        try:
            assert row["vibe_weights"] == {}
            assert row["interest_weights"] == {}
            assert row["type_weights"] == {}
            assert row["love_language_weights"] == {}
            assert row["feedback_count"] == 0
            assert row["created_at"] is not None
            assert row["updated_at"] is not None
            print("  All defaults applied correctly")
        finally:
            _delete_weights(row["id"])

    def test_anon_client_cannot_read_weights(self, test_auth_user):
        """The anon client should not see any weights (RLS enforced)."""
        user_id = test_auth_user["id"]
        row = _insert_weights({"user_id": user_id, "feedback_count": 1})
        try:
            resp = httpx.get(
                f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
                headers=_anon_headers(),
                params={"select": "*"},
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 0, (
                f"Anon client can see {len(rows)} weights row(s)! "
                "RLS is not properly configured."
            )
            print("  Anon client: 0 weights rows visible — RLS enforced")
        finally:
            _delete_weights(row["id"])


@requires_supabase
class TestWeightsCascadeDelete:
    """Verify CASCADE delete behavior."""

    def test_cascade_delete_from_auth_user(self):
        """Deleting an auth user should CASCADE delete their weights row."""
        temp_email = f"knot-fba-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeFBA!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)
            row = _insert_weights({
                "user_id": temp_user_id,
                "feedback_count": 1,
            })
            weights_id = row["id"]

            # Verify it exists
            found = _get_weights_for_user(temp_user_id)
            assert found is not None, "Weights row should exist before deletion"

            # Delete auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200
            time.sleep(0.5)

            # Verify weights are gone
            found_after = _get_weights_for_user(temp_user_id)
            assert found_after is None, (
                "Weights row still exists after auth user deletion. "
                "Check CASCADE on user_id FK."
            )
            print("  CASCADE delete verified: auth deletion removed weights row")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise


# ===================================================================
# 10. Integration tests: Upsert behavior (requires Supabase)
# ===================================================================

@requires_supabase
class TestWeightsUpsert:
    """Verify upsert logic works correctly."""

    def test_upsert_inserts_new_row(self, test_auth_user):
        """Upserting for a new user should create a row."""
        user_id = test_auth_user["id"]

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
            headers={
                **_service_headers(),
                "Prefer": "return=representation,resolution=merge-duplicates",
            },
            json={
                "user_id": user_id,
                "vibe_weights": {"romantic": 1.3},
                "feedback_count": 5,
            },
        )
        assert resp.status_code in (200, 201)
        row = resp.json()[0] if isinstance(resp.json(), list) else resp.json()
        try:
            assert row["vibe_weights"] == {"romantic": 1.3}
            assert row["feedback_count"] == 5
            print("  Upsert insert: new row created")
        finally:
            _delete_weights(row["id"])

    def test_upsert_updates_existing_row(self, test_auth_user):
        """Upserting for an existing user should update the row."""
        user_id = test_auth_user["id"]

        # Insert first
        row1 = _insert_weights({
            "user_id": user_id,
            "vibe_weights": {"romantic": 1.1},
            "feedback_count": 3,
        })

        # Upsert with new data (on_conflict=user_id for UNIQUE constraint)
        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/user_preferences_weights?on_conflict=user_id",
            headers={
                **_service_headers(),
                "Prefer": "return=representation,resolution=merge-duplicates",
            },
            json={
                "user_id": user_id,
                "vibe_weights": {"romantic": 1.5, "adventurous": 0.8},
                "feedback_count": 10,
            },
        )
        assert resp.status_code in (200, 201)
        row2 = resp.json()[0] if isinstance(resp.json(), list) else resp.json()

        try:
            # Should have the updated values
            assert row2["vibe_weights"] == {"romantic": 1.5, "adventurous": 0.8}
            assert row2["feedback_count"] == 10
            # Should be the same row (same ID)
            assert row2["id"] == row1["id"]
            print("  Upsert update: existing row updated in place")
        finally:
            _delete_weights(row1["id"])


# ===================================================================
# 11. Integration tests: Full analysis flow (requires Supabase)
# ===================================================================

@requires_supabase
class TestFeedbackAnalysisFlow:
    """
    End-to-end tests for the feedback analysis job.

    These tests seed the database with feedback data and run the analysis,
    verifying that the computed weights match expected patterns.
    """

    @pytest.mark.asyncio
    async def test_romantic_vibes_weighted_higher(self, test_seeded_feedback):
        """
        The spec test: seed high ratings for romantic, low for adventurous.
        Run the analysis. Confirm romantic weight > adventurous weight.
        """
        from app.services.feedback_analysis import analyze_user_feedback, upsert_user_weights

        user_id = test_seeded_feedback["user"]["id"]

        weights = await analyze_user_feedback(user_id)
        assert weights is not None, "Analysis should return weights for user with 7 feedback entries"

        # Romantic vibes should have higher weight than adventurous
        romantic_w = weights.vibe_weights.get("romantic", 1.0)
        adventurous_w = weights.vibe_weights.get("adventurous", 1.0)

        print(f"  Romantic weight: {romantic_w:.3f}")
        print(f"  Adventurous weight: {adventurous_w:.3f}")

        assert romantic_w > adventurous_w, (
            f"Romantic ({romantic_w:.3f}) should be weighted higher "
            f"than adventurous ({adventurous_w:.3f})"
        )
        assert romantic_w > 1.0, f"Romantic weight ({romantic_w:.3f}) should be above neutral"
        assert adventurous_w < 1.0, f"Adventurous weight ({adventurous_w:.3f}) should be below neutral"

    @pytest.mark.asyncio
    async def test_type_weights_computed(self, test_seeded_feedback):
        """Type weights should be computed based on recommendation_type feedback."""
        from app.services.feedback_analysis import analyze_user_feedback

        user_id = test_seeded_feedback["user"]["id"]
        weights = await analyze_user_feedback(user_id)
        assert weights is not None

        # Should have type weights for experience and/or date
        assert len(weights.type_weights) > 0, "Should have at least one type weight"
        print(f"  Type weights: {weights.type_weights}")

    @pytest.mark.asyncio
    async def test_upsert_stores_weights(self, test_seeded_feedback):
        """Running analysis and upsert should store weights in the database."""
        from app.services.feedback_analysis import analyze_user_feedback, upsert_user_weights

        user_id = test_seeded_feedback["user"]["id"]

        weights = await analyze_user_feedback(user_id)
        assert weights is not None

        await upsert_user_weights(weights)

        # Verify stored in database
        stored = _get_weights_for_user(user_id)
        assert stored is not None, "Weights should be stored in database"
        assert stored["feedback_count"] == 7
        assert stored["vibe_weights"].get("romantic") is not None
        assert stored["last_analyzed_at"] is not None
        print(f"  Stored weights: vibe_weights={stored['vibe_weights']}")

    @pytest.mark.asyncio
    async def test_analysis_idempotent(self, test_seeded_feedback):
        """Running analysis twice should produce identical weights."""
        from app.services.feedback_analysis import analyze_user_feedback

        user_id = test_seeded_feedback["user"]["id"]

        weights1 = await analyze_user_feedback(user_id)
        weights2 = await analyze_user_feedback(user_id)

        assert weights1 is not None
        assert weights2 is not None

        assert weights1.vibe_weights == weights2.vibe_weights
        assert weights1.type_weights == weights2.type_weights
        assert weights1.interest_weights == weights2.interest_weights
        assert weights1.love_language_weights == weights2.love_language_weights
        assert weights1.feedback_count == weights2.feedback_count
        print("  Idempotency verified: two runs produce identical weights")

    @pytest.mark.asyncio
    async def test_run_feedback_analysis_single_user(self, test_seeded_feedback):
        """run_feedback_analysis with a target user_id should analyze only that user."""
        from app.services.feedback_analysis import run_feedback_analysis

        user_id = test_seeded_feedback["user"]["id"]
        result = await run_feedback_analysis(target_user_id=user_id)

        assert result["status"] == "completed"
        assert result["users_analyzed"] == 1
        print(f"  Single user analysis: {result}")

        # Verify weights stored
        stored = _get_weights_for_user(user_id)
        assert stored is not None
        assert stored["feedback_count"] == 7

    @pytest.mark.asyncio
    async def test_no_feedback_returns_none(self, test_vault_with_vibes):
        """A user with no feedback should not get weights computed."""
        from app.services.feedback_analysis import analyze_user_feedback

        user_id = test_vault_with_vibes["user"]["id"]
        weights = await analyze_user_feedback(user_id)
        assert weights is None, "User with no feedback should return None"
        print("  No feedback: analysis returns None (no weights created)")

    @pytest.mark.asyncio
    async def test_insufficient_feedback_returns_none(self, test_vault_with_vibes):
        """A user with fewer than MIN_FEEDBACK_FOR_ADJUSTMENT entries should return None."""
        from app.services.feedback_analysis import analyze_user_feedback, MIN_FEEDBACK_FOR_ADJUSTMENT

        user_id = test_vault_with_vibes["user"]["id"]
        vault_id = test_vault_with_vibes["vault"]["id"]

        # Insert only 1 recommendation + 1 feedback (below threshold)
        rec = _insert_recommendation({
            "vault_id": vault_id,
            "recommendation_type": "gift",
            "title": "Test Gift",
            "external_url": "https://example.com/test",
        })
        _insert_feedback({
            "recommendation_id": rec["id"],
            "user_id": user_id,
            "action": "rated",
            "rating": 5,
        })

        weights = await analyze_user_feedback(user_id)
        assert weights is None, (
            f"User with 1 feedback entry (below {MIN_FEEDBACK_FOR_ADJUSTMENT}) "
            "should return None"
        )
        print(f"  Insufficient feedback (1 < {MIN_FEEDBACK_FOR_ADJUSTMENT}): returns None")

    @pytest.mark.asyncio
    async def test_refreshed_feedback_negative_signal(self, test_vault_with_vibes):
        """Refreshed (rejected) feedback should create a negative weight signal."""
        from app.services.feedback_analysis import analyze_user_feedback

        user_id = test_vault_with_vibes["user"]["id"]
        vault_id = test_vault_with_vibes["vault"]["id"]

        # Create 4 recommendations with 'refreshed' action (above threshold)
        for i in range(4):
            rec = _insert_recommendation({
                "vault_id": vault_id,
                "recommendation_type": "experience",
                "title": f"Extreme Adventure {i}",
                "description": "An adventurous thrill experience.",
                "external_url": f"https://example.com/adv-{i}",
            })
            _insert_feedback({
                "recommendation_id": rec["id"],
                "user_id": user_id,
                "action": "refreshed",
                "feedback_text": "not_their_style",
            })

        weights = await analyze_user_feedback(user_id)
        assert weights is not None

        # Adventurous vibe should be penalized
        adv_weight = weights.vibe_weights.get("adventurous", 1.0)
        assert adv_weight < 1.0, (
            f"Adventurous weight ({adv_weight:.3f}) should be below neutral "
            "after all-refreshed feedback"
        )
        print(f"  Refreshed signal: adventurous weight = {adv_weight:.3f}")

    @pytest.mark.asyncio
    async def test_full_spec_flow(self, test_seeded_feedback):
        """
        The exact test from the implementation plan spec:

        Seed the database with feedback data (high ratings for "romantic" vibe,
        low for "adventurous"). Run the job. Confirm weights are updated.
        Confirm subsequent recommendations favor "romantic."
        """
        from app.services.feedback_analysis import run_feedback_analysis

        user_id = test_seeded_feedback["user"]["id"]

        # Run the full job
        result = await run_feedback_analysis(target_user_id=user_id)
        assert result["status"] == "completed"
        assert result["users_analyzed"] == 1

        # Verify weights stored
        stored = _get_weights_for_user(user_id)
        assert stored is not None, "Weights should be stored after analysis"

        romantic_w = stored["vibe_weights"].get("romantic", 1.0)
        adventurous_w = stored["vibe_weights"].get("adventurous", 1.0)

        assert romantic_w > adventurous_w, (
            f"Romantic ({romantic_w}) should be weighted higher than "
            f"adventurous ({adventurous_w})"
        )
        assert stored["feedback_count"] == 7

        print(f"  Full spec flow passed:")
        print(f"    Romantic weight:    {romantic_w:.3f}")
        print(f"    Adventurous weight: {adventurous_w:.3f}")
        print(f"    Feedback count:     {stored['feedback_count']}")
        print(f"    Vibe weights:       {stored['vibe_weights']}")
        print(f"    Type weights:       {stored['type_weights']}")
