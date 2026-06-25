"""
Tests for URL resolution query localization.

`_localize_search_query` appends the partner's city/state to a Brave query for
location-bound experiences (date/experience candidates carry a `location`), so
booking links resolve locally even when Claude omits the city. Gifts/ideas have
no `location` and are left unchanged.

Run with: pytest tests/test_url_resolution.py -v
"""

from app.agents.state import LocationData
from app.agents.url_resolution import _localize_search_query


class TestLocalizeSearchQuery:
    def test_appends_city_and_state_when_missing(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        result = _localize_search_query("couples pottery class", loc)
        assert result == "couples pottery class Austin TX"

    def test_no_double_append_when_locale_present(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        query = "couples pottery class Austin TX"
        assert _localize_search_query(query, loc) == query

    def test_case_insensitive_locale_match(self):
        loc = LocationData(city="Austin", state="TX", country="US")
        query = "rooftop dinner austin tx"
        # Full locale already present (case-insensitive) — left unchanged.
        assert _localize_search_query(query, loc) == query

    def test_homonym_city_not_falsely_suppressed(self):
        # "Reading" is also a common word; a bare-substring check would wrongly
        # see it in "reading nook" and skip localization. The full-locale check
        # must still append "Reading PA".
        loc = LocationData(city="Reading", state="PA", country="US")
        result = _localize_search_query("couples reading nook event", loc)
        assert result == "couples reading nook event Reading PA"

    def test_unchanged_when_no_location(self):
        assert _localize_search_query("chef knife", None) == "chef knife"

    def test_unchanged_when_location_has_no_city(self):
        loc = LocationData(city=None, state="TX", country="US")
        assert _localize_search_query("chef knife", loc) == "chef knife"

    def test_city_only_when_no_state(self):
        loc = LocationData(city="Austin", state=None, country="US")
        assert _localize_search_query("jazz concert tickets", loc) == "jazz concert tickets Austin"
