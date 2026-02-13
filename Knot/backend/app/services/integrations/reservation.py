"""
OpenTable/Resy Reservation Integration — Search restaurants with booking URLs.

Generates parameterized booking/search URLs for OpenTable and Resy based on
cuisine, location, date, time, and party size. Returns results as
CandidateRecommendation-compatible dicts with type="date" and pre-filled
booking links that direct users to the platforms' search pages.

This is a URL-generation service (no API calls required). The interface is
designed so it can be swapped for real API integrations if/when those
platforms provide public APIs.

Step 8.5: Implement OpenTable/Resy Integration
"""

import logging
import uuid
from datetime import date as date_cls, datetime, timedelta
from typing import Any, Optional
from urllib.parse import quote_plus

from app.core.config import OPENTABLE_AFFILIATE_ID, is_reservation_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

# Default time slots for restaurant reservations (24-hour format)
DEFAULT_TIME_SLOTS: list[str] = [
    "17:30", "18:00", "18:30", "19:00", "19:30",
    "20:00", "20:30", "21:00",
]

# Map partner interest keywords to cuisine search terms
INTEREST_TO_CUISINE: dict[str, str] = {
    "Cooking": "restaurant",
    "Food": "restaurant",
    "Wine": "wine bar",
    "Coffee": "cafe",
    "Baking": "bakery dessert",
}

# Map city names to Resy city slugs for supported cities.
# Resy uses URL-path slugs like /cities/ny, /cities/la, etc.
CITY_TO_RESY_SLUG: dict[str, str] = {
    "New York": "ny",
    "New York City": "ny",
    "NYC": "ny",
    "Manhattan": "ny",
    "Brooklyn": "ny",
    "Los Angeles": "la",
    "LA": "la",
    "San Francisco": "sf",
    "SF": "sf",
    "Chicago": "chi",
    "Miami": "mia",
    "Austin": "atx",
    "Denver": "den",
    "Nashville": "nas",
    "Washington": "dc",
    "Washington DC": "dc",
    "DC": "dc",
    "Seattle": "sea",
    "Portland": "pdx",
    "Houston": "hou",
    "Dallas": "dal",
    "Atlanta": "atl",
    "Boston": "bos",
    "Philadelphia": "phi",
    "Las Vegas": "lv",
    "New Orleans": "nola",
    "London": "london",
    "Paris": "paris",
}

# Approximate average dinner cost per person (in cents) by cuisine type.
# Used for budget filtering when real prices aren't available.
CUISINE_PRICE_ESTIMATE: dict[str, int] = {
    "cafe": 1500,
    "bakery dessert": 2000,
    "brunch": 2500,
    "restaurant": 4000,
    "italian": 4500,
    "mexican": 3000,
    "chinese": 3000,
    "thai": 3000,
    "indian": 3000,
    "korean": 3500,
    "japanese sushi": 5000,
    "french": 6000,
    "mediterranean": 4000,
    "seafood": 5500,
    "steakhouse": 7000,
    "wine bar": 5000,
    "vegan": 3500,
}


# ======================================================================
# URL Builder Helpers
# ======================================================================

def _build_opentable_url(
    cuisine: str,
    city: str,
    date_str: str,
    time_str: str,
    party_size: int,
    affiliate_id: str = "",
) -> str:
    """
    Build an OpenTable search URL with pre-filled parameters.

    Args:
        cuisine: Cuisine or restaurant type search term.
        city: City name for location search.
        date_str: Date in YYYY-MM-DD format.
        time_str: Time in HH:MM format (24-hour).
        party_size: Number of diners.
        affiliate_id: Optional OpenTable affiliate ID for tracking.

    Returns:
        Fully formed OpenTable search URL.
    """
    datetime_str = f"{date_str}T{time_str}"
    params = [
        ("covers", str(party_size)),
        ("dateTime", datetime_str),
        ("term", cuisine),
        ("near", city),
    ]
    query = "&".join(f"{k}={quote_plus(str(v))}" for k, v in params)
    url = f"https://www.opentable.com/s?{query}"

    if affiliate_id:
        url += f"&ref={quote_plus(affiliate_id)}"

    return url


def _build_resy_url(
    cuisine: str,
    city_slug: str,
    date_str: str,
    party_size: int,
) -> str:
    """
    Build a Resy search URL with pre-filled parameters.

    Args:
        cuisine: Cuisine or restaurant type search term.
        city_slug: Resy city slug (e.g., "ny", "sf", "chi").
        date_str: Date in YYYY-MM-DD format.
        party_size: Number of diners.

    Returns:
        Fully formed Resy search URL.
    """
    return (
        f"https://resy.com/cities/{quote_plus(city_slug)}"
        f"?query={quote_plus(cuisine)}"
        f"&date={date_str}"
        f"&seats={party_size}"
    )


def _city_to_resy_slug(city: str) -> Optional[str]:
    """
    Convert a city name to a Resy city slug.

    Returns None if the city is not in Resy's supported cities map.
    Performs case-insensitive lookup with partial matching.
    """
    if not city or not city.strip():
        return None

    city_lower = city.strip().lower()

    # Try exact match first (case-insensitive)
    for key, slug in CITY_TO_RESY_SLUG.items():
        if key.lower() == city_lower:
            return slug

    # Try partial match (city name contained in key or vice versa)
    for key, slug in CITY_TO_RESY_SLUG.items():
        if city_lower in key.lower() or key.lower() in city_lower:
            return slug

    return None


def _generate_time_slots(
    preferred_time: Optional[str] = None,
    count: int = 4,
) -> list[str]:
    """
    Generate a list of reservation time slots centered around a preferred time.

    If no preferred time is given, returns the first ``count`` slots from
    DEFAULT_TIME_SLOTS. If a preferred time is given, returns the ``count``
    slots closest to it.

    Args:
        preferred_time: Preferred time in HH:MM format (24-hour). Optional.
        count: Number of time slots to return.

    Returns:
        List of time strings in HH:MM format.
    """
    if not preferred_time:
        return DEFAULT_TIME_SLOTS[:count]

    try:
        pref_hour, pref_min = map(int, preferred_time.split(":"))
        pref_minutes = pref_hour * 60 + pref_min
    except (ValueError, AttributeError):
        return DEFAULT_TIME_SLOTS[:count]

    # Sort default slots by proximity to preferred time
    def slot_distance(slot: str) -> int:
        h, m = map(int, slot.split(":"))
        return abs(h * 60 + m - pref_minutes)

    sorted_slots = sorted(DEFAULT_TIME_SLOTS, key=slot_distance)
    return sorted_slots[:count]


# ======================================================================
# ReservationService
# ======================================================================

class ReservationService:
    """
    Async service for generating OpenTable and Resy reservation search URLs.

    Generates parameterized booking URLs that pre-fill the user's criteria
    (cuisine, date, time, party size, location). No API calls are made —
    this is a pure URL construction service.
    """

    async def search_reservations(
        self,
        location: tuple[str, str, str],
        cuisine: Optional[str] = None,
        reservation_date: Optional[str] = None,
        reservation_time: Optional[str] = None,
        party_size: int = 2,
        limit: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Search for restaurant reservations on OpenTable and Resy.

        Args:
            location: Tuple of (city, state, country_code).
            cuisine: Cuisine type or search term (e.g., "italian", "sushi").
                     Defaults to "restaurant" if not provided.
            reservation_date: Date in YYYY-MM-DD format.
                              Defaults to tomorrow if not provided.
            reservation_time: Preferred time in HH:MM format (24-hour).
                              Defaults to evening slots if not provided.
            party_size: Number of diners (default 2).
            limit: Max results (default 10).

        Returns:
            List of normalized reservation dicts matching CandidateRecommendation schema.
            Returns [] if location is empty.
        """
        if not is_reservation_configured():
            logger.warning("Reservation service not configured — skipping")
            return []

        city, state, country = location
        if not city or not city.strip():
            logger.warning("Empty city provided — skipping reservation search")
            return []

        # Determine effective cuisine search term
        effective_cuisine = cuisine or "restaurant"

        # Determine effective date (default to tomorrow)
        if not reservation_date:
            tomorrow = date_cls.today() + timedelta(days=1)
            reservation_date = tomorrow.isoformat()

        # Validate date format
        if not self._is_valid_date(reservation_date):
            logger.warning(
                "Invalid date format '%s' — skipping reservation search",
                reservation_date,
            )
            return []

        # Clamp party size to valid range
        if party_size < 1 or party_size > 20:
            logger.warning(
                "Invalid party size %d — clamping to valid range", party_size
            )
            party_size = max(1, min(party_size, 20))

        # Generate time slots
        time_slots = _generate_time_slots(
            preferred_time=reservation_time,
            count=4,
        )

        results: list[dict[str, Any]] = []

        # Generate OpenTable results (always available)
        opentable_results = self._generate_opentable_results(
            city=city,
            state=state,
            country=country,
            cuisine=effective_cuisine,
            date_str=reservation_date,
            time_slots=time_slots,
            party_size=party_size,
        )
        results.extend(opentable_results)

        # Generate Resy results (only for supported cities)
        resy_slug = _city_to_resy_slug(city)
        if resy_slug:
            resy_results = self._generate_resy_results(
                city=city,
                city_slug=resy_slug,
                country=country,
                cuisine=effective_cuisine,
                date_str=reservation_date,
                time_slots=time_slots,
                party_size=party_size,
            )
            results.extend(resy_results)

        return results[:limit]

    def _generate_opentable_results(
        self,
        city: str,
        state: str,
        country: str,
        cuisine: str,
        date_str: str,
        time_slots: list[str],
        party_size: int,
    ) -> list[dict[str, Any]]:
        """Generate CandidateRecommendation dicts for OpenTable time slots."""
        results = []
        location_str = ", ".join(p for p in (city, state) if p)

        for slot in time_slots:
            url = _build_opentable_url(
                cuisine=cuisine,
                city=location_str,
                date_str=date_str,
                time_str=slot,
                party_size=party_size,
                affiliate_id=OPENTABLE_AFFILIATE_ID,
            )
            results.append(
                self._normalize_reservation(
                    source="opentable",
                    cuisine=cuisine,
                    city=city,
                    state=state,
                    country=country,
                    date_str=date_str,
                    time_slot=slot,
                    party_size=party_size,
                    booking_url=url,
                )
            )
        return results

    def _generate_resy_results(
        self,
        city: str,
        city_slug: str,
        country: str,
        cuisine: str,
        date_str: str,
        time_slots: list[str],
        party_size: int,
    ) -> list[dict[str, Any]]:
        """Generate CandidateRecommendation dicts for Resy time slots."""
        # Resy URLs don't include time — the time filter is applied
        # on the platform page. Generate one result per search.
        url = _build_resy_url(
            cuisine=cuisine,
            city_slug=city_slug,
            date_str=date_str,
            party_size=party_size,
        )
        return [
            self._normalize_reservation(
                source="resy",
                cuisine=cuisine,
                city=city,
                state="",
                country=country,
                date_str=date_str,
                time_slot=time_slots[0] if time_slots else "19:00",
                party_size=party_size,
                booking_url=url,
                all_time_slots=time_slots,
            )
        ]

    @staticmethod
    def _normalize_reservation(
        source: str,
        cuisine: str,
        city: str,
        state: str,
        country: str,
        date_str: str,
        time_slot: str,
        party_size: int,
        booking_url: str,
        all_time_slots: Optional[list[str]] = None,
    ) -> dict[str, Any]:
        """
        Build a CandidateRecommendation-compatible dict for a reservation result.

        Args:
            source: "opentable" or "resy".
            cuisine: Cuisine search term used.
            city: City name.
            state: State/province code.
            country: Country code.
            date_str: Date in YYYY-MM-DD format.
            time_slot: Primary time slot in HH:MM format.
            party_size: Number of diners.
            booking_url: Pre-filled booking/search URL.
            all_time_slots: All available time slots (for Resy).

        Returns:
            Dict matching the CandidateRecommendation schema fields.
        """
        # Build human-readable title
        platform_name = "OpenTable" if source == "opentable" else "Resy"
        cuisine_display = cuisine.replace("_", " ").title()
        title = f"{cuisine_display} Reservations on {platform_name}"

        # Build description with time slot info
        if source == "opentable":
            description = (
                f"Book a table for {party_size} on {date_str} at {time_slot} — "
                f"{cuisine_display} restaurants in {city}"
            )
        else:
            slots_str = ", ".join(all_time_slots or [time_slot])
            description = (
                f"Browse {cuisine_display} restaurants in {city} for {party_size} guests "
                f"on {date_str}. Suggested times: {slots_str}"
            )

        # Estimate price from cuisine type
        price_cents = CUISINE_PRICE_ESTIMATE.get(cuisine.lower())

        # Detect currency from country code
        from app.services.integrations.yelp import COUNTRY_CURRENCY_MAP
        currency = COUNTRY_CURRENCY_MAP.get((country or "US").upper(), "USD")

        return {
            "id": str(uuid.uuid4()),
            "source": source,
            "type": "date",
            "title": title,
            "description": description,
            "price_cents": price_cents,
            "currency": currency,
            "external_url": booking_url,
            "image_url": None,
            "merchant_name": platform_name,
            "location": {
                "city": city,
                "state": state if state else None,
                "country": country if country else None,
                "address": None,
            },
            "metadata": {
                "cuisine": cuisine,
                "reservation_date": date_str,
                "reservation_time": time_slot,
                "party_size": party_size,
                "time_slots": all_time_slots or [time_slot],
                "platform": source,
                "booking_type": "url_redirect",
            },
        }

    @staticmethod
    def _is_valid_date(date_str: str) -> bool:
        """Validate that a date string is in YYYY-MM-DD format."""
        try:
            datetime.strptime(date_str, "%Y-%m-%d")
            return True
        except ValueError:
            return False
