"""
Tests for URL resolution query localization.

`_localize_search_query` appends the partner's city/state to a Brave query for
location-bound experiences (date/experience candidates carry a `location`), so
booking links resolve locally even when Claude omits the city. Gifts/ideas have
no `location` and are left unchanged.

Run with: pytest tests/test_url_resolution.py -v
"""

from unittest.mock import AsyncMock, patch
from urllib.parse import parse_qs, urlparse

import pytest

from app.agents.state import (
    CandidateRecommendation,
    LocationData,
    RecommendationState,
)
from app.agents.url_resolution import (
    _build_search_fallback_url,
    _localize_search_query,
    resolve_purchase_urls,
)


class TestLocalizeSearchQuery:
    def test_appends_city_and_state_when_missing(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        result = _localize_search_query("couples pottery class", loc)
        assert result == "couples pottery class Austin TX"

    def test_no_double_append_when_locale_present(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        query = "couples pottery class Austin TX"
        assert _localize_search_query(query, loc) == query

    def test_case_insensitive_locale_match(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        query = "rooftop dinner austin tx"
        # Full locale already present (case-insensitive) — left unchanged.
        assert _localize_search_query(query, loc) == query

    def test_homonym_city_not_falsely_suppressed(self):
        # "Reading" is also a common word; a bare-substring check would wrongly
        # see it in "reading nook" and skip localization. The full-locale check
        # must still append "Reading PA".
        loc = LocationData(city="Reading", state="PA", country="US")
        result = _localize_search_query("couples reading nook event", loc)
        assert result == "couples reading nook event Reading PA"

    def test_unchanged_when_no_location(self):
        assert _localize_search_query("chef knife", None) == "chef knife"

    def test_unchanged_when_location_has_no_city(self):
        loc = LocationData(city=None, state="TX", country="US")
        assert _localize_search_query("chef knife", loc) == "chef knife"

    def test_city_only_when_no_state(self):
        loc = LocationData(city="Austin", state=None, country="US")
        assert _localize_search_query("jazz concert tickets", loc) == "jazz concert tickets Austin"


def _make_candidate(**overrides) -> CandidateRecommendation:
    """Minimal purchasable candidate for URL-resolution tests."""
    data = {
        "id": "cand-001",
        "source": "ticketmaster",
        "type": "date",
        "title": "Standing Room Concert at The Fonda Theatre",
        "merchant_name": "The Fonda Theatre / Ticketmaster",
        "search_query": "The Fonda Theatre Ticketmaster Los Angeles CA",
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


def _query_of(url: str) -> str:
    """Return the decoded value of the `q` param from a Google search URL."""
    return parse_qs(urlparse(url).query)["q"][0]


class TestBuildSearchFallbackURL:
    def test_uses_web_search_not_shopping(self):
        url = _build_search_fallback_url(_make_candidate())
        assert url.startswith("https://www.google.com/search?q=")
        # Google Shopping (tbm=shop) is the wrong surface for tickets/experiences.
        assert "tbm=shop" not in url

    def test_prefers_localized_query(self):
        candidate = _make_candidate(search_query="jazz concert tickets")
        localized = "jazz concert tickets Los Angeles CA"
        url = _build_search_fallback_url(candidate, localized_query=localized)
        assert _query_of(url) == localized

    def test_falls_back_to_claude_search_query(self):
        url = _build_search_fallback_url(_make_candidate())
        assert _query_of(url) == "The Fonda Theatre Ticketmaster Los Angeles CA"

    def test_url_encodes_special_characters(self):
        # No search_query → falls back to merchant_name + title, which contains a
        # slash and spaces that must be percent/plus-encoded, not injected raw.
        candidate = _make_candidate(search_query=None)
        url = _build_search_fallback_url(candidate)
        raw_query_string = url.split("?q=", 1)[1]
        assert "/" not in raw_query_string  # the "/" in the merchant name is encoded
        assert " " not in raw_query_string
        # …and it round-trips back to the intended human-readable query.
        assert _query_of(url) == "The Fonda Theatre / Ticketmaster Standing Room Concert at The Fonda Theatre"

    def test_falls_back_to_title_when_nothing_else(self):
        candidate = _make_candidate(search_query=None, merchant_name=None)
        url = _build_search_fallback_url(candidate)
        assert _query_of(url) == "Standing Room Concert at The Fonda Theatre"


def _make_state(candidate: CandidateRecommendation) -> RecommendationState:
    from app.agents.state import BudgetRange, VaultData

    vault = VaultData(
        vault_id="v1",
        partner_name="Alex",
        interests=["Music", "Travel"],
        dislikes=["Gaming"],
        vibes=["quiet_luxury"],
        primary_love_language="quality_time",
        secondary_love_language="words_of_affirmation",
        budgets=[],
    )
    return RecommendationState(
        vault_data=vault,
        occasion_type="just_because",
        budget_range=BudgetRange(min_amount=1000, max_amount=8000),
        final_three=[candidate],
    )


class TestResolvePurchaseURLs:
    @pytest.mark.asyncio
    async def test_resolved_url_is_not_flagged_as_search(self):
        state = _make_state(_make_candidate())
        with patch(
            "app.agents.url_resolution._search_for_purchase_url",
            new=AsyncMock(return_value="https://www.ticketmaster.com/event/abc123"),
        ):
            result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url == "https://www.ticketmaster.com/event/abc123"
        assert item.external_url_is_search is False

    @pytest.mark.asyncio
    async def test_failed_resolution_flags_search_fallback(self):
        state = _make_state(_make_candidate())
        with patch(
            "app.agents.url_resolution._search_for_purchase_url",
            new=AsyncMock(return_value=None),
        ):
            result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url.startswith("https://www.google.com/search?q=")
        assert "tbm=shop" not in item.external_url
        assert item.external_url_is_search is True

    @pytest.mark.asyncio
    async def test_idea_skips_resolution_and_is_not_search(self):
        candidate = _make_candidate(
            id="idea-1", type="idea", is_idea=True, search_query=None
        )
        state = _make_state(candidate)
        result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url is None
        assert item.external_url_is_search is False
