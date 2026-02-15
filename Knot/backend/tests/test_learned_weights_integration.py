"""
Step 10.3 Verification: Integrate Learned Weights into Recommendation Graph

Tests that learned preference weights (from the feedback analysis job) are
correctly applied as multipliers in the filtering and matching pipeline nodes:

1. Interest weights scale interest match scores in the filtering node
2. Vibe weights scale vibe boost contributions in the matching node
3. Love language weights scale love language boosts in the matching node
4. Type weights apply as final multipliers to candidate scores
5. No weights (None) preserves backward-compatible default behavior
6. Spec test: strong "receiving_gifts" weight ranks gifts higher than experiences
7. State schema accepts the learned_weights field
8. Integration: load_learned_weights returns weights from DB (requires Supabase)

Prerequisites:
- Complete Steps 5.1-5.5 (pipeline state, filtering, matching nodes)
- Complete Step 10.2 (feedback analysis job, user_preferences_weights table)

Run with: pytest tests/test_learned_weights_integration.py -v
"""

import uuid

import pytest
import httpx
import time

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.filtering import (
    _score_candidate,
    filter_by_interests,
)
from app.agents.matching import (
    VIBE_MATCH_BOOST,
    _compute_love_language_boost,
    _compute_vibe_boost,
    match_vibes_and_love_languages,
)
from app.models.feedback_analysis import UserPreferencesWeights
from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ======================================================================
# Supabase configuration check
# ======================================================================

def _supabase_configured() -> bool:
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ======================================================================
# Supabase helpers (for integration tests)
# ======================================================================

def _service_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _admin_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _create_auth_user(email: str, password: str) -> str:
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, (
        f"Failed to create test auth user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["id"]


def _delete_auth_user(user_id: str):
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
        warnings.warn(f"Exception deleting test auth user {user_id}: {exc}", stacklevel=2)


def _insert_weights(weights_data: dict) -> dict:
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


def _delete_weights(weights_id: str):
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/user_preferences_weights",
        headers=_service_headers(),
        params={"id": f"eq.{weights_id}"},
    )


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-weights-test",
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
        "interests": ["Cooking", "Travel", "Music", "Art", "Hiking"],
        "dislikes": ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        "vibes": ["quiet_luxury", "romantic"],
        "primary_love_language": "quality_time",
        "secondary_love_language": "receiving_gifts",
        "budgets": [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 10000, "currency": "USD"},
            {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 25000, "currency": "USD"},
        ],
    }
    data.update(overrides)
    return data


def _sample_milestone(**overrides) -> dict:
    data = {
        "id": "milestone-weights-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(
    filtered=None,
    candidates=None,
    learned_weights=None,
    **overrides,
) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=2000, max_amount=30000),
        "learned_weights": learned_weights,
    }
    defaults.update(overrides)
    state = RecommendationState(**defaults)
    if filtered is not None:
        state = state.model_copy(update={"filtered_recommendations": filtered})
    if candidates is not None:
        state = state.model_copy(update={"candidate_recommendations": candidates})
    return state


def _make_candidate(
    title: str = "Test Gift",
    description: str = "A test gift description",
    rec_type: str = "gift",
    source: str = "amazon",
    price_cents: int = 5000,
    interest_score: float = 0.0,
    matched_interest: str | None = None,
    matched_vibe: str | None = None,
    **overrides,
) -> CandidateRecommendation:
    """Build a CandidateRecommendation with sensible defaults."""
    metadata = {}
    if matched_interest:
        metadata["matched_interest"] = matched_interest
    if matched_vibe:
        metadata["matched_vibe"] = matched_vibe
    metadata["catalog"] = "stub"

    data = {
        "id": str(uuid.uuid4()),
        "source": source,
        "type": rec_type,
        "title": title,
        "description": description,
        "price_cents": price_cents,
        "external_url": f"https://{source}.com/products/test",
        "image_url": "https://images.example.com/test.jpg",
        "merchant_name": "Test Merchant",
        "metadata": metadata,
        "interest_score": interest_score,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


def _make_weights(**overrides) -> UserPreferencesWeights:
    """Build a UserPreferencesWeights with sensible defaults."""
    data = {
        "user_id": "test-user-weights",
        "vibe_weights": {},
        "interest_weights": {},
        "type_weights": {},
        "love_language_weights": {},
        "feedback_count": 10,
    }
    data.update(overrides)
    return UserPreferencesWeights(**data)


# ======================================================================
# 1. State schema tests
# ======================================================================

class TestStateSchemaUpdated:
    """Verify RecommendationState accepts the learned_weights field."""

    def test_state_accepts_learned_weights(self):
        """RecommendationState should accept a UserPreferencesWeights instance."""
        weights = _make_weights(vibe_weights={"romantic": 1.4})
        state = _make_state(learned_weights=weights)
        assert state.learned_weights is not None
        assert state.learned_weights.vibe_weights["romantic"] == 1.4

    def test_state_defaults_learned_weights_to_none(self):
        """RecommendationState should default learned_weights to None."""
        state = _make_state()
        assert state.learned_weights is None

    def test_state_serializes_with_learned_weights(self):
        """State with learned_weights should serialize to JSON and back."""
        weights = _make_weights(
            vibe_weights={"romantic": 1.4},
            type_weights={"gift": 1.2},
        )
        state = _make_state(learned_weights=weights)
        json_str = state.model_dump_json()
        restored = RecommendationState.model_validate_json(json_str)
        assert restored.learned_weights is not None
        assert restored.learned_weights.vibe_weights["romantic"] == 1.4
        assert restored.learned_weights.type_weights["gift"] == 1.2


# ======================================================================
# 2. Filtering node: interest weight tests
# ======================================================================

class TestFilteringWithWeights:
    """Verify _score_candidate applies interest weight multipliers."""

    def test_interest_weight_amplifies_score(self):
        """A boosted interest weight should increase the candidate's score."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        interests = ["Cooking", "Travel", "Music", "Art", "Hiking"]
        dislikes = ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"]

        score_default = _score_candidate(candidate, interests, dislikes)
        score_boosted = _score_candidate(
            candidate, interests, dislikes,
            interest_weights={"Cooking": 1.5},
        )
        assert score_boosted > score_default
        print(f"  Default: {score_default}, Boosted: {score_boosted}")

    def test_interest_weight_reduces_score(self):
        """A penalized interest weight should decrease the candidate's score."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        interests = ["Cooking", "Travel", "Music", "Art", "Hiking"]
        dislikes = ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"]

        score_default = _score_candidate(candidate, interests, dislikes)
        score_penalized = _score_candidate(
            candidate, interests, dislikes,
            interest_weights={"Cooking": 0.6},
        )
        assert score_penalized < score_default
        print(f"  Default: {score_default}, Penalized: {score_penalized}")

    def test_neutral_weight_preserves_score(self):
        """A weight of 1.0 should produce the same score as no weights."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        interests = ["Cooking", "Travel", "Music", "Art", "Hiking"]
        dislikes = ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"]

        score_default = _score_candidate(candidate, interests, dislikes)
        score_neutral = _score_candidate(
            candidate, interests, dislikes,
            interest_weights={"Cooking": 1.0},
        )
        assert score_default == score_neutral

    def test_none_weights_same_as_default(self):
        """Passing None for interest_weights should behave identically to no weights."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        interests = ["Cooking"]
        dislikes = ["Gaming"]

        score_none = _score_candidate(candidate, interests, dislikes, None)
        score_default = _score_candidate(candidate, interests, dislikes)
        assert score_none == score_default

    def test_metadata_bonus_not_scaled(self):
        """The 0.5 metadata bonus should NOT be scaled by interest weights."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        interests = ["Cooking"]
        dislikes = []

        # With weight 2.0: interest match = 1.0 * 2.0 = 2.0, bonus = 0.5 → total 2.5
        score = _score_candidate(
            candidate, interests, dislikes,
            interest_weights={"Cooking": 2.0},
        )
        assert score == 2.5

    def test_dislikes_still_filtered_with_weights(self):
        """Dislike matching should still return -1.0 regardless of weights."""
        candidate = _make_candidate(
            title="Gaming Keyboard",
            matched_interest="Gaming",
        )
        interests = ["Cooking"]
        dislikes = ["Gaming"]

        score = _score_candidate(
            candidate, interests, dislikes,
            interest_weights={"Gaming": 0.5},
        )
        assert score == -1.0

    async def test_full_filtering_node_with_weights(self):
        """The filtering node should pass through interest weights from learned_weights."""
        weights = _make_weights(interest_weights={"Cooking": 1.8, "Travel": 0.6})
        candidates = [
            _make_candidate(
                title="Chef Knife",
                matched_interest="Cooking",
            ),
            _make_candidate(
                title="Passport Holder",
                matched_interest="Travel",
            ),
        ]
        state = _make_state(candidates=candidates, learned_weights=weights)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # Cooking should rank higher than Travel due to weight amplification
        assert filtered[0].title == "Chef Knife"
        assert filtered[0].interest_score > filtered[1].interest_score
        print(f"  Cooking score: {filtered[0].interest_score}, Travel score: {filtered[1].interest_score}")


# ======================================================================
# 3. Matching node: vibe weight tests
# ======================================================================

class TestVibeBoostWithWeights:
    """Verify _compute_vibe_boost scales by vibe weights."""

    def test_boosted_vibe_weight_increases_boost(self):
        """A vibe with weight > 1.0 should increase the boost."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        default_boost = _compute_vibe_boost(candidate, ["quiet_luxury"])
        weighted_boost = _compute_vibe_boost(
            candidate, ["quiet_luxury"],
            vibe_weights={"quiet_luxury": 1.5},
        )
        assert weighted_boost > default_boost
        assert weighted_boost == VIBE_MATCH_BOOST * 1.5
        print(f"  Default: {default_boost}, Weighted: {weighted_boost}")

    def test_penalized_vibe_weight_decreases_boost(self):
        """A vibe with weight < 1.0 should decrease the boost."""
        candidate = _make_candidate(
            title="Escape Room Challenge",
            rec_type="experience",
            matched_vibe="adventurous",
        )
        default_boost = _compute_vibe_boost(candidate, ["adventurous"])
        weighted_boost = _compute_vibe_boost(
            candidate, ["adventurous"],
            vibe_weights={"adventurous": 0.7},
        )
        assert weighted_boost < default_boost
        assert weighted_boost == VIBE_MATCH_BOOST * 0.7

    def test_neutral_weight_preserves_boost(self):
        """A weight of 1.0 should produce the same boost as no weights."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        default_boost = _compute_vibe_boost(candidate, ["quiet_luxury"])
        neutral_boost = _compute_vibe_boost(
            candidate, ["quiet_luxury"],
            vibe_weights={"quiet_luxury": 1.0},
        )
        assert default_boost == neutral_boost

    def test_none_weights_same_as_default(self):
        """None vibe_weights should behave identically to no weights."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        default_boost = _compute_vibe_boost(candidate, ["quiet_luxury"])
        none_boost = _compute_vibe_boost(candidate, ["quiet_luxury"], vibe_weights=None)
        assert default_boost == none_boost

    def test_mixed_vibe_weights(self):
        """Different weights for different vibes should apply correctly."""
        candidate = _make_candidate(
            title="Candlelit Dinner Cruise",
            description="Exclusive luxury sunset cruise for couples",
            rec_type="date",
            matched_vibe="romantic",
        )
        # Matches romantic (metadata) and quiet_luxury (keyword "luxury")
        boost = _compute_vibe_boost(
            candidate, ["romantic", "quiet_luxury"],
            vibe_weights={"romantic": 1.5, "quiet_luxury": 0.8},
        )
        expected = VIBE_MATCH_BOOST * 1.5 + VIBE_MATCH_BOOST * 0.8
        assert abs(boost - expected) < 0.001


# ======================================================================
# 4. Matching node: love language weight tests
# ======================================================================

class TestLoveLanguageBoostWithWeights:
    """Verify _compute_love_language_boost scales by love language weights."""

    def test_boosted_primary_ll_weight(self):
        """A boosted primary love language weight should increase the boost."""
        candidate = _make_candidate(rec_type="gift")
        default_boost = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
        )
        weighted_boost = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
            ll_weights={"receiving_gifts": 1.5},
        )
        assert weighted_boost > default_boost
        # Primary receiving_gifts base is 0.40; scaled: 0.40 * 1.5 = 0.60
        assert weighted_boost == 0.40 * 1.5
        print(f"  Default: {default_boost}, Weighted: {weighted_boost}")

    def test_boosted_secondary_ll_weight(self):
        """A boosted secondary love language weight should increase the boost."""
        candidate = _make_candidate(rec_type="gift")
        default_boost = _compute_love_language_boost(
            candidate, "quality_time", "receiving_gifts",
        )
        weighted_boost = _compute_love_language_boost(
            candidate, "quality_time", "receiving_gifts",
            ll_weights={"receiving_gifts": 1.8},
        )
        assert weighted_boost > default_boost
        # Secondary receiving_gifts base is 0.20; scaled: 0.20 * 1.8 = 0.36
        assert weighted_boost == 0.20 * 1.8

    def test_none_ll_weights_same_as_default(self):
        """None ll_weights should behave identically to no weights."""
        candidate = _make_candidate(rec_type="gift")
        default_boost = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
        )
        none_boost = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
            ll_weights=None,
        )
        assert default_boost == none_boost

    def test_both_primary_and_secondary_weighted(self):
        """Both primary and secondary boosts should be scaled independently."""
        # Couples Spa: type=experience (quality_time), "spa" keyword (physical_touch)
        candidate = _make_candidate(
            title="Couples Spa Day",
            description="Couples massage and spa treatment",
            rec_type="experience",
        )
        boost = _compute_love_language_boost(
            candidate, "quality_time", "physical_touch",
            ll_weights={"quality_time": 1.3, "physical_touch": 1.5},
        )
        # Primary quality_time: 0.40 * 1.3 = 0.52
        # Secondary physical_touch: 0.10 * 1.5 = 0.15
        expected = 0.40 * 1.3 + 0.10 * 1.5
        assert abs(boost - expected) < 0.001


# ======================================================================
# 5. Matching node: type weight tests
# ======================================================================

class TestTypeWeightMultiplier:
    """Verify type weights apply as final multipliers to candidate scores."""

    async def test_gift_type_weight_boosts_gifts(self):
        """A gift type weight > 1.0 should increase gift candidate final scores."""
        weights = _make_weights(type_weights={"gift": 1.5, "experience": 1.0})

        gift = _make_candidate(
            title="Chef Knife",
            rec_type="gift",
            interest_score=1.0,
        )
        experience = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            interest_score=1.0,
        )

        # Run without weights
        state_no_weights = _make_state(
            filtered=[gift, experience],
            vault_data=VaultData(**_sample_vault_data(
                vibes=[],
                primary_love_language="acts_of_service",
                secondary_love_language="words_of_affirmation",
            )),
        )
        result_no_weights = await match_vibes_and_love_languages(state_no_weights)
        no_weight_gift_score = next(
            c.final_score for c in result_no_weights["filtered_recommendations"]
            if c.type == "gift"
        )

        # Run with weights
        state_with_weights = _make_state(
            filtered=[gift, experience],
            learned_weights=weights,
            vault_data=VaultData(**_sample_vault_data(
                vibes=[],
                primary_love_language="acts_of_service",
                secondary_love_language="words_of_affirmation",
            )),
        )
        result_with_weights = await match_vibes_and_love_languages(state_with_weights)
        weighted_gift_score = next(
            c.final_score for c in result_with_weights["filtered_recommendations"]
            if c.type == "gift"
        )

        assert weighted_gift_score > no_weight_gift_score
        print(f"  Gift no-weight: {no_weight_gift_score}, weighted: {weighted_gift_score}")

    async def test_experience_type_weight_penalty(self):
        """An experience type weight < 1.0 should decrease experience scores."""
        weights = _make_weights(type_weights={"experience": 0.7})
        candidate = _make_candidate(
            title="Generic Experience",
            rec_type="experience",
            interest_score=1.0,
        )

        # Without weights
        state_none = _make_state(
            filtered=[candidate],
            vault_data=VaultData(**_sample_vault_data(vibes=[])),
        )
        r1 = await match_vibes_and_love_languages(state_none)
        score_none = r1["filtered_recommendations"][0].final_score

        # With penalty weight
        state_weighted = _make_state(
            filtered=[candidate],
            learned_weights=weights,
            vault_data=VaultData(**_sample_vault_data(vibes=[])),
        )
        r2 = await match_vibes_and_love_languages(state_weighted)
        score_weighted = r2["filtered_recommendations"][0].final_score

        assert score_weighted < score_none


# ======================================================================
# 6. Full matching node with weights end-to-end
# ======================================================================

class TestFullMatchingNodeWithWeights:
    """End-to-end tests for the matching node with learned weights."""

    async def test_weights_change_ranking_order(self):
        """Learned weights should change the ranking order of candidates."""
        # Without weights: romantic + quiet_luxury vibes → Spa Day ranks high
        # With weights: adventurous boosted → Escape Room should rank higher
        romantic_candidate = _make_candidate(
            title="Candlelit Dinner",
            description="Romantic sunset dinner",
            rec_type="date",
            interest_score=0.0,
            matched_vibe="romantic",
        )
        adventurous_candidate = _make_candidate(
            title="Escape Room Adventure",
            description="Extreme puzzle thrill experience",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="adventurous",
        )

        vault = VaultData(**_sample_vault_data(
            vibes=["romantic", "adventurous"],
            primary_love_language="quality_time",
            secondary_love_language="receiving_gifts",
        ))

        # Without weights: both vibes match, romantic gets +0.30, adventurous gets +0.30
        # quality_time primary → both experience/date types get +0.40
        state_no_weights = _make_state(
            filtered=[romantic_candidate, adventurous_candidate],
            vault_data=vault,
        )
        r1 = await match_vibes_and_love_languages(state_no_weights)

        # With weights: adventurous boosted to 2.0, romantic penalized to 0.5
        weights = _make_weights(
            vibe_weights={"adventurous": 2.0, "romantic": 0.5},
        )
        state_with_weights = _make_state(
            filtered=[romantic_candidate, adventurous_candidate],
            learned_weights=weights,
            vault_data=vault,
        )
        r2 = await match_vibes_and_love_languages(state_with_weights)

        ranked_weighted = r2["filtered_recommendations"]
        # Adventurous should now rank first due to 2x vibe weight
        assert ranked_weighted[0].title == "Escape Room Adventure"

    async def test_no_weights_preserves_original_behavior(self):
        """When learned_weights is None, scoring should be identical to pre-Step-10.3."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )

        vault = VaultData(**_sample_vault_data(
            vibes=["quiet_luxury"],
            primary_love_language="quality_time",
            secondary_love_language="receiving_gifts",
        ))

        state = _make_state(
            filtered=[candidate],
            vault_data=vault,
            learned_weights=None,
        )
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        # Should match pre-10.3 behavior exactly:
        # base=1.0, vibe=+0.30, ll=+0.40 → 1.0 × 1.30 × 1.40 = 1.82
        expected = 1.0 * 1.30 * 1.40
        assert abs(c.final_score - expected) < 0.001
        assert c.vibe_score == 0.30
        assert c.love_language_score == 0.40


# ======================================================================
# 7. Spec test from implementation plan
# ======================================================================

class TestSpecRequirement:
    """
    The spec test from Step 10.3:
    Set up a user with strong preference weights for "receiving_gifts"
    love language. Generate recommendations. Confirm gift-type
    recommendations are ranked higher than experiences.
    """

    async def test_receiving_gifts_weight_ranks_gifts_higher(self):
        """
        With strong receiving_gifts love language weight, gift-type
        recommendations should rank higher than experiences.
        """
        # Learned weights: strong preference for receiving_gifts + gift type
        weights = _make_weights(
            love_language_weights={"receiving_gifts": 1.8},
            type_weights={"gift": 1.4, "experience": 0.8, "date": 0.8},
        )

        gift_a = _make_candidate(
            title="Japanese Chef Knife",
            rec_type="gift",
            interest_score=1.0,
            matched_interest="Cooking",
        )
        gift_b = _make_candidate(
            title="Premium Wireless Headphones",
            rec_type="gift",
            interest_score=1.0,
            matched_interest="Music",
        )
        experience_a = _make_candidate(
            title="Sunset Kayak Tour",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="outdoorsy",
        )
        experience_b = _make_candidate(
            title="Rock Climbing Class",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="adventurous",
        )

        state = _make_state(
            filtered=[experience_a, gift_a, experience_b, gift_b],
            learned_weights=weights,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["outdoorsy"],
                primary_love_language="receiving_gifts",
                secondary_love_language="acts_of_service",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        # Both gifts should rank above both experiences
        assert ranked[0].type == "gift", (
            f"Expected top recommendation to be gift, got {ranked[0].type}: {ranked[0].title}"
        )
        assert ranked[1].type == "gift", (
            f"Expected second recommendation to be gift, got {ranked[1].type}: {ranked[1].title}"
        )

        print(f"  Ranked order:")
        for i, c in enumerate(ranked):
            print(f"    {i+1}. [{c.type}] {c.title} — final_score={c.final_score:.3f}")

    async def test_receiving_gifts_weight_with_competing_vibes(self):
        """
        Even when experiences have vibe matches, strong gift preference
        should still rank gifts higher.
        """
        weights = _make_weights(
            love_language_weights={"receiving_gifts": 2.0},
            type_weights={"gift": 1.5},
        )

        gift = _make_candidate(
            title="Chef Knife",
            rec_type="gift",
            interest_score=1.0,
        )
        experience = _make_candidate(
            title="Spa Day for Two",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )

        state = _make_state(
            filtered=[experience, gift],
            learned_weights=weights,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury"],
                primary_love_language="receiving_gifts",
                secondary_love_language="quality_time",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        assert ranked[0].type == "gift", (
            f"Gift should rank first even against vibe-matched experience. "
            f"Got: {ranked[0].type} ({ranked[0].title})"
        )


# ======================================================================
# 8. No weights backward compatibility
# ======================================================================

class TestNoWeightsDefaultBehavior:
    """When learned_weights is None, behavior should be identical to pre-Step-10.3."""

    async def test_filtering_without_weights_unchanged(self):
        """Filtering node without weights should produce same results as before."""
        candidates = [
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Gaming Keyboard", matched_interest="Gaming"),
            _make_candidate(title="Spa Day", rec_type="experience", matched_vibe="romantic"),
        ]

        state = _make_state(candidates=candidates, learned_weights=None)
        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # Gaming removed (dislike), 2 survivors
        assert len(filtered) == 2
        assert all(c.title != "Gaming Keyboard" for c in filtered)

    async def test_matching_without_weights_unchanged(self):
        """Matching node without weights should produce same scores as before."""
        candidate = _make_candidate(
            title="Fine Dining Omakase",
            rec_type="date",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )

        state = _make_state(
            filtered=[candidate],
            learned_weights=None,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        assert c.vibe_score == 0.30
        assert c.love_language_score == 0.40
        expected_final = 1.0 * 1.30 * 1.40
        assert abs(c.final_score - expected_final) < 0.001


# ======================================================================
# 9. Module import tests
# ======================================================================

class TestModuleImports:
    """Verify all new functions and fields are importable."""

    def test_learned_weights_field_on_state(self):
        """RecommendationState should have learned_weights field."""
        state = RecommendationState(
            vault_data=VaultData(**_sample_vault_data()),
            occasion_type="just_because",
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
        )
        assert hasattr(state, "learned_weights")

    def test_load_learned_weights_importable(self):
        """load_learned_weights should be importable from vault_loader."""
        from app.services.vault_loader import load_learned_weights
        assert callable(load_learned_weights)

    def test_user_preferences_weights_importable(self):
        """UserPreferencesWeights should be importable from state module."""
        from app.agents.state import UserPreferencesWeights
        assert UserPreferencesWeights is not None

    def test_score_candidate_accepts_interest_weights(self):
        """_score_candidate should accept interest_weights parameter."""
        import inspect
        sig = inspect.signature(_score_candidate)
        assert "interest_weights" in sig.parameters

    def test_compute_vibe_boost_accepts_vibe_weights(self):
        """_compute_vibe_boost should accept vibe_weights parameter."""
        import inspect
        sig = inspect.signature(_compute_vibe_boost)
        assert "vibe_weights" in sig.parameters

    def test_compute_love_language_boost_accepts_ll_weights(self):
        """_compute_love_language_boost should accept ll_weights parameter."""
        import inspect
        sig = inspect.signature(_compute_love_language_boost)
        assert "ll_weights" in sig.parameters


# ======================================================================
# 10. Integration tests: load_learned_weights (requires Supabase)
# ======================================================================

@pytest.fixture
def test_auth_user():
    """Create a test user in auth.users. Cleanup via CASCADE."""
    test_email = f"knot-lw-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)
    yield {"id": user_id, "email": test_email}
    _delete_auth_user(user_id)


@requires_supabase
class TestLoadLearnedWeights:
    """Verify load_learned_weights returns correct results from DB."""

    @pytest.mark.asyncio
    async def test_returns_weights_when_they_exist(self, test_auth_user):
        """Should return UserPreferencesWeights when a row exists."""
        from app.services.vault_loader import load_learned_weights

        user_id = test_auth_user["id"]
        row = _insert_weights({
            "user_id": user_id,
            "vibe_weights": {"romantic": 1.4, "adventurous": 0.7},
            "interest_weights": {"Cooking": 1.3},
            "type_weights": {"gift": 1.2},
            "love_language_weights": {"receiving_gifts": 1.5},
            "feedback_count": 10,
        })

        try:
            weights = await load_learned_weights(user_id)
            assert weights is not None
            assert weights.user_id == user_id
            assert weights.vibe_weights["romantic"] == 1.4
            assert weights.vibe_weights["adventurous"] == 0.7
            assert weights.interest_weights["Cooking"] == 1.3
            assert weights.type_weights["gift"] == 1.2
            assert weights.love_language_weights["receiving_gifts"] == 1.5
            assert weights.feedback_count == 10
            print(f"  Loaded weights: {weights}")
        finally:
            _delete_weights(row["id"])

    @pytest.mark.asyncio
    async def test_returns_none_when_no_weights(self, test_auth_user):
        """Should return None for a user with no weights row."""
        from app.services.vault_loader import load_learned_weights

        user_id = test_auth_user["id"]
        weights = await load_learned_weights(user_id)
        assert weights is None
        print("  No weights: returns None")

    @pytest.mark.asyncio
    async def test_returns_none_for_nonexistent_user(self):
        """Should return None for a non-existent user ID."""
        from app.services.vault_loader import load_learned_weights

        weights = await load_learned_weights("00000000-0000-0000-0000-000000000000")
        assert weights is None
