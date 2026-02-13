"""
Ticketmaster Discovery API Integration — Search events for experience recommendations.

Queries the Ticketmaster Discovery API v2 to find concerts, theater, sports,
and other live events matching the partner's interests, location, and budget.
Normalizes results into the CandidateRecommendation schema used by the
LangGraph pipeline.

Supports international locations via country code parameter. Handles rate
limiting (5 calls/second) with exponential backoff on HTTP 429 responses.
Only returns events with available tickets (onsale status).

Step 8.2: Implement Ticketmaster API Integration
"""

import asyncio
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import httpx

from app.core.config import TICKETMASTER_API_KEY, is_ticketmaster_configured
from app.services.integrations.yelp import COUNTRY_CURRENCY_MAP

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

BASE_URL = "https://app.ticketmaster.com/discovery/v2"
DEFAULT_TIMEOUT = 10.0  # seconds
MAX_RETRIES = 3
DEFAULT_DATE_RANGE_DAYS = 30  # default to next 30 days

# Map partner interest categories to Ticketmaster genre IDs
# See: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/#search-classifications-v2
INTEREST_TO_TM_GENRE: dict[str, dict[str, str]] = {
    "Concerts": {"name": "Music", "genreId": "KnvZfZ7vAeA"},
    "Music": {"name": "Music", "genreId": "KnvZfZ7vAeA"},
    "Theater": {"name": "Arts & Theatre", "genreId": "KnvZfZ7v7l1"},
    "Sports": {"name": "Sports", "genreId": "KnvZfZ7vAdE"},
    "Comedy": {"name": "Comedy", "genreId": "KnvZfZ7vAe1"},
    "Dancing": {"name": "Dance/Electronic", "genreId": "KnvZfZ7vAvF"},
    "Movies": {"name": "Film", "genreId": "KnvZfZ7vAkF"},
    "Family": {"name": "Family", "genreId": "KnvZfZ7vA1n"},
}

# Valid onsale status codes — only events with these statuses are returned
VALID_ONSALE_STATUSES = {"onsale"}


# ======================================================================
# TicketmasterService
# ======================================================================

class TicketmasterService:
    """Async service for Ticketmaster Discovery API v2 event search."""

    async def search_events(
        self,
        location: tuple[str, str, str],
        genre_ids: Optional[list[str]] = None,
        date_range: Optional[tuple[str, str]] = None,
        price_range: Optional[tuple[int, int]] = None,
        limit: int = 20,
    ) -> list[dict[str, Any]]:
        """
        Search Ticketmaster events by location and filters.

        Args:
            location: Tuple of (city, state_code, country_code).
            genre_ids: Ticketmaster genre IDs to filter by.
            date_range: Tuple of (start_datetime, end_datetime) in ISO 8601 format.
                        Defaults to now through next 30 days if not provided.
            price_range: Budget in cents as (min_cents, max_cents).
            limit: Max results (default 20, capped at 50).

        Returns:
            List of normalized event dicts matching CandidateRecommendation schema.
            Returns [] on any error (missing API key, timeout, invalid location, etc.).
        """
        if not is_ticketmaster_configured():
            logger.warning("Ticketmaster API key not configured — skipping Ticketmaster search")
            return []

        # Build location string
        city, state, country = location
        if not city and not state and not country:
            logger.warning("Empty location provided — skipping Ticketmaster search")
            return []

        # Build query params
        params: dict[str, Any] = {
            "apikey": TICKETMASTER_API_KEY,
            "size": min(limit, 50),
            "sort": "relevance,asc",
        }

        # Location params
        if city:
            params["city"] = city
        if state:
            params["stateCode"] = state
        if country:
            params["countryCode"] = country

        # Genre filtering
        if genre_ids:
            params["genreId"] = ",".join(genre_ids)

        # Date range (default: next 30 days)
        if date_range:
            params["startDateTime"] = date_range[0]
            params["endDateTime"] = date_range[1]
        else:
            now = datetime.now(timezone.utc)
            end = now + timedelta(days=DEFAULT_DATE_RANGE_DAYS)
            params["startDateTime"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")
            params["endDateTime"] = end.strftime("%Y-%m-%dT%H:%M:%SZ")

        # Make request
        data = await self._make_request("events.json", params)
        embedded = data.get("_embedded", {})
        events = embedded.get("events", [])

        # Filter to onsale events only and normalize
        country_code = country or "US"
        results = []
        for event in events:
            if not self._is_onsale(event):
                continue

            normalized = self._normalize_event(event, country_code)

            # Apply price filter if specified
            if price_range and normalized["price_cents"] is not None:
                if normalized["price_cents"] < price_range[0] or normalized["price_cents"] > price_range[1]:
                    continue

            results.append(normalized)

        return results

    async def _make_request(
        self, endpoint: str, params: dict[str, Any]
    ) -> dict[str, Any]:
        """
        Make authenticated GET request to Ticketmaster API with retry on rate limit.

        Returns parsed JSON dict. Returns empty response on any error.
        """
        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            for retry in range(MAX_RETRIES):
                try:
                    response = await client.get(
                        f"{BASE_URL}/{endpoint}",
                        params=params,
                    )

                    if response.status_code == 429:
                        delay = 2**retry
                        logger.warning(
                            "Ticketmaster API rate limited (429), retrying in %ds "
                            "(attempt %d/%d)",
                            delay, retry + 1, MAX_RETRIES,
                        )
                        await asyncio.sleep(delay)
                        continue

                    response.raise_for_status()
                    return response.json()

                except httpx.TimeoutException:
                    logger.warning(
                        "Ticketmaster API timeout (attempt %d/%d)",
                        retry + 1, MAX_RETRIES,
                    )
                    if retry < MAX_RETRIES - 1:
                        await asyncio.sleep(1)
                    continue

                except httpx.HTTPStatusError as exc:
                    logger.error(
                        "Ticketmaster API HTTP error %d: %s",
                        exc.response.status_code, exc.response.text,
                    )
                    return {}

                except httpx.HTTPError as exc:
                    logger.error("Ticketmaster API request error: %s", exc)
                    return {}

        logger.warning("Ticketmaster API exhausted all %d retries", MAX_RETRIES)
        return {}

    @staticmethod
    def _is_onsale(event: dict[str, Any]) -> bool:
        """
        Check if an event has available tickets.

        Ticketmaster uses dates.status.code to indicate event status.
        Only events with "onsale" status are returned to users.
        """
        dates = event.get("dates", {})
        status = dates.get("status", {})
        status_code = status.get("code", "").lower()
        return status_code in VALID_ONSALE_STATUSES

    @staticmethod
    def _normalize_event(
        event: dict[str, Any], country_code: str
    ) -> dict[str, Any]:
        """
        Convert Ticketmaster API event JSON to CandidateRecommendation-compatible dict.

        Args:
            event: Raw Ticketmaster event object from the API response.
            country_code: ISO 3166-1 alpha-2 country code for currency fallback.

        Returns:
            Dict matching the CandidateRecommendation schema fields.
        """
        # Extract price information
        price_ranges = event.get("priceRanges", [])
        price_cents = None
        currency = COUNTRY_CURRENCY_MAP.get(country_code.upper(), "USD")

        if price_ranges:
            price_info = price_ranges[0]
            # Ticketmaster prices are in dollars — convert to cents
            min_price = price_info.get("min")
            max_price = price_info.get("max")
            if min_price is not None and max_price is not None:
                # Use midpoint as the representative price
                price_cents = int(((min_price + max_price) / 2) * 100)
            elif min_price is not None:
                price_cents = int(min_price * 100)
            elif max_price is not None:
                price_cents = int(max_price * 100)

            # Use currency from price data if available
            price_currency = price_info.get("currency")
            if price_currency:
                currency = price_currency

        # Extract venue information
        embedded = event.get("_embedded", {})
        venues = embedded.get("venues", [])
        venue_data = venues[0] if venues else {}

        venue_name = venue_data.get("name")
        venue_city = venue_data.get("city", {}).get("name")
        venue_state = venue_data.get("state", {}).get("stateCode")
        venue_country = venue_data.get("country", {}).get("countryCode")
        venue_address = venue_data.get("address", {}).get("line1")

        location_data = {
            "city": venue_city,
            "state": venue_state,
            "country": venue_country,
            "address": venue_address,
        }

        # Extract date information
        dates = event.get("dates", {})
        start_date = dates.get("start", {})
        event_date = start_date.get("localDate")
        event_time = start_date.get("localTime")

        # Build description from genre/subgenre + venue
        classifications = event.get("classifications", [])
        genre_name = None
        subgenre_name = None
        if classifications:
            genre_name = classifications[0].get("genre", {}).get("name")
            subgenre_name = classifications[0].get("subGenre", {}).get("name")

        description_parts = []
        if genre_name and genre_name != "Undefined":
            description_parts.append(genre_name)
        if subgenre_name and subgenre_name != "Undefined":
            description_parts.append(subgenre_name)
        if venue_name:
            description_parts.append(f"at {venue_name}")
        description = " — ".join(description_parts) if description_parts else None

        # Select best image (prefer 16:9 ratio, width >= 640)
        images = event.get("images", [])
        image_url = _select_best_image(images)

        # Extract coordinates from venue
        venue_location = venue_data.get("location", {})

        return {
            "id": str(uuid.uuid4()),
            "source": "ticketmaster",
            "type": "experience",
            "title": event.get("name", "Unknown Event"),
            "description": description,
            "price_cents": price_cents,
            "currency": currency,
            "external_url": event.get("url", ""),
            "image_url": image_url,
            "merchant_name": venue_name,
            "location": location_data,
            "metadata": {
                "event_date": event_date,
                "event_time": event_time,
                "genre": genre_name,
                "subgenre": subgenre_name,
                "venue_name": venue_name,
                "price_min": price_ranges[0].get("min") if price_ranges else None,
                "price_max": price_ranges[0].get("max") if price_ranges else None,
                "ticketmaster_id": event.get("id"),
                "coordinates": {
                    "latitude": venue_location.get("latitude"),
                    "longitude": venue_location.get("longitude"),
                },
            },
        }


def _select_best_image(images: list[dict[str, Any]]) -> Optional[str]:
    """
    Select the best image from Ticketmaster's image array.

    Prefers 16:9 ratio images with width >= 640 pixels.
    Falls back to the first available image if no ideal match.
    """
    if not images:
        return None

    # Prefer 16:9 ratio with decent width
    for img in images:
        ratio = img.get("ratio", "")
        width = img.get("width", 0)
        if ratio == "16_9" and width >= 640:
            return img.get("url")

    # Fallback: any 16:9
    for img in images:
        if img.get("ratio", "") == "16_9":
            return img.get("url")

    # Fallback: first image
    return images[0].get("url")
