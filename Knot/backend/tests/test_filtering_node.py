"""
Step 5.4 Verification: Semantic Filtering Node

Tests that the filter_by_interests LangGraph node:
1. Removes candidates matching disliked categories
2. Scores remaining candidates by interest alignment
3. Ranks by interest_score (descending)
4. Returns the top 9 candidates
5. Handles edge cases (empty input, all filtered, no matches)
6. Returns result compatible with RecommendationState update

Test categories:
- Category matching: Verify _matches_category helper detects metadata, title, description
- Scoring: Verify _score_candidate computes correct scores for interests and dislikes
- Dislike removal: Verify candidates matching dislikes are filtered out
- Interest ranking: Verify candidates matching interests rank higher
- Top 9 limit: Verify at most 9 candidates are returned
- Full node: Verify filter_by_interests end-to-end behavior
- Edge cases: Empty candidates, all filtered, no interest matches
- State compatibility: Verify returned dict updates RecommendationState correctly

Prerequisites:
- Complete Steps 5.1-5.3 (state schema, hint retrieval, aggregation node)

Run with: pytest tests/test_filtering_node.py -v
"""

import uuid

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.filtering import (
    MAX_FILTERED_CANDIDATES,
    _matches_category,
    _normalize,
    _score_candidate,
    filter_by_interests,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-filter-test",
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
        "secondary_love_language": "acts_of_service",
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
        "id": "milestone-filter-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(candidates=None, **overrides) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=2000, max_amount=30000),
    }
    defaults.update(overrides)
    state = RecommendationState(**defaults)
    if candidates is not None:
        state = state.model_copy(update={"candidate_recommendations": candidates})
    return state


def _make_candidate(
    title: str = "Test Gift",
    description: str = "A test gift description",
    rec_type: str = "gift",
    source: str = "amazon",
    price_cents: int = 5000,
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
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


# ======================================================================
# 1. Normalize helper
# ======================================================================

class TestNormalize:
    """Verify the _normalize helper."""

    def test_lowercase(self):
        assert _normalize("Gaming") == "gaming"

    def test_strip_whitespace(self):
        assert _normalize("  Cooking  ") == "cooking"

    def test_already_lowercase(self):
        assert _normalize("hiking") == "hiking"


# ======================================================================
# 2. Category matching
# ======================================================================

class TestMatchesCategory:
    """Verify _matches_category detects metadata, title, and description."""

    def test_matches_via_metadata_interest(self):
        """Metadata matched_interest is the strongest signal."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        assert _matches_category(candidate, "Cooking") is True

    def test_matches_via_metadata_case_insensitive(self):
        """Metadata matching is case-insensitive."""
        candidate = _make_candidate(
            title="Some Gift",
            matched_interest="cooking",
        )
        assert _matches_category(candidate, "Cooking") is True

    def test_matches_via_title_keyword(self):
        """Title keyword matching catches direct mentions."""
        candidate = _make_candidate(
            title="Hiking Boots",
            description="Great for trails",
        )
        assert _matches_category(candidate, "Hiking") is True

    def test_matches_via_description_keyword(self):
        """Description keyword matching catches mentions in the body."""
        candidate = _make_candidate(
            title="Trail Adventure Set",
            description="Perfect for hiking and outdoor adventures",
        )
        assert _matches_category(candidate, "Hiking") is True

    def test_no_match_when_unrelated(self):
        """Candidate with no relation to category returns False."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            description="Premium audio quality",
            matched_interest="Music",
        )
        assert _matches_category(candidate, "Gaming") is False

    def test_no_match_with_empty_metadata(self):
        """Candidate without matched_interest metadata doesn't match via metadata."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            description="Premium audio quality",
        )
        assert _matches_category(candidate, "Cooking") is False

    def test_matches_via_title_case_insensitive(self):
        """Title matching is case-insensitive."""
        candidate = _make_candidate(title="GAMING KEYBOARD")
        assert _matches_category(candidate, "gaming") is True

    def test_no_match_with_none_description(self):
        """Handles None description gracefully."""
        candidate = _make_candidate(
            title="Wireless Speaker",
            description=None,
        )
        # description=None should not crash
        assert _matches_category(candidate, "Cooking") is False

    def test_partial_word_match_in_title(self):
        """Substring matching catches partial words (e.g., 'gaming' in 'gaming')."""
        candidate = _make_candidate(title="Top Gaming Gear 2026")
        assert _matches_category(candidate, "Gaming") is True

    def test_metadata_vibe_does_not_match_interest(self):
        """matched_vibe in metadata does NOT count as an interest match."""
        candidate = _make_candidate(
            title="Spa Day",
            matched_vibe="quiet_luxury",
        )
        assert _matches_category(candidate, "quiet_luxury") is False


# ======================================================================
# 3. Scoring
# ======================================================================

class TestScoreCandidate:
    """Verify _score_candidate computes correct scores."""

    def test_dislike_match_returns_negative(self):
        """A candidate matching a dislike gets -1.0."""
        candidate = _make_candidate(
            title="Gaming Keyboard",
            matched_interest="Gaming",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        assert score == -1.0

    def test_interest_match_returns_positive(self):
        """A candidate matching an interest gets a positive score."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        assert score > 0

    def test_metadata_interest_gets_bonus(self):
        """Metadata-tagged interest match gets base + bonus."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            matched_interest="Cooking",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        # 1.0 (interest match via metadata) + 0.5 (metadata bonus)
        assert score == 1.5

    def test_no_match_returns_zero(self):
        """A candidate matching neither interest nor dislike gets 0.0."""
        candidate = _make_candidate(
            title="Generic Gift",
            description="A nice item",
            matched_interest="Reading",  # not in interests or dislikes
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        assert score == 0.0

    def test_multiple_interest_matches(self):
        """Candidate matching multiple interests accumulates higher score."""
        candidate = _make_candidate(
            title="Travel Cooking Kit",
            description="Cook while you travel with this hiking set",
            matched_interest="Cooking",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        # Cooking (metadata=1.0 + title=already counted), Travel (title=1.0),
        # Hiking (description=1.0), metadata bonus=0.5
        assert score >= 2.5

    def test_dislike_takes_priority_over_interest(self):
        """If a candidate matches BOTH an interest and a dislike, it is removed."""
        candidate = _make_candidate(
            title="Cooking and Gaming Bundle",
            description="For the cooking gamer",
            matched_interest="Cooking",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking"],
            dislikes=["Gaming"],
        )
        # Gaming in title means dislike match → -1.0
        assert score == -1.0

    def test_experience_without_interest_metadata_gets_zero(self):
        """Experience candidates (matched_vibe only) get 0.0 from interest scoring."""
        candidate = _make_candidate(
            title="Spa Day for Two",
            description="Couples massage package",
            rec_type="experience",
            source="yelp",
            matched_vibe="quiet_luxury",
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        )
        assert score == 0.0

    def test_title_only_interest_match_no_metadata_bonus(self):
        """Title-only match without metadata gets 1.0 (no bonus)."""
        candidate = _make_candidate(
            title="Cooking Masterclass",
            description="Learn to cook from experts",
            # no matched_interest metadata
        )
        score = _score_candidate(
            candidate,
            interests=["Cooking"],
            dislikes=["Gaming"],
        )
        # 1.0 (title match) + 0.0 (no metadata bonus since matched_interest not set)
        assert score == 1.0


# ======================================================================
# 4. Full node — dislike removal
# ======================================================================

class TestDislikeRemoval:
    """Verify candidates matching dislikes are filtered out."""

    async def test_removes_candidate_matching_dislike_metadata(self):
        """Candidate with matched_interest in dislikes is removed."""
        gaming_gift = _make_candidate(
            title="Gaming Keyboard",
            matched_interest="Gaming",
        )
        cooking_gift = _make_candidate(
            title="Chef Knife",
            matched_interest="Cooking",
        )
        state = _make_state(candidates=[gaming_gift, cooking_gift])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        titles = [c.title for c in filtered]
        assert "Gaming Keyboard" not in titles
        assert "Chef Knife" in titles

    async def test_removes_candidate_matching_dislike_in_title(self):
        """Candidate with dislike keyword in title is removed."""
        skiing_gift = _make_candidate(
            title="Heated Skiing Gloves",
            matched_interest="Skiing",
        )
        travel_gift = _make_candidate(
            title="Passport Holder",
            matched_interest="Travel",
        )
        state = _make_state(candidates=[skiing_gift, travel_gift])

        result = await filter_by_interests(state)
        titles = [c.title for c in result["filtered_recommendations"]]
        assert "Heated Skiing Gloves" not in titles
        assert "Passport Holder" in titles

    async def test_removes_multiple_disliked_candidates(self):
        """Multiple disliked candidates are all removed."""
        candidates = [
            _make_candidate(title="Gaming Setup", matched_interest="Gaming"),
            _make_candidate(title="Car Detailing Kit", matched_interest="Cars"),
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Karaoke Machine", matched_interest="Karaoke"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert len(filtered) == 1
        assert filtered[0].title == "Chef Knife"

    async def test_experience_matching_dislike_is_removed(self):
        """Experience candidate with dislike in description is removed."""
        surfing_exp = _make_candidate(
            title="Surfing Lesson Package",
            description="Learn to surf at the beach",
            rec_type="experience",
            source="yelp",
            matched_vibe="adventurous",
        )
        spa_exp = _make_candidate(
            title="Spa Day for Two",
            description="Couples massage package",
            rec_type="experience",
            source="yelp",
            matched_vibe="quiet_luxury",
        )
        state = _make_state(candidates=[surfing_exp, spa_exp])

        result = await filter_by_interests(state)
        titles = [c.title for c in result["filtered_recommendations"]]
        assert "Surfing Lesson Package" not in titles
        assert "Spa Day for Two" in titles


# ======================================================================
# 5. Full node — interest ranking
# ======================================================================

class TestInterestRanking:
    """Verify candidates matching interests rank higher."""

    async def test_interest_match_ranks_above_no_match(self):
        """Candidate matching an interest ranks above one with no match."""
        cooking_gift = _make_candidate(
            title="Chef Knife",
            matched_interest="Cooking",
        )
        generic_exp = _make_candidate(
            title="Spa Day for Two",
            description="Couples massage",
            rec_type="experience",
            source="yelp",
            matched_vibe="quiet_luxury",
        )
        state = _make_state(candidates=[generic_exp, cooking_gift])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # Cooking match should rank first
        assert filtered[0].title == "Chef Knife"
        assert filtered[0].interest_score > filtered[1].interest_score

    async def test_multiple_interest_matches_rank_highest(self):
        """Candidate matching multiple interests ranks above single match."""
        multi_match = _make_candidate(
            title="Travel Cooking Guide",
            description="Cook during your hiking adventures",
            matched_interest="Cooking",
        )
        single_match = _make_candidate(
            title="Concert Tickets",
            matched_interest="Music",
        )
        state = _make_state(candidates=[single_match, multi_match])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert filtered[0].title == "Travel Cooking Guide"
        assert filtered[0].interest_score > filtered[1].interest_score

    async def test_interest_score_populated_on_all_filtered(self):
        """All returned candidates have interest_score set."""
        candidates = [
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Passport Holder", matched_interest="Travel"),
            _make_candidate(title="Spa Day", rec_type="experience", matched_vibe="romantic"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        for c in result["filtered_recommendations"]:
            assert isinstance(c.interest_score, float)


# ======================================================================
# 6. Top 9 limit
# ======================================================================

class TestTop9Limit:
    """Verify at most MAX_FILTERED_CANDIDATES (9) are returned."""

    async def test_returns_at_most_9_candidates(self):
        """When more than 9 survive filtering, only top 9 are returned."""
        candidates = [
            _make_candidate(
                title=f"Gift {i}",
                matched_interest="Cooking" if i < 5 else None,
            )
            for i in range(15)
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert len(filtered) <= MAX_FILTERED_CANDIDATES
        assert len(filtered) == 9

    async def test_fewer_than_9_returned_when_few_survive(self):
        """When fewer than 9 survive filtering, return all survivors."""
        candidates = [
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Gaming Keyboard", matched_interest="Gaming"),  # dislike
            _make_candidate(title="Spa Day", rec_type="experience", matched_vibe="romantic"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert len(filtered) == 2  # Gaming removed, 2 survive

    async def test_highest_scored_are_kept(self):
        """The top 9 by interest_score are retained, not arbitrary 9."""
        # Create 12 candidates: 5 with interest match (high score), 7 neutral
        candidates = []
        for i in range(5):
            candidates.append(_make_candidate(
                title=f"Interest Gift {i}",
                matched_interest="Cooking",
            ))
        for i in range(7):
            candidates.append(_make_candidate(
                title=f"Neutral Gift {i}",
                rec_type="experience",
                source="yelp",
                matched_vibe="romantic",
            ))

        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # All 5 interest-matched should be in the result
        interest_titles = [c.title for c in filtered if c.interest_score > 0]
        assert len(interest_titles) == 5


# ======================================================================
# 7. Full node end-to-end
# ======================================================================

class TestFullNode:
    """Verify filter_by_interests end-to-end behavior."""

    async def test_returns_filtered_recommendations_key(self):
        """Result dict contains 'filtered_recommendations' key."""
        state = _make_state(candidates=[
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
        ])

        result = await filter_by_interests(state)
        assert "filtered_recommendations" in result

    async def test_candidates_are_candidate_recommendation_type(self):
        """All returned items are CandidateRecommendation instances."""
        state = _make_state(candidates=[
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Spa Day", rec_type="experience", matched_vibe="romantic"),
        ])

        result = await filter_by_interests(state)
        for c in result["filtered_recommendations"]:
            assert isinstance(c, CandidateRecommendation)

    async def test_state_update_compatible(self):
        """Result can be used to update RecommendationState."""
        state = _make_state(candidates=[
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
        ])

        result = await filter_by_interests(state)

        updated = state.model_copy(update=result)
        assert len(updated.filtered_recommendations) == 1
        assert updated.filtered_recommendations[0].title == "Chef Knife"

    async def test_preserves_candidate_fields(self):
        """Filtered candidates retain all original fields."""
        original = _make_candidate(
            title="Japanese Chef Knife",
            description="Professional VG-10 steel",
            price_cents=8900,
            matched_interest="Cooking",
            source="amazon",
        )
        state = _make_state(candidates=[original])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"][0]

        assert filtered.title == "Japanese Chef Knife"
        assert filtered.description == "Professional VG-10 steel"
        assert filtered.price_cents == 8900
        assert filtered.source == "amazon"
        assert filtered.type == "gift"
        assert filtered.external_url == original.external_url
        assert filtered.image_url == original.image_url
        assert filtered.merchant_name == original.merchant_name

    async def test_mixed_gifts_and_experiences(self):
        """Both gifts and experiences survive filtering correctly."""
        candidates = [
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Spa Day", rec_type="experience", source="yelp", matched_vibe="romantic"),
            _make_candidate(title="Gaming Setup", matched_interest="Gaming"),  # dislike
            _make_candidate(title="Concert Tickets", rec_type="experience", source="ticketmaster", matched_vibe="bohemian"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert len(filtered) == 3
        types = {c.type for c in filtered}
        assert "gift" in types
        assert "experience" in types

    async def test_no_error_on_normal_run(self):
        """No error key when candidates survive."""
        state = _make_state(candidates=[
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
        ])

        result = await filter_by_interests(state)
        assert "error" not in result

    async def test_unique_ids_preserved(self):
        """Each filtered candidate retains its unique ID."""
        c1 = _make_candidate(title="Gift A", matched_interest="Cooking")
        c2 = _make_candidate(title="Gift B", matched_interest="Travel")
        state = _make_state(candidates=[c1, c2])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        ids = [c.id for c in filtered]
        assert len(set(ids)) == len(ids)  # all unique


# ======================================================================
# 8. Edge cases
# ======================================================================

class TestEdgeCases:
    """Verify edge case handling."""

    async def test_empty_candidates_returns_empty(self):
        """Empty candidate list returns empty filtered list."""
        state = _make_state(candidates=[])

        result = await filter_by_interests(state)
        assert result["filtered_recommendations"] == []

    async def test_all_candidates_filtered_sets_error(self):
        """When all candidates match dislikes, error is set."""
        candidates = [
            _make_candidate(title="Gaming Keyboard", matched_interest="Gaming"),
            _make_candidate(title="Car Kit", matched_interest="Cars"),
            _make_candidate(title="Ski Goggles", matched_interest="Skiing"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        assert result["filtered_recommendations"] == []
        assert "error" in result
        assert "try adjusting" in result["error"].lower()

    async def test_no_interest_match_candidates_still_kept(self):
        """Candidates that don't match any interest (score=0) are kept, not removed."""
        candidate = _make_candidate(
            title="Spa Day",
            description="Couples massage",
            rec_type="experience",
            source="yelp",
            matched_vibe="romantic",
        )
        state = _make_state(candidates=[candidate])

        result = await filter_by_interests(state)
        assert len(result["filtered_recommendations"]) == 1
        assert result["filtered_recommendations"][0].interest_score == 0.0

    async def test_single_candidate_survives(self):
        """A single non-disliked candidate is returned."""
        candidate = _make_candidate(
            title="Chef Knife",
            matched_interest="Cooking",
        )
        state = _make_state(candidates=[candidate])

        result = await filter_by_interests(state)
        assert len(result["filtered_recommendations"]) == 1

    async def test_candidate_with_dislike_in_description_only(self):
        """Dislike keyword found only in description is still filtered."""
        candidate = _make_candidate(
            title="Multi-Sport Package",
            description="Includes skiing, swimming, and surfing activities",
            rec_type="experience",
            source="yelp",
        )
        state = _make_state(candidates=candidate and [candidate])

        result = await filter_by_interests(state)
        # "skiing" and "surfing" are both dislikes — should be removed
        assert len(result["filtered_recommendations"]) == 0

    async def test_deterministic_ordering_for_same_score(self):
        """Candidates with the same score are ordered deterministically by title."""
        c1 = _make_candidate(title="Zebra Gift", matched_interest="Cooking")
        c2 = _make_candidate(title="Alpha Gift", matched_interest="Travel")
        state = _make_state(candidates=[c1, c2])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # Both have same interest_score (1.5 each: 1.0 match + 0.5 bonus)
        # Should be sorted by title alphabetically
        assert filtered[0].title == "Alpha Gift"
        assert filtered[1].title == "Zebra Gift"

    async def test_max_filtered_candidates_constant_is_9(self):
        """MAX_FILTERED_CANDIDATES is 9 as specified in the plan."""
        assert MAX_FILTERED_CANDIDATES == 9


# ======================================================================
# 9. Integration with aggregation node output
# ======================================================================

class TestAggregationIntegration:
    """Verify filtering works with realistic aggregation node output."""

    async def test_filters_realistic_candidate_mix(self):
        """Realistic mix of stub catalog candidates is properly filtered."""
        # Simulate output from aggregate_external_data
        candidates = [
            # Gifts matching interests (should keep)
            _make_candidate(title="Japanese Chef Knife", description="Professional 8-inch VG-10 steel chef knife", price_cents=8900, matched_interest="Cooking"),
            _make_candidate(title="Premium Leather Passport Holder", description="Handcrafted genuine leather passport cover", price_cents=4500, matched_interest="Travel"),
            _make_candidate(title="Vinyl Record Player", description="Bluetooth turntable with built-in speakers", price_cents=7900, matched_interest="Music"),
            # Gifts matching dislikes (should remove)
            _make_candidate(title="Mechanical Gaming Keyboard", description="RGB mechanical keyboard with Cherry MX switches", price_cents=12900, matched_interest="Gaming"),
            _make_candidate(title="Professional Detailing Kit", description="Car detailing kit with ceramic coating spray", price_cents=7500, matched_interest="Cars"),
            # Experiences (neutral — no interest match)
            _make_candidate(title="Spa Day for Two", description="Couples massage and full spa treatment package", price_cents=18000, rec_type="experience", source="yelp", matched_vibe="quiet_luxury"),
            _make_candidate(title="Candlelit Cooking Class", description="Italian cooking class with wine pairing for two", price_cents=14000, rec_type="date", source="yelp", matched_vibe="romantic"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        # 2 disliked removed, 5 survive
        assert len(filtered) == 5

        # Disliked should not be present
        titles = [c.title for c in filtered]
        assert "Mechanical Gaming Keyboard" not in titles
        assert "Professional Detailing Kit" not in titles

        # Interest-matched should be present and ranked higher
        assert "Japanese Chef Knife" in titles
        assert "Premium Leather Passport Holder" in titles
        assert "Vinyl Record Player" in titles

        # Cooking class has "cooking" in title → should get interest boost
        cooking_class = next(c for c in filtered if "Cooking Class" in c.title)
        assert cooking_class.interest_score > 0

    async def test_interest_in_experience_title_gets_boosted(self):
        """Experience with interest keyword in title gets interest score."""
        # "Cooking" is an interest, and "Candlelit Cooking Class" has it in the title
        candidate = _make_candidate(
            title="Candlelit Cooking Class",
            description="Italian cooking class for two",
            rec_type="date",
            source="yelp",
            matched_vibe="romantic",
        )
        state = _make_state(candidates=[candidate])

        result = await filter_by_interests(state)
        filtered = result["filtered_recommendations"]

        assert len(filtered) == 1
        assert filtered[0].interest_score > 0

    async def test_json_round_trip(self):
        """Result survives JSON serialization via Pydantic."""
        candidates = [
            _make_candidate(title="Chef Knife", matched_interest="Cooking"),
            _make_candidate(title="Spa Day", rec_type="experience", matched_vibe="romantic"),
        ]
        state = _make_state(candidates=candidates)

        result = await filter_by_interests(state)
        updated_state = state.model_copy(update=result)

        # Serialize and deserialize
        json_str = updated_state.model_dump_json()
        restored = RecommendationState.model_validate_json(json_str)

        assert len(restored.filtered_recommendations) == 2
        assert restored.filtered_recommendations[0].title == "Chef Knife"
