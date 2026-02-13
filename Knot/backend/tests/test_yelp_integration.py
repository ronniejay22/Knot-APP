"""
Step 8.1 Verification: Yelp Fusion API Integration

Tests that:
1. YelpService correctly converts budget ranges to Yelp price levels
2. All 8 vibes map to valid Yelp category lists
3. Yelp business JSON is normalized to CandidateRecommendation schema
4. International currency detection works for 30+ countries
5. Rate limiting triggers exponential backoff retries on HTTP 429
6. Timeout and HTTP errors return empty results gracefully
7. Invalid locations return empty results (no crash)
8. Integration tests with real Yelp API (skipped without API key)

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)
- httpx installed

Run with: pytest tests/test_yelp_integration.py -v
"""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.core.config import is_yelp_configured
from app.services.integrations.yelp import (
    BASE_URL,
    COUNTRY_CURRENCY_MAP,
    DEFAULT_TIMEOUT,
    MAX_RETRIES,
    VIBE_TO_YELP_CATEGORIES,
    YELP_PRICE_TO_CENTS,
    YelpService,
)


# ---------------------------------------------------------------------------
# Skipif markers
# ---------------------------------------------------------------------------

requires_yelp = pytest.mark.skipif(
    not is_yelp_configured(),
    reason="Yelp API key not configured in .env",
)


# ---------------------------------------------------------------------------
# Sample Yelp API response data
# ---------------------------------------------------------------------------

def _sample_yelp_business(**overrides) -> dict:
    """Create a sample Yelp business object matching the API response format."""
    data = {
        "id": "yelp-biz-123",
        "name": "The Romantic Bistro",
        "url": "https://www.yelp.com/biz/the-romantic-bistro-sf",
        "image_url": "https://s3-media1.fl.yelpcdn.com/bphoto/example.jpg",
        "rating": 4.5,
        "review_count": 328,
        "price": "$$",
        "categories": [
            {"alias": "italian", "title": "Italian"},
            {"alias": "wine_bars", "title": "Wine Bars"},
        ],
        "coordinates": {
            "latitude": 37.7749,
            "longitude": -122.4194,
        },
        "location": {
            "address1": "123 Market St",
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
        },
    }
    data.update(overrides)
    return data


def _sample_yelp_response(businesses: list[dict] | None = None) -> dict:
    """Create a sample Yelp API search response."""
    if businesses is None:
        businesses = [_sample_yelp_business()]
    return {
        "businesses": businesses,
        "total": len(businesses),
        "region": {
            "center": {"latitude": 37.7749, "longitude": -122.4194},
        },
    }


# ======================================================================
# TestYelpPriceConversion
# ======================================================================

class TestYelpPriceConversion:
    """Test conversion from budget cents to Yelp price levels."""

    def test_low_budget_returns_level_1(self):
        """Budget 0-1000 cents should match level 1 ($)."""
        result = YelpService._convert_price_range_to_yelp(0, 1000)
        assert result == "1"

    def test_medium_budget_returns_levels_1_and_2(self):
        """Budget 0-2500 cents should match levels 1,2."""
        result = YelpService._convert_price_range_to_yelp(0, 2500)
        assert result == "1,2"

    def test_high_budget_returns_all_levels(self):
        """Budget 0-20000 cents should match all levels."""
        result = YelpService._convert_price_range_to_yelp(0, 20000)
        assert result == "1,2,3,4"

    def test_expensive_only_returns_levels_3_and_4(self):
        """Budget 5000-15000 cents should match levels 3,4."""
        result = YelpService._convert_price_range_to_yelp(5000, 15000)
        assert result == "3,4"

    def test_ultra_luxury_returns_level_4_only(self):
        """Budget 9000-50000 cents should match level 4."""
        result = YelpService._convert_price_range_to_yelp(9000, 50000)
        assert result == "4"

    def test_midrange_returns_level_2(self):
        """Budget 2000-3500 cents should match level 2."""
        result = YelpService._convert_price_range_to_yelp(2000, 3500)
        assert result == "2"

    def test_zero_range_returns_empty(self):
        """Budget 0-0 returns empty string (no matching levels)."""
        result = YelpService._convert_price_range_to_yelp(0, 0)
        assert result == ""

    def test_wide_midrange_returns_levels_2_and_3(self):
        """Budget 2000-7000 covers levels 2 and 3."""
        result = YelpService._convert_price_range_to_yelp(2000, 7000)
        assert result == "2,3"


# ======================================================================
# TestYelpCategoryMapping
# ======================================================================

class TestYelpCategoryMapping:
    """Test vibe-to-Yelp category mappings."""

    ALL_VIBES = [
        "quiet_luxury", "street_urban", "outdoorsy", "vintage",
        "minimalist", "bohemian", "romantic", "adventurous",
    ]

    def test_all_vibes_have_categories(self):
        """Every vibe should map to at least one Yelp category."""
        for vibe in self.ALL_VIBES:
            categories = VIBE_TO_YELP_CATEGORIES.get(vibe, [])
            assert len(categories) > 0, f"Vibe '{vibe}' has no Yelp categories"

    def test_all_categories_are_strings(self):
        """All mapped categories should be non-empty strings."""
        for vibe, categories in VIBE_TO_YELP_CATEGORIES.items():
            for cat in categories:
                assert isinstance(cat, str), f"Category in '{vibe}' is not a string"
                assert len(cat) > 0, f"Empty category in '{vibe}'"

    def test_no_unexpected_vibes(self):
        """VIBE_TO_YELP_CATEGORIES should only contain the 8 defined vibes."""
        for vibe in VIBE_TO_YELP_CATEGORIES:
            assert vibe in self.ALL_VIBES, f"Unexpected vibe '{vibe}' in mapping"

    def test_mapping_count_is_eight(self):
        """Should have exactly 8 vibe mappings."""
        assert len(VIBE_TO_YELP_CATEGORIES) == 8


# ======================================================================
# TestYelpBusinessNormalization
# ======================================================================

class TestYelpBusinessNormalization:
    """Test conversion of Yelp business JSON to CandidateRecommendation format."""

    def test_basic_normalization(self):
        """Should normalize a standard Yelp business."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "US")

        assert result["source"] == "yelp"
        assert result["title"] == "The Romantic Bistro"
        assert result["merchant_name"] == "The Romantic Bistro"
        assert result["external_url"] == "https://www.yelp.com/biz/the-romantic-bistro-sf"
        assert result["image_url"] == "https://s3-media1.fl.yelpcdn.com/bphoto/example.jpg"
        assert result["currency"] == "USD"
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36  # UUID format

    def test_price_conversion_from_yelp_levels(self):
        """Should convert Yelp price '$'/'$$'/etc to cents."""
        biz_cheap = _sample_yelp_business(price="$")
        result = YelpService._normalize_business(biz_cheap, "US")
        assert result["price_cents"] == 1500

        biz_mid = _sample_yelp_business(price="$$")
        result = YelpService._normalize_business(biz_mid, "US")
        assert result["price_cents"] == 3000

        biz_high = _sample_yelp_business(price="$$$")
        result = YelpService._normalize_business(biz_high, "US")
        assert result["price_cents"] == 6000

        biz_luxury = _sample_yelp_business(price="$$$$")
        result = YelpService._normalize_business(biz_luxury, "US")
        assert result["price_cents"] == 12000

    def test_missing_price_returns_none(self):
        """Should return None for price_cents when Yelp has no price."""
        biz = _sample_yelp_business(price=None)
        result = YelpService._normalize_business(biz, "US")
        assert result["price_cents"] is None

    def test_restaurant_typed_as_date(self):
        """Italian restaurant should be typed as 'date'."""
        biz = _sample_yelp_business(categories=[
            {"alias": "italian", "title": "Italian"},
        ])
        result = YelpService._normalize_business(biz, "US")
        assert result["type"] == "date"

    def test_non_restaurant_typed_as_experience(self):
        """Climbing gym should be typed as 'experience'."""
        biz = _sample_yelp_business(categories=[
            {"alias": "climbing", "title": "Rock Climbing"},
        ])
        result = YelpService._normalize_business(biz, "US")
        assert result["type"] == "experience"

    def test_gbp_currency_for_uk(self):
        """UK country code should produce GBP currency."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "GB")
        assert result["currency"] == "GBP"

        result_uk = YelpService._normalize_business(biz, "UK")
        assert result_uk["currency"] == "GBP"

    def test_eur_currency_for_france(self):
        """France country code should produce EUR currency."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "FR")
        assert result["currency"] == "EUR"

    def test_jpy_currency_for_japan(self):
        """Japan country code should produce JPY currency."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "JP")
        assert result["currency"] == "JPY"

    def test_unknown_country_defaults_to_usd(self):
        """Unknown country code should default to USD."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "ZZ")
        assert result["currency"] == "USD"

    def test_category_description(self):
        """Should join category titles as description."""
        biz = _sample_yelp_business(categories=[
            {"alias": "italian", "title": "Italian"},
            {"alias": "wine_bars", "title": "Wine Bars"},
        ])
        result = YelpService._normalize_business(biz, "US")
        assert result["description"] == "Italian, Wine Bars"

    def test_location_data(self):
        """Should extract location fields from business."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "US")
        loc = result["location"]
        assert loc["city"] == "San Francisco"
        assert loc["state"] == "CA"
        assert loc["country"] == "US"
        assert loc["address"] == "123 Market St"

    def test_metadata_includes_rating_and_review_count(self):
        """Should include Yelp-specific metadata."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "US")
        meta = result["metadata"]
        assert meta["rating"] == 4.5
        assert meta["review_count"] == 328
        assert meta["yelp_id"] == "yelp-biz-123"
        assert meta["yelp_price"] == "$$"
        assert meta["coordinates"]["latitude"] == 37.7749
        assert meta["coordinates"]["longitude"] == -122.4194

    def test_empty_categories_returns_none_description(self):
        """Empty categories list should produce None description."""
        biz = _sample_yelp_business(categories=[])
        result = YelpService._normalize_business(biz, "US")
        assert result["description"] is None

    def test_missing_name_defaults_to_unknown(self):
        """Missing name should default to 'Unknown Business'."""
        biz = _sample_yelp_business()
        del biz["name"]
        result = YelpService._normalize_business(biz, "US")
        assert result["title"] == "Unknown Business"

    def test_lowercase_country_code(self):
        """Should handle lowercase country codes."""
        biz = _sample_yelp_business()
        result = YelpService._normalize_business(biz, "gb")
        assert result["currency"] == "GBP"


# ======================================================================
# TestYelpCurrencyMapping
# ======================================================================

class TestYelpCurrencyMapping:
    """Test international currency detection from country codes."""

    def test_major_currencies_mapped(self):
        """Key currencies should be in the mapping."""
        assert COUNTRY_CURRENCY_MAP["US"] == "USD"
        assert COUNTRY_CURRENCY_MAP["GB"] == "GBP"
        assert COUNTRY_CURRENCY_MAP["JP"] == "JPY"
        assert COUNTRY_CURRENCY_MAP["AU"] == "AUD"
        assert COUNTRY_CURRENCY_MAP["CA"] == "CAD"

    def test_eurozone_countries_map_to_eur(self):
        """All eurozone countries should map to EUR."""
        eurozone = ["FR", "DE", "IT", "ES", "NL", "BE", "AT", "IE", "PT", "FI", "GR"]
        for code in eurozone:
            assert COUNTRY_CURRENCY_MAP[code] == "EUR", f"{code} should map to EUR"

    def test_mapping_has_30_plus_countries(self):
        """Should support 30+ countries."""
        assert len(COUNTRY_CURRENCY_MAP) >= 30


# ======================================================================
# TestYelpRateLimiting
# ======================================================================

class TestYelpRateLimiting:
    """Test rate limiting with exponential backoff."""

    async def test_retries_on_429_then_succeeds(self):
        """Should retry on 429 and return results when the retry succeeds."""
        rate_limit_response = httpx.Response(429, request=httpx.Request("GET", BASE_URL))
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response(),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=[rate_limit_response, success_response])
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
                categories=["restaurants"],
            )

        assert len(results) == 1
        assert results[0]["title"] == "The Romantic Bistro"
        assert mock_client.get.call_count == 2

    async def test_exhausts_retries_on_repeated_429(self):
        """Should return empty list after exhausting all retries on 429."""
        rate_limit_response = httpx.Response(429, request=httpx.Request("GET", BASE_URL))

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=rate_limit_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert results == []
        assert mock_client.get.call_count == MAX_RETRIES


# ======================================================================
# TestYelpErrorHandling
# ======================================================================

class TestYelpErrorHandling:
    """Test graceful error handling for various failure modes."""

    async def test_timeout_returns_empty(self):
        """Should return empty list on timeout after retries."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=httpx.TimeoutException("timeout"))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert results == []

    async def test_http_error_returns_empty(self):
        """Should return empty list on HTTP 500 error."""
        error_response = httpx.Response(
            500,
            text="Internal Server Error",
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=error_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert results == []

    async def test_missing_api_key_returns_empty(self):
        """Should return empty list when YELP_API_KEY is not configured."""
        with patch("app.services.integrations.yelp.is_yelp_configured", return_value=False):
            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert results == []

    async def test_empty_location_returns_empty(self):
        """Should return empty list for empty location tuple."""
        with patch("app.services.integrations.yelp.is_yelp_configured", return_value=True):
            service = YelpService()
            results = await service.search_businesses(
                location=("", "", ""),
            )

        assert results == []

    async def test_empty_businesses_response(self):
        """Should return empty list when Yelp returns no businesses."""
        empty_response = httpx.Response(
            200,
            json={"businesses": [], "total": 0},
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=empty_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            results = await service.search_businesses(
                location=("ZZZZZ", "", ""),
            )

        assert results == []

    async def test_connection_error_returns_empty(self):
        """Should return empty list on connection error."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(
            side_effect=httpx.ConnectError("Connection refused")
        )
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert results == []


# ======================================================================
# TestYelpSearchWithMock
# ======================================================================

class TestYelpSearchWithMock:
    """Test the full search_businesses method with mocked HTTP."""

    async def test_builds_correct_params(self):
        """Should send correct query parameters to Yelp API."""
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            await service.search_businesses(
                location=("San Francisco", "CA", "US"),
                categories=["wine_bars", "spas"],
                price_range=(3000, 10000),
                limit=10,
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["location"] == "San Francisco, CA, US"
        assert params["categories"] == "wine_bars,spas"
        assert params["limit"] == 10
        assert params["sort_by"] == "best_match"
        assert "price" in params

    async def test_caps_limit_at_50(self):
        """Should cap limit at Yelp's maximum of 50."""
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            await service.search_businesses(
                location=("NYC", "NY", "US"),
                limit=100,
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["limit"] == 50

    async def test_normalizes_multiple_businesses(self):
        """Should normalize all businesses in the response."""
        businesses = [
            _sample_yelp_business(name="Restaurant A"),
            _sample_yelp_business(name="Restaurant B"),
            _sample_yelp_business(name="Activity C", categories=[
                {"alias": "climbing", "title": "Rock Climbing"},
            ]),
        ]
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response(businesses),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            results = await service.search_businesses(
                location=("San Francisco", "CA", "US"),
            )

        assert len(results) == 3
        assert results[0]["title"] == "Restaurant A"
        assert results[1]["title"] == "Restaurant B"
        assert results[2]["title"] == "Activity C"
        assert results[2]["type"] == "experience"

    async def test_authorization_header_sent(self):
        """Should send Bearer token in Authorization header."""
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "my-secret-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            await service.search_businesses(
                location=("SF", "CA", "US"),
            )

        call_kwargs = mock_client.get.call_args
        headers = call_kwargs.kwargs.get("headers") or call_kwargs[1].get("headers")
        assert headers["Authorization"] == "Bearer my-secret-key"

    async def test_international_location_string(self):
        """Should build correct location string for international search."""
        success_response = httpx.Response(
            200,
            json=_sample_yelp_response([_sample_yelp_business()]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.yelp.YELP_API_KEY", "test-key"), \
             patch("app.services.integrations.yelp.is_yelp_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = YelpService()
            results = await service.search_businesses(
                location=("London", "", "GB"),
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["location"] == "London, GB"

        # Results should have GBP currency
        assert len(results) == 1
        assert results[0]["currency"] == "GBP"


# ======================================================================
# TestYelpSearchIntegration (requires real API key)
# ======================================================================

@requires_yelp
class TestYelpSearchIntegration:
    """Integration tests with real Yelp API. Skipped without YELP_API_KEY."""

    async def test_search_san_francisco_romantic(self):
        """Should return restaurants in San Francisco with romantic categories."""
        service = YelpService()
        results = await service.search_businesses(
            location=("San Francisco", "CA", "US"),
            categories=["wine_bars", "cookingschools"],
            limit=5,
        )

        assert len(results) > 0
        for biz in results:
            assert biz["source"] == "yelp"
            assert biz["currency"] == "USD"
            assert biz["title"]
            assert biz["external_url"]
            assert isinstance(biz["id"], str)

    async def test_search_london_international(self):
        """Should return London businesses with GBP currency."""
        service = YelpService()
        results = await service.search_businesses(
            location=("London", "", "GB"),
            limit=5,
        )

        assert len(results) > 0
        for biz in results:
            assert biz["currency"] == "GBP"
            assert biz["source"] == "yelp"

    async def test_invalid_location_graceful_error(self):
        """Should return empty results for invalid location 'ZZZZZ'."""
        service = YelpService()
        results = await service.search_businesses(
            location=("ZZZZZ", "", ""),
        )

        # Yelp may return empty or an error — either way, no crash
        assert isinstance(results, list)


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_yelp_service_importable(self):
        """YelpService class should be importable."""
        assert YelpService is not None

    def test_vibe_mapping_importable(self):
        """VIBE_TO_YELP_CATEGORIES should be importable."""
        assert isinstance(VIBE_TO_YELP_CATEGORIES, dict)

    def test_currency_mapping_importable(self):
        """COUNTRY_CURRENCY_MAP should be importable."""
        assert isinstance(COUNTRY_CURRENCY_MAP, dict)

    def test_price_mapping_importable(self):
        """YELP_PRICE_TO_CENTS should be importable."""
        assert isinstance(YELP_PRICE_TO_CENTS, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(BASE_URL, str)
        assert isinstance(DEFAULT_TIMEOUT, float)
        assert isinstance(MAX_RETRIES, int)

    def test_config_functions_importable(self):
        """Config functions should be importable."""
        from app.core.config import is_yelp_configured, validate_yelp_config
        assert callable(is_yelp_configured)
        assert callable(validate_yelp_config)
