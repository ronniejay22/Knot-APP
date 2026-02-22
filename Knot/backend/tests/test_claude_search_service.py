"""
Step 13.1 Verification: Claude Search Service

Tests the ClaudeSearchService that combines Brave Search + Claude extraction
to find and extract recommendation candidates.

Test categories:
- Query construction: Verify _build_search_queries produces correct queries
- Brave Search: Mock httpx for rate limiting, timeouts, response parsing
- Claude extraction: Mock Anthropic SDK for JSON parsing, error handling
- Normalization: Verify _normalize_claude_result produces valid dicts
- Full service flow: Mock both Brave and Claude end-to-end
- Unconfigured: Verify returns [] when keys missing

Run with: pytest tests/test_claude_search_service.py -v
"""

import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.services.integrations.claude_search_service import (
    ClaudeSearchService,
    _brave_search,
    _build_extraction_prompt,
    _build_search_queries,
    _extract_candidates_with_claude,
    _normalize_claude_result,
    CLAUDE_MODEL,
    MAX_SEARCH_QUERIES,
    RESULTS_PER_QUERY,
    TARGET_CANDIDATES,
)


# ======================================================================
# Test data factories
# ======================================================================

def _sample_brave_response() -> dict:
    """Return a realistic Brave Search API response."""
    return {
        "web": {
            "results": [
                {
                    "title": "Handmade Ceramic Ramen Bowls - Etsy",
                    "url": "https://www.etsy.com/listing/123456/ceramic-ramen-bowls",
                    "description": "Beautiful hand-thrown stoneware bowls. Set of 4, $65.00. Perfect for ramen lovers.",
                    "extra_snippets": ["Free shipping on orders over $35"],
                },
                {
                    "title": "Japanese Cooking Knife Set - Amazon",
                    "url": "https://www.amazon.com/dp/B08XYZ/cooking-knife",
                    "description": "Professional VG-10 steel chef knife set. $89.99. Great for home cooks.",
                    "extra_snippets": [],
                },
                {
                    "title": "10 Best Cooking Gifts 2026 - Good Housekeeping",
                    "url": "https://www.goodhousekeeping.com/best-cooking-gifts",
                    "description": "Our editors' picks for the best cooking gifts this year.",
                    "extra_snippets": ["Updated January 2026"],
                },
            ]
        }
    }


def _sample_claude_extraction() -> list[dict]:
    """Return what Claude's extraction would produce."""
    return [
        {
            "title": "Handmade Ceramic Ramen Bowl Set",
            "description": "Beautiful hand-thrown stoneware bowls, set of 4",
            "type": "gift",
            "price_cents": 6500,
            "external_url": "https://www.etsy.com/listing/123456/ceramic-ramen-bowls",
            "merchant_name": "CeramicStudio",
            "image_url": None,
        },
        {
            "title": "Japanese Cooking Knife Set",
            "description": "Professional VG-10 steel chef knife set for home cooks",
            "type": "gift",
            "price_cents": 8999,
            "external_url": "https://www.amazon.com/dp/B08XYZ/cooking-knife",
            "merchant_name": "Amazon",
            "image_url": None,
        },
    ]


# ======================================================================
# 1. Query construction
# ======================================================================

class TestBuildSearchQueries:
    """Verify _build_search_queries builds correct queries from vault data."""

    def test_generates_gift_queries_from_interests(self):
        queries = _build_search_queries(
            interests=["Cooking", "Travel", "Music"],
            vibes=["romantic"],
            location=("Austin", "TX", "US"),
            budget_range=(2000, 10000),
            occasion_type="just_because",
            hints=[],
        )

        gift_queries = [q for q in queries if q["search_type"] == "gift"]
        assert len(gift_queries) >= 2
        # Should contain interest keywords
        assert any("cooking" in q["query"].lower() for q in gift_queries)

    def test_generates_experience_queries_with_location(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=["romantic", "quiet_luxury"],
            location=("Austin", "TX", "US"),
            budget_range=(5000, 20000),
            occasion_type="minor_occasion",
            hints=[],
        )

        date_queries = [q for q in queries if q["search_type"] in ("date", "experience")]
        assert len(date_queries) >= 1
        assert any("austin" in q["query"].lower() for q in date_queries)

    def test_includes_hint_derived_queries(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=["romantic"],
            location=("Austin", "TX", "US"),
            budget_range=(2000, 10000),
            occasion_type="just_because",
            hints=["She mentioned wanting pottery classes", "Loves sushi"],
        )

        hint_queries = [q for q in queries if "pottery" in q["query"].lower() or "sushi" in q["query"].lower()]
        assert len(hint_queries) >= 1

    def test_includes_milestone_query(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=["romantic"],
            location=("Austin", "TX", "US"),
            budget_range=(10000, 25000),
            occasion_type="major_milestone",
            hints=[],
            milestone_context={"milestone_type": "birthday", "milestone_name": "Alex's Birthday"},
        )

        assert any("birthday" in q["query"].lower() for q in queries)

    def test_caps_at_max_queries(self):
        queries = _build_search_queries(
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            vibes=["romantic", "quiet_luxury"],
            location=("Austin", "TX", "US"),
            budget_range=(2000, 10000),
            occasion_type="just_because",
            hints=["hint1", "hint2", "hint3"],
            milestone_context={"milestone_type": "birthday"},
        )

        assert len(queries) <= MAX_SEARCH_QUERIES

    def test_no_location_uses_fallback(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=["romantic"],
            location=("", "", "US"),
            budget_range=(2000, 10000),
            occasion_type="just_because",
            hints=[],
        )

        # Should still generate gift queries even without location
        gift_queries = [q for q in queries if q["search_type"] == "gift"]
        assert len(gift_queries) >= 1

    def test_no_experience_queries_without_city(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=["romantic"],
            location=("", "", "US"),
            budget_range=(2000, 10000),
            occasion_type="just_because",
            hints=[],
        )

        # No date/experience queries since there's no city
        date_queries = [q for q in queries if q["search_type"] in ("date", "experience")]
        assert len(date_queries) == 0

    def test_budget_appears_in_queries(self):
        queries = _build_search_queries(
            interests=["Cooking"],
            vibes=[],
            location=("Austin", "TX", "US"),
            budget_range=(5000, 15000),
            occasion_type="just_because",
            hints=[],
        )

        # Budget max ($150) should appear in at least one query
        assert any("150" in q["query"] for q in queries)


# ======================================================================
# 2. Brave Search API
# ======================================================================

class TestBraveSearch:
    """Verify _brave_search handles API responses correctly."""

    async def test_returns_results_on_success(self):
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = _sample_brave_response()
        mock_response.raise_for_status = MagicMock()

        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = AsyncMock(return_value=mock_response)

        with patch("app.services.integrations.claude_search_service.httpx.AsyncClient", return_value=mock_client):
            results = await _brave_search("test query")

        assert len(results) == 3
        assert results[0]["title"] == "Handmade Ceramic Ramen Bowls - Etsy"
        assert results[0]["url"].startswith("https://")

    async def test_returns_empty_on_http_error(self):
        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = AsyncMock(side_effect=httpx.HTTPError("Connection failed"))

        with patch("app.services.integrations.claude_search_service.httpx.AsyncClient", return_value=mock_client):
            results = await _brave_search("test query")

        assert results == []

    async def test_returns_empty_on_timeout(self):
        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)
        mock_client.get = AsyncMock(side_effect=httpx.TimeoutException("Timeout"))

        with patch("app.services.integrations.claude_search_service.httpx.AsyncClient", return_value=mock_client):
            results = await _brave_search("test query")

        assert results == []


# ======================================================================
# 3. Claude extraction
# ======================================================================

class TestClaudeExtraction:
    """Verify Claude extraction parses responses correctly."""

    async def test_extracts_candidates_from_valid_json(self):
        candidates = _sample_claude_extraction()
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text=json.dumps(candidates))]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_client):
            results = await _extract_candidates_with_claude(
                search_results=[{"title": "Test", "url": "https://example.com", "description": "Test desc", "extra_snippets": []}],
                search_type="gift",
                interests=["Cooking"],
                vibes=["romantic"],
                budget_range=(2000, 10000),
                location_str="Austin, TX",
                occasion_type="just_because",
                hints=[],
            )

        assert len(results) == 2
        assert results[0]["title"] == "Handmade Ceramic Ramen Bowl Set"

    async def test_strips_markdown_code_fences(self):
        candidates = _sample_claude_extraction()
        fenced_json = f"```json\n{json.dumps(candidates)}\n```"
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text=fenced_json)]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_client):
            results = await _extract_candidates_with_claude(
                search_results=[{"title": "Test", "url": "https://example.com", "description": "Test", "extra_snippets": []}],
                search_type="gift",
                interests=["Cooking"],
                vibes=[],
                budget_range=(2000, 10000),
                location_str="Austin",
                occasion_type="just_because",
                hints=[],
            )

        assert len(results) == 2

    async def test_returns_empty_on_invalid_json(self):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text="This is not valid JSON at all")]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_client):
            results = await _extract_candidates_with_claude(
                search_results=[{"title": "Test", "url": "https://example.com", "description": "Test", "extra_snippets": []}],
                search_type="gift",
                interests=[],
                vibes=[],
                budget_range=(2000, 10000),
                location_str="Austin",
                occasion_type="just_because",
                hints=[],
            )

        assert results == []

    async def test_returns_empty_on_api_error(self):
        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(side_effect=RuntimeError("API error"))

        with patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_client):
            results = await _extract_candidates_with_claude(
                search_results=[{"title": "Test", "url": "https://example.com", "description": "Test", "extra_snippets": []}],
                search_type="gift",
                interests=[],
                vibes=[],
                budget_range=(2000, 10000),
                location_str="Austin",
                occasion_type="just_because",
                hints=[],
            )

        assert results == []

    async def test_returns_empty_for_empty_search_results(self):
        results = await _extract_candidates_with_claude(
            search_results=[],
            search_type="gift",
            interests=[],
            vibes=[],
            budget_range=(2000, 10000),
            location_str="Austin",
            occasion_type="just_because",
            hints=[],
        )

        assert results == []


# ======================================================================
# 4. Normalization
# ======================================================================

class TestNormalization:
    """Verify _normalize_claude_result produces valid CandidateRecommendation dicts."""

    def test_basic_normalization(self):
        raw = _sample_claude_extraction()[0]
        result = _normalize_claude_result(raw, "Austin", "TX", "US")

        assert result["source"] == "claude_search"
        assert result["type"] == "gift"
        assert result["title"] == "Handmade Ceramic Ramen Bowl Set"
        assert result["price_cents"] == 6500
        assert result["currency"] == "USD"
        assert result["external_url"] == "https://www.etsy.com/listing/123456/ceramic-ramen-bowls"
        assert result["metadata"]["search_source"] == "claude_search"

    def test_generates_unique_ids(self):
        raw = _sample_claude_extraction()[0]
        r1 = _normalize_claude_result(raw, "Austin", "TX", "US")
        r2 = _normalize_claude_result(raw, "Austin", "TX", "US")
        assert r1["id"] != r2["id"]

    def test_adds_location_for_experiences(self):
        raw = {"title": "Cooking Class", "type": "experience", "external_url": "https://example.com"}
        result = _normalize_claude_result(raw, "Austin", "TX", "US")

        assert result["location"] is not None
        assert result["location"]["city"] == "Austin"

    def test_no_location_for_gifts(self):
        raw = {"title": "Gift Item", "type": "gift", "external_url": "https://example.com"}
        result = _normalize_claude_result(raw, "Austin", "TX", "US")

        assert result["location"] is None

    def test_invalid_type_defaults_to_gift(self):
        raw = {"title": "Test", "type": "invalid_type", "external_url": "https://example.com"}
        result = _normalize_claude_result(raw, "Austin", "TX", "US")

        assert result["type"] == "gift"

    def test_handles_gb_currency(self):
        raw = {"title": "Test", "type": "gift", "external_url": "https://example.com"}
        result = _normalize_claude_result(raw, "London", "", "GB")

        assert result["currency"] == "GBP"

    def test_handles_empty_country(self):
        raw = {"title": "Test", "type": "gift", "external_url": "https://example.com"}
        result = _normalize_claude_result(raw, "Austin", "TX", "")

        assert result["currency"] == "USD"


# ======================================================================
# 5. Full service flow
# ======================================================================

class TestClaudeSearchServiceFlow:
    """Verify full end-to-end service behavior."""

    async def test_returns_empty_when_not_configured(self):
        with patch("app.services.integrations.claude_search_service.is_claude_search_configured", return_value=False):
            service = ClaudeSearchService()
            results = await service.search(
                interests=["Cooking"],
                vibes=["romantic"],
                location=("Austin", "TX", "US"),
                budget_range=(2000, 10000),
            )

        assert results == []

    async def test_full_search_flow(self):
        # Mock Brave Search
        brave_response = MagicMock()
        brave_response.status_code = 200
        brave_response.json.return_value = _sample_brave_response()
        brave_response.raise_for_status = MagicMock()

        mock_http_client = AsyncMock()
        mock_http_client.__aenter__ = AsyncMock(return_value=mock_http_client)
        mock_http_client.__aexit__ = AsyncMock(return_value=False)
        mock_http_client.get = AsyncMock(return_value=brave_response)

        # Mock Claude extraction
        candidates = _sample_claude_extraction()
        claude_response = MagicMock()
        claude_response.content = [MagicMock(text=json.dumps(candidates))]

        mock_anthropic = AsyncMock()
        mock_anthropic.messages.create = AsyncMock(return_value=claude_response)

        with patch("app.services.integrations.claude_search_service.is_claude_search_configured", return_value=True), \
             patch("app.services.integrations.claude_search_service.httpx.AsyncClient", return_value=mock_http_client), \
             patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_anthropic):
            service = ClaudeSearchService()
            results = await service.search(
                interests=["Cooking", "Travel"],
                vibes=["romantic"],
                location=("Austin", "TX", "US"),
                budget_range=(2000, 10000),
                occasion_type="just_because",
                hints=["She loves pottery"],
            )

        assert len(results) > 0
        assert all(r["source"] == "claude_search" for r in results)

    async def test_deduplicates_by_url(self):
        # Mock Brave returning same results for multiple queries
        brave_response = MagicMock()
        brave_response.status_code = 200
        brave_response.json.return_value = _sample_brave_response()
        brave_response.raise_for_status = MagicMock()

        mock_http_client = AsyncMock()
        mock_http_client.__aenter__ = AsyncMock(return_value=mock_http_client)
        mock_http_client.__aexit__ = AsyncMock(return_value=False)
        mock_http_client.get = AsyncMock(return_value=brave_response)

        # Mock Claude returning duplicates
        duplicate_candidates = _sample_claude_extraction() + _sample_claude_extraction()
        claude_response = MagicMock()
        claude_response.content = [MagicMock(text=json.dumps(duplicate_candidates))]

        mock_anthropic = AsyncMock()
        mock_anthropic.messages.create = AsyncMock(return_value=claude_response)

        with patch("app.services.integrations.claude_search_service.is_claude_search_configured", return_value=True), \
             patch("app.services.integrations.claude_search_service.httpx.AsyncClient", return_value=mock_http_client), \
             patch("app.services.integrations.claude_search_service.ANTHROPIC_API_KEY", "test-key"), \
             patch("app.services.integrations.claude_search_service.AsyncAnthropic", return_value=mock_anthropic):
            service = ClaudeSearchService()
            results = await service.search(
                interests=["Cooking"],
                vibes=["romantic"],
                location=("Austin", "TX", "US"),
                budget_range=(2000, 10000),
            )

        # Should be deduped — unique URLs only
        urls = [r["external_url"] for r in results]
        assert len(urls) == len(set(urls))


# ======================================================================
# 6. Extraction prompt
# ======================================================================

class TestExtractionPrompt:
    """Verify extraction prompt construction."""

    def test_includes_context(self):
        prompt = _build_extraction_prompt(
            search_results=[{"title": "Test", "url": "https://example.com", "description": "Desc", "extra_snippets": []}],
            search_type="gift",
            interests=["Cooking", "Travel"],
            vibes=["romantic"],
            budget_range=(5000, 15000),
            location_str="Austin, TX",
            occasion_type="major_milestone",
            hints=["She loves pottery"],
        )

        assert "Cooking" in prompt
        assert "romantic" in prompt
        assert "Austin, TX" in prompt
        assert "major_milestone" in prompt
        assert "She loves pottery" in prompt
        assert "$50" in prompt
        assert "$150" in prompt

    def test_includes_search_results(self):
        prompt = _build_extraction_prompt(
            search_results=[
                {"title": "Product A", "url": "https://a.com", "description": "Desc A", "extra_snippets": []},
                {"title": "Product B", "url": "https://b.com", "description": "Desc B", "extra_snippets": ["Extra info"]},
            ],
            search_type="gift",
            interests=[],
            vibes=[],
            budget_range=(2000, 10000),
            location_str="Austin",
            occasion_type="just_because",
            hints=[],
        )

        assert "Product A" in prompt
        assert "Product B" in prompt
        assert "https://a.com" in prompt
        assert "Extra info" in prompt
