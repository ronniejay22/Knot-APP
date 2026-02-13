"""
Amazon Product Advertising API Integration — Search products for gift recommendations.

Queries the Amazon Product Advertising API (PA-API 5.0) to find gift products
matching the partner's interests, budget, and preferences. Normalizes results
into the CandidateRecommendation schema used by the LangGraph pipeline.

Uses HMAC-SHA256 request signing (AWS Signature Version 4 style) for
authentication. Handles rate limiting with exponential backoff on HTTP 429
and 503 responses. All product URLs include the affiliate tag for revenue
attribution.

Step 8.3: Implement Amazon Associates API Integration
"""

import asyncio
import hashlib
import hmac
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

import httpx

from app.core.config import (
    AMAZON_ACCESS_KEY,
    AMAZON_ASSOCIATE_TAG,
    AMAZON_SECRET_KEY,
    is_amazon_configured,
)

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

# PA-API 5.0 endpoint — default to US marketplace
BASE_URL = "https://webservices.amazon.com"
PAAPI_PATH = "/paapi5/searchitems"
SERVICE = "ProductAdvertisingAPI"
REGION = "us-east-1"
DEFAULT_TIMEOUT = 10.0  # seconds
MAX_RETRIES = 3

# Map partner interest categories to Amazon search indices
# See: https://webservices.amazon.com/paapi5/documentation/locale-reference.html
INTEREST_TO_AMAZON_CATEGORY: dict[str, str] = {
    "Travel": "Luggage",
    "Cooking": "Kitchen",
    "Movies": "MoviesAndTV",
    "Music": "Music",
    "Reading": "Books",
    "Sports": "SportingGoods",
    "Gaming": "VideoGames",
    "Art": "ArtsAndCrafts",
    "Photography": "Electronics",
    "Fitness": "SportingGoods",
    "Fashion": "Fashion",
    "Technology": "Electronics",
    "Nature": "GardenAndOutdoor",
    "Food": "GroceryAndGourmetFood",
    "Coffee": "GroceryAndGourmetFood",
    "Wine": "GroceryAndGourmetFood",
    "Dancing": "Music",
    "Theater": "Books",
    "Concerts": "Music",
    "Museums": "Books",
    "Shopping": "Fashion",
    "Yoga": "SportingGoods",
    "Hiking": "SportingGoods",
    "Beach": "SportingGoods",
    "Pets": "PetSupplies",
    "Cars": "Automotive",
    "DIY": "ToolsAndHomeImprovement",
    "Gardening": "GardenAndOutdoor",
    "Meditation": "HealthAndPersonalCare",
    "Podcasts": "Electronics",
    "Baking": "Kitchen",
    "Camping": "SportingGoods",
    "Cycling": "SportingGoods",
    "Running": "SportingGoods",
    "Swimming": "SportingGoods",
    "Skiing": "SportingGoods",
    "Surfing": "SportingGoods",
    "Painting": "ArtsAndCrafts",
    "Board Games": "ToysAndGames",
    "Karaoke": "Electronics",
}


# ======================================================================
# HMAC-SHA256 Signing Helpers
# ======================================================================

def _sign(key: bytes, msg: str) -> bytes:
    """Create HMAC-SHA256 signature."""
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _get_signature_key(
    secret_key: str, date_stamp: str, region: str, service: str
) -> bytes:
    """Derive the signing key for AWS Signature Version 4."""
    k_date = _sign(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, service)
    k_signing = _sign(k_service, "aws4_request")
    return k_signing


def _build_authorization_header(
    access_key: str,
    secret_key: str,
    payload: str,
    host: str,
    path: str,
    amz_date: str,
    date_stamp: str,
) -> dict[str, str]:
    """
    Build AWS Signature V4 authorization headers for PA-API 5.0.

    Returns dict of headers including Authorization, X-Amz-Date, and Content-Type.
    """
    # Canonical request components
    method = "POST"
    content_type = "application/json; charset=UTF-8"
    amz_target = "com.amazon.paapi5.v1.ProductAdvertisingAPIv1.SearchItems"

    canonical_headers = (
        f"content-encoding:amz-1.0\n"
        f"content-type:{content_type}\n"
        f"host:{host}\n"
        f"x-amz-date:{amz_date}\n"
        f"x-amz-target:{amz_target}\n"
    )
    signed_headers = "content-encoding;content-type;host;x-amz-date;x-amz-target"

    payload_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()

    canonical_request = (
        f"{method}\n"
        f"{path}\n"
        f"\n"
        f"{canonical_headers}\n"
        f"{signed_headers}\n"
        f"{payload_hash}"
    )

    # String to sign
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = f"{date_stamp}/{REGION}/{SERVICE}/aws4_request"
    string_to_sign = (
        f"{algorithm}\n"
        f"{amz_date}\n"
        f"{credential_scope}\n"
        f"{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"
    )

    # Compute signature
    signing_key = _get_signature_key(secret_key, date_stamp, REGION, SERVICE)
    signature = hmac.new(
        signing_key, string_to_sign.encode("utf-8"), hashlib.sha256
    ).hexdigest()

    # Build authorization header
    authorization = (
        f"{algorithm} "
        f"Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, "
        f"Signature={signature}"
    )

    return {
        "Authorization": authorization,
        "Content-Encoding": "amz-1.0",
        "Content-Type": content_type,
        "Host": host,
        "X-Amz-Date": amz_date,
        "X-Amz-Target": amz_target,
    }


def _build_affiliate_url(url: str, tag: str) -> str:
    """
    Ensure the affiliate tag is present in an Amazon product URL.

    If the URL already contains the tag parameter, it is left unchanged.
    Otherwise, the tag is appended as a query parameter.
    """
    if not url:
        return url
    if not tag:
        return url

    if f"tag={tag}" in url:
        return url

    separator = "&" if "?" in url else "?"
    return f"{url}{separator}tag={tag}"


# ======================================================================
# AmazonService
# ======================================================================

class AmazonService:
    """Async service for Amazon Product Advertising API v5 product search."""

    async def search_products(
        self,
        keywords: str,
        category: Optional[str] = None,
        price_range: Optional[tuple[int, int]] = None,
        limit: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Search Amazon products by keywords and filters.

        Args:
            keywords: Search keywords (e.g., "gardening gifts").
            category: Amazon search index (e.g., "GardenAndOutdoor").
                      If not provided, defaults to "All".
            price_range: Budget in cents as (min_cents, max_cents).
            limit: Max results (default 10, PA-API max is 10 per request).

        Returns:
            List of normalized product dicts matching CandidateRecommendation schema.
            Returns [] on any error (missing credentials, timeout, etc.).
        """
        if not is_amazon_configured():
            logger.warning("Amazon API credentials not configured — skipping Amazon search")
            return []

        if not keywords or not keywords.strip():
            logger.warning("Empty keywords provided — skipping Amazon search")
            return []

        # Build PA-API request payload
        search_index = category or "All"
        payload = {
            "Keywords": keywords.strip(),
            "SearchIndex": search_index,
            "ItemCount": min(limit, 10),
            "PartnerTag": AMAZON_ASSOCIATE_TAG,
            "PartnerType": "Associates",
            "Marketplace": "www.amazon.com",
            "Resources": [
                "ItemInfo.Title",
                "ItemInfo.Features",
                "ItemInfo.ByLineInfo",
                "Offers.Listings.Price",
                "Images.Primary.Large",
                "BrowseNodeInfo.BrowseNodes",
            ],
        }

        # Add price filter if specified (PA-API accepts cents)
        if price_range:
            min_cents, max_cents = price_range
            if min_cents > 0:
                payload["MinPrice"] = min_cents  # PA-API accepts cents
            if max_cents > 0:
                payload["MaxPrice"] = max_cents  # PA-API accepts cents

        # Make signed request
        data = await self._make_request(payload)
        items = data.get("SearchResult", {}).get("Items", [])

        # Normalize results
        results = []
        for item in items:
            normalized = self._normalize_product(item)
            # Apply client-side price filter for results without price data
            if price_range and normalized["price_cents"] is not None:
                if normalized["price_cents"] < price_range[0] or normalized["price_cents"] > price_range[1]:
                    continue
            results.append(normalized)

        return results

    async def _make_request(
        self, payload: dict[str, Any]
    ) -> dict[str, Any]:
        """
        Make HMAC-SHA256 signed POST request to PA-API 5.0 with retry on rate limit.

        Returns parsed JSON dict. Returns empty response on any error.
        """
        host = "webservices.amazon.com"
        payload_str = json.dumps(payload)

        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            for retry in range(MAX_RETRIES):
                try:
                    # Generate fresh timestamp for each attempt
                    now = datetime.now(timezone.utc)
                    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
                    date_stamp = now.strftime("%Y%m%d")

                    headers = _build_authorization_header(
                        access_key=AMAZON_ACCESS_KEY,
                        secret_key=AMAZON_SECRET_KEY,
                        payload=payload_str,
                        host=host,
                        path=PAAPI_PATH,
                        amz_date=amz_date,
                        date_stamp=date_stamp,
                    )

                    response = await client.post(
                        f"{BASE_URL}{PAAPI_PATH}",
                        headers=headers,
                        content=payload_str,
                    )

                    if response.status_code in (429, 503):
                        delay = 2**retry
                        logger.warning(
                            "Amazon PA-API rate limited (%d), retrying in %ds "
                            "(attempt %d/%d)",
                            response.status_code, delay, retry + 1, MAX_RETRIES,
                        )
                        await asyncio.sleep(delay)
                        continue

                    response.raise_for_status()
                    return response.json()

                except httpx.TimeoutException:
                    logger.warning(
                        "Amazon PA-API timeout (attempt %d/%d)",
                        retry + 1, MAX_RETRIES,
                    )
                    if retry < MAX_RETRIES - 1:
                        await asyncio.sleep(1)
                    continue

                except httpx.HTTPStatusError as exc:
                    logger.error(
                        "Amazon PA-API HTTP error %d: %s",
                        exc.response.status_code, exc.response.text,
                    )
                    return {}

                except httpx.HTTPError as exc:
                    logger.error("Amazon PA-API request error: %s", exc)
                    return {}

        logger.warning("Amazon PA-API exhausted all %d retries", MAX_RETRIES)
        return {}

    @staticmethod
    def _normalize_product(item: dict[str, Any]) -> dict[str, Any]:
        """
        Convert PA-API 5.0 item JSON to CandidateRecommendation-compatible dict.

        Args:
            item: Raw Amazon product item from the SearchItems response.

        Returns:
            Dict matching the CandidateRecommendation schema fields.
        """
        # Extract title
        item_info = item.get("ItemInfo", {})
        title_info = item_info.get("Title", {})
        title = title_info.get("DisplayValue", "Unknown Product")

        # Extract price
        price_cents = None
        currency = "USD"
        offers = item.get("Offers", {})
        listings = offers.get("Listings", [])
        if listings:
            price_info = listings[0].get("Price", {})
            # PA-API returns price as a float in the local currency
            amount = price_info.get("Amount")
            if amount is not None:
                price_cents = int(float(amount) * 100)
            price_currency = price_info.get("Currency")
            if price_currency:
                currency = price_currency

        # Extract image URL
        images = item.get("Images", {})
        primary = images.get("Primary", {})
        large = primary.get("Large", {})
        image_url = large.get("URL")

        # Build product URL with affiliate tag
        detail_url = item.get("DetailPageURL", "")
        affiliate_url = _build_affiliate_url(detail_url, AMAZON_ASSOCIATE_TAG)

        # Extract brand/manufacturer for merchant_name
        by_line = item_info.get("ByLineInfo", {})
        brand = by_line.get("Brand", {})
        merchant_name = brand.get("DisplayValue")
        if not merchant_name:
            # Fallback to manufacturer
            manufacturer = by_line.get("Manufacturer", {})
            merchant_name = manufacturer.get("DisplayValue")

        # Extract features for description
        features = item_info.get("Features", {})
        feature_list = features.get("DisplayValues", [])
        description = feature_list[0] if feature_list else None

        # Extract browse node (category) for metadata
        browse_info = item.get("BrowseNodeInfo", {})
        browse_nodes = browse_info.get("BrowseNodes", [])
        category_name = None
        if browse_nodes:
            category_name = browse_nodes[0].get("DisplayName")

        return {
            "id": str(uuid.uuid4()),
            "source": "amazon",
            "type": "gift",
            "title": title,
            "description": description,
            "price_cents": price_cents,
            "currency": currency,
            "external_url": affiliate_url,
            "image_url": image_url,
            "merchant_name": merchant_name,
            "location": None,
            "metadata": {
                "asin": item.get("ASIN"),
                "brand": brand.get("DisplayValue"),
                "category": category_name,
                "features": feature_list[:3] if feature_list else [],
                "affiliate_tag": AMAZON_ASSOCIATE_TAG,
            },
        }
