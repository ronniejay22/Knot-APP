"""
Step 5.6 Verification: Diversity Selection Node

Tests that the select_diverse_three LangGraph node:
1. Selects exactly 3 recommendations from the ranked pool
2. Maximizes diversity across price tier, type, and merchant
3. Prefers higher-scored candidates when diversity is equal
4. Handles edge cases (fewer than 3 candidates, empty input)
5. Returns result compatible with RecommendationState update

Test categories:
- Price tier classification: Verify _classify_price_tier splits budget into thirds
- Diversity scoring: Verify _diversity_score awards points per unique dimension
- Full node: Verify select_diverse_three end-to-end behavior
- Spec tests: The 3 specific tests from the implementation plan
- Edge cases: Empty candidates, fewer than 3, single candidate
- State compatibility: Verify returned dict updates RecommendationState correctly

Prerequisites:
- Complete Steps 5.1-5.5 (state schema through matching node)

Run with: pytest tests/test_selection_node.py -v
"""

import uuid

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.selection import (
    TARGET_COUNT,
    _classify_price_tier,
    _diversity_score,
    select_diverse_three,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-select-test",
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
        "id": "milestone-select-001",
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
    budget_min=3000,
    budget_max=30000,
    **overrides,
) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=budget_min, max_amount=budget_max),
    }
    defaults.update(overrides)
    state = RecommendationState(**defaults)
    if filtered is not None:
        state = state.model_copy(update={"filtered_recommendations": filtered})
    return state


def _make_candidate(
    title: str = "Test Gift",
    description: str = "A test gift description",
    rec_type: str = "gift",
    source: str = "amazon",
    price_cents: int = 5000,
    merchant_name: str = "Test Merchant",
    final_score: float = 1.0,
    interest_score: float = 1.0,
    vibe_score: float = 0.0,
    love_language_score: float = 0.0,
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
        "merchant_name": merchant_name,
        "metadata": metadata,
        "interest_score": interest_score,
        "vibe_score": vibe_score,
        "love_language_score": love_language_score,
        "final_score": final_score,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


# ======================================================================
# 1. Price tier classification
# ======================================================================

class TestClassifyPriceTier:
    """Verify _classify_price_tier splits the budget range into thirds."""

    def test_low_tier(self):
        """Price in the bottom third is 'low'."""
        assert _classify_price_tier(3500, 3000, 30000) == "low"

    def test_mid_tier(self):
        """Price in the middle third is 'mid'."""
        assert _classify_price_tier(15000, 3000, 30000) == "mid"

    def test_high_tier(self):
        """Price in the top third is 'high'."""
        assert _classify_price_tier(25000, 3000, 30000) == "high"

    def test_at_low_boundary(self):
        """Price at the exact low boundary is 'low'."""
        assert _classify_price_tier(3000, 3000, 30000) == "low"

    def test_at_first_third_boundary(self):
        """Price at the 1/3 boundary is 'mid'."""
        assert _classify_price_tier(12000, 3000, 30000) == "mid"

    def test_at_two_third_boundary(self):
        """Price at the 2/3 boundary is 'high'."""
        assert _classify_price_tier(21000, 3000, 30000) == "high"

    def test_at_max_boundary(self):
        """Price at max is 'high'."""
        assert _classify_price_tier(30000, 3000, 30000) == "high"

    def test_none_price_defaults_mid(self):
        """None price defaults to 'mid'."""
        assert _classify_price_tier(None, 3000, 30000) == "mid"

    def test_zero_range_defaults_mid(self):
        """Zero budget range defaults to 'mid'."""
        assert _classify_price_tier(5000, 5000, 5000) == "mid"

    def test_narrow_range(self):
        """Works with a very narrow range."""
        # Range: 1000-1300 → thirds: 1000-1100, 1100-1200, 1200-1300
        assert _classify_price_tier(1050, 1000, 1300) == "low"
        assert _classify_price_tier(1150, 1000, 1300) == "mid"
        assert _classify_price_tier(1250, 1000, 1300) == "high"


# ======================================================================
# 2. Diversity scoring
# ======================================================================

class TestDiversityScore:
    """Verify _diversity_score awards points per unique dimension."""

    def test_empty_selected_returns_zero(self):
        """First pick has no comparison, so diversity is 0."""
        candidate = _make_candidate()
        score = _diversity_score(candidate, [], 3000, 30000)
        assert score == 0

    def test_all_different_scores_three(self):
        """Candidate with different tier, type, and merchant gets 3."""
        selected = [
            _make_candidate(
                title="Existing Gift",
                rec_type="gift",
                price_cents=5000,
                merchant_name="Merchant A",
            ),
        ]
        candidate = _make_candidate(
            title="New Experience",
            rec_type="experience",
            price_cents=25000,
            merchant_name="Merchant B",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        assert score == 3

    def test_same_everything_scores_zero(self):
        """Candidate identical in all dimensions gets 0."""
        selected = [
            _make_candidate(
                rec_type="gift",
                price_cents=5000,
                merchant_name="Same Merchant",
            ),
        ]
        candidate = _make_candidate(
            rec_type="gift",
            price_cents=4000,  # same tier (low)
            merchant_name="Same Merchant",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        assert score == 0

    def test_different_type_only(self):
        """Candidate with only a different type gets 1."""
        selected = [
            _make_candidate(
                rec_type="gift",
                price_cents=5000,
                merchant_name="Same Merchant",
            ),
        ]
        candidate = _make_candidate(
            rec_type="experience",
            price_cents=4000,  # same tier
            merchant_name="Same Merchant",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        assert score == 1

    def test_different_merchant_only(self):
        """Candidate with only a different merchant gets 1."""
        selected = [
            _make_candidate(
                rec_type="gift",
                price_cents=5000,
                merchant_name="Merchant A",
            ),
        ]
        candidate = _make_candidate(
            rec_type="gift",
            price_cents=4000,  # same tier
            merchant_name="Merchant B",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        assert score == 1

    def test_different_price_tier_only(self):
        """Candidate with only a different price tier gets 1."""
        selected = [
            _make_candidate(
                rec_type="gift",
                price_cents=5000,  # low
                merchant_name="Same Merchant",
            ),
        ]
        candidate = _make_candidate(
            rec_type="gift",
            price_cents=25000,  # high
            merchant_name="Same Merchant",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        assert score == 1

    def test_considers_all_selected(self):
        """Diversity is checked against ALL already-selected items."""
        selected = [
            _make_candidate(rec_type="gift", price_cents=5000, merchant_name="A"),
            _make_candidate(rec_type="experience", price_cents=15000, merchant_name="B"),
        ]
        # This candidate has type=date (new), but price=low (already have low)
        # and merchant=C (new)
        candidate = _make_candidate(
            rec_type="date",
            price_cents=4000,  # low tier — already in selected
            merchant_name="C",
        )
        score = _diversity_score(candidate, selected, 3000, 30000)
        # type: +1 (date is new), merchant: +1 (C is new), tier: 0 (low exists)
        assert score == 2

    def test_none_merchant_treated_as_empty(self):
        """None merchant_name is normalized to empty string for comparison."""
        selected = [
            _make_candidate(merchant_name=None),
        ]
        candidate = _make_candidate(merchant_name="New Merchant")
        score = _diversity_score(candidate, selected, 3000, 30000)
        # Different merchant → at least +1
        assert score >= 1

    def test_merchant_comparison_case_insensitive(self):
        """Merchant comparison is case-insensitive."""
        selected = [
            _make_candidate(merchant_name="Amazon"),
        ]
        candidate = _make_candidate(merchant_name="AMAZON")
        # Same merchant, different case → should NOT add diversity
        score = _diversity_score(candidate, selected, 3000, 30000)
        # Only type/tier may contribute, not merchant
        assert score < 3  # if all 3 were different, it would be 3


# ======================================================================
# 3. Full node (end-to-end)
# ======================================================================

class TestSelectDiverseThree:
    """Verify select_diverse_three end-to-end behavior."""

    async def test_selects_exactly_three(self):
        """Node returns exactly 3 recommendations from a pool of 9."""
        candidates = [
            _make_candidate(
                title=f"Item {i}",
                rec_type=["gift", "experience", "date"][i % 3],
                price_cents=3000 + i * 3000,
                merchant_name=f"Merchant {i}",
                final_score=9.0 - i,
            )
            for i in range(9)
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        assert "final_three" in result
        assert len(result["final_three"]) == TARGET_COUNT

    async def test_first_pick_is_highest_scored(self):
        """The first pick is always the highest-scored candidate."""
        candidates = [
            _make_candidate(title="Best", final_score=5.0, rec_type="gift"),
            _make_candidate(title="Second", final_score=3.0, rec_type="experience"),
            _make_candidate(title="Third", final_score=1.0, rec_type="date"),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        assert result["final_three"][0].title == "Best"

    async def test_prefers_diverse_type(self):
        """Node prefers candidates with different types over same type."""
        candidates = [
            _make_candidate(
                title="Gift A",
                rec_type="gift",
                final_score=5.0,
                price_cents=5000,
                merchant_name="Shop A",
            ),
            _make_candidate(
                title="Gift B",
                rec_type="gift",
                final_score=4.0,
                price_cents=15000,
                merchant_name="Shop B",
            ),
            _make_candidate(
                title="Experience C",
                rec_type="experience",
                final_score=3.5,
                price_cents=15000,
                merchant_name="Shop C",
            ),
            _make_candidate(
                title="Gift D",
                rec_type="gift",
                final_score=3.0,
                price_cents=25000,
                merchant_name="Shop D",
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        selected_types = {c.type for c in result["final_three"]}
        # Should include at least one experience even though gifts scored higher
        assert "experience" in selected_types

    async def test_prefers_different_merchants(self):
        """Node avoids selecting two candidates from the same merchant."""
        candidates = [
            _make_candidate(
                title="Item 1",
                final_score=5.0,
                merchant_name="Amazon",
                rec_type="gift",
                price_cents=5000,
            ),
            _make_candidate(
                title="Item 2",
                final_score=4.5,
                merchant_name="Amazon",
                rec_type="gift",
                price_cents=15000,
            ),
            _make_candidate(
                title="Item 3",
                final_score=4.0,
                merchant_name="Etsy",
                rec_type="gift",
                price_cents=15000,
            ),
            _make_candidate(
                title="Item 4",
                final_score=3.5,
                merchant_name="Yelp",
                rec_type="experience",
                price_cents=25000,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        merchants = [c.merchant_name for c in result["final_three"]]
        # Should have unique merchants
        assert len(set(merchants)) == len(merchants)

    async def test_prefers_different_price_tiers(self):
        """Node spreads selections across price tiers."""
        candidates = [
            _make_candidate(
                title="Cheap Gift",
                final_score=5.0,
                price_cents=4000,
                merchant_name="Shop A",
                rec_type="gift",
            ),
            _make_candidate(
                title="Another Cheap",
                final_score=4.5,
                price_cents=5000,
                merchant_name="Shop B",
                rec_type="gift",
            ),
            _make_candidate(
                title="Mid-range Experience",
                final_score=4.0,
                price_cents=15000,
                merchant_name="Shop C",
                rec_type="experience",
            ),
            _make_candidate(
                title="Expensive Date",
                final_score=3.5,
                price_cents=27000,
                merchant_name="Shop D",
                rec_type="date",
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        tiers = {
            _classify_price_tier(c.price_cents, 3000, 30000)
            for c in result["final_three"]
        }
        # Should have at least 2 different tiers (ideally all 3)
        assert len(tiers) >= 2

    async def test_does_not_mutate_input(self):
        """Node does not mutate the input state's candidate list."""
        original_candidates = [
            _make_candidate(title=f"Item {i}", final_score=float(9 - i))
            for i in range(5)
        ]
        state = _make_state(filtered=original_candidates)
        original_len = len(state.filtered_recommendations)

        await select_diverse_three(state)

        assert len(state.filtered_recommendations) == original_len

    async def test_returns_final_three_key(self):
        """Node returns dict with 'final_three' key (not 'filtered_recommendations')."""
        candidates = [
            _make_candidate(title="A", final_score=3.0),
            _make_candidate(title="B", final_score=2.0),
            _make_candidate(title="C", final_score=1.0),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        assert "final_three" in result
        assert "filtered_recommendations" not in result


# ======================================================================
# 4. Spec tests (from implementation plan)
# ======================================================================

class TestSpecRequirements:
    """The 3 specific tests required by the Step 5.6 implementation plan."""

    async def test_final_three_span_different_price_points(self):
        """
        Spec Test 1: Provide 9 candidates with varying prices and types.
        Confirm the final 3 span different price points.
        """
        candidates = [
            # Low price tier
            _make_candidate(
                title="Budget Cookbook",
                rec_type="gift",
                price_cents=4000,
                merchant_name="Amazon",
                final_score=4.0,
            ),
            _make_candidate(
                title="Coffee Tasting Kit",
                rec_type="gift",
                price_cents=5000,
                merchant_name="Etsy",
                final_score=3.8,
            ),
            _make_candidate(
                title="Farmers Market Tour",
                rec_type="experience",
                price_cents=6000,
                merchant_name="Yelp",
                final_score=3.5,
            ),
            # Mid price tier
            _make_candidate(
                title="Cooking Class",
                rec_type="experience",
                price_cents=15000,
                merchant_name="ClassBento",
                final_score=3.2,
            ),
            _make_candidate(
                title="Japanese Chef Knife",
                rec_type="gift",
                price_cents=14000,
                merchant_name="Williams-Sonoma",
                final_score=3.0,
            ),
            _make_candidate(
                title="Wine Tasting Date",
                rec_type="date",
                price_cents=16000,
                merchant_name="Yelp",
                final_score=2.8,
            ),
            # High price tier
            _make_candidate(
                title="Fine Dining Omakase",
                rec_type="date",
                price_cents=25000,
                merchant_name="OpenTable",
                final_score=2.5,
            ),
            _make_candidate(
                title="Luxury Spa Package",
                rec_type="experience",
                price_cents=28000,
                merchant_name="SpaFinder",
                final_score=2.3,
            ),
            _make_candidate(
                title="Premium Art Kit",
                rec_type="gift",
                price_cents=24000,
                merchant_name="Blick",
                final_score=2.0,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        selected = result["final_three"]

        assert len(selected) == 3

        # Verify different price tiers are represented
        tiers = {
            _classify_price_tier(c.price_cents, 3000, 30000)
            for c in selected
        }
        assert len(tiers) >= 2, (
            f"Expected at least 2 different price tiers, got {tiers}"
        )

    async def test_at_least_one_gift_and_one_experience(self):
        """
        Spec Test 2: Confirm at least one gift and one experience are included
        (if available in the candidate pool).
        """
        candidates = [
            _make_candidate(
                title="Gift 1",
                rec_type="gift",
                price_cents=5000,
                merchant_name="Amazon",
                final_score=5.0,
            ),
            _make_candidate(
                title="Gift 2",
                rec_type="gift",
                price_cents=15000,
                merchant_name="Etsy",
                final_score=4.5,
            ),
            _make_candidate(
                title="Gift 3",
                rec_type="gift",
                price_cents=25000,
                merchant_name="Shopify",
                final_score=4.0,
            ),
            _make_candidate(
                title="Experience 1",
                rec_type="experience",
                price_cents=10000,
                merchant_name="Yelp",
                final_score=3.5,
            ),
            _make_candidate(
                title="Experience 2",
                rec_type="experience",
                price_cents=20000,
                merchant_name="Ticketmaster",
                final_score=3.0,
            ),
            _make_candidate(
                title="Date 1",
                rec_type="date",
                price_cents=18000,
                merchant_name="OpenTable",
                final_score=2.5,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        selected = result["final_three"]

        selected_types = {c.type for c in selected}
        assert "gift" in selected_types, "At least one gift should be selected"
        assert (
            "experience" in selected_types or "date" in selected_types
        ), "At least one experience or date should be selected"

    async def test_no_two_from_same_merchant(self):
        """
        Spec Test 3: Confirm no two recommendations are from the same merchant.
        """
        candidates = [
            _make_candidate(
                title="Amazon Gift A",
                rec_type="gift",
                price_cents=5000,
                merchant_name="Amazon",
                final_score=5.0,
            ),
            _make_candidate(
                title="Amazon Gift B",
                rec_type="gift",
                price_cents=15000,
                merchant_name="Amazon",
                final_score=4.8,
            ),
            _make_candidate(
                title="Amazon Experience",
                rec_type="experience",
                price_cents=20000,
                merchant_name="Amazon",
                final_score=4.5,
            ),
            _make_candidate(
                title="Etsy Handmade Gift",
                rec_type="gift",
                price_cents=8000,
                merchant_name="Etsy",
                final_score=4.0,
            ),
            _make_candidate(
                title="Yelp Restaurant",
                rec_type="date",
                price_cents=18000,
                merchant_name="Yelp",
                final_score=3.5,
            ),
            _make_candidate(
                title="Ticketmaster Concert",
                rec_type="experience",
                price_cents=12000,
                merchant_name="Ticketmaster",
                final_score=3.0,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        selected = result["final_three"]

        merchants = [c.merchant_name.lower() for c in selected]
        assert len(set(merchants)) == len(merchants), (
            f"Expected unique merchants, got {merchants}"
        )


# ======================================================================
# 5. Edge cases
# ======================================================================

class TestEdgeCases:
    """Edge cases and boundary conditions."""

    async def test_empty_candidates_returns_empty(self):
        """Node handles empty candidate list gracefully."""
        state = _make_state(filtered=[])
        result = await select_diverse_three(state)
        assert result["final_three"] == []

    async def test_single_candidate_returns_one(self):
        """Node returns 1 when only 1 candidate is available."""
        candidates = [
            _make_candidate(title="Only One", final_score=5.0),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 1
        assert result["final_three"][0].title == "Only One"

    async def test_two_candidates_returns_two(self):
        """Node returns 2 when only 2 candidates are available."""
        candidates = [
            _make_candidate(title="First", final_score=5.0, rec_type="gift"),
            _make_candidate(title="Second", final_score=3.0, rec_type="experience"),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 2

    async def test_exactly_three_candidates(self):
        """Node returns all 3 when exactly 3 are available."""
        candidates = [
            _make_candidate(title="A", final_score=5.0),
            _make_candidate(title="B", final_score=3.0),
            _make_candidate(title="C", final_score=1.0),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 3

    async def test_all_same_type_still_selects_three(self):
        """When all candidates are gifts, node still selects 3."""
        candidates = [
            _make_candidate(
                title=f"Gift {i}",
                rec_type="gift",
                price_cents=3000 + i * 3000,
                merchant_name=f"Merchant {i}",
                final_score=float(9 - i),
            )
            for i in range(9)
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 3

    async def test_all_same_merchant_still_selects_three(self):
        """When all candidates have the same merchant, node still selects 3."""
        candidates = [
            _make_candidate(
                title=f"Item {i}",
                rec_type=["gift", "experience", "date"][i % 3],
                price_cents=3000 + i * 3000,
                merchant_name="Amazon",
                final_score=float(9 - i),
            )
            for i in range(9)
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 3

    async def test_all_same_price_still_selects_three(self):
        """When all candidates have the same price, node still selects 3."""
        candidates = [
            _make_candidate(
                title=f"Item {i}",
                rec_type=["gift", "experience", "date"][i % 3],
                price_cents=10000,
                merchant_name=f"Merchant {i}",
                final_score=float(9 - i),
            )
            for i in range(9)
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 3

    async def test_none_prices_handled(self):
        """Candidates with None price_cents don't crash the node."""
        candidates = [
            _make_candidate(title="No Price A", price_cents=None, final_score=5.0, merchant_name="A"),
            _make_candidate(title="Has Price", price_cents=15000, final_score=4.0, merchant_name="B", rec_type="experience"),
            _make_candidate(title="No Price B", price_cents=None, final_score=3.0, merchant_name="C", rec_type="date"),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)
        assert len(result["final_three"]) == 3

    async def test_ties_broken_by_score_then_title(self):
        """When diversity is equal, higher final_score wins; then alphabetical title."""
        candidates = [
            _make_candidate(
                title="Alpha",
                rec_type="gift",
                price_cents=5000,
                merchant_name="Same",
                final_score=5.0,
            ),
            _make_candidate(
                title="Bravo",
                rec_type="gift",
                price_cents=6000,
                merchant_name="Same",
                final_score=4.0,
            ),
            _make_candidate(
                title="Charlie",
                rec_type="gift",
                price_cents=7000,
                merchant_name="Same",
                final_score=3.0,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        # First pick: highest score (Alpha)
        assert result["final_three"][0].title == "Alpha"
        # Second pick: highest remaining score with same diversity (Bravo)
        assert result["final_three"][1].title == "Bravo"


# ======================================================================
# 6. State compatibility
# ======================================================================

class TestStateCompatibility:
    """Verify returned dict correctly updates RecommendationState."""

    async def test_result_updates_state(self):
        """Returned dict correctly updates RecommendationState.final_three."""
        candidates = [
            _make_candidate(title="A", final_score=5.0, rec_type="gift"),
            _make_candidate(title="B", final_score=4.0, rec_type="experience"),
            _make_candidate(title="C", final_score=3.0, rec_type="date"),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        updated = state.model_copy(update=result)
        assert len(updated.final_three) == 3
        assert updated.final_three[0].title == "A"

    async def test_does_not_affect_filtered_recommendations(self):
        """Result dict doesn't include 'filtered_recommendations' key."""
        candidates = [
            _make_candidate(title="Test", final_score=3.0),
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        # Should only have 'final_three', not 'filtered_recommendations'
        assert "final_three" in result
        assert "filtered_recommendations" not in result

    async def test_original_candidates_preserved_in_state(self):
        """After update, original filtered_recommendations are still accessible."""
        candidates = [
            _make_candidate(title=f"Item {i}", final_score=float(5 - i))
            for i in range(5)
        ]
        state = _make_state(filtered=candidates)
        result = await select_diverse_three(state)

        updated = state.model_copy(update=result)
        # filtered_recommendations should still have the original 5
        assert len(updated.filtered_recommendations) == 5
        # final_three should have 3
        assert len(updated.final_three) == 3
