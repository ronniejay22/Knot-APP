"""
Step 5.3 + 8.8 + 13.1 Verification: External API Aggregation Node

Tests the aggregate_external_data LangGraph node with three-tier fallback:
1. Claude Search path — mocks ClaudeSearchService as primary
2. AggregatorService path — mocks as secondary fallback
3. Stub fallback path — verifies graceful degradation when all services fail

Test categories:
- Dict-to-candidate conversion: Verify _dict_to_candidate produces valid objects
- Claude Search path: Mock ClaudeSearchService, verify primary path
- AggregatorService fallback: Mock both services, verify tier 2
- Stub fallback: Verify fallback when all services fail
- Stub catalog coverage: Verify all interests/vibes have fallback entries
- Build helpers: Verify candidate construction from stub data
- Edge cases: Empty results, restrictive budgets, malformed data

Run with: pytest tests/test_aggregation_node.py -v
"""

import uuid
from unittest.mock import AsyncMock, patch

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    LocationData,
    MilestoneContext,
    RecommendationState,
    RelevantHint,
    VaultData,
)
from app.agents.aggregation import (
    _INTEREST_GIFTS,
    _VIBE_EXPERIENCES,
    _build_gift_candidate,
    _build_experience_candidate,
    _dict_to_candidate,
    _fetch_stub_candidates,
    aggregate_external_data,
    TARGET_CANDIDATE_COUNT,
)


# ======================================================================
# Valid interest and vibe constants
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
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=2000, max_amount=30000),
    }
    defaults.update(overrides)
    return RecommendationState(**defaults)


def _mock_service_results() -> list[dict]:
    """Return realistic dicts like the real AggregatorService produces."""
    return [
        {
            "id": str(uuid.uuid4()),
            "source": "yelp",
            "type": "date",
            "title": "Mama's Italian Kitchen",
            "description": "Italian, Pizza, Wine Bars",
            "price_cents": 6000,
            "currency": "USD",
            "external_url": "https://www.yelp.com/biz/mamas-italian-kitchen-austin",
            "image_url": "https://s3-media1.fl.yelpcdn.com/bphoto/abc.jpg",
            "merchant_name": "Mama's Italian Kitchen",
            "location": {"city": "Austin", "state": "TX", "country": "US", "address": "123 Main St"},
            "metadata": {"rating": 4.5, "review_count": 320, "yelp_id": "mamas-italian-kitchen-austin"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "amazon",
            "type": "gift",
            "title": "Le Creuset Dutch Oven",
            "description": "Enameled cast iron dutch oven, 5.5 qt",
            "price_cents": 34999,
            "currency": "USD",
            "external_url": "https://www.amazon.com/dp/B00009K3EO?tag=knot-20",
            "image_url": "https://m.media-amazon.com/images/I/le-creuset.jpg",
            "merchant_name": "Amazon",
            "location": None,
            "metadata": {"asin": "B00009K3EO"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "ticketmaster",
            "type": "experience",
            "title": "Austin Symphony Orchestra",
            "description": "Classical music performance at the Long Center",
            "price_cents": 7500,
            "currency": "USD",
            "external_url": "https://www.ticketmaster.com/event/abc123",
            "image_url": "https://s1.ticketm.net/dam/a/abc/symphony.jpg",
            "merchant_name": "Long Center for the Performing Arts",
            "location": {"city": "Austin", "state": "TX", "country": "US", "address": "701 W Riverside Dr"},
            "metadata": {"event_id": "abc123", "genre": "Classical"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "shopify",
            "type": "gift",
            "title": "Artisan Spice Gift Set",
            "description": "Curated collection of 8 hand-blended spices",
            "price_cents": 4500,
            "currency": "USD",
            "external_url": "https://spicehouse.com/products/gift-set",
            "image_url": "https://cdn.shopify.com/s/files/spice-set.jpg",
            "merchant_name": "The Spice House",
            "location": None,
            "metadata": {"product_type": "Spices"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "opentable",
            "type": "date",
            "title": "Uchi Austin",
            "description": "Japanese, Sushi, Fine Dining",
            "price_cents": 12000,
            "currency": "USD",
            "external_url": "https://www.opentable.com/r/uchi-austin",
            "image_url": None,
            "merchant_name": "Uchi",
            "location": {"city": "Austin", "state": "TX", "country": "US", "address": "801 S Lamar Blvd"},
            "metadata": {"reservation_time": "19:00", "party_size": 2},
        },
    ]


def _mock_claude_results() -> list[dict]:
    """Return realistic dicts like ClaudeSearchService produces."""
    return [
        {
            "id": str(uuid.uuid4()),
            "source": "claude_search",
            "type": "gift",
            "title": "Handmade Ceramic Ramen Bowl Set",
            "description": "Beautiful hand-thrown stoneware bowls perfect for cooking enthusiasts",
            "price_cents": 6500,
            "currency": "USD",
            "external_url": "https://www.etsy.com/listing/123456/ceramic-ramen-bowls",
            "image_url": "https://i.etsystatic.com/example.jpg",
            "merchant_name": "CeramicStudio",
            "location": None,
            "metadata": {"search_source": "claude_search", "extraction_model": "claude-sonnet-4-20250514"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "claude_search",
            "type": "date",
            "title": "Sunset Sailing Tour for Two",
            "description": "Romantic 2-hour sunset cruise on Lady Bird Lake with champagne",
            "price_cents": 15000,
            "currency": "USD",
            "external_url": "https://www.viator.com/tours/Austin/sunset-sailing",
            "image_url": None,
            "merchant_name": "Austin Sailing Tours",
            "location": {"city": "Austin", "state": "TX", "country": "US", "address": None},
            "metadata": {"search_source": "claude_search", "extraction_model": "claude-sonnet-4-20250514"},
        },
        {
            "id": str(uuid.uuid4()),
            "source": "claude_search",
            "type": "experience",
            "title": "Pottery Wheel Workshop",
            "description": "Hands-on pottery class for beginners in a cozy studio",
            "price_cents": 8500,
            "currency": "USD",
            "external_url": "https://www.claycafe.com/classes/pottery-wheel",
            "image_url": "https://www.claycafe.com/images/pottery.jpg",
            "merchant_name": "Clay Cafe Austin",
            "location": {"city": "Austin", "state": "TX", "country": "US", "address": "123 Art St"},
            "metadata": {"search_source": "claude_search", "extraction_model": "claude-sonnet-4-20250514"},
        },
    ]


def _empty_claude_mock():
    """Create a ClaudeSearchService mock that returns [] (forces fallback)."""
    mock = AsyncMock()
    mock.search.return_value = []
    return mock


# ======================================================================
# 1. Dict-to-candidate conversion
# ======================================================================

class TestDictToCandidate:
    """Verify _dict_to_candidate converts service dicts correctly."""

    def test_basic_conversion(self):
        raw = _mock_service_results()[0]
        candidate = _dict_to_candidate(raw)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.title == "Mama's Italian Kitchen"
        assert candidate.source == "yelp"
        assert candidate.type == "date"
        assert candidate.price_cents == 6000
        assert candidate.external_url.startswith("https://")

    def test_location_dict_converted_to_location_data(self):
        raw = _mock_service_results()[0]
        candidate = _dict_to_candidate(raw)

        assert candidate.location is not None
        assert isinstance(candidate.location, LocationData)
        assert candidate.location.city == "Austin"
        assert candidate.location.state == "TX"
        assert candidate.location.address == "123 Main St"

    def test_null_location_stays_none(self):
        raw = _mock_service_results()[1]  # Amazon gift, no location
        candidate = _dict_to_candidate(raw)
        assert candidate.location is None

    def test_metadata_preserved(self):
        raw = _mock_service_results()[0]
        candidate = _dict_to_candidate(raw)
        assert candidate.metadata["rating"] == 4.5
        assert candidate.metadata["review_count"] == 320

    def test_scoring_defaults_to_zero(self):
        raw = _mock_service_results()[0]
        candidate = _dict_to_candidate(raw)
        assert candidate.interest_score == 0.0
        assert candidate.vibe_score == 0.0
        assert candidate.love_language_score == 0.0
        assert candidate.final_score == 0.0

    def test_generates_id_if_missing(self):
        raw = {"source": "yelp", "type": "date", "title": "Test", "external_url": "https://example.com"}
        candidate = _dict_to_candidate(raw)
        assert candidate.id
        uuid.UUID(candidate.id)

    def test_all_service_sources_accepted(self):
        for source in ["yelp", "ticketmaster", "amazon", "shopify", "opentable", "resy", "firecrawl", "claude_search"]:
            raw = {"id": str(uuid.uuid4()), "source": source, "type": "gift", "title": "Test", "external_url": "https://example.com"}
            candidate = _dict_to_candidate(raw)
            assert candidate.source == source

    def test_claude_search_candidate_conversion(self):
        raw = _mock_claude_results()[0]
        candidate = _dict_to_candidate(raw)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.source == "claude_search"
        assert candidate.title == "Handmade Ceramic Ramen Bowl Set"
        assert candidate.metadata["search_source"] == "claude_search"

    def test_price_confidence_passed_through(self):
        raw = {
            "source": "claude_search", "type": "gift", "title": "Test",
            "external_url": "https://example.com/item",
            "price_cents": 5000, "price_confidence": "estimated",
        }
        candidate = _dict_to_candidate(raw)
        assert candidate.price_confidence == "estimated"

    def test_price_confidence_defaults_to_unknown(self):
        raw = {
            "source": "yelp", "type": "gift", "title": "Test",
            "external_url": "https://example.com/item",
        }
        candidate = _dict_to_candidate(raw)
        assert candidate.price_confidence == "unknown"


# ======================================================================
# 2. Claude Search primary path
# ======================================================================

class TestClaudeSearchPath:
    """Verify aggregate_external_data uses ClaudeSearchService as primary."""

    async def test_calls_claude_search_and_converts(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        assert "candidate_recommendations" in result
        candidates = result["candidate_recommendations"]
        claude_candidates = [c for c in candidates if c.source == "claude_search"]
        assert len(claude_candidates) == 3
        # Stubs supplement when Claude returns fewer than TARGET_CANDIDATE_COUNT
        assert len(candidates) > 3

    async def test_returns_candidate_recommendation_objects(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert isinstance(c, CandidateRecommendation)

    async def test_passes_hints_to_claude_search(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            state = state.model_copy(update={
                "relevant_hints": [
                    RelevantHint(id="h1", hint_text="She loves pottery", similarity_score=0.9),
                    RelevantHint(id="h2", hint_text="Mentioned wanting to try sushi", similarity_score=0.8),
                ]
            })
            result = await aggregate_external_data(state)

        call_kwargs = mock_claude.search.call_args[1]
        assert "She loves pottery" in call_kwargs["hints"]
        assert "Mentioned wanting to try sushi" in call_kwargs["hints"]

    async def test_passes_milestone_context(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        call_kwargs = mock_claude.search.call_args[1]
        assert call_kwargs["milestone_context"]["milestone_type"] == "birthday"
        assert call_kwargs["occasion_type"] == "major_milestone"

    async def test_caps_at_target_count(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results() * 10  # 30 results

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        assert len(result["candidate_recommendations"]) <= TARGET_CANDIDATE_COUNT

    async def test_skips_malformed_candidates(self):
        results = _mock_claude_results()
        results.append({"title": "Bad Entry", "type": "gift"})  # missing required fields

        mock_claude = AsyncMock()
        mock_claude.search.return_value = results

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        claude_candidates = [
            c for c in result["candidate_recommendations"] if c.source == "claude_search"
        ]
        assert len(claude_candidates) == 3  # malformed entry skipped

    async def test_no_error_on_normal_run(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        assert "error" not in result or result.get("error") is None

    async def test_does_not_call_aggregator_when_claude_succeeds(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()
        mock_aggregator = AsyncMock()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            await aggregate_external_data(state)

        mock_aggregator.aggregate.assert_not_called()


# ======================================================================
# 3. AggregatorService fallback path (tier 2)
# ======================================================================

class TestAggregatorFallback:
    """Verify fallback to AggregatorService when Claude Search fails or returns empty."""

    async def test_falls_back_when_claude_returns_empty(self):
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.return_value = _mock_service_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=_empty_claude_mock()), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        service_candidates = [c for c in candidates if c.metadata.get("catalog") != "stub"]
        # 4 of 5 aggregator results survive budget filter (Le Creuset at $349.99 > $300 max)
        assert len(service_candidates) == 4
        assert any(c.source == "yelp" for c in candidates)
        # Stubs supplement since 4 < TARGET_CANDIDATE_COUNT
        assert len(candidates) > 4

    async def test_falls_back_when_claude_raises(self):
        mock_claude = AsyncMock()
        mock_claude.search.side_effect = RuntimeError("API error")
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.return_value = _mock_service_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        assert len(candidates) > 0

    async def test_passes_correct_args_to_aggregator(self):
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.return_value = []

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=_empty_claude_mock()), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            await aggregate_external_data(state)

        mock_aggregator.aggregate.assert_called_once_with(
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            vibes=["quiet_luxury", "romantic"],
            location=("Austin", "TX", "US"),
            budget_range=(2000, 30000),
            limit_per_service=10,
        )

    async def test_result_compatible_with_state_update(self):
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.return_value = _mock_service_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=_empty_claude_mock()), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        updated = state.model_copy(update=result)
        assert len(updated.candidate_recommendations) > 0
        assert updated.candidate_recommendations[0].title


# ======================================================================
# 4. Stub fallback path (tier 3)
# ======================================================================

class TestStubFallback:
    """Verify fallback to stub catalogs when both services fail."""

    async def test_falls_back_to_stubs_when_both_return_empty(self):
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.return_value = []

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=_empty_claude_mock()), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        assert len(candidates) > 0
        assert all(c.metadata.get("catalog") == "stub" for c in candidates)

    async def test_falls_back_to_stubs_when_both_raise(self):
        mock_claude = AsyncMock()
        mock_claude.search.side_effect = RuntimeError("Claude down")
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.side_effect = RuntimeError("All APIs down")

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        assert len(candidates) > 0
        assert all(c.metadata.get("catalog") == "stub" for c in candidates)

    async def test_falls_back_on_aggregation_error(self):
        from app.services.integrations.aggregator import AggregationError

        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.side_effect = AggregationError("All services failed")

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=_empty_claude_mock()), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        candidates = result["candidate_recommendations"]
        assert len(candidates) > 0
        assert all(c.metadata.get("catalog") == "stub" for c in candidates)

    async def test_stub_candidates_are_valid(self):
        mock_claude = AsyncMock()
        mock_claude.search.side_effect = RuntimeError("fail")
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.side_effect = RuntimeError("fail")

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            state = _make_state()
            result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            assert isinstance(c, CandidateRecommendation)
            assert c.title
            assert c.external_url.startswith("https://")
            assert c.price_cents > 0

    async def test_stub_respects_budget(self):
        mock_claude = AsyncMock()
        mock_claude.search.side_effect = RuntimeError("fail")
        mock_aggregator = AsyncMock()
        mock_aggregator.aggregate.side_effect = RuntimeError("fail")

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude), \
             patch("app.agents.aggregation.AggregatorService", return_value=mock_aggregator):
            budget = BudgetRange(min_amount=3000, max_amount=6000)
            state = _make_state(budget_range=budget)
            result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            if c.price_cents is not None:
                assert 3000 <= c.price_cents <= 6000


# ======================================================================
# 5. Stub catalog coverage (fallback integrity)
# ======================================================================

class TestStubCatalogCoverage:
    """Verify all predefined interests and vibes have fallback catalog entries."""

    def test_all_40_interests_have_gift_entries(self):
        for interest in ALL_INTERESTS:
            entries = _INTEREST_GIFTS.get(interest)
            assert entries is not None, f"Missing gift catalog for interest: {interest}"
            assert len(entries) >= 1, f"Empty gift catalog for interest: {interest}"

    def test_all_8_vibes_have_experience_entries(self):
        for vibe in ALL_VIBES:
            entries = _VIBE_EXPERIENCES.get(vibe)
            assert entries is not None, f"Missing experience catalog for vibe: {vibe}"
            assert len(entries) >= 1, f"Empty experience catalog for vibe: {vibe}"

    def test_gift_entries_have_valid_source(self):
        valid_sources = {"amazon", "shopify"}
        for interest, entries in _INTEREST_GIFTS.items():
            for entry in entries:
                _, _, _, _, source = entry
                assert source in valid_sources, f"Invalid source '{source}' for interest '{interest}'"

    def test_experience_entries_have_valid_source(self):
        valid_sources = {"yelp", "ticketmaster"}
        for vibe, entries in _VIBE_EXPERIENCES.items():
            for entry in entries:
                _, _, _, _, source, _ = entry
                assert source in valid_sources, f"Invalid source '{source}' for vibe '{vibe}'"

    def test_all_prices_are_positive(self):
        for interest, entries in _INTEREST_GIFTS.items():
            for entry in entries:
                _, _, price_cents, _, _ = entry
                assert price_cents > 0, f"Non-positive price for interest '{interest}'"

        for vibe, entries in _VIBE_EXPERIENCES.items():
            for entry in entries:
                _, _, price_cents, _, _, _ = entry
                assert price_cents > 0, f"Non-positive price for vibe '{vibe}'"


# ======================================================================
# 6. Build candidate helpers
# ======================================================================

class TestBuildCandidates:
    """Verify gift and experience candidate construction from stub data."""

    def test_build_gift_candidate_has_required_fields(self):
        entry = ("Test Gift", "A test gift description", 5000, "Amazon", "amazon")
        candidate = _build_gift_candidate("Cooking", entry)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.title == "Test Gift"
        assert candidate.price_cents == 5000
        assert candidate.type == "gift"
        assert candidate.source == "amazon"
        assert candidate.metadata["matched_interest"] == "Cooking"
        assert candidate.metadata["catalog"] == "stub"
        assert candidate.price_confidence == "estimated"
        assert "amazon.com/s?k=" in candidate.external_url

    def test_build_gift_candidate_has_unique_id(self):
        entry = ("Test Gift", "Desc", 5000, "Amazon", "amazon")
        c1 = _build_gift_candidate("Cooking", entry)
        c2 = _build_gift_candidate("Cooking", entry)
        assert c1.id != c2.id

    def test_build_experience_candidate_has_required_fields(self):
        entry = ("Test Experience", "A fun outing", 8000, "Local Venue", "yelp", "experience")
        location = LocationData(city="Austin", state="TX", country="US")
        candidate = _build_experience_candidate("romantic", entry, location)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.title == "Test Experience"
        assert candidate.type == "experience"
        assert candidate.location is not None
        assert candidate.location.city == "Austin"
        assert candidate.metadata["matched_vibe"] == "romantic"
        assert candidate.price_confidence == "estimated"
        assert "yelp.com/search?find_desc=" in candidate.external_url

    def test_build_experience_candidate_null_location(self):
        entry = ("Test Exp", "Desc", 8000, "Venue", "yelp", "experience")
        candidate = _build_experience_candidate("outdoorsy", entry, None)
        assert candidate.location is None


# ======================================================================
# 7. Edge cases
# ======================================================================

class TestEdgeCases:
    """Verify graceful handling of edge cases."""

    async def test_handles_missing_location(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            vault_data = _sample_vault_data(location_city=None, location_state=None)
            state = _make_state(vault_data=VaultData(**vault_data))
            result = await aggregate_external_data(state)

        call_kwargs = mock_claude.search.call_args[1]
        assert call_kwargs["location"] == ("", "", "US")

    async def test_candidate_json_round_trip(self):
        mock_claude = AsyncMock()
        mock_claude.search.return_value = _mock_claude_results()

        with patch("app.agents.aggregation.ClaudeSearchService", return_value=mock_claude):
            state = _make_state()
            result = await aggregate_external_data(state)

        for c in result["candidate_recommendations"]:
            json_str = c.model_dump_json()
            restored = CandidateRecommendation.model_validate_json(json_str)
            assert restored.title == c.title
            assert restored.source == c.source

    async def test_fetch_stub_candidates_directly(self):
        vault = VaultData(**_sample_vault_data())
        budget = BudgetRange(min_amount=2000, max_amount=30000)
        candidates = await _fetch_stub_candidates(vault, budget)

        assert len(candidates) > 0
        types = {c.type for c in candidates}
        assert "gift" in types
