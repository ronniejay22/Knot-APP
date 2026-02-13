"""
Yelp Fusion API Integration — Search businesses for experience/date recommendations.

Queries the Yelp Fusion API v3 to find restaurants, activities, and venues
matching the partner's vibes, location, and budget. Normalizes results into
the CandidateRecommendation schema used by the LangGraph pipeline.

Supports international locations (30+ countries) with automatic currency
detection based on country code. Handles rate limiting (5000 calls/day)
with exponential backoff on HTTP 429 responses.

Step 8.1: Implement Yelp Fusion API Integration
"""

import asyncio
import logging
import uuid
from typing import Any, Optional

import httpx

from app.core.config import YELP_API_KEY, is_yelp_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

BASE_URL = "https://api.yelp.com/v3"
DEFAULT_TIMEOUT = 10.0  # seconds
MAX_RETRIES = 3

# Map aesthetic vibes to Yelp category aliases
# See: https://docs.developer.yelp.com/docs/resources-categories
VIBE_TO_YELP_CATEGORIES: dict[str, list[str]] = {
    "quiet_luxury": ["wine_bars", "wineries", "spas"],
    "street_urban": ["streetart", "foodtrucks", "comedyclubs"],
    "outdoorsy": ["paddleboarding", "hot_air_balloons", "climbing"],
    "vintage": ["antiques", "vintage", "speakeasies"],
    "minimalist": ["tea", "meditation", "architecturetours"],
    "bohemian": ["pottery", "musicvenues", "artclasses"],
    "romantic": ["sailing", "cookingschools", "observatories"],
    "adventurous": ["skydiving", "rafting", "escapegames"],
}

# Country code → ISO 4217 currency code
COUNTRY_CURRENCY_MAP: dict[str, str] = {
    "US": "USD",
    "CA": "CAD",
    "GB": "GBP",
    "UK": "GBP",
    "FR": "EUR",
    "DE": "EUR",
    "IT": "EUR",
    "ES": "EUR",
    "NL": "EUR",
    "BE": "EUR",
    "AT": "EUR",
    "IE": "EUR",
    "PT": "EUR",
    "FI": "EUR",
    "GR": "EUR",
    "JP": "JPY",
    "AU": "AUD",
    "NZ": "NZD",
    "MX": "MXN",
    "BR": "BRL",
    "CH": "CHF",
    "SE": "SEK",
    "NO": "NOK",
    "DK": "DKK",
    "SG": "SGD",
    "HK": "HKD",
    "TW": "TWD",
    "KR": "KRW",
    "PH": "PHP",
    "AR": "ARS",
    "CL": "CLP",
    "PL": "PLN",
    "CZ": "CZK",
    "TR": "TRY",
    "MY": "MYR",
    "TH": "THB",
}

# Yelp price level → approximate midpoint in USD cents
YELP_PRICE_TO_CENTS: dict[str, int] = {
    "$": 1500,       # ~$15 per person
    "$$": 3000,      # ~$30 per person
    "$$$": 6000,     # ~$60 per person
    "$$$$": 12000,   # ~$120 per person
}


# ======================================================================
# YelpService
# ======================================================================

class YelpService:
    """Async service for Yelp Fusion API v3 business search."""

    async def search_businesses(
        self,
        location: tuple[str, str, str],
        categories: Optional[list[str]] = None,
        price_range: Optional[tuple[int, int]] = None,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        """
        Search Yelp businesses by location and filters.

        Args:
            location: Tuple of (city, state, country_code).
            categories: Yelp category aliases (e.g., "restaurants", "arts").
            price_range: Budget in cents as (min_cents, max_cents).
            limit: Max results (default 20, Yelp max is 50).

        Returns:
            List of normalized business dicts matching CandidateRecommendation schema.
            Returns [] on any error (missing API key, timeout, invalid location, etc.).
        """
        if not is_yelp_configured():
            logger.warning("Yelp API key not configured — skipping Yelp search")
            return []

        # Build location string
        city, state, country = location
        location_parts = [p for p in (city, state, country) if p]
        location_str = ", ".join(location_parts)

        if not location_str:
            logger.warning("Empty location provided — skipping Yelp search")
            return []

        # Build query params
        params: dict[str, Any] = {
            "location": location_str,
            "limit": min(limit, 50),
            "sort_by": "best_match",
        }

        if categories:
            params["categories"] = ",".join(categories)

        if price_range:
            price_filter = self._convert_price_range_to_yelp(
                price_range[0], price_range[1]
            )
            if price_filter:
                params["price"] = price_filter

        # Make request
        data = await self._make_request("businesses/search", params)
        businesses = data.get("businesses", [])

        # Normalize results
        country_code = country or "US"
        return [
            self._normalize_business(biz, country_code) for biz in businesses
        ]

    async def _make_request(
        self, endpoint: str, params: dict[str, Any]
    ) -> dict[str, Any]:
        """
        Make authenticated GET request to Yelp API with retry on rate limit.

        Returns parsed JSON dict. Returns {"businesses": []} on any error.
        """
        headers = {
            "Authorization": f"Bearer {YELP_API_KEY}",
            "Accept": "application/json",
        }

        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            for retry in range(MAX_RETRIES):
                try:
                    response = await client.get(
                        f"{BASE_URL}/{endpoint}",
                        headers=headers,
                        params=params,
                    )

                    if response.status_code == 429:
                        delay = 2**retry
                        logger.warning(
                            "Yelp API rate limited (429), retrying in %ds "
                            "(attempt %d/%d)",
                            delay, retry + 1, MAX_RETRIES,
                        )
                        await asyncio.sleep(delay)
                        continue

                    response.raise_for_status()
                    return response.json()

                except httpx.TimeoutException:
                    logger.warning(
                        "Yelp API timeout (attempt %d/%d)",
                        retry + 1, MAX_RETRIES,
                    )
                    if retry < MAX_RETRIES - 1:
                        await asyncio.sleep(1)
                    continue

                except httpx.HTTPStatusError as exc:
                    logger.error(
                        "Yelp API HTTP error %d: %s",
                        exc.response.status_code, exc.response.text,
                    )
                    return {"businesses": []}

                except httpx.HTTPError as exc:
                    logger.error("Yelp API request error: %s", exc)
                    return {"businesses": []}

        logger.warning("Yelp API exhausted all %d retries", MAX_RETRIES)
        return {"businesses": []}

    @staticmethod
    def _convert_price_range_to_yelp(min_cents: int, max_cents: int) -> str:
        """
        Convert budget in cents to Yelp price filter string.

        Yelp uses levels 1-4:
            1 ($)    = Under $15    → under 1500 cents
            2 ($$)   = $15-$40      → 1500-4000 cents
            3 ($$$)  = $40-$80      → 4000-8000 cents
            4 ($$$$) = Above $80    → over 8000 cents

        Returns comma-separated price levels that overlap with the budget range.
        """
        # Price level thresholds (level, min_cents, max_cents)
        levels = [
            (1, 0, 1500),
            (2, 1500, 4000),
            (3, 4000, 8000),
            (4, 8000, 100000),
        ]

        matching = []
        for level, level_min, level_max in levels:
            # Include level if budget range overlaps with level range
            if min_cents < level_max and max_cents > level_min:
                matching.append(str(level))

        return ",".join(matching) if matching else ""

    @staticmethod
    def _normalize_business(
        business: dict[str, Any], country_code: str
    ) -> dict[str, Any]:
        """
        Convert Yelp API business JSON to CandidateRecommendation-compatible dict.

        Args:
            business: Raw Yelp business object from the API response.
            country_code: ISO 3166-1 alpha-2 country code for currency detection.

        Returns:
            Dict matching the CandidateRecommendation schema fields.
        """
        # Detect currency from country
        currency = COUNTRY_CURRENCY_MAP.get(country_code.upper(), "USD")

        # Extract price estimate in cents from Yelp price level
        yelp_price = business.get("price")
        price_cents = YELP_PRICE_TO_CENTS.get(yelp_price) if yelp_price else None

        # Build category description
        categories = business.get("categories", [])
        category_names = [cat.get("title", "") for cat in categories]
        description = ", ".join(category_names) if category_names else None

        # Build location data
        biz_location = business.get("location", {})
        location_data = {
            "city": biz_location.get("city"),
            "state": biz_location.get("state"),
            "country": biz_location.get("country"),
            "address": biz_location.get("address1"),
        }

        # Determine type: restaurants/food → "date", everything else → "experience"
        category_aliases = [cat.get("alias", "") for cat in categories]
        is_date = any(
            alias in ("restaurants", "food", "bars", "wine_bars", "cocktailbars",
                       "newamerican", "italian", "french", "japanese", "sushi",
                       "seafood", "steak", "brunch", "breakfast_brunch",
                       "cookingschools", "sailing")
            for alias in category_aliases
        )
        rec_type = "date" if is_date else "experience"

        # Extract coordinates for metadata
        coordinates = business.get("coordinates", {})

        return {
            "id": str(uuid.uuid4()),
            "source": "yelp",
            "type": rec_type,
            "title": business.get("name", "Unknown Business"),
            "description": description,
            "price_cents": price_cents,
            "currency": currency,
            "external_url": business.get("url", ""),
            "image_url": business.get("image_url"),
            "merchant_name": business.get("name"),
            "location": location_data,
            "metadata": {
                "rating": business.get("rating"),
                "review_count": business.get("review_count"),
                "categories": category_aliases,
                "coordinates": {
                    "latitude": coordinates.get("latitude"),
                    "longitude": coordinates.get("longitude"),
                },
                "yelp_id": business.get("id"),
                "yelp_price": yelp_price,
            },
        }
