"""
Shopify Storefront API Integration — Search products for gift recommendations.

Queries the Shopify Storefront API (GraphQL) to find gift products from partner
Shopify stores matching the partner's interests, budget, and preferences.
Normalizes results into the CandidateRecommendation schema used by the LangGraph
pipeline.

Uses the Storefront Access Token for authentication (X-Shopify-Storefront-Access-Token
header). Handles rate limiting with exponential backoff on HTTP 429 responses. Shopify
Storefront API uses a cost-based throttle (bucket-based), so 429s are the main
rate-limit signal.

Step 8.4: Implement Shopify Storefront API Integration
"""

import asyncio
import logging
import uuid
from typing import Any, Optional

import httpx

from app.core.config import (
    SHOPIFY_STORE_DOMAIN,
    SHOPIFY_STOREFRONT_TOKEN,
    is_shopify_configured,
)

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

# Shopify Storefront API endpoint — domain is configurable per store
API_VERSION = "2025-01"
DEFAULT_TIMEOUT = 10.0  # seconds
MAX_RETRIES = 3
MAX_PRODUCTS_PER_QUERY = 20  # Shopify Storefront API max per page

# GraphQL query template for product search
PRODUCTS_SEARCH_QUERY = """
query searchProducts($query: String!, $first: Int!) {
  products(query: $query, first: $first) {
    edges {
      node {
        id
        title
        handle
        description
        vendor
        productType
        onlineStoreUrl
        images(first: 1) {
          edges {
            node {
              url
              altText
            }
          }
        }
        variants(first: 1) {
          edges {
            node {
              id
              title
              availableForSale
              price {
                amount
                currencyCode
              }
              sku
            }
          }
        }
      }
    }
  }
}
"""

# Map partner interest categories to Shopify product search keywords.
# These are used to build the GraphQL `query` string for product search.
INTEREST_TO_SHOPIFY_PRODUCT_TYPE: dict[str, str] = {
    "Travel": "travel luggage bag",
    "Cooking": "cooking kitchen utensils",
    "Movies": "movie film poster collectible",
    "Music": "music vinyl record headphones",
    "Reading": "book reading bookmark",
    "Sports": "sports fan gear jersey",
    "Gaming": "gaming controller accessories",
    "Art": "art supplies canvas paint",
    "Photography": "photography camera accessories",
    "Fitness": "fitness workout gym equipment",
    "Fashion": "fashion jewelry accessories",
    "Technology": "tech gadgets electronics",
    "Nature": "nature outdoor decor plant",
    "Food": "gourmet food gift basket",
    "Coffee": "coffee beans grinder mug",
    "Wine": "wine glass decanter accessories",
    "Dancing": "dance shoes accessories",
    "Theater": "theater playbill drama",
    "Concerts": "concert merch music band",
    "Museums": "art print museum replica",
    "Shopping": "gift card fashion accessories",
    "Yoga": "yoga mat accessories wellness",
    "Hiking": "hiking gear outdoor boots",
    "Beach": "beach towel sunglasses accessories",
    "Pets": "pet supplies toys treats",
    "Cars": "automotive car accessories detailing",
    "DIY": "diy tools craft supplies",
    "Gardening": "gardening tools planters seeds",
    "Meditation": "meditation cushion wellness candle",
    "Podcasts": "podcast microphone headphones",
    "Baking": "baking supplies tools kit",
    "Camping": "camping gear outdoor tent",
    "Cycling": "cycling bike accessories helmet",
    "Running": "running shoes gear watch",
    "Swimming": "swimming goggles accessories",
    "Skiing": "skiing gear accessories gloves",
    "Surfing": "surfing board accessories",
    "Painting": "painting supplies easel brushes",
    "Board Games": "board games tabletop puzzles",
    "Karaoke": "karaoke microphone speaker",
}


def _build_storefront_url(domain: str) -> str:
    """
    Build the Shopify Storefront API GraphQL endpoint URL.

    Args:
        domain: Shopify store domain (e.g., "my-store.myshopify.com").

    Returns:
        Full GraphQL endpoint URL.
    """
    # Strip protocol if present
    clean = domain.strip().rstrip("/")
    if clean.startswith("https://"):
        clean = clean[len("https://"):]
    elif clean.startswith("http://"):
        clean = clean[len("http://"):]
    return f"https://{clean}/api/{API_VERSION}/graphql.json"


def _dollars_to_cents(amount_str: str) -> Optional[int]:
    """
    Convert a dollar amount string (e.g., "34.99") to integer cents.

    Returns None if the amount cannot be parsed.
    """
    if not amount_str:
        return None
    try:
        amount = float(amount_str)
        return int(round(amount * 100))
    except (ValueError, TypeError):
        return None


# ======================================================================
# ShopifyService
# ======================================================================

class ShopifyService:
    """Async service for Shopify Storefront API product search."""

    async def search_products(
        self,
        keywords: str,
        interest: Optional[str] = None,
        price_range: Optional[tuple[int, int]] = None,
        limit: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Search Shopify products by keywords and filters.

        Args:
            keywords: Search keywords (e.g., "gardening gifts").
            interest: The partner interest category this search is for.
                      Stored in metadata for downstream matching.
            price_range: Budget in cents as (min_cents, max_cents).
            limit: Max results (default 10, capped at MAX_PRODUCTS_PER_QUERY).

        Returns:
            List of normalized product dicts matching CandidateRecommendation schema.
            Returns [] on any error (missing credentials, timeout, etc.).
        """
        if not is_shopify_configured():
            logger.warning("Shopify Storefront API not configured — skipping Shopify search")
            return []

        if not keywords or not keywords.strip():
            logger.warning("Empty keywords provided — skipping Shopify search")
            return []

        # Build GraphQL variables
        effective_limit = min(limit, MAX_PRODUCTS_PER_QUERY)
        variables = {
            "query": keywords.strip(),
            "first": effective_limit,
        }

        # Make GraphQL request
        data = await self._make_request(PRODUCTS_SEARCH_QUERY, variables)
        edges = data.get("data", {}).get("products", {}).get("edges", [])

        # Normalize and filter results
        results = []
        for edge in edges:
            node = edge.get("node", {})
            normalized = self._normalize_product(node, interest)

            # Skip products not available for sale
            if not normalized.get("_available", True):
                continue

            # Apply client-side price filter
            if price_range and normalized["price_cents"] is not None:
                if normalized["price_cents"] < price_range[0] or normalized["price_cents"] > price_range[1]:
                    continue

            # Remove internal field before returning
            normalized.pop("_available", None)
            results.append(normalized)

        return results

    async def _make_request(
        self,
        query: str,
        variables: dict[str, Any],
    ) -> dict[str, Any]:
        """
        Make authenticated GraphQL POST request to the Shopify Storefront API.

        Retries on HTTP 429 with exponential backoff. Returns empty dict on error.
        """
        url = _build_storefront_url(SHOPIFY_STORE_DOMAIN)
        headers = {
            "X-Shopify-Storefront-Access-Token": SHOPIFY_STOREFRONT_TOKEN,
            "Content-Type": "application/json",
        }
        payload = {
            "query": query,
            "variables": variables,
        }

        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            for retry in range(MAX_RETRIES):
                try:
                    response = await client.post(
                        url,
                        headers=headers,
                        json=payload,
                    )

                    if response.status_code == 429:
                        delay = 2**retry
                        logger.warning(
                            "Shopify Storefront API rate limited (429), retrying in %ds "
                            "(attempt %d/%d)",
                            delay, retry + 1, MAX_RETRIES,
                        )
                        await asyncio.sleep(delay)
                        continue

                    response.raise_for_status()
                    result = response.json()

                    # Check for GraphQL-level errors
                    if "errors" in result:
                        logger.error(
                            "Shopify GraphQL errors: %s",
                            result["errors"],
                        )
                        return {}

                    return result

                except httpx.TimeoutException:
                    logger.warning(
                        "Shopify Storefront API timeout (attempt %d/%d)",
                        retry + 1, MAX_RETRIES,
                    )
                    if retry < MAX_RETRIES - 1:
                        await asyncio.sleep(1)
                    continue

                except httpx.HTTPStatusError as exc:
                    logger.error(
                        "Shopify Storefront API HTTP error %d: %s",
                        exc.response.status_code, exc.response.text,
                    )
                    return {}

                except httpx.HTTPError as exc:
                    logger.error("Shopify Storefront API request error: %s", exc)
                    return {}

        logger.warning("Shopify Storefront API exhausted all %d retries", MAX_RETRIES)
        return {}

    @staticmethod
    def _normalize_product(
        product: dict[str, Any],
        interest: Optional[str] = None,
    ) -> dict[str, Any]:
        """
        Convert Shopify Storefront API product node to CandidateRecommendation-compatible dict.

        Args:
            product: Raw product node from the GraphQL response.
            interest: The partner interest category this product was searched for.

        Returns:
            Dict matching the CandidateRecommendation schema fields.
        """
        # Extract title
        title = product.get("title") or "Unknown Product"

        # Extract description (truncate to reasonable length)
        description = product.get("description")
        if description and len(description) > 300:
            description = description[:297] + "..."

        # Extract vendor as merchant name
        merchant_name = product.get("vendor")

        # Extract first variant for price and availability
        price_cents = None
        currency = "USD"
        available = True
        sku = None
        variants = product.get("variants", {}).get("edges", [])
        if variants:
            variant_node = variants[0].get("node", {})
            available = variant_node.get("availableForSale", True)
            sku = variant_node.get("sku")
            price_data = variant_node.get("price", {})
            amount_str = price_data.get("amount")
            price_cents = _dollars_to_cents(amount_str)
            currency_code = price_data.get("currencyCode")
            if currency_code:
                currency = currency_code

        # Extract first image URL
        image_url = None
        images = product.get("images", {}).get("edges", [])
        if images:
            image_node = images[0].get("node", {})
            image_url = image_node.get("url")

        # Build external URL — prefer onlineStoreUrl, fall back to handle-based URL
        external_url = product.get("onlineStoreUrl", "")
        if not external_url:
            handle = product.get("handle", "")
            if handle and SHOPIFY_STORE_DOMAIN:
                external_url = f"https://{SHOPIFY_STORE_DOMAIN}/products/{handle}"

        # Build metadata
        metadata: dict[str, Any] = {
            "shopify_id": product.get("id"),
            "handle": product.get("handle"),
            "product_type": product.get("productType"),
            "sku": sku,
        }
        if interest:
            metadata["matched_interest"] = interest

        return {
            "id": str(uuid.uuid4()),
            "source": "shopify",
            "type": "gift",
            "title": title,
            "description": description,
            "price_cents": price_cents,
            "currency": currency,
            "external_url": external_url,
            "image_url": image_url,
            "merchant_name": merchant_name,
            "location": None,
            "metadata": metadata,
            "_available": available,
        }
