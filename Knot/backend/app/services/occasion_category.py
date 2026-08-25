"""
Occasion Category — the stable key identifying WHICH occasion a milestone is.

`milestone_type` only distinguishes birthday / anniversary / holiday / custom.
Every holiday is stored as a free-text `milestone_name`, so before this module
there was no way to tell Christmas from Diwali except by matching the name.

The occasion category is that missing key. It drives two things:

  1. The per-occasion entry modal (copy + illustration) shown when a user taps a
     milestone push notification.
  2. Date computation for holidays that are not fixed in the Gregorian calendar
     (see notification_scheduler: Thanksgiving, Easter, and the lunisolar four).

Resolution is deliberately layered so that rows written before migration 00027
— which have `occasion_category = NULL` — keep working with no backfill.
"""

from __future__ import annotations

import re

# ======================================================================
# Canonical categories
# ======================================================================

#: Every occasion the app can render an entry modal for. Values are the stable
#: keys persisted in `partner_milestones.occasion_category` and mirrored by the
#: iOS asset slugs (`occasion-<key>` with underscores swapped for dashes).
DEFAULT_CATEGORY = "default"

OCCASION_CATEGORIES: frozenset[str] = frozenset(
    {
        # Relationship
        "birthday",
        "anniversary",
        # Romantic
        "valentines_day",
        "new_years",
        # Family role
        "mothers_day",
        "fathers_day",
        # Gifting season
        "christmas",
        "hanukkah",
        "diwali",
        "lunar_new_year",
        "eid",
        # Seasonal
        "thanksgiving",
        "easter",
        "halloween",
        # Life events
        "graduation",
        "new_job",
        "new_home",
        "big_day",
        "thinking_of_you",
        # Non-date
        "just_because",
        "hint_followup",
        # Fallback
        DEFAULT_CATEGORY,
    }
)


# ======================================================================
# Legacy name matching
# ======================================================================

#: Phrases that identify a category from a legacy milestone name.
#:
#: Matched against the lowercased name for rows written before migration 00027.
#:
#: Two rules keep this honest, both learned from real misfires:
#:
#:   * **Word boundaries.** Matching is `\bphrase\b`, not a bare substring. The
#:     previous implementation matched the substring "mother", which rerouted
#:     "Grandmother's Birthday" to the 2nd Sunday of May. Boundaries also stop
#:     "eid" matching inside a name like "Deidre's Birthday".
#:   * **Order.** The first match wins, so a more specific phrase must precede
#:     any phrase it contains — "lunar new year" before "new year", or every
#:     Lunar New Year silently becomes New Year's Eve.
_NAME_PATTERNS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("mothers_day", ("mother's day", "mothers day", "mother’s day")),
    ("fathers_day", ("father's day", "fathers day", "father’s day")),
    ("valentines_day", ("valentine", "valentines", "valentine's")),
    ("lunar_new_year", ("lunar new year", "chinese new year")),
    ("new_years", ("new year", "new years", "new year's")),
    ("christmas", ("christmas", "xmas")),
    ("hanukkah", ("hanukkah", "chanukah")),
    ("diwali", ("diwali", "deepavali")),
    ("eid", ("eid",)),
    ("thanksgiving", ("thanksgiving",)),
    ("easter", ("easter",)),
    ("halloween", ("halloween", "hallowe'en")),
    ("graduation", ("graduation", "graduating")),
    ("new_home", ("housewarming", "new home", "moving day")),
    ("new_job", ("new job", "promotion", "first day at")),
    ("anniversary", ("anniversary",)),
    ("birthday", ("birthday", "bday")),
)

#: Precompiled word-boundary matchers, in the same precedence order.
_NAME_MATCHERS: tuple[tuple[str, re.Pattern[str]], ...] = tuple(
    (
        category,
        re.compile(
            "|".join(rf"\b{re.escape(phrase)}\b" for phrase in phrases)
        ),
    )
    for category, phrases in _NAME_PATTERNS
)

#: Fallback when nothing else matches: the milestone_type itself is a category
#: for two of its four values.
_TYPE_TO_CATEGORY: dict[str, str] = {
    "birthday": "birthday",
    "anniversary": "anniversary",
}


# ======================================================================
# Resolution
# ======================================================================

def category_from_name(milestone_name: str) -> str | None:
    """
    Best-effort category from a milestone's display name.

    Used for rows created before `occasion_category` existed. Returns None when
    no pattern matches, so callers can fall through to the type mapping.
    """
    if not milestone_name:
        return None

    name_lower = milestone_name.lower()
    for category, matcher in _NAME_MATCHERS:
        if matcher.search(name_lower):
            return category
    return None


def resolve_occasion_category(
    *,
    occasion_category: str | None = None,
    milestone_name: str = "",
    milestone_type: str = "",
) -> str:
    """
    Resolve a milestone to its occasion category.

    Precedence:
      1. The persisted `occasion_category`, when set and recognised.
      2. A pattern match on `milestone_name` (legacy holiday rows only).
      3. The `milestone_type`, for the two types that are themselves categories.
      4. `"default"` — custom milestones and anything unrecognised.

    Never raises and never returns None: an unrecognised persisted value falls
    through to the same ladder as a missing one, so a typo or a key written by a
    newer client can't break an older server.
    """
    if occasion_category:
        normalized = occasion_category.strip().lower()
        if normalized in OCCASION_CATEGORIES:
            return normalized

    if _name_matching_applies(milestone_type):
        from_name = category_from_name(milestone_name)
        if from_name is not None:
            return from_name

    return _TYPE_TO_CATEGORY.get(milestone_type, DEFAULT_CATEGORY)


def _name_matching_applies(milestone_type: str) -> bool:
    """
    Whether a legacy row's name may be used to derive its category.

    Rung 2 exists for one population: holidays written before migration 00027,
    whose name is the only signal of which holiday they are. Letting it run for
    every type does real damage — a *custom* milestone called "Easter egg hunt"
    would be classified `easter` and permanently rescheduled onto the computed
    Easter date, discarding the date the user actually chose. Birthdays and
    anniversaries need it even less: rung 3 already names them exactly.

    An empty type means the caller doesn't know, so matching is allowed — that
    keeps the fallback available rather than silently narrowing it.
    """
    return milestone_type in ("", "holiday")


def resolve_from_row(milestone: dict) -> str:
    """Convenience wrapper for a `partner_milestones` row dict."""
    return resolve_occasion_category(
        occasion_category=milestone.get("occasion_category"),
        milestone_name=milestone.get("milestone_name", ""),
        milestone_type=milestone.get("milestone_type", ""),
    )
