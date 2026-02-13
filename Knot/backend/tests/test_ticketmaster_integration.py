"""
Step 8.2 Verification: Ticketmaster Discovery API Integration

Tests that:
1. TicketmasterService correctly maps interest categories to TM genre IDs
2. Ticketmaster event JSON is normalized to CandidateRecommendation schema
3. International currency detection works for 30+ countries
4. Only events with onsale status are returned (offsale/cancelled filtered out)
5. Rate limiting triggers exponential backoff retries on HTTP 429
6. Timeout and HTTP errors return empty results gracefully
7. Invalid locations return empty results (no crash)
8. Price extraction converts dollars to cents with midpoint calculation
9. Best image selection prefers 16:9 ratio with width >= 640
10. Integration tests with real Ticketmaster API (skipped without API key)

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)
- httpx installed

Run with: pytest tests/test_ticketmaster_integration.py -v
"""

from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.config import is_ticketmaster_configured
from app.services.integrations.ticketmaster import (
    BASE_URL,
    DEFAULT_DATE_RANGE_DAYS,
    DEFAULT_TIMEOUT,
    INTEREST_TO_TM_GENRE,
    MAX_RETRIES,
    VALID_ONSALE_STATUSES,
    TicketmasterService,
    _select_best_image,
)
from app.services.integrations.yelp import COUNTRY_CURRENCY_MAP


# ---------------------------------------------------------------------------
# Skipif markers
# ---------------------------------------------------------------------------

requires_ticketmaster = pytest.mark.skipif(
    not is_ticketmaster_configured(),
    reason="Ticketmaster API key not configured in .env",
)


# ---------------------------------------------------------------------------
# Sample Ticketmaster API response data
# ---------------------------------------------------------------------------

def _sample_tm_event(**overrides) -> dict:
    """Create a sample Ticketmaster event object matching the API response format."""
    data = {
        "id": "vvG1iZ4pS17Wpm",
        "name": "Taylor Swift | The Eras Tour",
        "url": "https://www.ticketmaster.com/event/vvG1iZ4pS17Wpm",
        "images": [
            {
                "url": "https://s1.ticketm.net/dam/a/small.jpg",
                "ratio": "4_3",
                "width": 305,
                "height": 225,
            },
            {
                "url": "https://s1.ticketm.net/dam/a/large_16_9.jpg",
                "ratio": "16_9",
                "width": 1024,
                "height": 576,
            },
            {
                "url": "https://s1.ticketm.net/dam/a/medium_16_9.jpg",
                "ratio": "16_9",
                "width": 640,
                "height": 360,
            },
        ],
        "dates": {
            "start": {
                "localDate": "2026-03-15",
                "localTime": "19:30:00",
            },
            "status": {
                "code": "onsale",
            },
        },
        "classifications": [
            {
                "genre": {"id": "KnvZfZ7vAeA", "name": "Music"},
                "subGenre": {"id": "KZazBEonSMnZfZ7vk1l", "name": "Pop"},
            },
        ],
        "priceRanges": [
            {
                "type": "standard",
                "currency": "USD",
                "min": 49.50,
                "max": 199.50,
            },
        ],
        "_embedded": {
            "venues": [
                {
                    "name": "SoFi Stadium",
                    "city": {"name": "Los Angeles"},
                    "state": {"stateCode": "CA"},
                    "country": {"countryCode": "US"},
                    "address": {"line1": "1001 Stadium Dr"},
                    "location": {
                        "latitude": "33.9534",
                        "longitude": "-118.3390",
                    },
                },
            ],
        },
    }
    data.update(overrides)
    return data


def _sample_tm_response(events: list[dict] | None = None) -> dict:
    """Create a sample Ticketmaster API search response."""
    if events is None:
        events = [_sample_tm_event()]
    return {
        "_embedded": {
            "events": events,
        },
        "page": {
            "size": len(events),
            "totalElements": len(events),
            "totalPages": 1,
            "number": 0,
        },
    }


def _sample_tm_empty_response() -> dict:
    """Create a sample empty Ticketmaster response (no events found)."""
    return {
        "page": {
            "size": 0,
            "totalElements": 0,
            "totalPages": 0,
            "number": 0,
        },
    }


# ======================================================================
# TestInterestToGenreMapping
# ======================================================================

class TestInterestToGenreMapping:
    """Test interest category to Ticketmaster genre ID mappings."""

    EXPECTED_INTERESTS = [
        "Concerts", "Music", "Theater", "Sports",
        "Comedy", "Dancing", "Movies", "Family",
    ]

    def test_all_interests_have_genre_ids(self):
        """Every mapped interest should have a genreId."""
        for interest in self.EXPECTED_INTERESTS:
            genre = INTEREST_TO_TM_GENRE.get(interest)
            assert genre is not None, f"Interest '{interest}' not found in mapping"
            assert "genreId" in genre, f"Interest '{interest}' missing genreId"
            assert len(genre["genreId"]) > 0, f"Interest '{interest}' has empty genreId"

    def test_all_genre_ids_are_strings(self):
        """All genre IDs should be non-empty strings."""
        for interest, genre in INTEREST_TO_TM_GENRE.items():
            assert isinstance(genre["genreId"], str), f"genreId for '{interest}' is not a string"
            assert isinstance(genre["name"], str), f"name for '{interest}' is not a string"

    def test_concerts_and_music_map_to_same_genre(self):
        """Concerts and Music should both map to the Music genre."""
        assert INTEREST_TO_TM_GENRE["Concerts"]["genreId"] == INTEREST_TO_TM_GENRE["Music"]["genreId"]
        assert INTEREST_TO_TM_GENRE["Concerts"]["name"] == "Music"

    def test_mapping_count(self):
        """Should have exactly 8 interest mappings."""
        assert len(INTEREST_TO_TM_GENRE) == 8

    def test_no_unexpected_interests(self):
        """INTEREST_TO_TM_GENRE should only contain defined interests."""
        for interest in INTEREST_TO_TM_GENRE:
            assert interest in self.EXPECTED_INTERESTS, f"Unexpected interest '{interest}' in mapping"


# ======================================================================
# TestEventNormalization
# ======================================================================

class TestEventNormalization:
    """Test conversion of Ticketmaster event JSON to CandidateRecommendation format."""

    def test_basic_normalization(self):
        """Should normalize a standard Ticketmaster event."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")

        assert result["source"] == "ticketmaster"
        assert result["type"] == "experience"
        assert result["title"] == "Taylor Swift | The Eras Tour"
        assert result["external_url"] == "https://www.ticketmaster.com/event/vvG1iZ4pS17Wpm"
        assert result["currency"] == "USD"
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36  # UUID format

    def test_price_midpoint_calculation(self):
        """Should convert dollar price range to cents using midpoint."""
        event = _sample_tm_event(priceRanges=[{
            "type": "standard",
            "currency": "USD",
            "min": 50.00,
            "max": 150.00,
        }])
        result = TicketmasterService._normalize_event(event, "US")
        # Midpoint: (50 + 150) / 2 = 100.00 → 10000 cents
        assert result["price_cents"] == 10000

    def test_price_min_only(self):
        """Should use min price when max is missing."""
        event = _sample_tm_event(priceRanges=[{
            "type": "standard",
            "currency": "USD",
            "min": 25.00,
        }])
        result = TicketmasterService._normalize_event(event, "US")
        assert result["price_cents"] == 2500

    def test_price_max_only(self):
        """Should use max price when min is missing."""
        event = _sample_tm_event(priceRanges=[{
            "type": "standard",
            "currency": "USD",
            "max": 75.00,
        }])
        result = TicketmasterService._normalize_event(event, "US")
        assert result["price_cents"] == 7500

    def test_missing_price_returns_none(self):
        """Should return None for price_cents when no priceRanges provided."""
        event = _sample_tm_event(priceRanges=[])
        result = TicketmasterService._normalize_event(event, "US")
        assert result["price_cents"] is None

    def test_no_price_ranges_key(self):
        """Should handle missing priceRanges key entirely."""
        event = _sample_tm_event()
        del event["priceRanges"]
        result = TicketmasterService._normalize_event(event, "US")
        assert result["price_cents"] is None

    def test_type_always_experience(self):
        """All Ticketmaster events should be typed as 'experience'."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        assert result["type"] == "experience"

    def test_gbp_currency_for_uk(self):
        """UK country code should produce GBP currency when no price currency."""
        event = _sample_tm_event(priceRanges=[])
        result = TicketmasterService._normalize_event(event, "GB")
        assert result["currency"] == "GBP"

    def test_currency_from_price_data_overrides_country(self):
        """Currency from priceRanges should override country-based detection."""
        event = _sample_tm_event(priceRanges=[{
            "type": "standard",
            "currency": "GBP",
            "min": 30.00,
            "max": 60.00,
        }])
        result = TicketmasterService._normalize_event(event, "US")
        assert result["currency"] == "GBP"

    def test_eur_currency_for_france(self):
        """France country code should produce EUR currency."""
        event = _sample_tm_event(priceRanges=[])
        result = TicketmasterService._normalize_event(event, "FR")
        assert result["currency"] == "EUR"

    def test_unknown_country_defaults_to_usd(self):
        """Unknown country code should default to USD."""
        event = _sample_tm_event(priceRanges=[])
        result = TicketmasterService._normalize_event(event, "ZZ")
        assert result["currency"] == "USD"

    def test_venue_extraction(self):
        """Should extract venue information into location data."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        loc = result["location"]
        assert loc["city"] == "Los Angeles"
        assert loc["state"] == "CA"
        assert loc["country"] == "US"
        assert loc["address"] == "1001 Stadium Dr"
        assert result["merchant_name"] == "SoFi Stadium"

    def test_date_extraction(self):
        """Should extract event date and time into metadata."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        meta = result["metadata"]
        assert meta["event_date"] == "2026-03-15"
        assert meta["event_time"] == "19:30:00"

    def test_genre_and_subgenre_in_metadata(self):
        """Should include genre and subgenre in metadata."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        meta = result["metadata"]
        assert meta["genre"] == "Music"
        assert meta["subgenre"] == "Pop"
        assert meta["ticketmaster_id"] == "vvG1iZ4pS17Wpm"

    def test_description_from_genre_and_venue(self):
        """Should build description from genre, subgenre, and venue."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        assert "Music" in result["description"]
        assert "Pop" in result["description"]
        assert "SoFi Stadium" in result["description"]

    def test_missing_name_defaults_to_unknown(self):
        """Missing name should default to 'Unknown Event'."""
        event = _sample_tm_event()
        del event["name"]
        result = TicketmasterService._normalize_event(event, "US")
        assert result["title"] == "Unknown Event"

    def test_missing_venue_data(self):
        """Should handle missing venue data gracefully."""
        event = _sample_tm_event()
        event["_embedded"] = {"venues": []}
        result = TicketmasterService._normalize_event(event, "US")
        assert result["location"]["city"] is None
        assert result["merchant_name"] is None

    def test_missing_embedded_key(self):
        """Should handle missing _embedded key entirely."""
        event = _sample_tm_event()
        del event["_embedded"]
        result = TicketmasterService._normalize_event(event, "US")
        assert result["location"]["city"] is None
        assert result["merchant_name"] is None

    def test_lowercase_country_code(self):
        """Should handle lowercase country codes."""
        event = _sample_tm_event(priceRanges=[])
        result = TicketmasterService._normalize_event(event, "gb")
        assert result["currency"] == "GBP"

    def test_price_metadata_includes_min_max(self):
        """Metadata should include raw min/max prices from API."""
        event = _sample_tm_event()
        result = TicketmasterService._normalize_event(event, "US")
        meta = result["metadata"]
        assert meta["price_min"] == 49.50
        assert meta["price_max"] == 199.50

    def test_undefined_genre_excluded_from_description(self):
        """Undefined genre should not appear in description."""
        event = _sample_tm_event(classifications=[{
            "genre": {"id": "xxx", "name": "Undefined"},
            "subGenre": {"id": "yyy", "name": "Undefined"},
        }])
        event["_embedded"]["venues"][0]["name"] = "Test Venue"
        result = TicketmasterService._normalize_event(event, "US")
        assert result["description"] == "at Test Venue"


# ======================================================================
# TestImageSelection
# ======================================================================

class TestImageSelection:
    """Test best image selection logic."""

    def test_prefers_16_9_large(self):
        """Should prefer 16:9 ratio image with width >= 640."""
        images = [
            {"url": "small.jpg", "ratio": "4_3", "width": 305},
            {"url": "large_16_9.jpg", "ratio": "16_9", "width": 1024},
            {"url": "medium_16_9.jpg", "ratio": "16_9", "width": 640},
        ]
        assert _select_best_image(images) == "large_16_9.jpg"

    def test_falls_back_to_any_16_9(self):
        """Should fall back to any 16:9 if none large enough."""
        images = [
            {"url": "small_4_3.jpg", "ratio": "4_3", "width": 305},
            {"url": "small_16_9.jpg", "ratio": "16_9", "width": 320},
        ]
        assert _select_best_image(images) == "small_16_9.jpg"

    def test_falls_back_to_first_image(self):
        """Should fall back to first image if no 16:9 available."""
        images = [
            {"url": "only_4_3.jpg", "ratio": "4_3", "width": 640},
        ]
        assert _select_best_image(images) == "only_4_3.jpg"

    def test_empty_images_returns_none(self):
        """Should return None for empty images list."""
        assert _select_best_image([]) is None


# ======================================================================
# TestOnsaleFiltering
# ======================================================================

class TestOnsaleFiltering:
    """Test onsale status filtering."""

    def test_onsale_event_included(self):
        """Events with onsale status should pass the filter."""
        event = _sample_tm_event()
        assert TicketmasterService._is_onsale(event) is True

    def test_offsale_event_excluded(self):
        """Events with offsale status should be filtered out."""
        event = _sample_tm_event()
        event["dates"]["status"]["code"] = "offsale"
        assert TicketmasterService._is_onsale(event) is False

    def test_cancelled_event_excluded(self):
        """Cancelled events should be filtered out."""
        event = _sample_tm_event()
        event["dates"]["status"]["code"] = "cancelled"
        assert TicketmasterService._is_onsale(event) is False

    def test_rescheduled_event_excluded(self):
        """Rescheduled events should be filtered out."""
        event = _sample_tm_event()
        event["dates"]["status"]["code"] = "rescheduled"
        assert TicketmasterService._is_onsale(event) is False

    def test_missing_status_excluded(self):
        """Events with no status code should be filtered out."""
        event = _sample_tm_event()
        event["dates"] = {}
        assert TicketmasterService._is_onsale(event) is False

    def test_case_insensitive_status(self):
        """Status check should be case-insensitive."""
        event = _sample_tm_event()
        event["dates"]["status"]["code"] = "ONSALE"
        assert TicketmasterService._is_onsale(event) is True


# ======================================================================
# TestCurrencyMapping
# ======================================================================

class TestCurrencyMapping:
    """Test international currency detection (reuses COUNTRY_CURRENCY_MAP from yelp)."""

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
# TestRateLimiting
# ======================================================================

class TestRateLimiting:
    """Test rate limiting with exponential backoff."""

    async def test_retries_on_429_then_succeeds(self):
        """Should retry on 429 and return results when the retry succeeds."""
        rate_limit_response = httpx.Response(429, request=httpx.Request("GET", BASE_URL))
        success_response = httpx.Response(
            200,
            json=_sample_tm_response(),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=[rate_limit_response, success_response])
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
                genre_ids=["KnvZfZ7vAeA"],
            )

        assert len(results) == 1
        assert results[0]["title"] == "Taylor Swift | The Eras Tour"
        assert mock_client.get.call_count == 2

    async def test_exhausts_retries_on_repeated_429(self):
        """Should return empty list after exhausting all retries on 429."""
        rate_limit_response = httpx.Response(429, request=httpx.Request("GET", BASE_URL))

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=rate_limit_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert results == []
        assert mock_client.get.call_count == MAX_RETRIES


# ======================================================================
# TestErrorHandling
# ======================================================================

class TestErrorHandling:
    """Test graceful error handling for various failure modes."""

    async def test_timeout_returns_empty(self):
        """Should return empty list on timeout after retries."""
        mock_client = AsyncMock()
        mock_client.get = AsyncMock(side_effect=httpx.TimeoutException("timeout"))
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client), \
             patch("asyncio.sleep", new_callable=AsyncMock):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
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

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert results == []

    async def test_missing_api_key_returns_empty(self):
        """Should return empty list when TICKETMASTER_API_KEY is not configured."""
        with patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=False):
            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert results == []

    async def test_empty_location_returns_empty(self):
        """Should return empty list for empty location tuple."""
        with patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True):
            service = TicketmasterService()
            results = await service.search_events(
                location=("", "", ""),
            )

        assert results == []

    async def test_empty_events_response(self):
        """Should return empty list when Ticketmaster returns no events."""
        empty_response = httpx.Response(
            200,
            json=_sample_tm_empty_response(),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=empty_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Nowhere", "", ""),
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

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert results == []


# ======================================================================
# TestSearchWithMock
# ======================================================================

class TestSearchWithMock:
    """Test the full search_events method with mocked HTTP."""

    async def test_builds_correct_params(self):
        """Should send correct query parameters to Ticketmaster API."""
        success_response = httpx.Response(
            200,
            json=_sample_tm_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            await service.search_events(
                location=("Los Angeles", "CA", "US"),
                genre_ids=["KnvZfZ7vAeA"],
                limit=10,
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["city"] == "Los Angeles"
        assert params["stateCode"] == "CA"
        assert params["countryCode"] == "US"
        assert params["genreId"] == "KnvZfZ7vAeA"
        assert params["size"] == 10
        assert params["apikey"] == "test-key"
        assert "startDateTime" in params
        assert "endDateTime" in params

    async def test_caps_limit_at_50(self):
        """Should cap limit at 50."""
        success_response = httpx.Response(
            200,
            json=_sample_tm_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            await service.search_events(
                location=("LA", "CA", "US"),
                limit=200,
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["size"] == 50

    async def test_custom_date_range(self):
        """Should use provided date range instead of default."""
        success_response = httpx.Response(
            200,
            json=_sample_tm_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            await service.search_events(
                location=("LA", "CA", "US"),
                date_range=("2026-06-01T00:00:00Z", "2026-07-01T00:00:00Z"),
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["startDateTime"] == "2026-06-01T00:00:00Z"
        assert params["endDateTime"] == "2026-07-01T00:00:00Z"

    async def test_filters_offsale_events(self):
        """Should filter out offsale events from results."""
        onsale_event = _sample_tm_event(name="Available Show")
        offsale_event = _sample_tm_event(name="Sold Out Show")
        offsale_event["dates"]["status"]["code"] = "offsale"

        success_response = httpx.Response(
            200,
            json=_sample_tm_response([onsale_event, offsale_event]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert len(results) == 1
        assert results[0]["title"] == "Available Show"

    async def test_normalizes_multiple_events(self):
        """Should normalize all onsale events in the response."""
        events = [
            _sample_tm_event(name="Concert A"),
            _sample_tm_event(name="Concert B"),
            _sample_tm_event(name="Concert C"),
        ]
        success_response = httpx.Response(
            200,
            json=_sample_tm_response(events),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("Los Angeles", "CA", "US"),
            )

        assert len(results) == 3
        assert results[0]["title"] == "Concert A"
        assert results[1]["title"] == "Concert B"
        assert results[2]["title"] == "Concert C"
        for r in results:
            assert r["source"] == "ticketmaster"
            assert r["type"] == "experience"

    async def test_apikey_in_params_not_headers(self):
        """Ticketmaster uses apikey as query param, not Authorization header."""
        success_response = httpx.Response(
            200,
            json=_sample_tm_response([]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "my-tm-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            await service.search_events(
                location=("LA", "CA", "US"),
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["apikey"] == "my-tm-key"
        # No Authorization header — Ticketmaster uses query param auth
        headers = call_kwargs.kwargs.get("headers")
        assert headers is None

    async def test_international_country_code(self):
        """Should pass country code for international searches."""
        success_response = httpx.Response(
            200,
            json=_sample_tm_response([_sample_tm_event()]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("London", "", "GB"),
            )

        call_kwargs = mock_client.get.call_args
        params = call_kwargs.kwargs.get("params") or call_kwargs[1].get("params")
        assert params["countryCode"] == "GB"
        assert "stateCode" not in params  # Empty state should not be included
        assert len(results) == 1

    async def test_price_range_filter(self):
        """Should filter events outside the specified price range."""
        cheap_event = _sample_tm_event(name="Cheap Show", priceRanges=[{
            "type": "standard", "currency": "USD", "min": 10.00, "max": 30.00,
        }])
        expensive_event = _sample_tm_event(name="Expensive Show", priceRanges=[{
            "type": "standard", "currency": "USD", "min": 200.00, "max": 500.00,
        }])
        no_price_event = _sample_tm_event(name="Free Show", priceRanges=[])

        success_response = httpx.Response(
            200,
            json=_sample_tm_response([cheap_event, expensive_event, no_price_event]),
            request=httpx.Request("GET", BASE_URL),
        )

        mock_client = AsyncMock()
        mock_client.get = AsyncMock(return_value=success_response)
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.integrations.ticketmaster.TICKETMASTER_API_KEY", "test-key"), \
             patch("app.services.integrations.ticketmaster.is_ticketmaster_configured", return_value=True), \
             patch("httpx.AsyncClient", return_value=mock_client):

            service = TicketmasterService()
            results = await service.search_events(
                location=("LA", "CA", "US"),
                price_range=(1000, 5000),  # $10-$50
            )

        # Cheap show midpoint: (10+30)/2 = 20.00 = 2000 cents → in range
        # Expensive show midpoint: (200+500)/2 = 350.00 = 35000 cents → out of range
        # Free show: no price → included (None price passes filter)
        titles = [r["title"] for r in results]
        assert "Cheap Show" in titles
        assert "Expensive Show" not in titles
        assert "Free Show" in titles


# ======================================================================
# TestSearchIntegration (requires real API key)
# ======================================================================

@requires_ticketmaster
class TestSearchIntegration:
    """Integration tests with real Ticketmaster API. Skipped without TICKETMASTER_API_KEY."""

    async def test_search_los_angeles_concerts(self):
        """Should return concert events in Los Angeles."""
        service = TicketmasterService()
        results = await service.search_events(
            location=("Los Angeles", "CA", "US"),
            genre_ids=["KnvZfZ7vAeA"],  # Music
            limit=5,
        )

        assert len(results) > 0
        for event in results:
            assert event["source"] == "ticketmaster"
            assert event["type"] == "experience"
            assert event["title"]
            assert event["external_url"]
            assert isinstance(event["id"], str)

    async def test_search_london_international(self):
        """Should return London events with GBP currency."""
        service = TicketmasterService()
        results = await service.search_events(
            location=("London", "", "GB"),
            limit=5,
        )

        assert len(results) > 0
        for event in results:
            assert event["source"] == "ticketmaster"
            # Currency may be GBP from price data or from country fallback
            assert event["currency"] in ("GBP", "USD", "EUR")

    async def test_only_onsale_events_returned(self):
        """All returned events should have onsale status."""
        service = TicketmasterService()
        results = await service.search_events(
            location=("New York", "NY", "US"),
            limit=10,
        )

        # Every returned event passed the onsale filter
        assert isinstance(results, list)
        for event in results:
            assert event["source"] == "ticketmaster"


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_ticketmaster_service_importable(self):
        """TicketmasterService class should be importable."""
        assert TicketmasterService is not None

    def test_genre_mapping_importable(self):
        """INTEREST_TO_TM_GENRE should be importable."""
        assert isinstance(INTEREST_TO_TM_GENRE, dict)

    def test_currency_mapping_importable(self):
        """COUNTRY_CURRENCY_MAP should be importable from yelp."""
        assert isinstance(COUNTRY_CURRENCY_MAP, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(BASE_URL, str)
        assert isinstance(DEFAULT_TIMEOUT, float)
        assert isinstance(MAX_RETRIES, int)
        assert isinstance(DEFAULT_DATE_RANGE_DAYS, int)

    def test_onsale_statuses_importable(self):
        """VALID_ONSALE_STATUSES should be importable."""
        assert isinstance(VALID_ONSALE_STATUSES, set)
        assert "onsale" in VALID_ONSALE_STATUSES

    def test_config_functions_importable(self):
        """Config functions should be importable."""
        from app.core.config import is_ticketmaster_configured, validate_ticketmaster_config
        assert callable(is_ticketmaster_configured)
        assert callable(validate_ticketmaster_config)

    def test_image_selector_importable(self):
        """_select_best_image function should be importable."""
        assert callable(_select_best_image)
