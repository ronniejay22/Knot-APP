"""
Semantic Filtering Node — LangGraph node for filtering candidates by interests.

Filters candidate recommendations against the partner's interests and dislikes:
1. Removes any candidate that matches a disliked category
2. Scores remaining candidates by interest alignment
3. Ranks by interest_score (descending)
4. Returns the top 9 candidates

Currently uses keyword/metadata matching for deterministic scoring.
In Phase 8, Gemini 1.5 Pro will enhance scoring with semantic understanding
when real API data (without pre-tagged metadata) is used.

Step 5.4: Create Semantic Filtering Node
"""

import logging
from typing import Any

from app.agents.state import CandidateRecommendation, RecommendationState

logger = logging.getLogger(__name__)

# --- Constants ---
MAX_FILTERED_CANDIDATES = 9  # return top 9 for diversity selection node


# ======================================================================
# Category matching helpers
# ======================================================================

def _normalize(text: str) -> str:
    """Lowercase and strip a string for comparison."""
    return text.strip().lower()


def _matches_category(
    candidate: CandidateRecommendation,
    category: str,
) -> bool:
    """
    Check if a candidate matches a given interest/dislike category.

    Uses multiple signals (checked in order of strength):
    1. Metadata ``matched_interest`` — exact tag from the stub catalog
    2. Title keyword match — case-insensitive substring
    3. Description keyword match — case-insensitive substring

    Args:
        candidate: The recommendation candidate to check.
        category: An interest or dislike category name (e.g., "Gaming").

    Returns:
        True if the candidate matches the category.
    """
    cat = _normalize(category)

    # 1. Metadata exact match (strongest signal — stub catalogs tag this)
    matched_interest = candidate.metadata.get("matched_interest", "")
    if _normalize(matched_interest) == cat:
        return True

    # 2. Title keyword match
    if cat in _normalize(candidate.title):
        return True

    # 3. Description keyword match
    if candidate.description and cat in _normalize(candidate.description):
        return True

    return False


# ======================================================================
# Scoring
# ======================================================================

def _score_candidate(
    candidate: CandidateRecommendation,
    interests: list[str],
    dislikes: list[str],
) -> float:
    """
    Score a candidate based on interest alignment.

    Scoring rules:
    - If the candidate matches ANY dislike → return -1.0 (filtered out)
    - For each matching interest → +1.0
    - Metadata-tagged interest match gets a bonus +0.5
      (stronger signal than keyword-only)
    - Candidates with no interest match get 0.0 (neutral — kept but low rank)

    Args:
        candidate: The recommendation candidate to score.
        interests: The partner's 5 liked categories.
        dislikes: The partner's 5 disliked categories.

    Returns:
        A float score. Negative means dislike match (remove).
        Zero or positive means keep (higher = better rank).
    """
    # Check dislikes first — any match means remove
    for dislike in dislikes:
        if _matches_category(candidate, dislike):
            return -1.0

    score = 0.0

    # Score based on interest matches
    for interest in interests:
        if _matches_category(candidate, interest):
            score += 1.0

    # Bonus for metadata-tagged interest (exact catalog match)
    metadata_interest = candidate.metadata.get("matched_interest", "")
    if metadata_interest and metadata_interest in interests:
        score += 0.5

    return score


# ======================================================================
# LangGraph node
# ======================================================================

async def filter_by_interests(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Filter candidates by interests and remove disliked categories.

    Processing:
    1. Takes candidate_recommendations from the state
    2. Scores each candidate against the vault's 5 interests and 5 dislikes
    3. Removes any candidate that matches a dislike (score < 0)
    4. Ranks remaining candidates by interest_score (descending)
    5. Returns the top 9 candidates as filtered_recommendations

    If all candidates are filtered out, sets an error message suggesting
    the user adjust their preferences.

    Currently uses keyword/metadata matching for scoring. In Phase 8,
    Gemini 1.5 Pro will enhance semantic scoring for real API data
    that lacks pre-tagged metadata.

    Args:
        state: The current RecommendationState with candidate_recommendations
               and vault_data (interests + dislikes).

    Returns:
        A dict with "filtered_recommendations" key containing
        list[CandidateRecommendation], and optionally "error" if
        all candidates were filtered out.
    """
    candidates = state.candidate_recommendations
    interests = state.vault_data.interests
    dislikes = state.vault_data.dislikes

    logger.info(
        "Filtering %d candidates: interests=%s, dislikes=%s",
        len(candidates), interests, dislikes,
    )

    if not candidates:
        logger.warning(
            "No candidates to filter for vault %s",
            state.vault_data.vault_id,
        )
        return {"filtered_recommendations": []}

    # Score and filter
    scored: list[tuple[CandidateRecommendation, float]] = []
    removed_count = 0

    for candidate in candidates:
        score = _score_candidate(candidate, interests, dislikes)
        if score < 0:
            removed_count += 1
            logger.debug(
                "Removed candidate '%s' (matched dislike)", candidate.title,
            )
            continue

        # Update the candidate's interest_score
        candidate = candidate.model_copy(update={"interest_score": score})
        scored.append((candidate, score))

    # Sort by score descending, then by title for deterministic ordering
    scored.sort(key=lambda x: (-x[1], x[0].title))

    # Take top 9
    filtered = [c for c, _ in scored[:MAX_FILTERED_CANDIDATES]]

    logger.info(
        "Filtered to %d candidates (%d removed for dislikes, %d trimmed by rank)",
        len(filtered),
        removed_count,
        max(0, len(scored) - MAX_FILTERED_CANDIDATES),
    )

    result: dict[str, Any] = {"filtered_recommendations": filtered}

    if not filtered:
        result["error"] = (
            "All candidates filtered out — try adjusting your preferences"
        )
        logger.warning(
            "No candidates survived filtering for vault %s",
            state.vault_data.vault_id,
        )

    return result
