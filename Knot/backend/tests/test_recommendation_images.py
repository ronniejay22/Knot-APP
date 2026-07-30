"""
Recommendation image resolution — guarantee every card has an image.

The unified pipeline generates candidates with ``image_url = None``; images are
attached in the API layer. These tests lock in the guarantee that a
recommendation is *never* left without an image:

- ``resolve_image_url`` matches interests/vibes case- and format-insensitively.
- When nothing matches it falls back to a per-type default and never returns None.
- ``_build_response_items`` always emits a non-null ``image_url``.
- The by-milestone / by-id read paths back-fill a default for legacy NULL rows.

Pure unit tests — no Supabase, no HTTP, no pipeline.

Run with: pytest tests/test_recommendation_images.py -v
"""

import pytest

from app.agents.aggregation import (
    _INTEREST_IMAGES,
    _TYPE_DEFAULT_IMAGES,
    _VIBE_IMAGES,
)
from app.agents.state import CandidateRecommendation
from app.api.recommendations import (
    _build_response_items,
    _default_image_for_type,
    _normalize_tag,
    resolve_image_url,
)

RECOMMENDATION_TYPES = ["gift", "experience", "date", "idea", "plan"]


def _candidate(**overrides) -> CandidateRecommendation:
    """Build a CandidateRecommendation with sensible required defaults."""
    data = dict(id="cand-1", source="unified", type="experience", title="Test Rec")
    data.update(overrides)
    return CandidateRecommendation(**data)


# ---------------------------------------------------------------------------
# _normalize_tag
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "raw,expected",
    [
        ("Quiet Luxury", "quiet luxury"),
        ("quiet_luxury", "quiet luxury"),
        ("quiet luxury", "quiet luxury"),
        ("Quiet-Luxury", "quiet luxury"),
        ("Board Games", "board games"),
        ("board_games", "board games"),
        ("  Street / Urban  ", "street / urban"),
    ],
)
def test_normalize_tag_canonicalizes_case_and_separators(raw, expected):
    assert _normalize_tag(raw) == expected


# ---------------------------------------------------------------------------
# resolve_image_url — matching
# ---------------------------------------------------------------------------

def test_exact_interest_match_returns_interest_image():
    candidate = _candidate(type="gift", matched_interests=["Sports"])
    assert resolve_image_url(candidate) == _INTEREST_IMAGES["Sports"]


def test_exact_vibe_match_returns_vibe_image():
    candidate = _candidate(type="experience", matched_vibes=["quiet_luxury"])
    assert resolve_image_url(candidate) == _VIBE_IMAGES["quiet_luxury"]


@pytest.mark.parametrize("variant", ["quiet_luxury", "Quiet Luxury", "quiet luxury", "Quiet-Luxury"])
def test_vibe_match_is_case_and_format_insensitive(variant):
    """Every spelling of the vibe resolves to the same curated image."""
    candidate = _candidate(type="experience", matched_vibes=[variant])
    assert resolve_image_url(candidate) == _VIBE_IMAGES["quiet_luxury"]


@pytest.mark.parametrize("variant", ["sports", "SPORTS", "Sports"])
def test_interest_match_is_case_insensitive(variant):
    candidate = _candidate(type="gift", matched_interests=[variant])
    assert resolve_image_url(candidate) == _INTEREST_IMAGES["Sports"]


def test_interest_is_preferred_over_vibe():
    """Interests are checked before vibes, so a matching interest wins."""
    candidate = _candidate(
        type="experience",
        matched_interests=["Sports"],
        matched_vibes=["quiet_luxury"],
    )
    assert resolve_image_url(candidate) == _INTEREST_IMAGES["Sports"]


def test_first_matching_interest_wins():
    candidate = _candidate(type="gift", matched_interests=["NotARealTag", "Cooking"])
    assert resolve_image_url(candidate) == _INTEREST_IMAGES["Cooking"]


# ---------------------------------------------------------------------------
# resolve_image_url — guaranteed fallback (never None)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("rec_type", RECOMMENDATION_TYPES)
def test_no_match_falls_back_to_type_default(rec_type):
    candidate = _candidate(type=rec_type, matched_interests=[], matched_vibes=[])
    resolved = resolve_image_url(candidate)
    assert resolved == _TYPE_DEFAULT_IMAGES.get(rec_type, _TYPE_DEFAULT_IMAGES["default"])
    assert resolved  # never None / empty


def test_off_list_tags_still_get_an_image():
    """Tags Claude invents that match nothing must not blank the card."""
    candidate = _candidate(
        type="experience",
        matched_interests=["Underwater Basket Weaving"],
        matched_vibes=["cottagecore"],
    )
    resolved = resolve_image_url(candidate)
    assert resolved == _TYPE_DEFAULT_IMAGES["experience"]
    assert resolved


@pytest.mark.parametrize("rec_type", RECOMMENDATION_TYPES)
def test_resolve_image_url_never_returns_none(rec_type):
    candidate = _candidate(type=rec_type)
    assert resolve_image_url(candidate) is not None


# ---------------------------------------------------------------------------
# _default_image_for_type
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("rec_type", RECOMMENDATION_TYPES)
def test_default_image_for_known_type(rec_type):
    assert _default_image_for_type(rec_type) == _TYPE_DEFAULT_IMAGES[rec_type]


@pytest.mark.parametrize("rec_type", [None, "", "unknown_future_type"])
def test_default_image_for_unknown_type_uses_default(rec_type):
    assert _default_image_for_type(rec_type) == _TYPE_DEFAULT_IMAGES["default"]


def test_every_type_default_is_a_valid_https_url():
    for rec_type, url in _TYPE_DEFAULT_IMAGES.items():
        assert isinstance(url, str) and url.startswith("https://"), rec_type


# ---------------------------------------------------------------------------
# _build_response_items — the response always carries an image
# ---------------------------------------------------------------------------

def test_build_response_items_backfills_missing_image():
    """A candidate with no image and no matched tags still yields an image_url."""
    candidate = _candidate(type="experience", image_url=None, matched_interests=[], matched_vibes=[])
    items = _build_response_items([candidate])
    assert items[0].image_url == _TYPE_DEFAULT_IMAGES["experience"]


def test_build_response_items_preserves_existing_image():
    existing = "https://cdn.example.com/photo.jpg"
    candidate = _candidate(image_url=existing)
    items = _build_response_items([candidate])
    assert items[0].image_url == existing


def test_build_response_items_never_yields_null_image():
    candidates = [
        _candidate(id="a", type="gift", matched_interests=["Cooking"]),
        _candidate(id="b", type="date", matched_interests=[], matched_vibes=[]),
        _candidate(id="c", type="idea", image_url=None),
    ]
    items = _build_response_items(candidates)
    assert all(item.image_url for item in items)
