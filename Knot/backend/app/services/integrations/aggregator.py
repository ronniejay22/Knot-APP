"""
Aggregator Service — Unifies all integration services into a single candidate list.

Calls all 6 integration services (Yelp, Ticketmaster, Amazon, Shopify,
Reservation, Firecrawl) in parallel using asyncio.gather(). Deduplicates
results, handles partial failures gracefully, and returns a unified list
of CandidateRecommendation-compatible dicts.

Step 8.7: Create Aggregator Service
"""

import asyncio
import logging
from typing import Any, Optional

from app.services.integrations.amazon import AmazonService
from app.services.integrations.firecrawl_service import CuratedContentService
from app.services.integrations.reservation import ReservationService
from app.services.integrations.shopify import ShopifyService
from app.services.integrations.ticketmaster import TicketmasterService
from app.services.integrations.yelp import YelpService

logger = logging.getLogger(__name__)


# Source priority for deduplication — higher number = preferred when duplicates found
SOURCE_PRIORITY: dict[str, int] = {
    "amazon": 1,
    "shopify": 1,
    "ticketmaster": 2,
    "yelp": 3,
    "firecrawl": 4,
    "opentable": 5,
    "resy": 5,
}


class AggregationError(Exception):
    """Raised when all integration services fail during aggregation."""

    pass


class AggregatorService:
    """
    Async service that aggregates results from all integration services
    in parallel, deduplicates, and returns a unified candidate list.
    """

    def __init__(self) -> None:
        self._yelp = YelpService()
        self._ticketmaster = TicketmasterService()
        self._amazon = AmazonService()
        self._shopify = ShopifyService()
        self._reservation = ReservationService()
        self._curated = CuratedContentService()

    async def aggregate(
        self,
        interests: list[str],
        vibes: list[str],
        location: tuple[str, str, str],
        budget_range: tuple[int, int],
        limit_per_service: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Aggregate results from all configured integration services.

        Calls all services in parallel, deduplicates, and returns
        a unified list of CandidateRecommendation-compatible dicts.

        Args:
            interests: Partner interest categories (e.g., ["Cooking", "Music"]).
            vibes: Partner aesthetic vibes (e.g., ["romantic", "quiet_luxury"]).
            location: Tuple of (city, state, country_code).
            budget_range: Budget in cents as (min_cents, max_cents).
            limit_per_service: Max results per service (default 10).

        Returns:
            List of normalized dicts matching CandidateRecommendation schema.

        Raises:
            AggregationError: If all services fail to return results.
        """
        service_calls = [
            ("yelp", self._call_yelp(vibes, location, budget_range, limit_per_service)),
            ("ticketmaster", self._call_ticketmaster(interests, location, budget_range, limit_per_service)),
            ("amazon", self._call_amazon(interests, budget_range, limit_per_service)),
            ("shopify", self._call_shopify(interests, budget_range, limit_per_service)),
            ("reservation", self._call_reservation(interests, location, limit_per_service)),
            ("curated", self._call_curated(interests, location, limit_per_service)),
        ]

        service_names = [name for name, _ in service_calls]
        coroutines = [coro for _, coro in service_calls]

        results = await asyncio.gather(*coroutines, return_exceptions=True)

        all_candidates: list[dict[str, Any]] = []
        failures: list[str] = []

        for name, result in zip(service_names, results):
            if isinstance(result, Exception):
                logger.error("Service '%s' failed: %s", name, result)
                failures.append(name)
            elif isinstance(result, list):
                logger.info("Service '%s' returned %d results", name, len(result))
                all_candidates.extend(result)
            else:
                logger.warning(
                    "Service '%s' returned unexpected type: %s", name, type(result)
                )
                failures.append(name)

        if failures:
            logger.warning(
                "Aggregation partial failures (%d/%d services): %s",
                len(failures),
                len(service_names),
                ", ".join(failures),
            )

        if len(failures) == len(service_names):
            raise AggregationError("Unable to find recommendations right now")

        deduplicated = self._deduplicate(all_candidates)

        logger.info(
            "Aggregation complete: %d candidates (%d before dedup, %d failures)",
            len(deduplicated),
            len(all_candidates),
            len(failures),
        )

        return deduplicated

    # ------------------------------------------------------------------
    # Private dispatch methods
    # ------------------------------------------------------------------

    async def _call_yelp(
        self,
        vibes: list[str],
        location: tuple[str, str, str],
        budget_range: tuple[int, int],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to YelpService with vibe-derived categories."""
        from app.services.integrations.yelp import VIBE_TO_YELP_CATEGORIES

        categories: list[str] = []
        seen: set[str] = set()
        for vibe in vibes:
            for cat in VIBE_TO_YELP_CATEGORIES.get(vibe, []):
                if cat not in seen:
                    categories.append(cat)
                    seen.add(cat)

        return await self._yelp.search_businesses(
            location=location,
            categories=categories or None,
            price_range=budget_range,
            limit=limit,
        )

    async def _call_ticketmaster(
        self,
        interests: list[str],
        location: tuple[str, str, str],
        budget_range: tuple[int, int],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to TicketmasterService with interest-derived genre IDs."""
        from app.services.integrations.ticketmaster import INTEREST_TO_TM_GENRE

        genre_ids: list[str] = []
        for interest in interests:
            genre_info = INTEREST_TO_TM_GENRE.get(interest)
            if genre_info:
                genre_ids.append(genre_info["genreId"])

        return await self._ticketmaster.search_events(
            location=location,
            genre_ids=genre_ids or None,
            price_range=budget_range,
            limit=limit,
        )

    async def _call_amazon(
        self,
        interests: list[str],
        budget_range: tuple[int, int],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to AmazonService with interest-derived keywords."""
        from app.services.integrations.amazon import INTEREST_TO_AMAZON_CATEGORY

        keywords = " ".join(interests[:3]) + " gift"
        category: Optional[str] = None
        for interest in interests:
            cat = INTEREST_TO_AMAZON_CATEGORY.get(interest)
            if cat:
                category = cat
                break

        return await self._amazon.search_products(
            keywords=keywords,
            category=category,
            price_range=budget_range,
            limit=limit,
        )

    async def _call_shopify(
        self,
        interests: list[str],
        budget_range: tuple[int, int],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to ShopifyService with interest-derived keywords."""
        from app.services.integrations.shopify import INTEREST_TO_SHOPIFY_PRODUCT_TYPE

        keywords_parts: list[str] = []
        matched_interest: Optional[str] = None
        for interest in interests:
            shopify_kw = INTEREST_TO_SHOPIFY_PRODUCT_TYPE.get(interest)
            if shopify_kw:
                keywords_parts.append(shopify_kw)
                if not matched_interest:
                    matched_interest = interest

        keywords = (
            " ".join(keywords_parts[:2])
            if keywords_parts
            else " ".join(interests[:2]) + " gift"
        )

        return await self._shopify.search_products(
            keywords=keywords,
            interest=matched_interest,
            price_range=budget_range,
            limit=limit,
        )

    async def _call_reservation(
        self,
        interests: list[str],
        location: tuple[str, str, str],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to ReservationService with interest-derived cuisine."""
        from app.services.integrations.reservation import INTEREST_TO_CUISINE

        cuisine: Optional[str] = None
        for interest in interests:
            c = INTEREST_TO_CUISINE.get(interest)
            if c:
                cuisine = c
                break

        return await self._reservation.search_reservations(
            location=location,
            cuisine=cuisine,
            limit=limit,
        )

    async def _call_curated(
        self,
        interests: list[str],
        location: tuple[str, str, str],
        limit: int,
    ) -> list[dict[str, Any]]:
        """Dispatch to CuratedContentService with location and interests."""
        return await self._curated.search_curated_content(
            location=location,
            interests=interests,
            limit=limit,
        )

    # ------------------------------------------------------------------
    # Deduplication
    # ------------------------------------------------------------------

    def _deduplicate(
        self, candidates: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """
        Remove duplicate venues, preferring sources with reservation URLs.

        Duplicates are identified by matching merchant_name + city
        (case-insensitive). When duplicates are found, the candidate
        from the higher-priority source is kept.
        """
        seen: dict[str, dict[str, Any]] = {}

        for candidate in candidates:
            key = self._dedup_key(candidate)
            if key is None:
                seen[candidate["id"]] = candidate
                continue

            if key in seen:
                existing = seen[key]
                existing_priority = SOURCE_PRIORITY.get(existing["source"], 0)
                new_priority = SOURCE_PRIORITY.get(candidate["source"], 0)
                if new_priority > existing_priority:
                    logger.debug(
                        "Dedup: replacing '%s' (%s) with (%s) for key '%s'",
                        existing["title"],
                        existing["source"],
                        candidate["source"],
                        key,
                    )
                    seen[key] = candidate
            else:
                seen[key] = candidate

        return list(seen.values())

    @staticmethod
    def _dedup_key(candidate: dict[str, Any]) -> Optional[str]:
        """
        Build a deduplication key from merchant_name and city.

        Returns None if merchant_name is missing (candidate can't be deduped).
        """
        merchant = candidate.get("merchant_name")
        if not merchant or not merchant.strip():
            return None

        city = ""
        location = candidate.get("location")
        if isinstance(location, dict):
            city = location.get("city") or ""

        return f"{merchant.strip().lower()}|{city.strip().lower()}"
