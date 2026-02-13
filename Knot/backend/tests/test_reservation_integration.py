"""
Step 8.5 Verification: OpenTable/Resy Reservation Integration

Tests that:
1. ReservationService generates correct OpenTable search URLs
2. ReservationService generates correct Resy search URLs
3. Cuisine-to-search-term mapping covers expected interests
4. City-to-Resy-slug mapping covers major cities
5. Time slot generation centers around preferred time
6. Results are normalized to CandidateRecommendation schema
7. Date validation rejects invalid formats
8. Party size is clamped to valid range
9. Empty/missing location returns empty results
10. Resy results only generated for supported cities
11. OpenTable affiliate ID is appended when configured
12. International locations use correct currency

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)

Run with: pytest tests/test_reservation_integration.py -v
"""

from unittest.mock import patch

import pytest

from app.core.config import is_reservation_configured, validate_reservation_config
from app.services.integrations.reservation import (
    CITY_TO_RESY_SLUG,
    CUISINE_PRICE_ESTIMATE,
    DEFAULT_TIME_SLOTS,
    INTEREST_TO_CUISINE,
    ReservationService,
    _build_opentable_url,
    _build_resy_url,
    _city_to_resy_slug,
    _generate_time_slots,
)


# ======================================================================
# TestOpenTableUrlGeneration
# ======================================================================

class TestOpenTableUrlGeneration:
    """Test OpenTable search URL construction."""

    def test_basic_url_structure(self):
        """Should build a URL with covers, dateTime, term, near params."""
        url = _build_opentable_url(
            cuisine="italian",
            city="New York",
            date_str="2026-02-14",
            time_str="19:00",
            party_size=2,
        )
        assert "https://www.opentable.com/s?" in url
        assert "covers=2" in url
        assert "dateTime=2026-02-14T19%3A00" in url
        assert "term=italian" in url
        assert "near=New+York" in url

    def test_url_encodes_special_characters(self):
        """Should URL-encode spaces and special characters."""
        url = _build_opentable_url(
            cuisine="wine bar",
            city="San Francisco, CA",
            date_str="2026-03-01",
            time_str="18:30",
            party_size=4,
        )
        assert "wine+bar" in url
        assert "San+Francisco" in url

    def test_affiliate_id_appended(self):
        """Should append ref= when affiliate ID is provided."""
        url = _build_opentable_url(
            cuisine="restaurant",
            city="Chicago",
            date_str="2026-03-15",
            time_str="19:00",
            party_size=2,
            affiliate_id="knot-app-123",
        )
        assert "ref=knot-app-123" in url

    def test_no_affiliate_id_omitted(self):
        """Should not include ref= when affiliate ID is empty."""
        url = _build_opentable_url(
            cuisine="restaurant",
            city="Chicago",
            date_str="2026-03-15",
            time_str="19:00",
            party_size=2,
            affiliate_id="",
        )
        assert "ref=" not in url

    def test_datetime_format(self):
        """Should format dateTime as YYYY-MM-DDTHH:MM."""
        url = _build_opentable_url(
            cuisine="sushi",
            city="LA",
            date_str="2026-12-25",
            time_str="20:30",
            party_size=2,
        )
        assert "dateTime=2026-12-25T20%3A30" in url

    def test_url_is_valid_https(self):
        """URL should start with https://www.opentable.com/s?."""
        url = _build_opentable_url(
            cuisine="restaurant",
            city="NYC",
            date_str="2026-01-01",
            time_str="19:00",
            party_size=2,
        )
        assert url.startswith("https://www.opentable.com/s?")


# ======================================================================
# TestResyUrlGeneration
# ======================================================================

class TestResyUrlGeneration:
    """Test Resy search URL construction."""

    def test_basic_url_structure(self):
        """Should build a URL with query, date, seats params."""
        url = _build_resy_url(
            cuisine="italian",
            city_slug="ny",
            date_str="2026-02-14",
            party_size=2,
        )
        assert "https://resy.com/cities/ny" in url
        assert "query=italian" in url
        assert "date=2026-02-14" in url
        assert "seats=2" in url

    def test_city_slug_in_path(self):
        """City slug should appear in the /cities/ path segment."""
        url = _build_resy_url(
            cuisine="sushi",
            city_slug="sf",
            date_str="2026-03-01",
            party_size=2,
        )
        assert "/cities/sf?" in url

    def test_url_encodes_cuisine(self):
        """Should URL-encode special characters in cuisine."""
        url = _build_resy_url(
            cuisine="wine bar",
            city_slug="chi",
            date_str="2026-03-01",
            party_size=3,
        )
        assert "query=wine+bar" in url

    def test_date_format(self):
        """Date should be in YYYY-MM-DD format."""
        url = _build_resy_url(
            cuisine="restaurant",
            city_slug="la",
            date_str="2026-06-15",
            party_size=2,
        )
        assert "date=2026-06-15" in url

    def test_url_is_valid_https(self):
        """URL should start with https://resy.com/cities/."""
        url = _build_resy_url(
            cuisine="restaurant",
            city_slug="ny",
            date_str="2026-01-01",
            party_size=2,
        )
        assert url.startswith("https://resy.com/cities/")


# ======================================================================
# TestCityToResySlug
# ======================================================================

class TestCityToResySlug:
    """Test city name to Resy slug conversion."""

    def test_major_us_cities_mapped(self):
        """Major US cities should map to known slugs."""
        assert _city_to_resy_slug("New York") == "ny"
        assert _city_to_resy_slug("Los Angeles") == "la"
        assert _city_to_resy_slug("San Francisco") == "sf"
        assert _city_to_resy_slug("Chicago") == "chi"
        assert _city_to_resy_slug("Miami") == "mia"

    def test_case_insensitive_lookup(self):
        """Lookup should be case-insensitive."""
        assert _city_to_resy_slug("new york") == "ny"
        assert _city_to_resy_slug("NEW YORK") == "ny"
        assert _city_to_resy_slug("san francisco") == "sf"

    def test_abbreviation_lookup(self):
        """Common abbreviations should map correctly."""
        assert _city_to_resy_slug("NYC") == "ny"
        assert _city_to_resy_slug("SF") == "sf"
        assert _city_to_resy_slug("LA") == "la"
        assert _city_to_resy_slug("DC") == "dc"

    def test_unsupported_city_returns_none(self):
        """Unsupported cities should return None."""
        assert _city_to_resy_slug("Tulsa") is None
        assert _city_to_resy_slug("Boise") is None
        assert _city_to_resy_slug("Albuquerque") is None

    def test_international_cities_mapped(self):
        """International cities in the map should be found."""
        assert _city_to_resy_slug("London") == "london"
        assert _city_to_resy_slug("Paris") == "paris"

    def test_partial_match(self):
        """Partial city name match should work."""
        assert _city_to_resy_slug("San Fran") == "sf"

    def test_empty_city_returns_none(self):
        """Empty or whitespace-only city should return None."""
        assert _city_to_resy_slug("") is None
        assert _city_to_resy_slug("   ") is None


# ======================================================================
# TestTimeSlotGeneration
# ======================================================================

class TestTimeSlotGeneration:
    """Test time slot generation logic."""

    def test_default_slots_returned(self):
        """When no preferred time, should return first N default slots."""
        slots = _generate_time_slots(preferred_time=None, count=4)
        assert len(slots) == 4
        assert slots == DEFAULT_TIME_SLOTS[:4]

    def test_preferred_time_centers_slots(self):
        """Should return slots closest to the preferred time."""
        slots = _generate_time_slots(preferred_time="20:00", count=3)
        assert len(slots) == 3
        # 20:00 should be first since it's exact match
        assert "20:00" in slots
        # Nearby slots should be included
        assert "19:30" in slots or "20:30" in slots

    def test_early_preferred_time(self):
        """Early preferred time should favor early slots."""
        slots = _generate_time_slots(preferred_time="17:30", count=3)
        assert "17:30" in slots
        assert "18:00" in slots

    def test_invalid_time_falls_back(self):
        """Invalid time format should fall back to defaults."""
        slots = _generate_time_slots(preferred_time="not-a-time", count=4)
        assert slots == DEFAULT_TIME_SLOTS[:4]

    def test_count_parameter_respected(self):
        """Should return exactly the requested number of slots."""
        slots = _generate_time_slots(preferred_time=None, count=2)
        assert len(slots) == 2
        slots = _generate_time_slots(preferred_time=None, count=6)
        assert len(slots) == 6


# ======================================================================
# TestCuisineMapping
# ======================================================================

class TestCuisineMapping:
    """Test interest-to-cuisine mapping."""

    def test_food_related_interests_mapped(self):
        """Food-related interests should have cuisine mappings."""
        assert "Cooking" in INTEREST_TO_CUISINE
        assert "Food" in INTEREST_TO_CUISINE
        assert "Wine" in INTEREST_TO_CUISINE
        assert "Coffee" in INTEREST_TO_CUISINE
        assert "Baking" in INTEREST_TO_CUISINE

    def test_all_values_are_strings(self):
        """All mapped values should be non-empty strings."""
        for interest, cuisine in INTEREST_TO_CUISINE.items():
            assert isinstance(cuisine, str), f"Cuisine for '{interest}' is not a string"
            assert len(cuisine) > 0, f"Empty cuisine for '{interest}'"

    def test_default_cuisine_when_unmapped(self):
        """Unmapped interests should not be in the mapping dict."""
        assert "Gaming" not in INTEREST_TO_CUISINE
        assert "Sports" not in INTEREST_TO_CUISINE
        assert "Photography" not in INTEREST_TO_CUISINE


# ======================================================================
# TestReservationNormalization
# ======================================================================

class TestReservationNormalization:
    """Test normalization of reservation data to CandidateRecommendation format."""

    def test_basic_schema_fields(self):
        """Should include all required CandidateRecommendation fields."""
        result = ReservationService._normalize_reservation(
            source="opentable",
            cuisine="italian",
            city="New York",
            state="NY",
            country="US",
            date_str="2026-02-14",
            time_slot="19:00",
            party_size=2,
            booking_url="https://www.opentable.com/s?test=1",
        )
        required_keys = [
            "id", "source", "type", "title", "description",
            "price_cents", "currency", "external_url", "image_url",
            "merchant_name", "location", "metadata",
        ]
        for key in required_keys:
            assert key in result, f"Missing key: {key}"

    def test_source_is_opentable(self):
        """OpenTable results should have source='opentable'."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="restaurant", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://www.opentable.com/s?test=1",
        )
        assert result["source"] == "opentable"

    def test_source_is_resy(self):
        """Resy results should have source='resy'."""
        result = ReservationService._normalize_reservation(
            source="resy", cuisine="restaurant", city="NYC",
            state="", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://resy.com/cities/ny?test=1",
        )
        assert result["source"] == "resy"

    def test_type_is_date(self):
        """All reservation results should have type='date'."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="italian", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result["type"] == "date"

    def test_uuid_format(self):
        """ID should be a valid UUID string (36 characters)."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="restaurant", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert isinstance(result["id"], str)
        assert len(result["id"]) == 36

    def test_opentable_title_format(self):
        """OpenTable title should contain cuisine and platform name."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="italian", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert "Italian" in result["title"]
        assert "OpenTable" in result["title"]

    def test_resy_title_format(self):
        """Resy title should contain cuisine and platform name."""
        result = ReservationService._normalize_reservation(
            source="resy", cuisine="sushi", city="NYC",
            state="", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert "Sushi" in result["title"]
        assert "Resy" in result["title"]

    def test_opentable_description_contains_time(self):
        """OpenTable description should include the time slot."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="italian", city="NYC",
            state="NY", country="US", date_str="2026-02-14",
            time_slot="19:30", party_size=2,
            booking_url="https://test.com",
        )
        assert "19:30" in result["description"]
        assert "2026-02-14" in result["description"]

    def test_resy_description_contains_all_slots(self):
        """Resy description should include all suggested time slots."""
        result = ReservationService._normalize_reservation(
            source="resy", cuisine="italian", city="NYC",
            state="", country="US", date_str="2026-02-14",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
            all_time_slots=["18:30", "19:00", "19:30"],
        )
        assert "18:30" in result["description"]
        assert "19:00" in result["description"]
        assert "19:30" in result["description"]

    def test_metadata_fields(self):
        """Metadata should include all reservation context."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="french", city="NYC",
            state="NY", country="US", date_str="2026-03-15",
            time_slot="20:00", party_size=4,
            booking_url="https://test.com",
        )
        meta = result["metadata"]
        assert meta["cuisine"] == "french"
        assert meta["reservation_date"] == "2026-03-15"
        assert meta["reservation_time"] == "20:00"
        assert meta["party_size"] == 4
        assert meta["platform"] == "opentable"
        assert meta["booking_type"] == "url_redirect"

    def test_currency_based_on_country(self):
        """Currency should be detected from country code."""
        result_us = ReservationService._normalize_reservation(
            source="opentable", cuisine="restaurant", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result_us["currency"] == "USD"

        result_gb = ReservationService._normalize_reservation(
            source="opentable", cuisine="restaurant", city="London",
            state="", country="GB", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result_gb["currency"] == "GBP"

        result_fr = ReservationService._normalize_reservation(
            source="resy", cuisine="french", city="Paris",
            state="", country="FR", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result_fr["currency"] == "EUR"


# ======================================================================
# TestReservationSearch
# ======================================================================

class TestReservationSearch:
    """Test the full search_reservations method."""

    async def test_returns_opentable_results(self):
        """Basic search should return OpenTable results."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="italian",
            reservation_date="2026-02-14",
            reservation_time="19:00",
            party_size=2,
        )
        opentable_results = [r for r in results if r["source"] == "opentable"]
        assert len(opentable_results) > 0
        for r in opentable_results:
            assert r["type"] == "date"
            assert "opentable.com" in r["external_url"]

    async def test_returns_resy_results_for_supported_city(self):
        """Search in a Resy-supported city should return both platforms."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="sushi",
            reservation_date="2026-02-14",
            party_size=2,
        )
        sources = {r["source"] for r in results}
        assert "opentable" in sources
        assert "resy" in sources

    async def test_no_resy_for_unsupported_city(self):
        """Search in an unsupported city should only return OpenTable."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("Tulsa", "OK", "US"),
            cuisine="restaurant",
            reservation_date="2026-02-14",
            party_size=2,
        )
        sources = {r["source"] for r in results}
        assert "opentable" in sources
        assert "resy" not in sources

    async def test_respects_limit(self):
        """Should cap total results at the limit parameter."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="restaurant",
            reservation_date="2026-02-14",
            party_size=2,
            limit=3,
        )
        assert len(results) <= 3

    async def test_default_date_is_tomorrow(self):
        """When no date is provided, should use tomorrow's date."""
        from datetime import date, timedelta
        expected_date = (date.today() + timedelta(days=1)).isoformat()

        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="restaurant",
            party_size=2,
        )
        assert len(results) > 0
        # All results should have tomorrow's date in metadata
        for r in results:
            assert r["metadata"]["reservation_date"] == expected_date

    async def test_empty_city_returns_empty(self):
        """Empty city in location tuple should return empty list."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("", "NY", "US"),
            cuisine="restaurant",
            reservation_date="2026-02-14",
            party_size=2,
        )
        assert results == []

    async def test_invalid_date_returns_empty(self):
        """Invalid date format should return empty list."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="restaurant",
            reservation_date="02/14/2026",
            party_size=2,
        )
        assert results == []

    async def test_party_size_clamped(self):
        """Party size outside 1-20 should be clamped."""
        service = ReservationService()
        # Party size 0 gets clamped to 1
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="restaurant",
            reservation_date="2026-02-14",
            party_size=0,
        )
        assert len(results) > 0
        for r in results:
            assert r["metadata"]["party_size"] == 1

        # Party size 50 gets clamped to 20
        results2 = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="restaurant",
            reservation_date="2026-02-14",
            party_size=50,
        )
        assert len(results2) > 0
        for r in results2:
            assert r["metadata"]["party_size"] == 20


# ======================================================================
# TestReservationDateValidation
# ======================================================================

class TestReservationDateValidation:
    """Test date format validation."""

    def test_valid_date_accepted(self):
        """YYYY-MM-DD format should be accepted."""
        assert ReservationService._is_valid_date("2026-03-15") is True

    def test_invalid_format_rejected(self):
        """MM/DD/YYYY format should be rejected."""
        assert ReservationService._is_valid_date("03/15/2026") is False

    def test_invalid_date_rejected(self):
        """Invalid calendar date should be rejected."""
        assert ReservationService._is_valid_date("2026-13-45") is False

    def test_empty_date_rejected(self):
        """Empty string should be rejected."""
        assert ReservationService._is_valid_date("") is False


# ======================================================================
# TestSaturdayEveningSearch
# ======================================================================

class TestSaturdayEveningSearch:
    """
    Test the specific scenario from the implementation plan:
    Search for available reservations for 2 people on a Saturday evening.
    """

    async def test_saturday_evening_search_for_two(self):
        """Should return results with specific time slots for 2 people."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("New York", "NY", "US"),
            cuisine="italian",
            reservation_date="2026-02-14",  # Saturday
            reservation_time="19:00",
            party_size=2,
        )

        assert len(results) > 0

        # Check that results include time slots
        for r in results:
            assert "time_slots" in r["metadata"]
            assert len(r["metadata"]["time_slots"]) > 0
            # Each time slot should be HH:MM format
            for slot in r["metadata"]["time_slots"]:
                parts = slot.split(":")
                assert len(parts) == 2
                assert 0 <= int(parts[0]) <= 23
                assert 0 <= int(parts[1]) <= 59

    async def test_booking_urls_contain_correct_parameters(self):
        """Booking URLs should contain the date, party size, and cuisine."""
        service = ReservationService()
        results = await service.search_reservations(
            location=("San Francisco", "CA", "US"),
            cuisine="sushi",
            reservation_date="2026-02-14",
            reservation_time="20:00",
            party_size=2,
        )

        for r in results:
            url = r["external_url"]
            assert url.startswith("https://")
            # URL should contain party size and date info
            if r["source"] == "opentable":
                assert "covers=2" in url
                assert "2026-02-14" in url
                assert "sushi" in url.lower()
            elif r["source"] == "resy":
                assert "seats=2" in url
                assert "date=2026-02-14" in url
                assert "sushi" in url.lower()


# ======================================================================
# TestOpenTableAffiliateId
# ======================================================================

class TestOpenTableAffiliateId:
    """Test OpenTable affiliate ID integration."""

    async def test_affiliate_id_in_opentable_urls(self):
        """When configured, affiliate ID should appear in OpenTable URLs."""
        with patch(
            "app.services.integrations.reservation.OPENTABLE_AFFILIATE_ID",
            "knot-test-123",
        ):
            service = ReservationService()
            results = await service.search_reservations(
                location=("New York", "NY", "US"),
                cuisine="restaurant",
                reservation_date="2026-02-14",
                party_size=2,
            )
            opentable_results = [r for r in results if r["source"] == "opentable"]
            for r in opentable_results:
                assert "ref=knot-test-123" in r["external_url"]

    async def test_no_affiliate_id_when_empty(self):
        """When not configured, no ref= param in OpenTable URLs."""
        with patch(
            "app.services.integrations.reservation.OPENTABLE_AFFILIATE_ID",
            "",
        ):
            service = ReservationService()
            results = await service.search_reservations(
                location=("New York", "NY", "US"),
                cuisine="restaurant",
                reservation_date="2026-02-14",
                party_size=2,
            )
            opentable_results = [r for r in results if r["source"] == "opentable"]
            for r in opentable_results:
                assert "ref=" not in r["external_url"]


# ======================================================================
# TestPriceEstimation
# ======================================================================

class TestPriceEstimation:
    """Test cuisine-based price estimation."""

    def test_known_cuisine_has_price(self):
        """Known cuisines should have price estimates."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="italian", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result["price_cents"] == 4500  # italian = 4500

    def test_unknown_cuisine_no_price(self):
        """Unknown cuisines should have None for price_cents."""
        result = ReservationService._normalize_reservation(
            source="opentable", cuisine="exotic_fusion", city="NYC",
            state="NY", country="US", date_str="2026-01-01",
            time_slot="19:00", party_size=2,
            booking_url="https://test.com",
        )
        assert result["price_cents"] is None

    def test_all_cuisine_prices_are_positive(self):
        """All price estimates should be positive integers."""
        for cuisine, price in CUISINE_PRICE_ESTIMATE.items():
            assert isinstance(price, int), f"Price for '{cuisine}' is not int"
            assert price > 0, f"Price for '{cuisine}' is not positive"


# ======================================================================
# TestModuleImports
# ======================================================================

class TestModuleImports:
    """Verify all expected exports are accessible."""

    def test_reservation_service_importable(self):
        """ReservationService class should be importable."""
        assert ReservationService is not None

    def test_cuisine_mapping_importable(self):
        """INTEREST_TO_CUISINE should be importable."""
        assert isinstance(INTEREST_TO_CUISINE, dict)

    def test_resy_slug_mapping_importable(self):
        """CITY_TO_RESY_SLUG should be importable."""
        assert isinstance(CITY_TO_RESY_SLUG, dict)

    def test_constants_importable(self):
        """Module constants should be importable."""
        assert isinstance(DEFAULT_TIME_SLOTS, list)
        assert isinstance(CUISINE_PRICE_ESTIMATE, dict)

    def test_config_functions_importable(self):
        """Config functions should be importable and callable."""
        assert callable(is_reservation_configured)
        assert callable(validate_reservation_config)

    def test_config_always_true(self):
        """Reservation config functions should always return True."""
        assert is_reservation_configured() is True
        assert validate_reservation_config() is True

    def test_helper_functions_importable(self):
        """Helper functions should be importable."""
        assert callable(_build_opentable_url)
        assert callable(_build_resy_url)
        assert callable(_city_to_resy_slug)
        assert callable(_generate_time_slots)
