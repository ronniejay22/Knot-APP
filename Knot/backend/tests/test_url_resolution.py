"""
Tests for URL resolution query localization.

`_localize_search_query` appends the partner's city/state to a Brave query for
location-bound experiences (date/experience candidates carry a `location`), so
booking links resolve locally even when Claude omits the city. Gifts/ideas have
no `location` and are left unchanged.

Run with: pytest tests/test_url_resolution.py -v
"""

from unittest.mock import AsyncMock, patch

import pytest

from app.agents.state import (
    CandidateRecommendation,
    LocationData,
    RecommendationState,
)
from app.agents.url_resolution import (
    _is_rejected_domain,
    _localize_search_query,
    _score_result,
    _search_for_purchase_url,
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


class _FakeBraveResponse:
    status_code = 200

    def __init__(self, results: list[dict]):
        self._data = {"web": {"results": results}}

    def raise_for_status(self):
        pass

    def json(self):
        return self._data


class _FakeBraveClient:
    def __init__(self, results: list[dict]):
        self._results = results

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False

    async def get(self, *args, **kwargs):
        return _FakeBraveResponse(self._results)


def _patch_brave(results: list[dict]):
    """Patch Brave config + the httpx client so _search_for_purchase_url sees `results`."""
    return (
        patch("app.agents.url_resolution.is_brave_search_configured", return_value=True),
        patch(
            "app.agents.url_resolution.httpx.AsyncClient",
            lambda *a, **k: _FakeBraveClient(results),
        ),
    )


class TestRejectDomain:
    def test_rejects_general_search_engines(self):
        for host in ("www.google.com", "www.bing.com", "duckduckgo.com", "search.yahoo.com"):
            assert _is_rejected_domain(host) is True

    def test_rejects_article_domains(self):
        assert _is_rejected_domain("www.reddit.com") is True
        assert _is_rejected_domain("en.wikipedia.org") is True

    def test_accepts_real_merchant_domains(self):
        for host in ("www.ticketmaster.com", "thefondatheatre.com", "resy.com"):
            assert _is_rejected_domain(host) is False

    def test_merchant_on_site_search_not_rejected(self):
        # A venue's own on-site search path is acceptable (only general engines are barred).
        assert _is_rejected_domain("search.thefondatheatre.com") is False

    def test_real_google_merchant_properties_not_rejected(self):
        # The allow-listed Google stores (real goods) must survive subdomain rejection.
        for host in ("store.google.com", "play.google.com", "www.store.google.com"):
            assert _is_rejected_domain(host) is False

    def test_search_and_comparison_subdomains_rejected(self):
        # Any subdomain of a search engine — results, shopping/comparison, cache — is
        # a web-search-style page and must be rejected, not just the `www.` spelling.
        for host in (
            "cse.google.com", "shopping.google.com", "webcache.googleusercontent.com",
            "html.duckduckgo.com", "lite.duckduckgo.com", "r.search.yahoo.com", "cn.bing.com",
        ):
            assert _is_rejected_domain(host) is True

    def test_lookalike_domains_not_rejected(self):
        # Unrelated hosts that merely contain a search-engine substring stay allowed.
        for host in ("task.com", "flask.com", "basking.com"):
            assert _is_rejected_domain(host) is False

    def test_international_and_news_search_rejected(self):
        for host in ("google.co.uk", "www.google.de", "news.google.com", "search.brave.com"):
            assert _is_rejected_domain(host) is True


class TestScoreResult:
    def test_preferred_commerce_domain_beats_bare_blog(self):
        commerce = _score_result("https://www.ticketmaster.com/event/123", rank=4)
        blog = _score_result("https://somevenue.com/about", rank=0)
        assert commerce > blog

    def test_purchase_path_keyword_adds_score(self):
        with_kw = _score_result("https://shop.example.com/product/42", rank=3)
        without = _score_result("https://info.example.com/hello", rank=3)
        assert with_kw > without

    def test_rank_is_a_tiebreak(self):
        earlier = _score_result("https://a.example.com/page", rank=0)
        later = _score_result("https://b.example.com/page", rank=5)
        assert earlier > later


class TestSearchForPurchaseURL:
    @pytest.mark.asyncio
    async def test_returns_none_when_all_results_are_search_engines(self):
        cfg, cli = _patch_brave([
            {"url": "https://www.google.com/search?q=x"},
            {"url": "https://www.bing.com/search?q=x"},
        ])
        with cfg, cli:
            url = await _search_for_purchase_url("the fonda theatre tickets")
        assert url is None

    @pytest.mark.asyncio
    async def test_picks_best_scoring_not_first(self):
        # A bare blog is ranked first; a real ticketing page is ranked lower but wins.
        cfg, cli = _patch_brave([
            {"url": "https://someblog.com/best-jazz-nights"},
            {"url": "https://www.ticketmaster.com/event/the-fonda-123"},
        ])
        with cfg, cli:
            url = await _search_for_purchase_url("the fonda theatre tickets")
        assert url == "https://www.ticketmaster.com/event/the-fonda-123"

    @pytest.mark.asyncio
    async def test_accepts_any_real_non_search_page(self):
        cfg, cli = _patch_brave([{"url": "https://thefondatheatre.com/calendar"}])
        with cfg, cli:
            url = await _search_for_purchase_url("the fonda theatre")
        assert url == "https://thefondatheatre.com/calendar"

    @pytest.mark.asyncio
    async def test_returns_none_when_brave_unconfigured(self):
        with patch("app.agents.url_resolution.is_brave_search_configured", return_value=False):
            assert await _search_for_purchase_url("anything") is None


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
    async def test_resolved_url_is_set(self):
        state = _make_state(_make_candidate())
        with patch(
            "app.agents.url_resolution._search_for_purchase_url",
            new=AsyncMock(return_value="https://www.ticketmaster.com/event/abc123"),
        ):
            result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url == "https://www.ticketmaster.com/event/abc123"

    @pytest.mark.asyncio
    async def test_failed_resolution_leaves_url_none(self):
        # No real page found → external_url stays None (a signal to swap it later).
        # Never a web-search fallback.
        state = _make_state(_make_candidate())
        with patch(
            "app.agents.url_resolution._search_for_purchase_url",
            new=AsyncMock(return_value=None),
        ):
            result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url is None

    @pytest.mark.asyncio
    async def test_idea_skips_resolution(self):
        candidate = _make_candidate(
            id="idea-1", type="idea", is_idea=True, search_query=None
        )
        state = _make_state(candidate)
        result = await resolve_purchase_urls(state)

        item = result["final_three"][0]
        assert item.external_url is None
