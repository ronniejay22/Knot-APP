"""
Step 8.4 Verification: Shopify Storefront API Integration

Tests that:
1. ShopifyService correctly maps interest categories to Shopify search keywords
2. Shopify product JSON is normalized to CandidateRecommendation schema
3. Dollar-to-cents price conversion works correctly
4. GraphQL query and variables are constructed properly
5. Rate limiting triggers exponential backoff retries on HTTP 429
6. Timeout and HTTP errors return empty results gracefully
7. Missing credentials return empty results (no crash)
8. Unavailable products are filtered out
9. Client-side price filtering works with budget range
10. Integration tests with real Shopify Storefront API (skipped without credentials)

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)
- httpx installed

Run with: pytest tests/test_shopify_integration.py -v
"""

from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.config import is_shopify_configured
from app.services.integrations.shopify import (
    API_VERSION,
    DEFAULT_TIMEOUT,
    INTEREST_TO_SHOPIFY_PRODUCT_TYPE,
    MAX_PRODUCTS_PER_QUERY,
    MAX_RETRIES,
    PRODUCTS_SEARCH_QUERY,
    ShopifyService,
    _build_storefront_url,
    _dollars_to_cents,
)


# ---------------------------------------------------------------------------
# Skipif markers
# ---------------------------------------------------------------------------

requires_shopify = pytest.mark.skipif(
    not is_shopify_configured(),
    reason="Shopify Storefront API credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Test store domain for mocked tests
# ---------------------------------------------------------------------------

TEST_STORE_DOMAIN = "test-store.myshopify.com"
TEST_STOREFRONT_TOKEN = "test-storefront-token-abc123"
TEST_API_URL = f"https://{TEST_STORE_DOMAIN}/api/{API_VERSION}/graphql.json"


# ---------------------------------------------------------------------------
# Sample Shopify Storefront API response data
# ---------------------------------------------------------------------------

def _sample_shopify_product(**overrides) -> dict:
    """Create a sample Shopify Storefront API product node."""
    data = {
        "id": "gid://shopify/Product/123456789",
        "title": "Premium Gardening Tool Set",
        "handle": "premium-gardening-tool-set",
        "description": "Complete 10-piece stainless steel garden tool set with ergonomic handles.",
        "vendor": "GardenPro",
        "productType": "Garden Tools",
        "onlineStoreUrl": f"https://{TEST_STORE_DOMAIN}/products/premium-gardening-tool-set",
        "images": {
            "edges": [
                {
                    "node": {
                        "url": "https://cdn.shopify.com/s/files/example.jpg",
                        "altText": "Gardening Tool Set",
                    }
                }
            ]
        },
        "variants": {
            "edges": [
                {
                    "node": {
                        "id": "gid://shopify/ProductVariant/987654321",
                        "title": "Default Title",
                        "availableForSale": True,
                        "price": {
                            "amount": "34.99",
                            "currencyCode": "USD",
                        },
                        "sku": "GT-SET-001",
                    }
                }
            ]
        },
    }
    for key, value in overrides.items():
        if isinstance(value, dict) and key in data and isinstance(data[key], dict):
            data[key].update(value)
        else:
            data[key] = value
    return data


def _sample_shopify_response(products: list[dict] | None = None) -> dict:
    """Create a sample Shopify Storefront API GraphQL response."""
    if products is None:
        products = [_sample_shopify_product()]
    return {
        "data": {
            "products": {
                "edges": [{"node": p} for p in products],
            }
        }
    }


def _sample_shopify_empty_response() -> dict:
    """Create an empty Shopify Storefront API response."""
    return {
        "data": {
            "products": {
                "edges": [],
            }
        }
    }


def _sample_shopify_error_response() -> dict:
    """Create a Shopify GraphQL error response."""
    return {
        "errors": [
            {
                "message": "Throttled",
                "extensions": {
                    "code": "THROTTLED",
                }
            }
        ]
    }


# ======================================================================
# TestShopifyCategoryMapping
# ======================================================================

class TestShopifyCategoryMapping:
    """Test interest-to-Shopify product type keyword mappings."""

    ALL_INTERESTS = [
        "Travel", "Cooking", "Movies", "Music", "Reading", "Sports", "Gaming",
        "Art", "Photography", "Fitness", "Fashion", "Technology", "Nature",
        "Food", "Coffee", "Wine", "Dancing", "Theater", "Concerts", "Museums",
        "Shopping", "Yoga", "Hiking", "Beach", "Pets", "Cars", "DIY",
        "Gardening", "Meditation", "Podcasts", "Baking", "Camping", "Cycling",
        "Running", "Swimming", "Skiing", "Surfing", "Painting", "Board Games",
        "Karaoke",
    ]

    def test_all_interests_have_keywords(self):
        """Every predefined interest should map to Shopify search keywords."""
        for interest in self.ALL_INTERESTS:
            keywords = INTEREST_TO_SHOPIFY_PRODUCT_TYPE.get(interest)
            assert keywords is not None, f"Interest '{interest}' has no Shopify keywords"

    def test_all_keywords_are_strings(self):
        """All mapped keywords should be non-empty strings."""
        for interest, keywords in INTEREST_TO_SHOPIFY_PRODUCT_TYPE.items():
            assert isinstance(keywords, str), f"Keywords for '{interest}' is not a string"
            assert len(keywords) > 0, f"Empty keywords for '{interest}'"

    def test_mapping_covers_all_40_interests(self):
        """Should have mappings for all 40 predefined interests."""
        assert len(INTEREST_TO_SHOPIFY_PRODUCT_TYPE) == 40

    def test_no_unexpected_interests(self):
        """INTEREST_TO_SHOPIFY_PRODUCT_TYPE should only contain known interests."""
        for interest in INTEREST_TO_SHOPIFY_PRODUCT_TYPE:
            assert interest in self.ALL_INTERESTS, f"Unexpected interest '{interest}' in mapping"

    def test_common_interest_mappings(self):
        """Spot-check that key interests map to logical search keywords."""
        assert "cooking" in INTEREST_TO_SHOPIFY_PRODUCT_TYPE["Cooking"].lower()
        assert "book" in INTEREST_TO_SHOPIFY_PRODUCT_TYPE["Reading"].lower()
        assert "gaming" in INTEREST_TO_SHOPIFY_PRODUCT_TYPE["Gaming"].lower()
        assert "garden" in INTEREST_TO_SHOPIFY_PRODUCT_TYPE["Gardening"].lower()
        assert "pet" in INTEREST_TO_SHOPIFY_PRODUCT_TYPE["Pets"].lower()


# ======================================================================
# TestShopifyProductNormalization
# ======================================================================

class TestShopifyProductNormalization:
    """Test conversion of Shopify product JSON to CandidateRecommendation format."""

    def test_basic_normalization(self):
        """Should normalize a standard Shopify product."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product, interest="Gardening")

        assert result["source"] == "shopify"
        assert result["type"] == "gift"
        assert result["title"] == "Premium Gardening Tool Set"
        assert result["merchant_name"] == "GardenPro"
        assert result["currency"] == "USD"
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36  # UUID format

    def test_price_extraction_in_cents(self):
        """Should convert dollar string amount to cents."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["price_cents"] == 3499  # "34.99" → 3499 cents

    def test_price_with_whole_dollars(self):
        """Should handle whole-dollar prices."""
        product = _sample_shopify_product()
        product["variants"]["edges"][0]["node"]["price"]["amount"] = "25.00"
        result = ShopifyService._normalize_product(product)
        assert result["price_cents"] == 2500

    def test_missing_price_returns_none(self):
        """Should return None for price_cents when no variants exist."""
        product = _sample_shopify_product()
        product["variants"] = {"edges": []}
        result = ShopifyService._normalize_product(product)
        assert result["price_cents"] is None

    def test_missing_variant_price_returns_none(self):
        """Should return None when variant has no price data."""
        product = _sample_shopify_product()
        product["variants"]["edges"][0]["node"]["price"] = {}
        result = ShopifyService._normalize_product(product)
        assert result["price_cents"] is None

    def test_image_url_extracted(self):
        """Should extract the first image URL."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["image_url"] == "https://cdn.shopify.com/s/files/example.jpg"

    def test_missing_images_returns_none(self):
        """Should return None when no images are available."""
        product = _sample_shopify_product()
        product["images"] = {"edges": []}
        result = ShopifyService._normalize_product(product)
        assert result["image_url"] is None

    def test_description_extracted(self):
        """Should extract product description."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert "stainless steel garden tool set" in result["description"]

    def test_long_description_truncated(self):
        """Should truncate very long descriptions to 300 chars."""
        product = _sample_shopify_product()
        product["description"] = "A" * 500
        result = ShopifyService._normalize_product(product)
        assert len(result["description"]) == 300
        assert result["description"].endswith("...")

    def test_missing_description_returns_none(self):
        """Should return None when no description exists."""
        product = _sample_shopify_product()
        product["description"] = None
        result = ShopifyService._normalize_product(product)
        assert result["description"] is None

    def test_vendor_as_merchant_name(self):
        """Should use vendor as merchant_name."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["merchant_name"] == "GardenPro"

    def test_missing_vendor_returns_none(self):
        """Should return None when vendor is missing."""
        product = _sample_shopify_product()
        product["vendor"] = None
        result = ShopifyService._normalize_product(product)
        assert result["merchant_name"] is None

    def test_location_is_none(self):
        """Shopify products should have no location (they're shipped)."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["location"] is None

    def test_online_store_url_used(self):
        """Should use onlineStoreUrl as external_url."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert "premium-gardening-tool-set" in result["external_url"]

    def test_handle_fallback_url(self):
        """Should build URL from handle when onlineStoreUrl is missing."""
        product = _sample_shopify_product()
        product["onlineStoreUrl"] = ""
        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN):
            result = ShopifyService._normalize_product(product)
        assert f"https://{TEST_STORE_DOMAIN}/products/premium-gardening-tool-set" == result["external_url"]

    def test_metadata_includes_shopify_id(self):
        """Should include Shopify product ID in metadata."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["metadata"]["shopify_id"] == "gid://shopify/Product/123456789"

    def test_metadata_includes_handle(self):
        """Should include product handle in metadata."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["metadata"]["handle"] == "premium-gardening-tool-set"

    def test_metadata_includes_product_type(self):
        """Should include product type in metadata."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["metadata"]["product_type"] == "Garden Tools"

    def test_metadata_includes_sku(self):
        """Should include SKU in metadata."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["metadata"]["sku"] == "GT-SET-001"

    def test_metadata_includes_matched_interest(self):
        """Should include matched_interest in metadata when provided."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product, interest="Gardening")
        assert result["metadata"]["matched_interest"] == "Gardening"

    def test_metadata_no_interest_when_not_provided(self):
        """Should not include matched_interest when interest is None."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product, interest=None)
        assert "matched_interest" not in result["metadata"]

    def test_missing_title_defaults_to_unknown(self):
        """Missing title should default to 'Unknown Product'."""
        product = _sample_shopify_product()
        product["title"] = None
        result = ShopifyService._normalize_product(product)
        assert result["title"] == "Unknown Product"

    def test_currency_from_variant(self):
        """Should use currencyCode from the variant price."""
        product = _sample_shopify_product()
        product["variants"]["edges"][0]["node"]["price"]["currencyCode"] = "GBP"
        result = ShopifyService._normalize_product(product)
        assert result["currency"] == "GBP"

    def test_all_products_typed_as_gift(self):
        """All Shopify products should be typed as 'gift'."""
        product = _sample_shopify_product()
        result = ShopifyService._normalize_product(product)
        assert result["type"] == "gift"

    def test_unavailable_product_flagged(self):
        """Should flag unavailable products via _available field."""
        product = _sample_shopify_product()
        product["variants"]["edges"][0]["node"]["availableForSale"] = False
        result = ShopifyService._normalize_product(product)
        assert result["_available"] is False


# ======================================================================
# TestDollarsToCents
# ======================================================================

class TestDollarsToCents:
    """Test the _dollars_to_cents helper function."""

    def test_basic_conversion(self):
        """Should convert '34.99' to 3499."""
        assert _dollars_to_cents("34.99") == 3499

    def test_whole_dollars(self):
        """Should convert '25.00' to 2500."""
        assert _dollars_to_cents("25.00") == 2500

    def test_single_cent(self):
        """Should convert '0.01' to 1."""
        assert _dollars_to_cents("0.01") == 1

    def test_large_amount(self):
        """Should convert '999.99' to 99999."""
        assert _dollars_to_cents("999.99") == 99999

    def test_zero(self):
        """Should convert '0.00' to 0."""
        assert _dollars_to_cents("0.00") == 0

    def test_none_returns_none(self):
        """Should return None for None input."""
        assert _dollars_to_cents(None) is None

    def test_empty_string_returns_none(self):
        """Should return None for empty string."""
        assert _dollars_to_cents("") is None

    def test_invalid_string_returns_none(self):
        """Should return None for non-numeric string."""
        assert _dollars_to_cents("not-a-number") is None

    def test_integer_string(self):
        """Should handle integer string without decimal."""
        assert _dollars_to_cents("50") == 5000

    def test_rounding(self):
        """Should handle floating point precision via rounding."""
        # 19.99 * 100 = 1998.9999... in floating point
        assert _dollars_to_cents("19.99") == 1999


# ======================================================================
# TestStorefrontUrl
# ======================================================================

class TestStorefrontUrl:
    """Test the _build_storefront_url helper function."""

    def test_basic_domain(self):
        """Should build URL from bare domain."""
        url = _build_storefront_url("my-store.myshopify.com")
        assert url == f"https://my-store.myshopify.com/api/{API_VERSION}/graphql.json"

    def test_domain_with_https(self):
        """Should strip https:// prefix."""
        url = _build_storefront_url("https://my-store.myshopify.com")
        assert url == f"https://my-store.myshopify.com/api/{API_VERSION}/graphql.json"

    def test_domain_with_http(self):
        """Should strip http:// prefix and use https."""
        url = _build_storefront_url("http://my-store.myshopify.com")
        assert url == f"https://my-store.myshopify.com/api/{API_VERSION}/graphql.json"

    def test_domain_with_trailing_slash(self):
        """Should strip trailing slash."""
        url = _build_storefront_url("my-store.myshopify.com/")
        assert url == f"https://my-store.myshopify.com/api/{API_VERSION}/graphql.json"

    def test_domain_with_whitespace(self):
        """Should strip whitespace."""
        url = _build_storefront_url("  my-store.myshopify.com  ")
        assert url == f"https://my-store.myshopify.com/api/{API_VERSION}/graphql.json"


# ======================================================================
# TestShopifyGraphQL
# ======================================================================

class TestShopifyGraphQL:
    """Test GraphQL query construction and request format."""

    async def test_sends_graphql_query(self):
        """Should send the GraphQL query with correct variables."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response([]),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            await service.search_products(keywords="gardening gifts", limit=5)

        call_kwargs = mock_client.post.call_args
        json_body = call_kwargs.kwargs.get("json") or call_kwargs[1].get("json")
        assert json_body["query"] == PRODUCTS_SEARCH_QUERY
        assert json_body["variables"]["query"] == "gardening gifts"
        assert json_body["variables"]["first"] == 5

    async def test_storefront_access_token_header(self):
        """Should send the Storefront Access Token in the header."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response([]),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            await service.search_products(keywords="gifts")

        call_kwargs = mock_client.post.call_args
        headers = call_kwargs.kwargs.get("headers") or call_kwargs[1].get("headers")
        assert headers["X-Shopify-Storefront-Access-Token"] == TEST_STOREFRONT_TOKEN
        assert headers["Content-Type"] == "application/json"

    async def test_posts_to_correct_endpoint(self):
        """Should POST to the Shopify Storefront API GraphQL endpoint."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response([]),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            await service.search_products(keywords="gifts")

        call_args = mock_client.post.call_args
        url = call_args[0][0] if call_args[0] else call_args.kwargs.get("url", "")
        assert url == TEST_API_URL

    async def test_caps_limit_at_max(self):
        """Should cap limit at MAX_PRODUCTS_PER_QUERY."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response([]),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            await service.search_products(keywords="gifts", limit=100)

        call_kwargs = mock_client.post.call_args
        json_body = call_kwargs.kwargs.get("json") or call_kwargs[1].get("json")
        assert json_body["variables"]["first"] == MAX_PRODUCTS_PER_QUERY

    async def test_graphql_error_returns_empty(self):
        """Should return empty list when Shopify returns GraphQL errors."""
        error_response = httpx.Response(
            200,
            json=_sample_shopify_error_response(),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=error_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []


# ======================================================================
# TestShopifyRateLimiting
# ======================================================================

class TestShopifyRateLimiting:
    """Test rate limiting with exponential backoff."""

    async def test_retries_on_429_then_succeeds(self):
        """Should retry on 429 and return results when the retry succeeds."""
        rate_limit_response = httpx.Response(
            429, request=httpx.Request("POST", TEST_API_URL)
        )
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(side_effect=[rate_limit_response, success_response])
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = ShopifyService()
            results = await service.search_products(keywords="gardening gifts")

        assert len(results) == 1
        assert results[0]["title"] == "Premium Gardening Tool Set"
        assert mock_client.post.call_count == 2

    async def test_exhausts_retries_on_repeated_429(self):
        """Should return empty list after exhausting all retries on 429."""
        rate_limit_response = httpx.Response(
            429, request=httpx.Request("POST", TEST_API_URL)
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=rate_limit_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []
        assert mock_client.post.call_count == MAX_RETRIES


# ======================================================================
# TestShopifyErrorHandling
# ======================================================================

class TestShopifyErrorHandling:
    """Test graceful error handling for various failure modes."""

    async def test_timeout_returns_empty(self):
        """Should return empty list on timeout after retries."""
        mock_client = AsyncMock()
        mock_client.post = AsyncMock(side_effect=httpx.TimeoutException("timeout"))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_http_error_returns_empty(self):
        """Should return empty list on HTTP 500 error."""
        error_response = httpx.Response(
            500,
            text="Internal Server Error",
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=error_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_missing_credentials_returns_empty(self):
        """Should return empty list when Shopify credentials are not configured."""
        with patch("app.services.integrations.shopify.is_shopify_configured", return_value=False):
            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []

    async def test_empty_keywords_returns_empty(self):
        """Should return empty list for empty keywords."""
        with patch("app.services.integrations.shopify.is_shopify_configured", return_value=True):
            service = ShopifyService()
            results = await service.search_products(keywords="")

        assert results == []

    async def test_whitespace_keywords_returns_empty(self):
        """Should return empty list for whitespace-only keywords."""
        with patch("app.services.integrations.shopify.is_shopify_configured", return_value=True):
            service = ShopifyService()
            results = await service.search_products(keywords="   ")

        assert results == []

    async def test_empty_response_returns_empty(self):
        """Should return empty list when Shopify returns no products."""
        empty_response = httpx.Response(
            200,
            json=_sample_shopify_empty_response(),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=empty_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
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

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert results == []


# ======================================================================
# TestShopifySearchWithMock
# ======================================================================

class TestShopifySearchWithMock:
    """Test the full search_products method with mocked HTTP."""

    async def test_normalizes_multiple_products(self):
        """Should normalize all products in the response."""
        products = [
            _sample_shopify_product(),
            _sample_shopify_product(
                id="gid://shopify/Product/987654321",
                title="Cooking Apron Set",
                handle="cooking-apron-set",
                vendor="ChefWear",
                productType="Kitchen",
                onlineStoreUrl=f"https://{TEST_STORE_DOMAIN}/products/cooking-apron-set",
            ),
        ]
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(products),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert len(results) == 2
        assert results[0]["title"] == "Premium Gardening Tool Set"
        assert results[1]["title"] == "Cooking Apron Set"
        assert all(r["source"] == "shopify" for r in results)
        assert all(r["type"] == "gift" for r in results)

    async def test_filters_unavailable_products(self):
        """Should exclude products not available for sale."""
        available_product = _sample_shopify_product()
        unavailable_product = _sample_shopify_product(
            id="gid://shopify/Product/111",
            title="Sold Out Item",
        )
        unavailable_product["variants"]["edges"][0]["node"]["availableForSale"] = False

        products = [available_product, unavailable_product]
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(products),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert len(results) == 1
        assert results[0]["title"] == "Premium Gardening Tool Set"

    async def test_client_side_price_filtering(self):
        """Should filter out products outside the price range."""
        expensive_product = _sample_shopify_product()
        expensive_product["variants"]["edges"][0]["node"]["price"]["amount"] = "99.99"

        cheap_product = _sample_shopify_product(
            id="gid://shopify/Product/222",
            title="Budget Gift",
        )
        cheap_product["variants"]["edges"][0]["node"]["price"]["amount"] = "15.00"

        products = [expensive_product, cheap_product]
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(products),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(
                keywords="gifts",
                price_range=(0, 5000),  # Max $50
            )

        assert len(results) == 1
        assert results[0]["title"] == "Budget Gift"
        assert results[0]["price_cents"] == 1500

    async def test_interest_passed_to_metadata(self):
        """Should pass interest to metadata via normalization."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(
                keywords="gardening gifts",
                interest="Gardening",
            )

        assert len(results) == 1
        assert results[0]["metadata"]["matched_interest"] == "Gardening"

    async def test_no_available_field_in_output(self):
        """The internal _available field should be stripped from results."""
        success_response = httpx.Response(
            200,
            json=_sample_shopify_response(),
            request=httpx.Request("POST", TEST_API_URL),
        )

        mock_client = AsyncMock()
        mock_client.post = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.shopify.SHOPIFY_STORE_DOMAIN", TEST_STORE_DOMAIN), \
             patch("app.services.integrations.shopify.SHOPIFY_STOREFRONT_TOKEN", TEST_STOREFRONT_TOKEN), \
             patch("app.services.integrations.shopify.is_shopify_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = ShopifyService()
            results = await service.search_products(keywords="gifts")

        assert len(results) == 1
        assert "_available" not in results[0]


# ======================================================================
# TestShopifySearchIntegration (requires real API credentials)
# ======================================================================

@requires_shopify
class TestShopifySearchIntegration:
    """Integration tests with real Shopify Storefront API. Skipped without credentials."""

    async def test_search_products(self):
        """Should return products from a real Shopify store."""
        service = ShopifyService()
        results = await service.search_products(
            keywords="gift",
            limit=5,
        )

        assert len(results) > 0
        for product in results:
            assert product["source"] == "shopify"
            assert product["type"] == "gift"
            assert product["title"]
            assert product["external_url"]
            assert isinstance(product["id"], str)

    async def test_price_in_results(self):
        """Should include price data in product results."""
        service = ShopifyService()
        results = await service.search_products(
            keywords="shirt",
            limit=3,
        )

        assert len(results) > 0
        for product in results:
            if product["price_cents"] is not None:
                assert product["price_cents"] > 0
                assert isinstance(product["currency"], str)

    async def test_empty_results_graceful(self):
        """Should return empty list for very specific unlikely search."""
        service = ShopifyService()
        results = await service.search_products(
            keywords="xyznonexistentproduct12345678",
        )

        assert isinstance(results, list)


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_shopify_service_importable(self):
        """ShopifyService class should be importable."""
        assert ShopifyService is not None

    def test_category_mapping_importable(self):
        """INTEREST_TO_SHOPIFY_PRODUCT_TYPE should be importable."""
        assert isinstance(INTEREST_TO_SHOPIFY_PRODUCT_TYPE, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(API_VERSION, str)
        assert isinstance(DEFAULT_TIMEOUT, float)
        assert isinstance(MAX_RETRIES, int)
        assert isinstance(MAX_PRODUCTS_PER_QUERY, int)

    def test_graphql_query_importable(self):
        """PRODUCTS_SEARCH_QUERY should be importable."""
        assert isinstance(PRODUCTS_SEARCH_QUERY, str)
        assert "products" in PRODUCTS_SEARCH_QUERY

    def test_helper_functions_importable(self):
        """Helper functions should be importable."""
        assert callable(_build_storefront_url)
        assert callable(_dollars_to_cents)

    def test_config_functions_importable(self):
        """Config functions should be importable."""
        from app.core.config import is_shopify_configured, validate_shopify_config
        assert callable(is_shopify_configured)
        assert callable(validate_shopify_config)
