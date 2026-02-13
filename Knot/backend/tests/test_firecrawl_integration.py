"""
Step 8.6 Verification: Firecrawl Curated Content Integration

Tests that:
1. CuratedContentService crawls city guide URLs via Firecrawl API
2. Venue extraction parses markdown into structured venue dicts
3. Results are normalized to CandidateRecommendation schema
4. Cache stores results and serves within 24 hours
5. Cache expires after TTL and re-scrapes
6. Empty/missing location returns empty results
7. Missing API key returns empty results gracefully
8. Rate limiting (429) triggers exponential backoff
9. International locations use correct currency
10. Interest filtering narrows results to relevant venues
11. Venue type classification distinguishes date vs experience

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)

Run with: pytest tests/test_firecrawl_integration.py -v
"""

import time
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.core.config import is_firecrawl_configured, validate_firecrawl_config
from app.services.integrations.firecrawl_service import (
    CACHE_TTL_SECONDS,
    CITY_GUIDE_URLS,
    CuratedContentService,
    DATE_KEYWORDS,
    EXPERIENCE_KEYWORDS,
    RELEVANT_INTERESTS,
    _cache,
    _classify_venue_type,
    _extract_description,
    _extract_url_from_block,
    _extract_venues_from_markdown,
    _filter_by_interests,
    _get_guide_urls,
    _is_cache_valid,
    _normalize_venue,
    _set_cache,
    clear_cache,
    clear_expired_cache,
)

# ======================================================================
# Sample data
# ======================================================================

SAMPLE_MARKDOWN_CITY_GUIDE = """\
# Best New Restaurants in NYC 2026

Discover the hottest new openings in New York City.

## The Blue Room

A stunning new Italian restaurant in the West Village, The Blue Room
brings fresh pasta and coastal flavors to Manhattan. Chef Maria Torres
delivers an unforgettable dining experience with a focus on seasonal ingredients.

[Visit The Blue Room](https://www.theblueroom.com)

## Skyline Gallery

This innovative art space in Chelsea combines contemporary exhibitions
with an immersive multimedia experience. Open Thursday through Sunday
with rotating installations from emerging artists.

[Book tickets](https://www.skylinegallery.com/tickets)

## Midnight Rooftop Bar

The city's newest rooftop cocktail lounge sits 40 floors above Midtown.
Craft cocktails and stunning views of the skyline make this the perfect
date night spot.

## Cedar & Vine

**Cedar & Vine** — A cozy wine bar and bistro in Brooklyn Heights. The natural
wine list is impeccable, and the small plates are designed for sharing.

## Urban Trails Walking Tour

**Urban Trails Walking Tour** — Explore hidden corners of the city on this
guided walking tour through historic neighborhoods. Each tour lasts 2 hours
and covers 3 miles of architecture and street art.

1. [Noma Pop-Up](https://www.noma-popup-nyc.com) — The legendary Copenhagen
   restaurant returns to NYC for a limited 3-month residency.
2. [Brooklyn Night Market](https://www.bknight.market) — Weekly outdoor food
   market with 50+ vendors, live music, and craft cocktails.
3. [Jazz at Lincoln Center](https://www.jazz.org) — World-class jazz performances
   in an intimate setting overlooking Central Park.
"""

SAMPLE_FIRECRAWL_RESPONSE = {
    "success": True,
    "data": {
        "markdown": SAMPLE_MARKDOWN_CITY_GUIDE,
    },
}


# ======================================================================
# TestCityGuideUrls
# ======================================================================

class TestCityGuideUrls:
    """Test city guide URL configuration."""

    def test_major_us_cities_have_guides(self):
        """Major US cities should have guide URLs configured."""
        assert "new york" in CITY_GUIDE_URLS
        assert "los angeles" in CITY_GUIDE_URLS
        assert "san francisco" in CITY_GUIDE_URLS
        assert "chicago" in CITY_GUIDE_URLS
        assert "miami" in CITY_GUIDE_URLS

    def test_international_cities_have_guides(self):
        """Some international cities should have guide URLs."""
        assert "london" in CITY_GUIDE_URLS
        assert "paris" in CITY_GUIDE_URLS

    def test_all_urls_are_https(self):
        """All configured URLs should use HTTPS."""
        for city, urls in CITY_GUIDE_URLS.items():
            for url in urls:
                assert url.startswith("https://"), (
                    f"URL for '{city}' is not HTTPS: {url}"
                )

    def test_all_url_lists_nonempty(self):
        """Every city should have at least one guide URL."""
        for city, urls in CITY_GUIDE_URLS.items():
            assert len(urls) > 0, f"No URLs for '{city}'"

    def test_get_guide_urls_exact_match(self):
        """Exact city name match should return URLs."""
        urls = _get_guide_urls("new york")
        assert len(urls) > 0
        assert urls == CITY_GUIDE_URLS["new york"]

    def test_get_guide_urls_case_insensitive(self):
        """City lookup should be case-insensitive."""
        assert _get_guide_urls("New York") == _get_guide_urls("new york")
        assert _get_guide_urls("LOS ANGELES") == _get_guide_urls("los angeles")

    def test_get_guide_urls_partial_match(self):
        """Partial city name should match."""
        assert len(_get_guide_urls("san fran")) > 0

    def test_get_guide_urls_unsupported_city(self):
        """Unsupported city should return empty list."""
        assert _get_guide_urls("Tulsa") == []
        assert _get_guide_urls("Boise") == []

    def test_get_guide_urls_empty_city(self):
        """Empty city string should return empty list."""
        assert _get_guide_urls("") == []
        assert _get_guide_urls("   ") == []


# ======================================================================
# TestVenueExtraction
# ======================================================================

class TestVenueExtraction:
    """Test markdown parsing and venue extraction."""

    def test_extracts_header_venues(self):
        """Should extract venues from markdown headers."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        names = [v["name"] for v in venues]
        assert "The Blue Room" in names
        assert "Skyline Gallery" in names
        assert "Midnight Rooftop Bar" in names

    def test_extracts_bold_venues(self):
        """Should extract venues from bold-formatted names."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        names = [v["name"] for v in venues]
        assert "Cedar & Vine" in names or "Cedar &amp; Vine" in names
        assert "Urban Trails Walking Tour" in names

    def test_extracts_numbered_link_venues(self):
        """Should extract venues from numbered lists with links."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        names = [v["name"] for v in venues]
        assert "Noma Pop-Up" in names
        assert "Brooklyn Night Market" in names

    def test_extracts_urls(self):
        """Extracted venues should include URLs when present."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        noma = next((v for v in venues if v["name"] == "Noma Pop-Up"), None)
        assert noma is not None
        assert noma["url"] == "https://www.noma-popup-nyc.com"

    def test_extracts_descriptions(self):
        """Extracted venues should include description text."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        blue_room = next(
            (v for v in venues if v["name"] == "The Blue Room"), None
        )
        assert blue_room is not None
        assert blue_room["description"] is not None
        assert "Italian" in blue_room["description"] or "pasta" in blue_room["description"]

    def test_deduplicates_venues(self):
        """Should not return duplicate venue names."""
        venues = _extract_venues_from_markdown(SAMPLE_MARKDOWN_CITY_GUIDE)
        names = [v["name"].lower() for v in venues]
        assert len(names) == len(set(names))

    def test_empty_markdown_returns_empty(self):
        """Empty markdown should return empty list."""
        assert _extract_venues_from_markdown("") == []
        assert _extract_venues_from_markdown("   ") == []
        assert _extract_venues_from_markdown(None) == []

    def test_no_venues_in_plain_text(self):
        """Plain text without venue patterns should return empty."""
        result = _extract_venues_from_markdown(
            "This is just a paragraph with no venues or headers."
        )
        assert result == []

    def test_short_names_filtered(self):
        """Names shorter than 3 characters should be excluded."""
        md = "## Hi\nSome text about it.\n\n## The Great Spot\nA wonderful place."
        venues = _extract_venues_from_markdown(md)
        names = [v["name"] for v in venues]
        assert "Hi" not in names
        assert "The Great Spot" in names

    def test_interest_filtering(self):
        """When interests are provided, should filter by relevance."""
        venues = _extract_venues_from_markdown(
            SAMPLE_MARKDOWN_CITY_GUIDE,
            interests=["Art", "Music"],
        )
        # Should still return results (non-empty)
        assert len(venues) > 0


# ======================================================================
# TestDescriptionExtraction
# ======================================================================

class TestDescriptionExtraction:
    """Test description text extraction helper."""

    def test_extracts_first_sentence(self):
        """Should extract the first sentence(s)."""
        desc = _extract_description(
            "This is a great restaurant. It serves Italian food. "
            "Located in the heart of town."
        )
        assert desc is not None
        assert "great restaurant" in desc

    def test_strips_markdown_formatting(self):
        """Should remove markdown bold/italic markers."""
        desc = _extract_description(
            "A **stunning** new *restaurant* with `excellent` food."
        )
        assert desc is not None
        assert "**" not in desc
        assert "*" not in desc
        assert "`" not in desc

    def test_converts_links_to_text(self):
        """Should convert [text](url) to plain text."""
        desc = _extract_description(
            "Visit [The Blue Room](https://example.com) for dinner."
        )
        assert desc is not None
        assert "The Blue Room" in desc
        assert "https://" not in desc

    def test_truncates_long_text(self):
        """Should truncate descriptions over 300 characters."""
        long_text = "A" * 400 + ". Second sentence."
        desc = _extract_description(long_text)
        assert desc is not None
        assert len(desc) <= 303  # 300 + "..."

    def test_empty_text_returns_none(self):
        """Empty text should return None."""
        assert _extract_description("") is None
        assert _extract_description(None) is None


# ======================================================================
# TestUrlExtraction
# ======================================================================

class TestUrlExtraction:
    """Test URL extraction from text blocks."""

    def test_extracts_https_url(self):
        """Should extract HTTPS URLs."""
        url = _extract_url_from_block(
            "Visit https://www.example.com/page for more."
        )
        assert url == "https://www.example.com/page"

    def test_extracts_http_url(self):
        """Should extract HTTP URLs."""
        url = _extract_url_from_block("Go to http://example.com today.")
        assert url == "http://example.com"

    def test_extracts_first_url(self):
        """Should return the first URL when multiple are present."""
        url = _extract_url_from_block(
            "See https://first.com and https://second.com"
        )
        assert url == "https://first.com"

    def test_no_url_returns_none(self):
        """Text without URLs should return None."""
        assert _extract_url_from_block("No URLs here.") is None

    def test_empty_text_returns_none(self):
        """Empty or None input should return None."""
        assert _extract_url_from_block("") is None
        assert _extract_url_from_block(None) is None


# ======================================================================
# TestInterestFiltering
# ======================================================================

class TestInterestFiltering:
    """Test interest-based venue filtering."""

    def test_filters_by_matching_interest(self):
        """Venues matching interest keywords should be preferred."""
        venues = [
            {"name": "Italian Cooking Class", "description": "Learn to cook pasta"},
            {"name": "Skydiving Center", "description": "Jump from a plane"},
            {"name": "Wine Tasting Event", "description": "Sample fine wines"},
        ]
        filtered = _filter_by_interests(venues, ["Cooking", "Wine"])
        names = [v["name"] for v in filtered]
        assert "Italian Cooking Class" in names
        assert "Wine Tasting Event" in names

    def test_returns_all_when_no_match(self):
        """If no venues match interests, return all (avoid empty)."""
        venues = [
            {"name": "Mystery Spot", "description": "A mysterious place"},
            {"name": "Unknown Venue", "description": "Something unique"},
        ]
        filtered = _filter_by_interests(venues, ["Photography"])
        assert len(filtered) == len(venues)

    def test_empty_interests_returns_all(self):
        """Empty interest list should return all venues."""
        venues = [{"name": "Test", "description": "test"}]
        assert _filter_by_interests(venues, []) == venues

    def test_none_interests_returns_all(self):
        """None interests should return all venues."""
        venues = [{"name": "Test", "description": "test"}]
        assert _filter_by_interests(venues, None) == venues


# ======================================================================
# TestVenueTypeClassification
# ======================================================================

class TestVenueTypeClassification:
    """Test venue type classification (date vs experience)."""

    def test_restaurant_classified_as_date(self):
        """Restaurant venues should be classified as 'date'."""
        venue = {"name": "Fine Dining Restaurant", "description": "Upscale dinner"}
        assert _classify_venue_type(venue) == "date"

    def test_bar_classified_as_date(self):
        """Bar venues should be classified as 'date'."""
        venue = {"name": "Rooftop Cocktail Bar", "description": "Craft cocktails"}
        assert _classify_venue_type(venue) == "date"

    def test_museum_classified_as_experience(self):
        """Museums should be classified as 'experience'."""
        venue = {"name": "Modern Art Museum", "description": "Contemporary exhibit"}
        assert _classify_venue_type(venue) == "experience"

    def test_tour_classified_as_experience(self):
        """Tours should be classified as 'experience'."""
        venue = {"name": "City Walking Tour", "description": "A guided tour"}
        assert _classify_venue_type(venue) == "experience"

    def test_ambiguous_defaults_to_experience(self):
        """Ambiguous venues should default to 'experience'."""
        venue = {"name": "Some Place", "description": "A nice spot"}
        assert _classify_venue_type(venue) == "experience"

    def test_wine_classified_as_date(self):
        """Wine venues should be classified as 'date'."""
        venue = {"name": "Natural Wine Bar", "description": "Wine tasting"}
        assert _classify_venue_type(venue) == "date"

    def test_concert_classified_as_experience(self):
        """Concert venues should be classified as 'experience'."""
        venue = {"name": "Jazz Concert Hall", "description": "Live concert tonight"}
        assert _classify_venue_type(venue) == "experience"


# ======================================================================
# TestVenueNormalization
# ======================================================================

class TestVenueNormalization:
    """Test normalization of venue data to CandidateRecommendation format."""

    def test_basic_schema_fields(self):
        """Should include all required CandidateRecommendation fields."""
        result = _normalize_venue(
            {"name": "Test Venue", "description": "A place", "url": "https://test.com"},
            city="New York", state="NY", country_code="US",
        )
        required_keys = [
            "id", "source", "type", "title", "description",
            "price_cents", "currency", "external_url", "image_url",
            "merchant_name", "location", "metadata",
        ]
        for key in required_keys:
            assert key in result, f"Missing key: {key}"

    def test_source_is_firecrawl(self):
        """Source should always be 'firecrawl'."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result["source"] == "firecrawl"

    def test_type_based_on_keywords(self):
        """Type should be classified based on venue content."""
        result_date = _normalize_venue(
            {"name": "Italian Restaurant", "description": "Fine dining", "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result_date["type"] == "date"

        result_exp = _normalize_venue(
            {"name": "Art Gallery Tour", "description": "Guided exhibit", "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result_exp["type"] == "experience"

    def test_uuid_format(self):
        """ID should be a valid UUID string (36 characters)."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36

    def test_price_cents_is_none(self):
        """Price should be None (city guides rarely include prices)."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result["price_cents"] is None

    def test_location_populated(self):
        """Location should be populated with city/state/country."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="San Francisco", state="CA", country_code="US",
        )
        assert result["location"]["city"] == "San Francisco"
        assert result["location"]["state"] == "CA"
        assert result["location"]["country"] == "US"

    def test_metadata_fields(self):
        """Metadata should include source type and venue type."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": "https://test.com"},
            city="NYC", state="NY", country_code="US",
        )
        assert result["metadata"]["source_type"] == "curated_guide"
        assert "venue_type" in result["metadata"]

    def test_merchant_name_set(self):
        """Merchant name should be the venue name."""
        result = _normalize_venue(
            {"name": "Blue Room", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result["merchant_name"] == "Blue Room"

    def test_external_url_from_venue(self):
        """External URL should come from the venue data."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": "https://www.venue.com"},
            city="NYC", state="NY", country_code="US",
        )
        assert result["external_url"] == "https://www.venue.com"

    def test_missing_url_defaults_to_empty(self):
        """Missing URL should default to empty string."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result["external_url"] == ""


# ======================================================================
# TestCurrencyMapping
# ======================================================================

class TestCurrencyMapping:
    """Test international currency detection in normalization."""

    def test_us_currency(self):
        """US should use USD."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="NYC", state="NY", country_code="US",
        )
        assert result["currency"] == "USD"

    def test_uk_currency(self):
        """UK should use GBP."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="London", state="", country_code="GB",
        )
        assert result["currency"] == "GBP"

    def test_france_currency(self):
        """France should use EUR."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="Paris", state="", country_code="FR",
        )
        assert result["currency"] == "EUR"

    def test_japan_currency(self):
        """Japan should use JPY."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="Tokyo", state="", country_code="JP",
        )
        assert result["currency"] == "JPY"

    def test_unknown_country_defaults_to_usd(self):
        """Unknown country code should default to USD."""
        result = _normalize_venue(
            {"name": "Test", "description": None, "url": None},
            city="Unknown", state="", country_code="ZZ",
        )
        assert result["currency"] == "USD"


# ======================================================================
# TestCacheLogic
# ======================================================================

class TestCacheLogic:
    """Test in-memory caching behavior."""

    def setup_method(self):
        """Clear cache before each test."""
        clear_cache()

    def test_cache_miss_returns_none(self):
        """Uncached URL should return not valid."""
        assert not _is_cache_valid("https://example.com/guide")

    def test_cache_set_and_get(self):
        """Setting cache should make it valid and retrievable."""
        from app.services.integrations.firecrawl_service import _get_cached

        url = "https://example.com/guide"
        venues = [{"name": "Test Venue", "description": "Desc", "url": None}]
        _set_cache(url, venues)

        assert _is_cache_valid(url)
        cached = _get_cached(url)
        assert cached is not None
        assert len(cached) == 1
        assert cached[0]["name"] == "Test Venue"

    def test_cache_expires_after_ttl(self):
        """Cache entries should expire after CACHE_TTL_SECONDS."""
        url = "https://example.com/guide"
        venues = [{"name": "Old Venue", "description": None, "url": None}]
        _set_cache(url, venues)

        # Artificially age the cache entry
        _cache[url].timestamp = time.time() - CACHE_TTL_SECONDS - 1

        assert not _is_cache_valid(url)

    def test_cache_valid_within_ttl(self):
        """Cache entries within TTL should be valid."""
        url = "https://example.com/guide"
        _set_cache(url, [])

        # Set timestamp to 1 hour ago (well within 24h TTL)
        _cache[url].timestamp = time.time() - 3600

        assert _is_cache_valid(url)

    def test_clear_cache(self):
        """clear_cache() should remove all entries."""
        _set_cache("https://a.com", [])
        _set_cache("https://b.com", [])
        assert len(_cache) == 2

        clear_cache()
        assert len(_cache) == 0

    def test_clear_expired_cache(self):
        """clear_expired_cache() should only remove expired entries."""
        _set_cache("https://fresh.com", [])
        _set_cache("https://stale.com", [])
        _cache["https://stale.com"].timestamp = (
            time.time() - CACHE_TTL_SECONDS - 1
        )

        clear_expired_cache()
        assert "https://fresh.com" in _cache
        assert "https://stale.com" not in _cache


# ======================================================================
# TestSearchWithMock
# ======================================================================

class TestSearchWithMock:
    """Test full search flow with mocked HTTP responses."""

    def setup_method(self):
        """Clear cache before each test."""
        clear_cache()

    async def test_search_returns_normalized_results(self):
        """Full search should return CandidateRecommendation-format dicts."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = SAMPLE_FIRECRAWL_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client):
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                    interests=["Food", "Art"],
                    limit=10,
                )

        assert len(results) > 0
        for r in results:
            assert r["source"] == "firecrawl"
            assert r["type"] in ("date", "experience")
            assert "id" in r
            assert "title" in r
            assert "currency" in r
            assert r["currency"] == "USD"

    async def test_search_uses_cache_on_second_call(self):
        """Second call should use cached results (no HTTP request)."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = SAMPLE_FIRECRAWL_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client):
                service = CuratedContentService()

                # First call — scrapes
                results1 = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                    limit=10,
                )

                # Second call — should use cache
                results2 = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                    limit=10,
                )

        # Both should return results
        assert len(results1) > 0
        assert len(results2) > 0

        # HTTP post should only have been called for each URL once
        # (NYC has 2 guide URLs, so 2 calls total — not 4)
        assert mock_client.post.call_count == 2  # 2 URLs for NYC

    async def test_search_respects_limit(self):
        """Should cap results at the limit parameter."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = SAMPLE_FIRECRAWL_RESPONSE
        mock_response.raise_for_status = MagicMock()

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client):
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                    limit=3,
                )

        assert len(results) <= 3


# ======================================================================
# TestErrorHandling
# ======================================================================

class TestErrorHandling:
    """Test graceful error handling."""

    def setup_method(self):
        """Clear cache before each test."""
        clear_cache()

    async def test_missing_config_returns_empty(self):
        """Should return empty list when API key is not configured."""
        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=False,
        ):
            service = CuratedContentService()
            results = await service.search_curated_content(
                location=("New York", "NY", "US"),
            )
            assert results == []

    async def test_empty_city_returns_empty(self):
        """Should return empty list for empty city."""
        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ):
            service = CuratedContentService()
            results = await service.search_curated_content(
                location=("", "NY", "US"),
            )
            assert results == []

    async def test_unsupported_city_returns_empty(self):
        """Should return empty list for city with no guides."""
        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ):
            service = CuratedContentService()
            results = await service.search_curated_content(
                location=("Tulsa", "OK", "US"),
            )
            assert results == []

    async def test_timeout_returns_empty(self):
        """Should return empty list on timeout."""
        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.side_effect = httpx.TimeoutException("timeout")
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client), \
                 patch("asyncio.sleep", new_callable=AsyncMock):
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                )
                assert results == []

    async def test_http_error_returns_empty(self):
        """Should return empty list on HTTP errors."""
        mock_response = MagicMock()
        mock_response.status_code = 500
        mock_response.text = "Internal Server Error"
        mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "500", request=MagicMock(), response=mock_response,
        )

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client):
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                )
                assert results == []

    async def test_firecrawl_success_false_returns_empty(self):
        """Should handle Firecrawl API returning success=false."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "success": False,
            "error": "Unable to scrape URL",
        }
        mock_response.raise_for_status = MagicMock()

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            mock_client.post.return_value = mock_response
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client):
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                )
                assert results == []

    async def test_rate_limit_retry_with_backoff(self):
        """Should retry with exponential backoff on 429."""
        mock_429 = MagicMock()
        mock_429.status_code = 429

        mock_200 = MagicMock()
        mock_200.status_code = 200
        mock_200.json.return_value = SAMPLE_FIRECRAWL_RESPONSE
        mock_200.raise_for_status = MagicMock()

        with patch(
            "app.services.integrations.firecrawl_service.is_firecrawl_configured",
            return_value=True,
        ), patch(
            "app.services.integrations.firecrawl_service.FIRECRAWL_API_KEY",
            "test-key",
        ):
            mock_client = AsyncMock()
            # First call: 429, second call: 200 (for first URL)
            # Third call: 200 (for second URL)
            mock_client.post.side_effect = [mock_429, mock_200, mock_200]
            mock_client.__aenter__ = AsyncMock(return_value=mock_client)
            mock_client.__aexit__ = AsyncMock(return_value=False)

            with patch("httpx.AsyncClient", return_value=mock_client), \
                 patch("asyncio.sleep", new_callable=AsyncMock) as mock_sleep:
                service = CuratedContentService()
                results = await service.search_curated_content(
                    location=("New York", "NY", "US"),
                )
                assert len(results) > 0
                # asyncio.sleep should have been called for backoff
                mock_sleep.assert_called()


# ======================================================================
# TestSearchIntegration (requires FIRECRAWL_API_KEY)
# ======================================================================

requires_firecrawl = pytest.mark.skipif(
    not is_firecrawl_configured(),
    reason="Firecrawl API key not configured in .env",
)


@requires_firecrawl
class TestSearchIntegration:
    """Real API tests — only run when FIRECRAWL_API_KEY is set."""

    def setup_method(self):
        """Clear cache before each integration test."""
        clear_cache()

    async def test_real_scrape_returns_results(self):
        """Should return results from a real city guide scrape."""
        service = CuratedContentService()
        results = await service.search_curated_content(
            location=("New York", "NY", "US"),
            limit=5,
        )
        assert len(results) > 0
        for r in results:
            assert r["source"] == "firecrawl"
            assert r["type"] in ("date", "experience")
            assert r["title"]
            assert r["currency"] == "USD"

    async def test_cache_works_with_real_api(self):
        """Second call should use cached results (faster)."""
        service = CuratedContentService()
        # First call
        results1 = await service.search_curated_content(
            location=("New York", "NY", "US"),
            limit=5,
        )
        # Second call — should be near-instant from cache
        results2 = await service.search_curated_content(
            location=("New York", "NY", "US"),
            limit=5,
        )
        assert len(results1) == len(results2)


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_service_importable(self):
        """CuratedContentService class should be importable."""
        assert CuratedContentService is not None

    def test_city_guide_urls_importable(self):
        """CITY_GUIDE_URLS should be importable."""
        assert isinstance(CITY_GUIDE_URLS, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(RELEVANT_INTERESTS, set)
        assert isinstance(DATE_KEYWORDS, set)
        assert isinstance(EXPERIENCE_KEYWORDS, set)
        assert isinstance(CACHE_TTL_SECONDS, int)

    def test_config_functions_importable(self):
        """Config functions should be importable and callable."""
        assert callable(is_firecrawl_configured)
        assert callable(validate_firecrawl_config)

    def test_helper_functions_importable(self):
        """Helper functions should be importable."""
        assert callable(_extract_venues_from_markdown)
        assert callable(_normalize_venue)
        assert callable(_classify_venue_type)
        assert callable(_get_guide_urls)
        assert callable(_is_cache_valid)
        assert callable(clear_cache)
        assert callable(clear_expired_cache)

    def test_cache_ttl_is_24_hours(self):
        """Cache TTL should be 86400 seconds (24 hours)."""
        assert CACHE_TTL_SECONDS == 86400
