"""
Step 5.3 Verification: External API Aggregation Node

Tests that the aggregate_external_data LangGraph node:
1. Returns candidate recommendations with required fields
2. Generates candidates matching vault interests (gifts)
3. Generates candidates matching vault vibes (experiences/dates)
4. Filters candidates by budget range
5. Handles edge cases (missing location, empty results, partial failures)
6. Returns result compatible with RecommendationState update

Test categories:
- Stub catalog coverage: Verify all 40 interests and 8 vibes have entries
- Candidate construction: Verify gift and experience candidate helpers
- Budget filtering: Verify candidates outside budget are excluded
- Full node: Verify aggregate_external_data end-to-end behavior
- Edge cases: Empty interests, restrictive budgets, partial failures

Prerequisites:
- Complete Steps 5.1-5.2 (state schema and hint retrieval node)

Run with: pytest tests/test_aggregation_node.py -v
"""

import uuid

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    LocationData,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.aggregation import (
    _INTEREST_GIFTS,
    _VIBE_EXPERIENCES,
    _build_gift_candidate,
    _build_experience_candidate,
    _fetch_gift_candidates,
    _fetch_experience_candidates,
    aggregate_external_data,
    TARGET_CANDIDATE_COUNT,
)


# ======================================================================
# Valid interest and vibe constants (from Constants.swift / vault.py)
# ======================================================================

ALL_INTERESTS = [
    "Travel", "Cooking", "Movies", "Music", "Reading", "Sports", "Gaming",
    "Art", "Photography", "Fitness", "Fashion", "Technology", "Nature",
    "Food", "Coffee", "Wine", "Dancing", "Theater", "Concerts", "Museums",
    "Shopping", "Yoga", "Hiking", "Beach", "Pets", "Cars", "DIY",
    "Gardening", "Meditation", "Podcasts", "Baking", "Camping", "Cycling",
    "Running", "Swimming", "Skiing", "Surfing", "Painting", "Board Games",
    "Karaoke",
]

ALL_VIBES = [
    "quiet_luxury", "street_urban", "outdoorsy", "vintage",
    "minimalist", "bohemian", "romantic", "adventurous",
]


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-agg-test",
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
        "id": "milestone-agg-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(**overrides) -> RecommendationState:
    """Build a RecommendationState with sensible defaults and wide budget."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=2000, max_amount=30000),
    }
    defaults.update(overrides)
    return RecommendationState(**defaults)


# ======================================================================
# 1. Stub catalog coverage
# ======================================================================

class TestStubCatalogCoverage:
    """Verify all predefined interests and vibes have catalog entries."""

    def test_all_40_interests_have_gift_entries(self):
        """Every predefined interest must have at least one gift in the catalog."""
        for interest in ALL_INTERESTS:
            entries = _INTEREST_GIFTS.get(interest)
            assert entries is not None, f"Missing gift catalog for interest: {interest}"
            assert len(entries) >= 1, f"Empty gift catalog for interest: {interest}"

    def test_all_8_vibes_have_experience_entries(self):
        """Every predefined vibe must have at least one experience in the catalog."""
        for vibe in ALL_VIBES:
            entries = _VIBE_EXPERIENCES.get(vibe)
            assert entries is not None, f"Missing experience catalog for vibe: {vibe}"
            assert len(entries) >= 1, f"Empty experience catalog for vibe: {vibe}"

    def test_gift_entries_have_valid_source(self):
        """All gift catalog entries must use 'amazon' or 'shopify' as source."""
        valid_sources = {"amazon", "shopify"}
        for interest, entries in _INTEREST_GIFTS.items():
            for entry in entries:
                _, _, _, _, source = entry
                assert source in valid_sources, (
                    f"Invalid source '{source}' for interest '{interest}'"
                )

    def test_experience_entries_have_valid_source(self):
        """All experience catalog entries must use 'yelp' or 'ticketmaster'."""
        valid_sources = {"yelp", "ticketmaster"}
        for vibe, entries in _VIBE_EXPERIENCES.items():
            for entry in entries:
                _, _, _, _, source, _ = entry
                assert source in valid_sources, (
                    f"Invalid source '{source}' for vibe '{vibe}'"
                )

    def test_experience_entries_have_valid_type(self):
        """All experience entries must use 'experience' or 'date' as type."""
        valid_types = {"experience", "date"}
        for vibe, entries in _VIBE_EXPERIENCES.items():
            for entry in entries:
                _, _, _, _, _, rec_type = entry
                assert rec_type in valid_types, (
                    f"Invalid type '{rec_type}' for vibe '{vibe}'"
                )

    def test_all_prices_are_positive(self):
        """All catalog prices must be positive integers (in cents)."""
        for interest, entries in _INTEREST_GIFTS.items():
            for entry in entries:
                _, _, price_cents, _, _ = entry
                assert price_cents > 0, (
                    f"Non-positive price {price_cents} for interest '{interest}'"
                )

        for vibe, entries in _VIBE_EXPERIENCES.items():
            for entry in entries:
                _, _, price_cents, _, _, _ = entry
                assert price_cents > 0, (
                    f"Non-positive price {price_cents} for vibe '{vibe}'"
                )


# ======================================================================
# 2. Candidate construction helpers
# ======================================================================

class TestBuildCandidates:
    """Verify gift and experience candidate construction."""

    def test_build_gift_candidate_has_required_fields(self):
        """Gift candidate should have title, price, URL, and merchant."""
        entry = ("Test Gift", "A test gift description", 5000, "Amazon", "amazon")
        candidate = _build_gift_candidate("Cooking", entry)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.title == "Test Gift"
        assert candidate.description == "A test gift description"
        assert candidate.price_cents == 5000
        assert candidate.merchant_name == "Amazon"
        assert candidate.external_url.startswith("https://")
        assert candidate.image_url.startswith("https://")
        assert candidate.type == "gift"
        assert candidate.source == "amazon"

    def test_build_gift_candidate_has_unique_id(self):
        """Each gift candidate should get a unique UUID."""
        entry = ("Test Gift", "Desc", 5000, "Amazon", "amazon")
        c1 = _build_gift_candidate("Cooking", entry)
        c2 = _build_gift_candidate("Cooking", entry)
        assert c1.id != c2.id
        # Verify IDs are valid UUIDs
        uuid.UUID(c1.id)
        uuid.UUID(c2.id)

    def test_build_gift_candidate_stores_matched_interest(self):
        """Gift candidate metadata should record which interest it matched."""
        entry = ("Test Gift", "Desc", 5000, "Amazon", "amazon")
        candidate = _build_gift_candidate("Cooking", entry)
        assert candidate.metadata["matched_interest"] == "Cooking"
        assert candidate.metadata["catalog"] == "stub"

    def test_build_gift_candidate_has_no_location(self):
        """Gift candidates should not have location data."""
        entry = ("Test Gift", "Desc", 5000, "Amazon", "amazon")
        candidate = _build_gift_candidate("Cooking", entry)
        assert candidate.location is None

    def test_build_experience_candidate_has_required_fields(self):
        """Experience candidate should have title, price, URL, merchant, and type."""
        entry = ("Test Experience", "A fun outing", 8000, "Local Venue", "yelp", "experience")
        location = LocationData(city="Austin", state="TX", country="US")
        candidate = _build_experience_candidate("romantic", entry, location)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.title == "Test Experience"
        assert candidate.description == "A fun outing"
        assert candidate.price_cents == 8000
        assert candidate.merchant_name == "Local Venue"
        assert candidate.external_url.startswith("https://")
        assert candidate.type == "experience"
        assert candidate.source == "yelp"

    def test_build_experience_candidate_includes_location(self):
        """Experience candidates should carry location data."""
        entry = ("Test Exp", "Desc", 8000, "Venue", "yelp", "date")
        location = LocationData(city="Austin", state="TX", country="US")
        candidate = _build_experience_candidate("romantic", entry, location)

        assert candidate.location is not None
        assert candidate.location.city == "Austin"
        assert candidate.location.state == "TX"

    def test_build_experience_candidate_stores_matched_vibe(self):
        """Experience candidate metadata should record which vibe it matched."""
        entry = ("Test Exp", "Desc", 8000, "Venue", "yelp", "date")
        candidate = _build_experience_candidate("romantic", entry, None)
        assert candidate.metadata["matched_vibe"] == "romantic"

    def test_build_experience_candidate_date_type(self):
        """Experience candidates with 'date' type should be typed correctly."""
        entry = ("Dinner Date", "Romantic dinner", 15000, "Restaurant", "yelp", "date")
        candidate = _build_experience_candidate("romantic", entry, None)
        assert candidate.type == "date"

    def test_build_experience_candidate_null_location(self):
        """Experience candidates should accept None location gracefully."""
        entry = ("Test Exp", "Desc", 8000, "Venue", "yelp", "experience")
        candidate = _build_experience_candidate("outdoorsy", entry, None)
        assert candidate.location is None


# ======================================================================
# 3. Fetch functions with budget filtering
# ======================================================================

class TestFetchGiftCandidates:
    """Verify gift candidate fetching and budget filtering."""

    async def test_returns_candidates_for_known_interests(self):
        """Should return gift candidates for valid interests."""
        results = await _fetch_gift_candidates(
            interests=["Cooking"], budget_min=0, budget_max=999999,
        )
        assert len(results) >= 2
        for r in results:
            assert r.type == "gift"
            assert r.metadata["matched_interest"] == "Cooking"

    async def test_filters_by_budget_range(self):
        """Candidates outside the budget range should be excluded."""
        # Cooking has: Chef Knife $89 (8900), Spices $42 (4200), Bowls $65 (6500)
        results = await _fetch_gift_candidates(
            interests=["Cooking"], budget_min=5000, budget_max=7000,
        )
        for r in results:
            assert 5000 <= r.price_cents <= 7000

    async def test_narrow_budget_excludes_all(self):
        """Very narrow budget should return empty list."""
        results = await _fetch_gift_candidates(
            interests=["Cooking"], budget_min=1, budget_max=2,
        )
        assert results == []

    async def test_returns_empty_for_unknown_interest(self):
        """Unknown interests should return empty list (no crash)."""
        results = await _fetch_gift_candidates(
            interests=["Underwater Basket Weaving"], budget_min=0, budget_max=999999,
        )
        assert results == []

    async def test_multiple_interests_combine_results(self):
        """Candidates from multiple interests should be combined."""
        results = await _fetch_gift_candidates(
            interests=["Cooking", "Travel"], budget_min=0, budget_max=999999,
        )
        interests_matched = {r.metadata["matched_interest"] for r in results}
        assert "Cooking" in interests_matched
        assert "Travel" in interests_matched

    async def test_all_candidates_are_gifts(self):
        """All returned candidates should be typed as 'gift'."""
        results = await _fetch_gift_candidates(
            interests=["Music", "Art"], budget_min=0, budget_max=999999,
        )
        for r in results:
            assert r.type == "gift"

    async def test_sources_are_amazon_or_shopify(self):
        """Gift sources should be 'amazon' or 'shopify'."""
        results = await _fetch_gift_candidates(
            interests=["Cooking", "Music"], budget_min=0, budget_max=999999,
        )
        for r in results:
            assert r.source in ("amazon", "shopify")


class TestFetchExperienceCandidates:
    """Verify experience candidate fetching and budget filtering."""

    async def test_returns_candidates_for_known_vibes(self):
        """Should return experience candidates for valid vibes."""
        results = await _fetch_experience_candidates(
            vibes=["romantic"], budget_min=0, budget_max=999999, location=None,
        )
        assert len(results) >= 2
        for r in results:
            assert r.type in ("experience", "date")
            assert r.metadata["matched_vibe"] == "romantic"

    async def test_filters_by_budget_range(self):
        """Candidates outside the budget range should be excluded."""
        # romantic has: Sunset Cruise $220 (22000), Cooking Class $140 (14000), Stargazing $95 (9500)
        results = await _fetch_experience_candidates(
            vibes=["romantic"], budget_min=10000, budget_max=15000, location=None,
        )
        for r in results:
            assert 10000 <= r.price_cents <= 15000

    async def test_narrow_budget_excludes_all(self):
        """Very narrow budget should return empty list."""
        results = await _fetch_experience_candidates(
            vibes=["romantic"], budget_min=1, budget_max=2, location=None,
        )
        assert results == []

    async def test_returns_empty_for_unknown_vibe(self):
        """Unknown vibes should return empty list (no crash)."""
        results = await _fetch_experience_candidates(
            vibes=["cyber_punk"], budget_min=0, budget_max=999999, location=None,
        )
        assert results == []

    async def test_location_attached_to_candidates(self):
        """Experience candidates should carry the provided location."""
        location = LocationData(city="Austin", state="TX", country="US")
        results = await _fetch_experience_candidates(
            vibes=["romantic"], budget_min=0, budget_max=999999, location=location,
        )
        for r in results:
            assert r.location is not None
            assert r.location.city == "Austin"

    async def test_null_location_accepted(self):
        """Should work without location data."""
        results = await _fetch_experience_candidates(
            vibes=["romantic"], budget_min=0, budget_max=999999, location=None,
        )
        assert len(results) >= 1
        for r in results:
            assert r.location is None

    async def test_sources_are_yelp_or_ticketmaster(self):
        """Experience sources should be 'yelp' or 'ticketmaster'."""
        results = await _fetch_experience_candidates(
            vibes=["street_urban", "bohemian"], budget_min=0, budget_max=999999,
            location=None,
        )
        for r in results:
            assert r.source in ("yelp", "ticketmaster")


# ======================================================================
# 4. Full node: aggregate_external_data
# ======================================================================

class TestAggregateExternalDataNode:
    """Verify the full aggregate_external_data LangGraph node."""

    async def test_returns_candidate_recommendations_key(self):
        """Node should return a dict with 'candidate_recommendations' key."""
        state = _make_state()
        result = await aggregate_external_data(state)

        assert "candidate_recommendations" in result
        assert isinstance(result["candidate_recommendations"], list)

    async def test_candidates_are_candidate_recommendation_instances(self):
        """All returned candidates should be CandidateRecommendation objects."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert isinstance(c, CandidateRecommendation)

    async def test_candidates_have_required_fields(self):
        """Each candidate must have title, price_cents, external_url, and merchant_name."""
        state = _make_state()
        result = await aggregate_external_data(state)
        candidates = result["candidate_recommendations"]

        assert len(candidates) > 0, "Expected at least some candidates"
        for c in candidates:
            assert c.title, f"Missing title on candidate {c.id}"
            assert c.price_cents is not None, f"Missing price on candidate {c.id}"
            assert c.price_cents > 0, f"Non-positive price on candidate {c.id}"
            assert c.external_url, f"Missing URL on candidate {c.id}"
            assert c.merchant_name, f"Missing merchant on candidate {c.id}"

    async def test_candidates_within_budget_range(self):
        """All candidates should have prices within the budget range."""
        budget = BudgetRange(min_amount=3000, max_amount=10000)
        state = _make_state(budget_range=budget)
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            if c.price_cents is not None:
                assert 3000 <= c.price_cents <= 10000, (
                    f"Candidate '{c.title}' price {c.price_cents} outside "
                    f"budget range 3000-10000"
                )

    async def test_includes_both_gifts_and_experiences(self):
        """Result should include both gift and experience/date candidates."""
        state = _make_state()
        result = await aggregate_external_data(state)
        candidates = result["candidate_recommendations"]

        types = {c.type for c in candidates}
        assert "gift" in types, "Expected at least one gift candidate"
        assert len(types & {"experience", "date"}) > 0, (
            "Expected at least one experience or date candidate"
        )

    async def test_gifts_match_vault_interests(self):
        """Gift candidates should correspond to the vault's interests."""
        state = _make_state()
        result = await aggregate_external_data(state)

        gift_interests = {
            c.metadata["matched_interest"]
            for c in result["candidate_recommendations"]
            if c.type == "gift"
        }
        vault_interests = set(state.vault_data.interests)
        # All matched interests should be from the vault's interests
        assert gift_interests.issubset(vault_interests), (
            f"Gift interests {gift_interests} not subset of vault {vault_interests}"
        )

    async def test_experiences_match_vault_vibes(self):
        """Experience candidates should correspond to the vault's vibes."""
        state = _make_state()
        result = await aggregate_external_data(state)

        exp_vibes = {
            c.metadata["matched_vibe"]
            for c in result["candidate_recommendations"]
            if c.type in ("experience", "date")
        }
        vault_vibes = set(state.vault_data.vibes)
        # All matched vibes should be from the vault's vibes
        assert exp_vibes.issubset(vault_vibes), (
            f"Experience vibes {exp_vibes} not subset of vault {vault_vibes}"
        )

    async def test_experience_candidates_have_location(self):
        """Experience candidates should have location when vault has location."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            if c.type in ("experience", "date"):
                assert c.location is not None, (
                    f"Experience '{c.title}' missing location"
                )
                assert c.location.city == "Austin"
                assert c.location.state == "TX"

    async def test_handles_missing_location(self):
        """Node should work when vault has no city/state location data."""
        vault_data = _sample_vault_data(
            location_city=None, location_state=None,
        )
        state = _make_state(vault_data=VaultData(**vault_data))
        result = await aggregate_external_data(state)

        # Should still return candidates; location_country defaults to "US"
        # so experiences will have a LocationData with only country set
        assert len(result["candidate_recommendations"]) > 0
        for c in result["candidate_recommendations"]:
            if c.type in ("experience", "date"):
                assert c.location is not None
                assert c.location.city is None
                assert c.location.state is None
                assert c.location.country == "US"

    async def test_all_candidates_have_unique_ids(self):
        """Every candidate should have a unique ID."""
        state = _make_state()
        result = await aggregate_external_data(state)
        candidates = result["candidate_recommendations"]

        ids = [c.id for c in candidates]
        assert len(ids) == len(set(ids)), "Duplicate candidate IDs found"

    async def test_reasonable_candidate_count(self):
        """With a wide budget, should return a reasonable number of candidates."""
        state = _make_state(
            budget_range=BudgetRange(min_amount=1000, max_amount=50000),
        )
        result = await aggregate_external_data(state)
        count = len(result["candidate_recommendations"])

        # 5 interests × 2-3 gifts + 2 vibes × 3 experiences = 16-21 candidates
        assert count >= 10, f"Too few candidates: {count}"
        assert count <= TARGET_CANDIDATE_COUNT, (
            f"Exceeded target: {count} > {TARGET_CANDIDATE_COUNT}"
        )

    async def test_capped_at_target_count(self):
        """Total candidates should not exceed TARGET_CANDIDATE_COUNT."""
        # Use many vibes to generate lots of experience candidates
        vault_data = _sample_vault_data(
            vibes=["quiet_luxury", "romantic", "adventurous", "bohemian",
                   "outdoorsy", "vintage", "minimalist", "street_urban"],
        )
        state = _make_state(
            vault_data=VaultData(**vault_data),
            budget_range=BudgetRange(min_amount=1000, max_amount=50000),
        )
        result = await aggregate_external_data(state)

        assert len(result["candidate_recommendations"]) <= TARGET_CANDIDATE_COUNT

    async def test_result_compatible_with_state_update(self):
        """The returned dict should work with state.model_copy(update=result)."""
        state = _make_state()
        result = await aggregate_external_data(state)

        updated = state.model_copy(update=result)
        assert len(updated.candidate_recommendations) > 0
        assert updated.candidate_recommendations[0].title

    async def test_no_error_on_normal_run(self):
        """Normal run should not set an error."""
        state = _make_state()
        result = await aggregate_external_data(state)

        assert "error" not in result or result.get("error") is None

    async def test_error_when_no_candidates_found(self):
        """When budget excludes all candidates, should return error."""
        state = _make_state(
            budget_range=BudgetRange(min_amount=1, max_amount=2),
        )
        result = await aggregate_external_data(state)

        assert result["candidate_recommendations"] == []
        assert result.get("error") == "No candidates found matching budget and criteria"

    async def test_gift_sources_correct(self):
        """Gift candidates should use 'amazon' or 'shopify' source."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            if c.type == "gift":
                assert c.source in ("amazon", "shopify"), (
                    f"Gift '{c.title}' has wrong source: {c.source}"
                )

    async def test_experience_sources_correct(self):
        """Experience candidates should use 'yelp' or 'ticketmaster' source."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            if c.type in ("experience", "date"):
                assert c.source in ("yelp", "ticketmaster"), (
                    f"Experience '{c.title}' has wrong source: {c.source}"
                )

    async def test_candidates_have_valid_urls(self):
        """All candidates should have well-formed URLs."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert c.external_url.startswith("https://"), (
                f"URL for '{c.title}' doesn't start with https://"
            )
            assert c.image_url.startswith("https://"), (
                f"Image URL for '{c.title}' doesn't start with https://"
            )

    async def test_candidates_have_descriptions(self):
        """All stub candidates should include descriptions."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert c.description, f"Missing description on '{c.title}'"

    async def test_scoring_defaults_to_zero(self):
        """All scoring fields should default to 0.0 (scoring happens later)."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert c.interest_score == 0.0
            assert c.vibe_score == 0.0
            assert c.love_language_score == 0.0
            assert c.final_score == 0.0


# ======================================================================
# 5. Edge cases
# ======================================================================

class TestEdgeCases:
    """Verify graceful handling of edge cases."""

    async def test_just_because_budget_returns_candidates(self):
        """Lower 'just_because' budget should still return affordable candidates."""
        state = _make_state(
            occasion_type="just_because",
            milestone_context=None,
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
        )
        result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        # Should find candidates in $20-$50 range
        assert len(candidates) > 0
        for c in candidates:
            assert 2000 <= c.price_cents <= 5000

    async def test_single_interest_single_vibe(self):
        """Should work with minimal interests and vibes."""
        vault_data = _sample_vault_data(
            interests=["Cooking"],
            vibes=["romantic"],
        )
        # Only 1 interest + 1 vibe, still need 5 likes/dislikes for valid vault
        # but the aggregation node only reads interests and vibes
        state = _make_state(
            vault_data=VaultData(**vault_data),
            budget_range=BudgetRange(min_amount=1000, max_amount=50000),
        )
        result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        assert len(candidates) >= 2  # at least some gifts + some experiences

        interests = {c.metadata.get("matched_interest") for c in candidates if c.type == "gift"}
        vibes = {c.metadata.get("matched_vibe") for c in candidates if c.type in ("experience", "date")}
        assert interests == {"Cooking"}
        assert vibes == {"romantic"}

    async def test_different_currency_passes_through(self):
        """Budget currency should not affect filtering (filtering is on amount only)."""
        state = _make_state(
            budget_range=BudgetRange(min_amount=2000, max_amount=30000, currency="EUR"),
        )
        result = await aggregate_external_data(state)

        # Should still return candidates (currency is informational for stubs)
        assert len(result["candidate_recommendations"]) > 0

    async def test_all_vibes_selected(self):
        """Should handle all 8 vibes being selected."""
        vault_data = _sample_vault_data(vibes=ALL_VIBES)
        state = _make_state(
            vault_data=VaultData(**vault_data),
            budget_range=BudgetRange(min_amount=1000, max_amount=50000),
        )
        result = await aggregate_external_data(state)

        # Should be capped at TARGET_CANDIDATE_COUNT
        candidates = result["candidate_recommendations"]
        assert len(candidates) <= TARGET_CANDIDATE_COUNT
        assert len(candidates) > 0

    async def test_candidate_recommendation_json_round_trip(self):
        """Candidates should survive JSON serialization round-trip."""
        state = _make_state()
        result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            json_str = c.model_dump_json()
            restored = CandidateRecommendation.model_validate_json(json_str)
            assert restored.title == c.title
            assert restored.price_cents == c.price_cents
            assert restored.source == c.source
            assert restored.type == c.type
