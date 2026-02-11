"""
Vibe and Love Language Matching Node — LangGraph node for scoring candidates
by aesthetic vibe alignment and love language preferences.

1. Computes vibe_boost from matching vault vibes to candidate vibes
2. Computes love_language_boost from primary/secondary love language alignment
3. Calculates final_score = max(interest_score, 1.0) × (1 + vibe_boost) × (1 + love_language_boost)
4. Re-ranks candidates by final_score (descending)

The max(1.0) floor ensures experience candidates with 0.0 interest_score (the
default from the filtering node) still benefit from vibe and love language
matching. Without it, the spec formula (base × multipliers) would collapse to 0.

Currently uses metadata/keyword matching for deterministic scoring.
In Phase 8, Gemini 1.5 Pro will classify candidate vibes semantically
when real API data (without pre-tagged metadata) is used.

Step 5.5: Create Vibe and Love Language Matching Node
"""

import logging
from typing import Any

from app.agents.state import CandidateRecommendation, RecommendationState

logger = logging.getLogger(__name__)


# ======================================================================
# Vibe matching constants and helpers
# ======================================================================

VIBE_MATCH_BOOST = 0.30  # +30% per matching vibe tag

# Vibe → keywords for text-based matching (supplements metadata tags).
# In Phase 8, Gemini 1.5 Pro replaces keyword matching with semantic classification.
_VIBE_KEYWORDS: dict[str, list[str]] = {
    "quiet_luxury": [
        "luxury", "fine dining", "exclusive", "upscale",
        "boutique", "sommelier", "omakase", "artisan", "spa",
    ],
    "street_urban": [
        "street art", "urban", "underground", "food truck", "graffiti", "mural",
    ],
    "outdoorsy": [
        "outdoor", "kayak", "hiking", "climbing", "balloon",
        "nature", "trail",
    ],
    "vintage": [
        "vintage", "antique", "classic", "retro", "prohibition", "speakeasy",
    ],
    "minimalist": [
        "minimalist", "zen", "meditation", "tea ceremony", "mindfulness",
        "architecture",
    ],
    "bohemian": [
        "pottery", "indie", "tie-dye", "handmade", "craft", "workshop",
    ],
    "romantic": [
        "romantic", "candlelit", "sunset", "stargazing", "cruise", "couples",
    ],
    "adventurous": [
        "adventure", "skydiving", "rafting", "escape room", "extreme",
        "thrill", "white water",
    ],
}


def _normalize(text: str) -> str:
    """Lowercase and strip a string for comparison."""
    return text.strip().lower()


def _candidate_matches_vibe(
    candidate: CandidateRecommendation,
    vibe: str,
) -> bool:
    """
    Check if a candidate matches a given vibe.

    Uses multiple signals (checked in order of strength):
    1. Metadata ``matched_vibe`` — exact tag from the stub catalog
    2. Title/description keyword match — case-insensitive substring

    Args:
        candidate: The recommendation candidate to check.
        vibe: A vibe tag (e.g., "quiet_luxury").

    Returns:
        True if the candidate matches the vibe.
    """
    norm_vibe = _normalize(vibe)

    # 1. Metadata exact match (strongest signal — stub catalogs tag this)
    matched_vibe = candidate.metadata.get("matched_vibe", "")
    if _normalize(matched_vibe) == norm_vibe:
        return True

    # 2. Keyword matching in title/description
    keywords = _VIBE_KEYWORDS.get(norm_vibe, [])
    if not keywords:
        return False

    text = _normalize(candidate.title)
    if candidate.description:
        text += " " + _normalize(candidate.description)

    for keyword in keywords:
        if keyword in text:
            return True

    return False


def _compute_vibe_boost(
    candidate: CandidateRecommendation,
    vault_vibes: list[str],
) -> float:
    """
    Compute the vibe boost for a candidate.

    Each matching vibe contributes +30% (0.30).
    Multiple matching vibes stack additively.

    Args:
        candidate: The recommendation candidate to score.
        vault_vibes: The partner's selected vibe tags (1-8).

    Returns:
        Total vibe boost as a float (e.g., 0.60 for 2 matching vibes).
    """
    boost = 0.0
    for vibe in vault_vibes:
        if _candidate_matches_vibe(candidate, vibe):
            boost += VIBE_MATCH_BOOST
    return boost


# ======================================================================
# Love language matching constants and helpers
# ======================================================================

# (primary_boost, secondary_boost) for each love language
_LOVE_LANGUAGE_BOOSTS: dict[str, tuple[float, float]] = {
    "receiving_gifts": (0.40, 0.20),
    "quality_time": (0.40, 0.20),
    "acts_of_service": (0.20, 0.10),
    "words_of_affirmation": (0.20, 0.10),
    "physical_touch": (0.20, 0.10),
}

# Keywords for context-dependent love language matching
_ACTS_OF_SERVICE_KEYWORDS: list[str] = [
    "tool", "kit", "repair", "practical", "organizer", "useful",
    "home", "cleaning", "service",
]

_WORDS_OF_AFFIRMATION_KEYWORDS: list[str] = [
    "personalized", "custom", "portrait", "engraved", "sentimental",
    "monogram", "letter", "journal", "poem", "song",
]

_PHYSICAL_TOUCH_KEYWORDS: list[str] = [
    "couples", "massage", "spa", "dance class",
    "together", "two people", "for two",
]


def _candidate_matches_love_language(
    candidate: CandidateRecommendation,
    love_language: str,
) -> bool:
    """
    Check if a candidate aligns with a specific love language.

    Matching criteria per love language:
    - receiving_gifts: gift-type items
    - quality_time: experiences/dates
    - acts_of_service: practical/useful gifts (keyword-based)
    - words_of_affirmation: personalized/sentimental items (keyword-based)
    - physical_touch: couples experiences (keyword-based)

    Args:
        candidate: The recommendation candidate to check.
        love_language: A love language key (e.g., "quality_time").

    Returns:
        True if the candidate aligns with the love language.
    """
    ll = _normalize(love_language)

    if ll == "receiving_gifts":
        return candidate.type == "gift"

    if ll == "quality_time":
        return candidate.type in ("experience", "date")

    # Keyword-based matching for the remaining three
    text = _normalize(candidate.title)
    if candidate.description:
        text += " " + _normalize(candidate.description)

    if ll == "acts_of_service":
        keywords = _ACTS_OF_SERVICE_KEYWORDS
    elif ll == "words_of_affirmation":
        keywords = _WORDS_OF_AFFIRMATION_KEYWORDS
    elif ll == "physical_touch":
        keywords = _PHYSICAL_TOUCH_KEYWORDS
    else:
        return False

    return any(kw in text for kw in keywords)


def _compute_love_language_boost(
    candidate: CandidateRecommendation,
    primary_love_language: str,
    secondary_love_language: str,
) -> float:
    """
    Compute the love language boost for a candidate.

    Checks if the candidate matches the primary and/or secondary
    love language. Boosts stack if both match.

    Args:
        candidate: The recommendation candidate to score.
        primary_love_language: The partner's primary love language.
        secondary_love_language: The partner's secondary love language.

    Returns:
        Total love language boost as a float (e.g., 0.60 for both matching).
    """
    boost = 0.0

    # Primary love language check
    if _candidate_matches_love_language(candidate, primary_love_language):
        primary_boost, _ = _LOVE_LANGUAGE_BOOSTS.get(
            _normalize(primary_love_language), (0.0, 0.0),
        )
        boost += primary_boost

    # Secondary love language check
    if _candidate_matches_love_language(candidate, secondary_love_language):
        _, secondary_boost = _LOVE_LANGUAGE_BOOSTS.get(
            _normalize(secondary_love_language), (0.0, 0.0),
        )
        boost += secondary_boost

    return boost


# ======================================================================
# LangGraph node
# ======================================================================

async def match_vibes_and_love_languages(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Apply vibe and love language scoring to filtered candidates.

    Processing:
    1. Takes filtered_recommendations from the state
    2. For each candidate, computes:
       - vibe_boost: +30% per matching vault vibe
       - love_language_boost: based on primary/secondary love language alignment
    3. Calculates final_score using the formula:
       final_score = max(interest_score, 1.0) × (1 + vibe_boost) × (1 + love_language_boost)
    4. Re-ranks candidates by final_score (descending)

    The max(1.0) floor ensures experience candidates (which have 0.0
    interest_score from the filtering node) compete fairly with
    interest-matched gifts via vibe and love language multipliers.

    In Phase 8, Gemini 1.5 Pro will classify candidate vibes semantically
    instead of using metadata/keyword matching.

    Args:
        state: The current RecommendationState with filtered_recommendations
               and vault_data (vibes, love languages).

    Returns:
        A dict with "filtered_recommendations" key containing
        list[CandidateRecommendation] re-ranked by final_score.
    """
    candidates = state.filtered_recommendations
    vault = state.vault_data

    logger.info(
        "Matching vibes and love languages for %d candidates: "
        "vibes=%s, primary_ll=%s, secondary_ll=%s",
        len(candidates), vault.vibes,
        vault.primary_love_language, vault.secondary_love_language,
    )

    if not candidates:
        logger.warning("No candidates to match for vault %s", vault.vault_id)
        return {"filtered_recommendations": []}

    scored: list[CandidateRecommendation] = []

    for candidate in candidates:
        vibe_boost = _compute_vibe_boost(candidate, vault.vibes)
        ll_boost = _compute_love_language_boost(
            candidate,
            vault.primary_love_language,
            vault.secondary_love_language,
        )

        # Floor at 1.0 so candidates with 0.0 interest_score still rank
        base = max(candidate.interest_score, 1.0)
        final_score = base * (1 + vibe_boost) * (1 + ll_boost)

        scored_candidate = candidate.model_copy(update={
            "vibe_score": vibe_boost,
            "love_language_score": ll_boost,
            "final_score": final_score,
        })
        scored.append(scored_candidate)

        logger.debug(
            "Candidate '%s': base=%.2f, vibe=+%.0f%%, ll=+%.0f%%, final=%.2f",
            candidate.title, base, vibe_boost * 100, ll_boost * 100,
            final_score,
        )

    # Sort by final_score descending, then by title for deterministic ordering
    scored.sort(key=lambda c: (-c.final_score, c.title))

    logger.info(
        "Re-ranked %d candidates by vibe/love language scoring. "
        "Top: '%s' (%.2f), Bottom: '%s' (%.2f)",
        len(scored),
        scored[0].title if scored else "N/A",
        scored[0].final_score if scored else 0,
        scored[-1].title if scored else "N/A",
        scored[-1].final_score if scored else 0,
    )

    return {"filtered_recommendations": scored}
