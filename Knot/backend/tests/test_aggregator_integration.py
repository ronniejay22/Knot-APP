"""
Tests for AggregatorService — Step 8.7.

Validates parallel aggregation of all 6 integration services,
deduplication logic, partial failure handling, and performance.
"""

import asyncio
import time
import uuid
from contextlib import contextmanager
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest

from app.services.integrations.aggregator import (
    AggregationError,
    AggregatorService,
    SOURCE_PRIORITY,
)
from app.services.integrations.amazon import AmazonService
from app.services.integrations.firecrawl_service import CuratedContentService
from app.services.integrations.reservation import ReservationService
from app.services.integrations.shopify import ShopifyService
from app.services.integrations.ticketmaster import TicketmasterService
from app.services.integrations.yelp import YelpService


# ======================================================================
# Sample data factories
# ======================================================================


def _sample_yelp_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from Yelp."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "yelp",
        "type": "date",
        "title": "Bella Italia",
        "description": "Italian, Wine Bars",
        "price_cents": 3000,
        "currency": "USD",
        "external_url": "https://www.yelp.com/biz/bella-italia-sf",
        "image_url": "https://s3-media1.fl.yelpcdn.com/example.jpg",
        "merchant_name": "Bella Italia",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "123 Main St",
        },
        "metadata": {"rating": 4.5, "yelp_id": "bella-italia-sf"},
    }
    data.update(overrides)
    return data


def _sample_ticketmaster_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from Ticketmaster."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "ticketmaster",
        "type": "experience",
        "title": "Jazz Night at The Blue Note",
        "description": "Music / Jazz — The Blue Note",
        "price_cents": 5000,
        "currency": "USD",
        "external_url": "https://www.ticketmaster.com/event/12345",
        "image_url": "https://s1.ticketm.net/example.jpg",
        "merchant_name": "The Blue Note",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": "456 Jazz Ave",
        },
        "metadata": {
            "event_date": "2026-03-15",
            "genre": "Jazz",
            "ticketmaster_id": "tm-12345",
        },
    }
    data.update(overrides)
    return data


def _sample_amazon_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from Amazon."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "amazon",
        "type": "gift",
        "title": "Japanese Chef Knife",
        "description": "Professional 8-inch VG-10 steel chef knife",
        "price_cents": 8900,
        "currency": "USD",
        "external_url": "https://www.amazon.com/dp/B0EXAMPLE",
        "image_url": "https://images-na.ssl-images-amazon.com/example.jpg",
        "merchant_name": "KitchenPro",
        "location": None,
        "metadata": {"asin": "B0EXAMPLE", "brand": "KitchenPro"},
    }
    data.update(overrides)
    return data


def _sample_shopify_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from Shopify."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "shopify",
        "type": "gift",
        "title": "Artisan Spice Collection",
        "description": "Curated set of 12 small-batch spices",
        "price_cents": 4200,
        "currency": "USD",
        "external_url": "https://example.myshopify.com/products/spice-collection",
        "image_url": "https://cdn.shopify.com/example.jpg",
        "merchant_name": "The Spice House",
        "location": None,
        "metadata": {"shopify_id": "gid://shopify/Product/123"},
    }
    data.update(overrides)
    return data


def _sample_reservation_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from OpenTable."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "opentable",
        "type": "date",
        "title": "Italian Reservations on OpenTable",
        "description": "Book a table for 2 — Italian cuisine, Feb 14 at 19:00",
        "price_cents": 4500,
        "currency": "USD",
        "external_url": "https://www.opentable.com/s?term=italian&covers=2",
        "image_url": None,
        "merchant_name": "OpenTable",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": None,
        },
        "metadata": {
            "cuisine": "italian",
            "platform": "opentable",
            "booking_type": "url_redirect",
        },
    }
    data.update(overrides)
    return data


def _sample_curated_result(**overrides: Any) -> dict[str, Any]:
    """Create a sample CandidateRecommendation-compatible dict from Firecrawl."""
    data: dict[str, Any] = {
        "id": str(uuid.uuid4()),
        "source": "firecrawl",
        "type": "experience",
        "title": "The Exploratorium",
        "description": "World-class science museum with interactive exhibits",
        "price_cents": None,
        "currency": "USD",
        "external_url": "https://www.exploratorium.edu",
        "image_url": None,
        "merchant_name": "The Exploratorium",
        "location": {
            "city": "San Francisco",
            "state": "CA",
            "country": "US",
            "address": None,
        },
        "metadata": {"source_type": "curated_guide"},
    }
    data.update(overrides)
    return data


# ======================================================================
# Mock helper
# ======================================================================

# Default test inputs
_TEST_INTERESTS = ["Cooking", "Music"]
_TEST_VIBES = ["romantic", "quiet_luxury"]
_TEST_LOCATION = ("San Francisco", "CA", "US")
_TEST_BUDGET = (2000, 10000)


@contextmanager
def _mock_all_services(**overrides: Any):
    """
    Patch all 6 integration service search methods.

    By default each returns []. Pass keyword overrides to set specific
    return values or side_effects:
        _mock_all_services(yelp=[_sample_yelp_result()])
        _mock_all_services(yelp=RuntimeError("API down"))
    """
    defaults: dict[str, Any] = {
        "yelp": [],
        "ticketmaster": [],
        "amazon": [],
        "shopify": [],
        "reservation": [],
        "curated": [],
    }
    defaults.update(overrides)

    def _make_mock(value: Any) -> AsyncMock:
        mock = AsyncMock()
        if isinstance(value, Exception):
            mock.side_effect = value
        else:
            mock.return_value = value
        return mock

    with (
        patch.object(
            YelpService, "search_businesses", _make_mock(defaults["yelp"])
        ) as m_yelp,
        patch.object(
            TicketmasterService, "search_events", _make_mock(defaults["ticketmaster"])
        ) as m_tm,
        patch.object(
            AmazonService, "search_products", _make_mock(defaults["amazon"])
        ) as m_amazon,
        patch.object(
            ShopifyService, "search_products", _make_mock(defaults["shopify"])
        ) as m_shopify,
        patch.object(
            ReservationService,
            "search_reservations",
            _make_mock(defaults["reservation"]),
        ) as m_reservation,
        patch.object(
            CuratedContentService,
            "search_curated_content",
            _make_mock(defaults["curated"]),
        ) as m_curated,
    ):
        yield {
            "yelp": m_yelp,
            "ticketmaster": m_tm,
            "amazon": m_amazon,
            "shopify": m_shopify,
            "reservation": m_reservation,
            "curated": m_curated,
        }


# ======================================================================
# Tests: Aggregator Init
# ======================================================================


class TestAggregatorInit:
    """Test AggregatorService initialization."""

    def test_aggregator_creates_all_services(self):
        """Should instantiate all 6 integration services."""
        service = AggregatorService()
        assert isinstance(service._yelp, YelpService)
        assert isinstance(service._ticketmaster, TicketmasterService)
        assert isinstance(service._amazon, AmazonService)
        assert isinstance(service._shopify, ShopifyService)
        assert isinstance(service._reservation, ReservationService)
        assert isinstance(service._curated, CuratedContentService)

    def test_aggregator_service_importable(self):
        """Should be importable from the integrations module."""
        from app.services.integrations.aggregator import AggregatorService as Svc

        assert Svc is not None


# ======================================================================
# Tests: Aggregation (happy path)
# ======================================================================


class TestAggregation:
    """Test core aggregation functionality."""

    async def test_aggregate_returns_results_from_multiple_services(self):
        """Should combine results from all services into a single list."""
        yelp_results = [_sample_yelp_result()]
        tm_results = [_sample_ticketmaster_result()]
        amazon_results = [_sample_amazon_result()]

        with _mock_all_services(
            yelp=yelp_results, ticketmaster=tm_results, amazon=amazon_results
        ):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 3
        sources = {r["source"] for r in results}
        assert "yelp" in sources
        assert "ticketmaster" in sources
        assert "amazon" in sources

    async def test_aggregate_with_italian_food_and_live_music(self):
        """Should return both restaurants and concerts for mixed interests."""
        restaurant = _sample_yelp_result(
            title="Trattoria Roma", merchant_name="Trattoria Roma"
        )
        concert = _sample_ticketmaster_result(
            title="Live Jazz Concert", merchant_name="Jazz Club"
        )

        with _mock_all_services(yelp=[restaurant], ticketmaster=[concert]):
            service = AggregatorService()
            results = await service.aggregate(
                ["Cooking", "Concerts"],
                ["romantic"],
                _TEST_LOCATION,
                _TEST_BUDGET,
            )

        types = {r["type"] for r in results}
        assert "date" in types or "experience" in types
        assert len(results) == 2
        titles = {r["title"] for r in results}
        assert "Trattoria Roma" in titles
        assert "Live Jazz Concert" in titles

    async def test_aggregate_returns_normalized_schema(self):
        """Should return dicts with all required CandidateRecommendation fields."""
        with _mock_all_services(yelp=[_sample_yelp_result()]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        required_keys = [
            "id",
            "source",
            "type",
            "title",
            "description",
            "price_cents",
            "currency",
            "external_url",
            "image_url",
            "merchant_name",
            "location",
            "metadata",
        ]
        for result in results:
            for key in required_keys:
                assert key in result, f"Missing key: {key}"

    async def test_aggregate_empty_when_all_return_empty(self):
        """Should return empty list when all services return empty (not an error)."""
        with _mock_all_services():
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert results == []

    async def test_aggregate_passes_limit_per_service(self):
        """Should forward limit_per_service to each service call."""
        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET,
                limit_per_service=5,
            )

        mocks["yelp"].assert_called_once()
        _, kwargs = mocks["yelp"].call_args
        assert kwargs.get("limit") == 5

        mocks["ticketmaster"].assert_called_once()
        _, kwargs = mocks["ticketmaster"].call_args
        assert kwargs.get("limit") == 5

    async def test_aggregate_passes_location_to_location_services(self):
        """Should forward location tuple to Yelp, Ticketmaster, Reservation, and Curated."""
        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["yelp"].call_args
        assert kwargs.get("location") == _TEST_LOCATION

        _, kwargs = mocks["ticketmaster"].call_args
        assert kwargs.get("location") == _TEST_LOCATION

        _, kwargs = mocks["reservation"].call_args
        assert kwargs.get("location") == _TEST_LOCATION

        _, kwargs = mocks["curated"].call_args
        assert kwargs.get("location") == _TEST_LOCATION


# ======================================================================
# Tests: Deduplication
# ======================================================================


class TestDeduplication:
    """Test deduplication logic."""

    async def test_dedup_same_venue_yelp_and_opentable(self):
        """Should keep OpenTable result when same merchant_name+city from Yelp and OpenTable."""
        yelp_result = _sample_yelp_result(
            merchant_name="Bella Italia",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": "123 Main"},
        )
        opentable_result = _sample_reservation_result(
            merchant_name="Bella Italia",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )

        with _mock_all_services(yelp=[yelp_result], reservation=[opentable_result]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        bella_results = [r for r in results if r["merchant_name"] == "Bella Italia"]
        assert len(bella_results) == 1
        assert bella_results[0]["source"] == "opentable"

    async def test_dedup_same_venue_yelp_and_resy(self):
        """Should keep Resy result when same merchant_name+city from Yelp and Resy."""
        yelp_result = _sample_yelp_result(
            merchant_name="Sushi Nakazawa",
            location={"city": "New York", "state": "NY", "country": "US", "address": None},
        )
        resy_result = _sample_reservation_result(
            source="resy",
            merchant_name="Sushi Nakazawa",
            location={"city": "New York", "state": "NY", "country": "US", "address": None},
        )

        with _mock_all_services(yelp=[yelp_result], reservation=[resy_result]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        sushi_results = [r for r in results if r["merchant_name"] == "Sushi Nakazawa"]
        assert len(sushi_results) == 1
        assert sushi_results[0]["source"] == "resy"

    async def test_dedup_different_cities_not_deduped(self):
        """Should keep both results when same merchant_name in different cities."""
        sf_result = _sample_yelp_result(
            merchant_name="Shake Shack",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )
        ny_result = _sample_yelp_result(
            merchant_name="Shake Shack",
            location={"city": "New York", "state": "NY", "country": "US", "address": None},
        )

        with _mock_all_services(yelp=[sf_result, ny_result]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        shake_results = [r for r in results if r["merchant_name"] == "Shake Shack"]
        assert len(shake_results) == 2

    async def test_dedup_case_insensitive_matching(self):
        """Should match merchant names case-insensitively."""
        upper = _sample_yelp_result(
            merchant_name="BELLA ITALIA",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )
        lower = _sample_curated_result(
            merchant_name="bella italia",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )

        with _mock_all_services(yelp=[upper], curated=[lower]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        # Firecrawl (priority 4) > Yelp (priority 3) — curated result kept
        bella_results = [
            r for r in results if r["merchant_name"].lower() == "bella italia"
        ]
        assert len(bella_results) == 1
        assert bella_results[0]["source"] == "firecrawl"

    async def test_dedup_no_merchant_name_always_kept(self):
        """Should never deduplicate results with missing merchant_name."""
        result1 = _sample_curated_result(merchant_name=None, title="Mystery Venue 1")
        result2 = _sample_curated_result(merchant_name=None, title="Mystery Venue 2")
        result3 = _sample_curated_result(merchant_name="", title="Empty Name Venue")

        with _mock_all_services(curated=[result1, result2, result3]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 3

    async def test_dedup_prefers_higher_priority_source(self):
        """Should keep the higher-priority source when deduplicating."""
        amazon_result = _sample_amazon_result(
            merchant_name="Cool Store",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )
        yelp_result = _sample_yelp_result(
            merchant_name="Cool Store",
            location={"city": "San Francisco", "state": "CA", "country": "US", "address": None},
        )

        with _mock_all_services(amazon=[amazon_result], yelp=[yelp_result]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        cool_results = [r for r in results if r["merchant_name"] == "Cool Store"]
        assert len(cool_results) == 1
        # Yelp (priority 3) > Amazon (priority 1)
        assert cool_results[0]["source"] == "yelp"

    async def test_dedup_preserves_unique_results(self):
        """Should not remove results with unique merchant_name+city."""
        results_in = [
            _sample_yelp_result(merchant_name="Restaurant A"),
            _sample_ticketmaster_result(merchant_name="Venue B"),
            _sample_amazon_result(merchant_name="Brand C"),
            _sample_shopify_result(merchant_name="Shop D"),
        ]

        with _mock_all_services(
            yelp=[results_in[0]],
            ticketmaster=[results_in[1]],
            amazon=[results_in[2]],
            shopify=[results_in[3]],
        ):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 4


# ======================================================================
# Tests: Partial Failure
# ======================================================================


class TestPartialFailure:
    """Test graceful handling of service failures."""

    async def test_single_service_failure_returns_remaining(self):
        """Should return results from other services when one fails."""
        with _mock_all_services(
            yelp=RuntimeError("Yelp API timeout"),
            ticketmaster=[_sample_ticketmaster_result()],
            amazon=[_sample_amazon_result()],
        ):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 2
        sources = {r["source"] for r in results}
        assert "yelp" not in sources
        assert "ticketmaster" in sources
        assert "amazon" in sources

    async def test_two_services_fail_returns_remaining(self):
        """Should return results from remaining services when two fail."""
        with _mock_all_services(
            yelp=RuntimeError("Yelp down"),
            ticketmaster=ConnectionError("Ticketmaster down"),
            amazon=[_sample_amazon_result()],
            shopify=[_sample_shopify_result()],
        ):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 2
        sources = {r["source"] for r in results}
        assert "amazon" in sources
        assert "shopify" in sources

    async def test_all_services_fail_raises_aggregation_error(self):
        """Should raise AggregationError when all 6 services fail."""
        with _mock_all_services(
            yelp=RuntimeError("Yelp down"),
            ticketmaster=RuntimeError("TM down"),
            amazon=RuntimeError("Amazon down"),
            shopify=RuntimeError("Shopify down"),
            reservation=RuntimeError("Reservation down"),
            curated=RuntimeError("Firecrawl down"),
        ):
            service = AggregatorService()
            with pytest.raises(AggregationError) as exc_info:
                await service.aggregate(
                    _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
                )

        assert str(exc_info.value) == "Unable to find recommendations right now"

    async def test_service_returns_empty_not_counted_as_failure(self):
        """Empty list from a service is valid, not a failure."""
        with _mock_all_services(
            yelp=[],
            ticketmaster=[],
            amazon=[],
            shopify=[],
            reservation=[],
            curated=[],
        ):
            service = AggregatorService()
            # Should NOT raise AggregationError — empty is valid
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert results == []

    async def test_five_failures_one_success_returns_results(self):
        """Should return results even if only 1 of 6 services succeeds."""
        with _mock_all_services(
            yelp=RuntimeError("down"),
            ticketmaster=RuntimeError("down"),
            amazon=RuntimeError("down"),
            shopify=RuntimeError("down"),
            reservation=RuntimeError("down"),
            curated=[_sample_curated_result()],
        ):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 1
        assert results[0]["source"] == "firecrawl"

    async def test_partial_failure_logs_warning(self, caplog):
        """Should log a warning with failing service names."""
        import logging

        with caplog.at_level(logging.WARNING):
            with _mock_all_services(
                yelp=RuntimeError("Yelp timeout"),
                ticketmaster=[_sample_ticketmaster_result()],
            ):
                service = AggregatorService()
                await service.aggregate(
                    _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
                )

        assert any("yelp" in record.message for record in caplog.records)
        assert any("partial failures" in record.message.lower() for record in caplog.records)


# ======================================================================
# Tests: Performance
# ======================================================================


class TestPerformance:
    """Test parallel execution performance."""

    async def test_aggregation_completes_under_2_seconds(self):
        """Should run all services in parallel, completing well under 2 seconds."""

        async def _slow_yelp(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_yelp_result()]

        async def _slow_ticketmaster(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_ticketmaster_result()]

        async def _slow_amazon(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_amazon_result()]

        async def _slow_shopify(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_shopify_result()]

        async def _slow_reservation(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_reservation_result()]

        async def _slow_curated(**kw: Any) -> list[dict[str, Any]]:
            await asyncio.sleep(0.1)
            return [_sample_curated_result()]

        with (
            patch.object(YelpService, "search_businesses", side_effect=_slow_yelp),
            patch.object(TicketmasterService, "search_events", side_effect=_slow_ticketmaster),
            patch.object(AmazonService, "search_products", side_effect=_slow_amazon),
            patch.object(ShopifyService, "search_products", side_effect=_slow_shopify),
            patch.object(ReservationService, "search_reservations", side_effect=_slow_reservation),
            patch.object(CuratedContentService, "search_curated_content", side_effect=_slow_curated),
        ):
            service = AggregatorService()
            start = time.monotonic()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )
            elapsed = time.monotonic() - start

        # 6 services x 100ms each — if sequential would be 600ms+
        # Parallel should complete in ~100-200ms
        assert elapsed < 2.0, f"Aggregation took {elapsed:.2f}s (expected < 2.0s)"
        assert len(results) == 6


# ======================================================================
# Tests: Interest Mapping
# ======================================================================


class TestInterestMapping:
    """Test that interests/vibes are correctly mapped to service parameters."""

    async def test_yelp_receives_categories_from_vibes(self):
        """Should map vibes to Yelp categories via VIBE_TO_YELP_CATEGORIES."""
        from app.services.integrations.yelp import VIBE_TO_YELP_CATEGORIES

        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                _TEST_INTERESTS, ["romantic"], _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["yelp"].call_args
        expected_cats = VIBE_TO_YELP_CATEGORIES.get("romantic", [])
        if expected_cats:
            assert kwargs.get("categories") is not None
            for cat in expected_cats:
                assert cat in kwargs["categories"]

    async def test_ticketmaster_receives_genre_ids_from_interests(self):
        """Should map interests to Ticketmaster genre IDs via INTEREST_TO_TM_GENRE."""
        from app.services.integrations.ticketmaster import INTEREST_TO_TM_GENRE

        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                ["Concerts"], _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["ticketmaster"].call_args
        genre_info = INTEREST_TO_TM_GENRE.get("Concerts")
        if genre_info:
            assert kwargs.get("genre_ids") is not None
            assert genre_info["genreId"] in kwargs["genre_ids"]

    async def test_amazon_receives_keywords_from_interests(self):
        """Should build keywords from interests for Amazon search."""
        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                ["Cooking", "Music"], _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["amazon"].call_args
        assert "Cooking" in kwargs.get("keywords", "")
        assert "gift" in kwargs.get("keywords", "")

    async def test_shopify_receives_keywords_from_interests(self):
        """Should build Shopify keywords from interests."""
        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                ["Travel"], _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["shopify"].call_args
        assert kwargs.get("keywords") is not None
        assert len(kwargs["keywords"]) > 0

    async def test_reservation_receives_cuisine_from_interests(self):
        """Should derive cuisine from interests for reservation search."""
        from app.services.integrations.reservation import INTEREST_TO_CUISINE

        with _mock_all_services() as mocks:
            service = AggregatorService()
            await service.aggregate(
                ["Cooking"], _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        _, kwargs = mocks["reservation"].call_args
        expected_cuisine = INTEREST_TO_CUISINE.get("Cooking")
        assert kwargs.get("cuisine") == expected_cuisine

    async def test_unconfigured_service_returns_empty_list(self):
        """When a service is not configured, it returns [] (not an error)."""
        with _mock_all_services(yelp=[], ticketmaster=[_sample_ticketmaster_result()]):
            service = AggregatorService()
            results = await service.aggregate(
                _TEST_INTERESTS, _TEST_VIBES, _TEST_LOCATION, _TEST_BUDGET
            )

        assert len(results) == 1
        assert results[0]["source"] == "ticketmaster"


# ======================================================================
# Tests: AggregationError
# ======================================================================


class TestAggregationError:
    """Test AggregationError exception."""

    def test_aggregation_error_is_exception_subclass(self):
        """Should inherit from Exception."""
        assert issubclass(AggregationError, Exception)

    def test_aggregation_error_message(self):
        """Should store the error message."""
        err = AggregationError("Unable to find recommendations right now")
        assert str(err) == "Unable to find recommendations right now"


# ======================================================================
# Tests: Module Imports
# ======================================================================


class TestModuleImports:
    """Test module-level imports and constants."""

    def test_aggregator_service_importable(self):
        """Should be importable from the integrations module."""
        from app.services.integrations.aggregator import AggregatorService

        assert AggregatorService is not None

    def test_aggregation_error_importable(self):
        """Should be importable from the integrations module."""
        from app.services.integrations.aggregator import AggregationError

        assert AggregationError is not None

    def test_source_priority_importable(self):
        """Should export SOURCE_PRIORITY dict with all 8 sources."""
        from app.services.integrations.aggregator import SOURCE_PRIORITY

        assert isinstance(SOURCE_PRIORITY, dict)
        assert "yelp" in SOURCE_PRIORITY
        assert "ticketmaster" in SOURCE_PRIORITY
        assert "amazon" in SOURCE_PRIORITY
        assert "shopify" in SOURCE_PRIORITY
        assert "firecrawl" in SOURCE_PRIORITY
        assert "opentable" in SOURCE_PRIORITY
        assert "resy" in SOURCE_PRIORITY
        assert "claude_search" in SOURCE_PRIORITY
        assert len(SOURCE_PRIORITY) == 8
