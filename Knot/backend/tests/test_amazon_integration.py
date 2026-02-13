"""
Step 8.3 Verification: Amazon Product Advertising API Integration

Tests that:
1. AmazonService correctly maps interest categories to Amazon search indices
2. Amazon product JSON is normalized to CandidateRecommendation schema
3. Affiliate tags are always present in product URLs
4. Price filtering works with PA-API price data
5. HMAC-SHA256 request signing produces valid authorization headers
6. Rate limiting triggers exponential backoff retries on HTTP 429/503
7. Timeout and HTTP errors return empty results gracefully
8. Missing credentials return empty results (no crash)
9. Integration tests with real Amazon PA-API (skipped without credentials)

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)
- httpx installed

Run with: pytest tests/test_amazon_integration.py -v
"""

import json
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.config import is_amazon_configured
from app.services.integrations.amazon import (
    BASE_URL,
    DEFAULT_TIMEOUT,
    INTEREST_TO_AMAZON_CATEGORY,
    MAX_RETRIES,
    PAAPI_PATH,
    AmazonService,
    _build_affiliate_url,
    _build_authorization_header,
    _get_signature_key,
)


# ---------------------------------------------------------------------------
# Skipif markers
# ---------------------------------------------------------------------------

requires_amazon = pytest.mark.skipif(
    not is_amazon_configured(),
    reason="Amazon PA-API credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Sample Amazon PA-API response data
# ---------------------------------------------------------------------------

def _sample_amazon_item(**overrides) -> dict:
    """Create a sample Amazon PA-API 5.0 item matching the SearchItems response format."""
    data = {
        "ASIN": "B09V3KXJPB",
        "DetailPageURL": "https://www.amazon.com/dp/B09V3KXJPB",
        "ItemInfo": {
            "Title": {
                "DisplayValue": "Premium Gardening Tool Set",
                "Label": "Title",
                "Locale": "en_US",
            },
            "Features": {
                "DisplayValues": [
                    "Complete 10-piece stainless steel garden tool set",
                    "Ergonomic non-slip handles for comfort",
                    "Includes carry bag for easy storage",
                ],
                "Label": "Features",
                "Locale": "en_US",
            },
            "ByLineInfo": {
                "Brand": {
                    "DisplayValue": "GardenPro",
                    "Label": "Brand",
                    "Locale": "en_US",
                },
                "Manufacturer": {
                    "DisplayValue": "GardenPro LLC",
                    "Label": "Manufacturer",
                    "Locale": "en_US",
                },
            },
        },
        "Offers": {
            "Listings": [
                {
                    "Price": {
                        "Amount": 34.99,
                        "Currency": "USD",
                        "DisplayAmount": "$34.99",
                    },
                },
            ],
        },
        "Images": {
            "Primary": {
                "Large": {
                    "URL": "https://m.media-amazon.com/images/I/example.jpg",
                    "Width": 500,
                    "Height": 500,
                },
            },
        },
        "BrowseNodeInfo": {
            "BrowseNodes": [
                {
                    "DisplayName": "Garden Tools",
                    "Id": "553788",
                },
            ],
        },
    }
    # Apply overrides with deep merge for nested dicts
    for key, value in overrides.items():
        if isinstance(value, dict) and key in data and isinstance(data[key], dict):
            data[key].update(value)
        else:
            data[key] = value
    return data


def _sample_amazon_response(items: list[dict] | None = None) -> dict:
    """Create a sample Amazon PA-API SearchItems response."""
    if items is None:
        items = [_sample_amazon_item()]
    return {
        "SearchResult": {
            "Items": items,
            "SearchURL": "https://www.amazon.com/s?k=gardening+tools&tag=test-20",
            "TotalResultCount": len(items),
        },
    }


def _sample_amazon_empty_response() -> dict:
    """Create an empty Amazon PA-API response."""
    return {
        "SearchResult": {
            "Items": [],
            "TotalResultCount": 0,
        },
    }


# ======================================================================
# TestAmazonCategoryMapping
# ======================================================================

class TestAmazonCategoryMapping:
    """Test interest-to-Amazon search index mappings."""

    ALL_INTERESTS = [
        "Travel", "Cooking", "Movies", "Music", "Reading", "Sports", "Gaming",
        "Art", "Photography", "Fitness", "Fashion", "Technology", "Nature",
        "Food", "Coffee", "Wine", "Dancing", "Theater", "Concerts", "Museums",
        "Shopping", "Yoga", "Hiking", "Beach", "Pets", "Cars", "DIY",
        "Gardening", "Meditation", "Podcasts", "Baking", "Camping", "Cycling",
        "Running", "Swimming", "Skiing", "Surfing", "Painting", "Board Games",
        "Karaoke",
    ]

    def test_all_interests_have_categories(self):
        """Every predefined interest should map to an Amazon search index."""
        for interest in self.ALL_INTERESTS:
            category = INTEREST_TO_AMAZON_CATEGORY.get(interest)
            assert category is not None, f"Interest '{interest}' has no Amazon category"

    def test_all_categories_are_strings(self):
        """All mapped categories should be non-empty strings."""
        for interest, category in INTEREST_TO_AMAZON_CATEGORY.items():
            assert isinstance(category, str), f"Category for '{interest}' is not a string"
            assert len(category) > 0, f"Empty category for '{interest}'"

    def test_mapping_covers_all_40_interests(self):
        """Should have mappings for all 40 predefined interests."""
        assert len(INTEREST_TO_AMAZON_CATEGORY) == 40

    def test_no_unexpected_interests(self):
        """INTEREST_TO_AMAZON_CATEGORY should only contain known interests."""
        for interest in INTEREST_TO_AMAZON_CATEGORY:
            assert interest in self.ALL_INTERESTS, f"Unexpected interest '{interest}' in mapping"

    def test_common_interest_mappings(self):
        """Spot-check that key interests map to logical categories."""
        assert INTEREST_TO_AMAZON_CATEGORY["Cooking"] == "Kitchen"
        assert INTEREST_TO_AMAZON_CATEGORY["Reading"] == "Books"
        assert INTEREST_TO_AMAZON_CATEGORY["Gaming"] == "VideoGames"
        assert INTEREST_TO_AMAZON_CATEGORY["Gardening"] == "GardenAndOutdoor"
        assert INTEREST_TO_AMAZON_CATEGORY["Pets"] == "PetSupplies"


# ======================================================================
# TestAmazonProductNormalization
# ======================================================================

class TestAmazonProductNormalization:
    """Test conversion of Amazon product JSON to CandidateRecommendation format."""

    def test_basic_normalization(self):
        """Should normalize a standard Amazon product."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)

        assert result["source"] == "amazon"
        assert result["type"] == "gift"
        assert result["title"] == "Premium Gardening Tool Set"
        assert result["merchant_name"] == "GardenPro"
        assert result["currency"] == "USD"
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36  # UUID format

    def test_price_extraction_in_cents(self):
        """Should convert dollar amount to cents."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["price_cents"] == 3499  # $34.99 → 3499 cents

    def test_price_with_whole_dollars(self):
        """Should handle whole-dollar prices."""
        item = _sample_amazon_item()
        item["Offers"]["Listings"][0]["Price"]["Amount"] = 25.0
        result = AmazonService._normalize_product(item)
        assert result["price_cents"] == 2500

    def test_missing_price_returns_none(self):
        """Should return None for price_cents when no offers exist."""
        item = _sample_amazon_item()
        item["Offers"] = {}
        result = AmazonService._normalize_product(item)
        assert result["price_cents"] is None

    def test_missing_listings_returns_none_price(self):
        """Should return None when Listings array is empty."""
        item = _sample_amazon_item()
        item["Offers"]["Listings"] = []
        result = AmazonService._normalize_product(item)
        assert result["price_cents"] is None

    def test_affiliate_tag_in_url(self):
        """Should include affiliate tag in the product URL."""
        with patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "knot-20"):
            item = _sample_amazon_item()
            result = AmazonService._normalize_product(item)
            assert "tag=knot-20" in result["external_url"]

    def test_image_url_extracted(self):
        """Should extract the primary large image URL."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["image_url"] == "https://m.media-amazon.com/images/I/example.jpg"

    def test_missing_image_returns_none(self):
        """Should return None when no images are available."""
        item = _sample_amazon_item()
        item["Images"] = {}
        result = AmazonService._normalize_product(item)
        assert result["image_url"] is None

    def test_brand_as_merchant_name(self):
        """Should use Brand as merchant_name."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["merchant_name"] == "GardenPro"

    def test_manufacturer_fallback_for_merchant(self):
        """Should fall back to Manufacturer when Brand is missing."""
        item = _sample_amazon_item()
        item["ItemInfo"]["ByLineInfo"]["Brand"] = {}
        result = AmazonService._normalize_product(item)
        assert result["merchant_name"] == "GardenPro LLC"

    def test_missing_brand_and_manufacturer_returns_none(self):
        """Should return None when both Brand and Manufacturer are missing."""
        item = _sample_amazon_item()
        item["ItemInfo"]["ByLineInfo"] = {}
        result = AmazonService._normalize_product(item)
        assert result["merchant_name"] is None

    def test_description_from_first_feature(self):
        """Should use the first feature as description."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["description"] == "Complete 10-piece stainless steel garden tool set"

    def test_missing_features_returns_none_description(self):
        """Should return None description when no features exist."""
        item = _sample_amazon_item()
        item["ItemInfo"]["Features"] = {}
        result = AmazonService._normalize_product(item)
        assert result["description"] is None

    def test_location_is_none(self):
        """Amazon products should have no location (they're shipped)."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["location"] is None

    def test_metadata_includes_asin(self):
        """Should include ASIN in metadata."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["metadata"]["asin"] == "B09V3KXJPB"

    def test_metadata_includes_brand(self):
        """Should include brand in metadata."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["metadata"]["brand"] == "GardenPro"

    def test_metadata_includes_category(self):
        """Should include browse node category in metadata."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["metadata"]["category"] == "Garden Tools"

    def test_metadata_includes_features_max_3(self):
        """Should include up to 3 features in metadata."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert len(result["metadata"]["features"]) == 3

    def test_missing_title_defaults_to_unknown(self):
        """Missing title should default to 'Unknown Product'."""
        item = _sample_amazon_item()
        item["ItemInfo"]["Title"] = {}
        result = AmazonService._normalize_product(item)
        assert result["title"] == "Unknown Product"

    def test_currency_from_price_data(self):
        """Should use currency from the price listing."""
        item = _sample_amazon_item()
        item["Offers"]["Listings"][0]["Price"]["Currency"] = "GBP"
        result = AmazonService._normalize_product(item)
        assert result["currency"] == "GBP"

    def test_all_items_typed_as_gift(self):
        """All Amazon products should be typed as 'gift'."""
        item = _sample_amazon_item()
        result = AmazonService._normalize_product(item)
        assert result["type"] == "gift"


# ======================================================================
# TestAffiliateUrl
# ======================================================================

class TestAffiliateUrl:
    """Test affiliate URL building."""

    def test_appends_tag_to_clean_url(self):
        """Should append tag parameter to URL without query string."""
        url = "https://www.amazon.com/dp/B09V3KXJPB"
        result = _build_affiliate_url(url, "knot-20")
        assert result == "https://www.amazon.com/dp/B09V3KXJPB?tag=knot-20"

    def test_appends_tag_to_url_with_query(self):
        """Should append tag with & when URL already has query params."""
        url = "https://www.amazon.com/dp/B09V3KXJPB?ref=sr_1"
        result = _build_affiliate_url(url, "knot-20")
        assert result == "https://www.amazon.com/dp/B09V3KXJPB?ref=sr_1&tag=knot-20"

    def test_preserves_url_with_existing_tag(self):
        """Should not duplicate the tag if already present."""
        url = "https://www.amazon.com/dp/B09V3KXJPB?tag=knot-20"
        result = _build_affiliate_url(url, "knot-20")
        assert result == url

    def test_empty_url_returns_empty(self):
        """Should return empty string for empty URL."""
        assert _build_affiliate_url("", "knot-20") == ""

    def test_empty_tag_returns_original_url(self):
        """Should return original URL when tag is empty."""
        url = "https://www.amazon.com/dp/B09V3KXJPB"
        assert _build_affiliate_url(url, "") == url


# ======================================================================
# TestAmazonSigning
# ======================================================================

class TestAmazonSigning:
    """Test HMAC-SHA256 request signing."""

    def test_signature_key_is_bytes(self):
        """Signing key should be bytes."""
        key = _get_signature_key("secret", "20260101", "us-east-1", "ProductAdvertisingAPI")
        assert isinstance(key, bytes)
        assert len(key) == 32  # SHA-256 produces 32 bytes

    def test_authorization_header_format(self):
        """Authorization header should follow AWS Signature V4 format."""
        headers = _build_authorization_header(
            access_key="AKIATEST",
            secret_key="secret123",
            payload='{"Keywords":"test"}',
            host="webservices.amazon.com",
            path="/paapi5/searchitems",
            amz_date="20260212T120000Z",
            date_stamp="20260212",
        )

        assert "Authorization" in headers
        assert headers["Authorization"].startswith("AWS4-HMAC-SHA256")
        assert "Credential=AKIATEST/" in headers["Authorization"]
        assert "SignedHeaders=" in headers["Authorization"]
        assert "Signature=" in headers["Authorization"]

    def test_required_headers_present(self):
        """Should include all required PA-API headers."""
        headers = _build_authorization_header(
            access_key="AKIATEST",
            secret_key="secret123",
            payload='{"Keywords":"test"}',
            host="webservices.amazon.com",
            path="/paapi5/searchitems",
            amz_date="20260212T120000Z",
            date_stamp="20260212",
        )

        assert "Content-Encoding" in headers
        assert headers["Content-Encoding"] == "amz-1.0"
        assert "Content-Type" in headers
        assert "application/json" in headers["Content-Type"]
        assert "Host" in headers
        assert headers["Host"] == "webservices.amazon.com"
        assert "X-Amz-Date" in headers
        assert headers["X-Amz-Date"] == "20260212T120000Z"
        assert "X-Amz-Target" in headers

    def test_different_payloads_produce_different_signatures(self):
        """Different payloads should produce different authorization headers."""
        headers1 = _build_authorization_header(
            access_key="AKIATEST",
            secret_key="secret123",
            payload='{"Keywords":"gardening"}',
            host="webservices.amazon.com",
            path="/paapi5/searchitems",
            amz_date="20260212T120000Z",
            date_stamp="20260212",
        )
        headers2 = _build_authorization_header(
            access_key="AKIATEST",
            secret_key="secret123",
            payload='{"Keywords":"cooking"}',
            host="webservices.amazon.com",
            path="/paapi5/searchitems",
            amz_date="20260212T120000Z",
            date_stamp="20260212",
        )

        assert headers1["Authorization"] != headers2["Authorization"]


# ======================================================================
# TestAmazonRateLimiting
# ======================================================================

class TestAmazonRateLimiting:
    """Test rate limiting with exponential backoff."""

    async def test_retries_on_429_then_succeeds(self):
        """Should retry on 429 and return results when the retry succeeds."""
        rate_limit_response = httpx.Response(
            429, request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}")
        )
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response(),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(side_effect=[rate_limit_response, success_response])
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = AmazonService()
            results = await service.search_products(keywords="gardening gifts")

        assert len(results) == 1
        assert results[0]["title"] == "Premium Gardening Tool Set"
        assert mock_client.post.call_count == 2

    async def test_retries_on_503_then_succeeds(self):
        """Should retry on 503 (Service Unavailable) and succeed."""
        retry_response = httpx.Response(
            503, request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}")
        )
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response(),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(side_effect=[retry_response, success_response])
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = AmazonService()
            results = await service.search_products(keywords="cooking set")

        assert len(results) == 1
        assert mock_client.post.call_count == 2

    async def test_exhausts_retries_on_repeated_429(self):
        """Should return empty list after exhausting all retries on 429."""
        rate_limit_response = httpx.Response(
            429, request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}")
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=rate_limit_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert results == []
        assert mock_client.post.call_count == MAX_RETRIES


# ======================================================================
# TestAmazonErrorHandling
# ======================================================================

class TestAmazonErrorHandling:
    """Test graceful error handling for various failure modes."""

    async def test_timeout_returns_empty(self):
        """Should return empty list on timeout after retries."""
        mock_client = AsyncMock()
        mock_client.post = AsyncMock(side_effect=httpx.TimeoutException("timeout"))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_http_error_returns_empty(self):
        """Should return empty list on HTTP 500 error."""
        error_response = httpx.Response(
            500,
            text="Internal Server Error",
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=error_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_missing_credentials_returns_empty(self):
        """Should return empty list when Amazon credentials are not configured."""
        with patch("app.services.integrations.amazon.is_amazon_configured", return_value=False):
            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_empty_keywords_returns_empty(self):
        """Should return empty list for empty keywords."""
        with patch("app.services.integrations.amazon.is_amazon_configured", return_value=True):
            service = AmazonService()
            results = await service.search_products(keywords="")

        assert results == []

    async def test_whitespace_keywords_returns_empty(self):
        """Should return empty list for whitespace-only keywords."""
        with patch("app.services.integrations.amazon.is_amazon_configured", return_value=True):
            service = AmazonService()
            results = await service.search_products(keywords="   ")

        assert results == []

    async def test_empty_response_returns_empty(self):
        """Should return empty list when Amazon returns no items."""
        empty_response = httpx.Response(
            200,
            json=_sample_amazon_empty_response(),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=empty_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            results = await service.search_products(keywords="nonexistent product xyz")

        assert results == []

    async def test_connection_error_returns_empty(self):
        """Should return empty list on connection error."""
        mock_client = AsyncMock()
        mock_client.post = AsyncMock(
            side_effect=httpx.ConnectError("Connection refused")
        )
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert results == []


# ======================================================================
# TestAmazonSearchWithMock
# ======================================================================

class TestAmazonSearchWithMock:
    """Test the full search_products method with mocked HTTP."""

    async def test_builds_correct_payload(self):
        """Should send correct JSON payload to PA-API."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(
                keywords="gardening gifts",
                category="GardenAndOutdoor",
                limit=5,
            )

        call_kwargs = mock_client.post.call_args
        payload_str = call_kwargs.kwargs.get("content") or call_kwargs[1].get("content")
        payload = json.loads(payload_str)
        assert payload["Keywords"] == "gardening gifts"
        assert payload["SearchIndex"] == "GardenAndOutdoor"
        assert payload["ItemCount"] == 5
        assert payload["PartnerTag"] == "test-20"
        assert payload["PartnerType"] == "Associates"

    async def test_caps_limit_at_10(self):
        """Should cap limit at PA-API's maximum of 10 per request."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(keywords="gifts", limit=50)

        call_kwargs = mock_client.post.call_args
        payload_str = call_kwargs.kwargs.get("content") or call_kwargs[1].get("content")
        payload = json.loads(payload_str)
        assert payload["ItemCount"] == 10

    async def test_normalizes_multiple_products(self):
        """Should normalize all items in the response."""
        items = [
            _sample_amazon_item(),
            _sample_amazon_item(
                ASIN="B0ANOTHER1",
                ItemInfo={
                    "Title": {"DisplayValue": "Cooking Apron Set"},
                    "Features": {"DisplayValues": ["Waterproof apron"]},
                    "ByLineInfo": {"Brand": {"DisplayValue": "ChefWear"}},
                },
            ),
        ]
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response(items),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            results = await service.search_products(keywords="gifts")

        assert len(results) == 2
        assert results[0]["title"] == "Premium Gardening Tool Set"
        assert results[1]["title"] == "Cooking Apron Set"
        assert all(r["source"] == "amazon" for r in results)
        assert all(r["type"] == "gift" for r in results)

    async def test_price_range_in_payload(self):
        """Should include MinPrice and MaxPrice when price_range is specified."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(
                keywords="gifts",
                price_range=(2000, 5000),
            )

        call_kwargs = mock_client.post.call_args
        payload_str = call_kwargs.kwargs.get("content") or call_kwargs[1].get("content")
        payload = json.loads(payload_str)
        assert payload["MinPrice"] == 2000
        assert payload["MaxPrice"] == 5000

    async def test_default_search_index_is_all(self):
        """Should default to 'All' search index when no category is provided."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(keywords="gifts")

        call_kwargs = mock_client.post.call_args
        payload_str = call_kwargs.kwargs.get("content") or call_kwargs[1].get("content")
        payload = json.loads(payload_str)
        assert payload["SearchIndex"] == "All"

    async def test_signed_request_includes_auth_headers(self):
        """Should send signed request with Authorization and X-Amz-Date headers."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "AKIATEST123"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "secret123"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(keywords="gifts")

        call_kwargs = mock_client.post.call_args
        headers = call_kwargs.kwargs.get("headers") or call_kwargs[1].get("headers")
        assert "Authorization" in headers
        assert headers["Authorization"].startswith("AWS4-HMAC-SHA256")
        assert "AKIATEST123" in headers["Authorization"]
        assert "X-Amz-Date" in headers
        assert "X-Amz-Target" in headers

    async def test_posts_to_correct_endpoint(self):
        """Should POST to the PA-API SearchItems endpoint."""
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response([]),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            await service.search_products(keywords="gifts")

        call_args = mock_client.post.call_args
        url = call_args[0][0] if call_args[0] else call_args.kwargs.get("url", "")
        assert url == f"{BASE_URL}{PAAPI_PATH}"

    async def test_client_side_price_filtering(self):
        """Should filter out products outside the price range."""
        expensive_item = _sample_amazon_item()
        expensive_item["Offers"]["Listings"][0]["Price"]["Amount"] = 99.99

        cheap_item = _sample_amazon_item(ASIN="B0CHEAP")
        cheap_item["Offers"]["Listings"][0]["Price"]["Amount"] = 15.00
        cheap_item["ItemInfo"]["Title"]["DisplayValue"] = "Budget Gift"

        items = [expensive_item, cheap_item]
        success_response = httpx.Response(
            200,
            json=_sample_amazon_response(items),
            request=httpx.Request("POST", f"{BASE_URL}{PAAPI_PATH}"),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.amazon.AMAZON_ACCESS_KEY", "test-key"), \
             patch("app.services.integrations.amazon.AMAZON_SECRET_KEY", "test-secret"), \
             patch("app.services.integrations.amazon.AMAZON_ASSOCIATE_TAG", "test-20"), \
             patch("app.services.integrations.amazon.is_amazon_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = AmazonService()
            # Only want products under $50 (5000 cents)
            results = await service.search_products(
                keywords="gifts",
                price_range=(0, 5000),
            )

        assert len(results) == 1
        assert results[0]["title"] == "Budget Gift"
        assert results[0]["price_cents"] == 1500


# ======================================================================
# TestAmazonSearchIntegration (requires real API credentials)
# ======================================================================

@requires_amazon
class TestAmazonSearchIntegration:
    """Integration tests with real Amazon PA-API. Skipped without credentials."""

    async def test_search_gardening_gifts(self):
        """Should return gardening products under $50."""
        service = AmazonService()
        results = await service.search_products(
            keywords="gardening gifts",
            category="GardenAndOutdoor",
            price_range=(0, 5000),
            limit=5,
        )

        assert len(results) > 0
        for product in results:
            assert product["source"] == "amazon"
            assert product["type"] == "gift"
            assert product["title"]
            assert product["external_url"]
            assert isinstance(product["id"], str)

    async def test_affiliate_tag_in_results(self):
        """Should include affiliate tag in all product URLs."""
        service = AmazonService()
        results = await service.search_products(
            keywords="cooking gifts",
            limit=3,
        )

        assert len(results) > 0
        for product in results:
            assert "tag=" in product["external_url"]

    async def test_empty_results_graceful(self):
        """Should return empty list for very specific unlikely search."""
        service = AmazonService()
        results = await service.search_products(
            keywords="xyznonexistentproduct12345678",
        )

        assert isinstance(results, list)


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_amazon_service_importable(self):
        """AmazonService class should be importable."""
        assert AmazonService is not None

    def test_category_mapping_importable(self):
        """INTEREST_TO_AMAZON_CATEGORY should be importable."""
        assert isinstance(INTEREST_TO_AMAZON_CATEGORY, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(BASE_URL, str)
        assert isinstance(DEFAULT_TIMEOUT, float)
        assert isinstance(MAX_RETRIES, int)
        assert isinstance(PAAPI_PATH, str)

    def test_affiliate_url_helper_importable(self):
        """_build_affiliate_url helper should be importable."""
        assert callable(_build_affiliate_url)

    def test_signing_helpers_importable(self):
        """Signing helper functions should be importable."""
        assert callable(_build_authorization_header)
        assert callable(_get_signature_key)

    def test_config_functions_importable(self):
        """Config functions should be importable."""
        from app.core.config import is_amazon_configured, validate_amazon_config
        assert callable(is_amazon_configured)
        assert callable(validate_amazon_config)
