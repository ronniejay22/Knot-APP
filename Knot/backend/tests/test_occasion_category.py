"""
Occasion Category Resolution

Tests the ladder that turns a milestone row into the stable occasion key driving
the entry modal and the holiday date math:

  1. persisted `occasion_category`
  2. name pattern match (rows predating migration 00027)
  3. `milestone_type`
  4. "default"

Pure unit tests — no Supabase, no network.

Run with: pytest tests/test_occasion_category.py -v
"""

import pytest

from app.services.occasion_category import (
    DEFAULT_CATEGORY,
    OCCASION_CATEGORIES,
    category_from_name,
    resolve_from_row,
    resolve_occasion_category,
)


# ===================================================================
# 1. The category set
# ===================================================================

class TestCategorySet:
    """The canonical list the client's assets and copy are keyed on."""

    def test_contains_all_twenty_two(self):
        assert len(OCCASION_CATEGORIES) == 22

    def test_default_is_a_member(self):
        assert DEFAULT_CATEGORY in OCCASION_CATEGORIES

    def test_keys_are_snake_case(self):
        """Slugs map to iOS asset names, so no spaces, dashes or capitals."""
        for category in OCCASION_CATEGORIES:
            assert category == category.lower()
            assert " " not in category
            assert "-" not in category


# ===================================================================
# 2. Precedence
# ===================================================================

class TestPrecedence:
    """Each rung of the ladder, and that the higher one wins."""

    def test_persisted_category_wins(self):
        """A stored key beats both the name and the type."""
        assert resolve_occasion_category(
            occasion_category="thanksgiving",
            milestone_name="Christmas",
            milestone_type="birthday",
        ) == "thanksgiving"

    def test_falls_back_to_name(self):
        assert resolve_occasion_category(
            occasion_category=None,
            milestone_name="Christmas",
            milestone_type="holiday",
        ) == "christmas"

    def test_falls_back_to_type(self):
        """An unrecognised name on a birthday still resolves to birthday."""
        assert resolve_occasion_category(
            occasion_category=None,
            milestone_name="The Big One",
            milestone_type="birthday",
        ) == "birthday"

    def test_falls_back_to_default(self):
        assert resolve_occasion_category(
            occasion_category=None,
            milestone_name="Trip to Lisbon",
            milestone_type="custom",
        ) == DEFAULT_CATEGORY

    def test_unknown_persisted_value_does_not_win(self):
        """
        A key written by a newer client (or a typo) must not break an older
        server — it falls through the same ladder as a missing value.
        """
        assert resolve_occasion_category(
            occasion_category="mardi_gras",
            milestone_name="Christmas",
            milestone_type="holiday",
        ) == "christmas"

    def test_persisted_value_is_normalized(self):
        assert resolve_occasion_category(
            occasion_category="  Thanksgiving  ",
        ) == "thanksgiving"

    def test_empty_string_is_treated_as_missing(self):
        assert resolve_occasion_category(
            occasion_category="",
            milestone_name="Diwali",
        ) == "diwali"

    def test_never_returns_none(self):
        """Called with nothing at all it still yields a usable key."""
        assert resolve_occasion_category() == DEFAULT_CATEGORY


# ===================================================================
# 3. Name matching
# ===================================================================

class TestNameMatching:
    """Legacy rows are resolved from their display name."""

    @pytest.mark.parametrize(
        "name,expected",
        [
            ("Mother's Day", "mothers_day"),
            ("Mother’s Day", "mothers_day"),          # curly apostrophe
            ("Mothers Day", "mothers_day"),
            ("Father's Day", "fathers_day"),
            ("Valentine's Day", "valentines_day"),
            ("New Year's Eve", "new_years"),
            ("Christmas", "christmas"),
            ("Hanukkah", "hanukkah"),
            ("Chanukah", "hanukkah"),
            ("Diwali", "diwali"),
            ("Deepavali", "diwali"),
            ("Lunar New Year", "lunar_new_year"),
            ("Chinese New Year", "lunar_new_year"),
            ("Eid", "eid"),
            ("Thanksgiving", "thanksgiving"),
            ("Easter", "easter"),
            ("Halloween", "halloween"),
            ("Jas's Graduation", "graduation"),
            ("Housewarming", "new_home"),
            ("Our Anniversary", "anniversary"),
            ("Jas's Birthday", "birthday"),
        ],
    )
    def test_known_names(self, name, expected):
        assert category_from_name(name) == expected

    def test_case_insensitive(self):
        assert category_from_name("CHRISTMAS") == "christmas"
        assert category_from_name("thanksgiving dinner") == "thanksgiving"

    def test_lunar_new_year_beats_new_years(self):
        """
        "Lunar New Year" contains "new year". Pattern order must resolve the
        more specific holiday, or every Lunar New Year becomes NYE.
        """
        assert category_from_name("Lunar New Year") == "lunar_new_year"
        assert category_from_name("Chinese New Year") == "lunar_new_year"
        assert category_from_name("New Year's Eve") == "new_years"

    def test_specific_day_names_beat_bare_relations(self):
        """The regression that motivated tightening these patterns."""
        assert category_from_name("Grandmother's Birthday") == "birthday"
        assert category_from_name("Stepfather's Birthday") == "birthday"

    def test_unmatched_returns_none(self):
        assert category_from_name("Trip to Lisbon") is None
        assert category_from_name("") is None


class TestNameMatchingIsScopedToHolidays:
    """
    Name matching exists for one population — holidays written before the
    column did. Letting it run for every type reclassifies user-chosen dates.
    """

    def test_custom_milestone_keeps_its_own_date(self):
        """
        The damaging case: "Easter egg hunt" is a custom milestone on a real
        date the user picked. Classifying it `easter` would permanently
        reschedule it onto the computed Easter.
        """
        assert (
            resolve_occasion_category(
                milestone_name="Easter egg hunt", milestone_type="custom"
            )
            == DEFAULT_CATEGORY
        )
        assert (
            resolve_occasion_category(
                milestone_name="Diwali dinner with her parents",
                milestone_type="custom",
            )
            == DEFAULT_CATEGORY
        )

    def test_birthday_type_is_never_reclassified_by_its_name(self):
        assert (
            resolve_occasion_category(
                milestone_name="Christmas Eve Birthday", milestone_type="birthday"
            )
            == "birthday"
        )

    def test_holiday_type_still_matches(self):
        """The population this rung was built for."""
        assert (
            resolve_occasion_category(
                milestone_name="Thanksgiving", milestone_type="holiday"
            )
            == "thanksgiving"
        )

    def test_unknown_type_still_matches(self):
        """An empty type means the caller doesn't know — keep the fallback."""
        assert (
            resolve_occasion_category(milestone_name="Thanksgiving")
            == "thanksgiving"
        )

    def test_explicit_category_wins_even_for_custom(self):
        """Scoping rung 2 must not touch rung 1."""
        assert (
            resolve_occasion_category(
                occasion_category="graduation",
                milestone_name="Easter egg hunt",
                milestone_type="custom",
            )
            == "graduation"
        )


# ===================================================================
# 4. Row helper
# ===================================================================

class TestResolveFromRow:
    """The convenience wrapper used by the API response builders."""

    def test_reads_all_three_fields(self):
        row = {
            "occasion_category": "eid",
            "milestone_name": "Christmas",
            "milestone_type": "holiday",
        }
        assert resolve_from_row(row) == "eid"

    def test_legacy_row_without_column(self):
        """A row selected before the column existed has no key at all."""
        row = {"milestone_name": "Valentine's Day", "milestone_type": "holiday"}
        assert resolve_from_row(row) == "valentines_day"

    def test_null_column_falls_through(self):
        row = {
            "occasion_category": None,
            "milestone_name": "Jas's Birthday",
            "milestone_type": "birthday",
        }
        assert resolve_from_row(row) == "birthday"

    def test_empty_row_is_default(self):
        assert resolve_from_row({}) == DEFAULT_CATEGORY
