"""
Diversity Selection Node — LangGraph node for selecting 3 diverse recommendations.

Picks 3 candidates from the top-ranked pool that maximize diversity across:
1. Price tier (low / mid / high within the budget range)
2. Type (gift vs experience vs date)
3. Merchant (no two from the same merchant)

Selection algorithm:
- Start with the highest-scored candidate as the first pick.
- For each subsequent pick, choose the candidate that adds the most
  diversity (different price tier, different type, different merchant)
  while maintaining the best possible score.

Step 5.6: Create Diversity Selection Node
"""

import logging
from typing import Any

from app.agents.state import CandidateRecommendation, RecommendationState

logger = logging.getLogger(__name__)

# --- Constants ---
TARGET_COUNT = 3  # always select exactly 3


# ======================================================================
# Price tier classification
# ======================================================================

def _classify_price_tier(
    price_cents: int | None,
    budget_min: int,
    budget_max: int,
) -> str:
    """
    Classify a price into low / mid / high within the budget range.

    Splits the budget range into three equal bands:
    - low:  min → min + 1/3 of range
    - mid:  min + 1/3 → min + 2/3 of range
    - high: min + 2/3 → max

    Candidates without a price default to "mid" (neutral).

    Args:
        price_cents: The candidate's price in cents (or None).
        budget_min: The budget range minimum in cents.
        budget_max: The budget range maximum in cents.

    Returns:
        One of "low", "mid", "high".
    """
    if price_cents is None:
        return "mid"

    budget_range = budget_max - budget_min
    if budget_range <= 0:
        return "mid"

    third = budget_range / 3
    if price_cents < budget_min + third:
        return "low"
    elif price_cents < budget_min + 2 * third:
        return "mid"
    else:
        return "high"


# ======================================================================
# Diversity scoring
# ======================================================================

def _diversity_score(
    candidate: CandidateRecommendation,
    already_selected: list[CandidateRecommendation],
    budget_min: int,
    budget_max: int,
) -> int:
    """
    Score how much diversity a candidate adds relative to already-selected items.

    Awards +1 for each dimension that is different from ALL already-selected:
    - Price tier: candidate's tier is not in the set of selected tiers
    - Type: candidate's type is not in the set of selected types
    - Merchant: candidate's merchant is not in the set of selected merchants

    Maximum diversity score is 3 (all dimensions unique).

    Args:
        candidate: The candidate to evaluate.
        already_selected: The list of already-selected recommendations.
        budget_min: The budget range minimum in cents.
        budget_max: The budget range maximum in cents.

    Returns:
        An integer diversity score (0–3).
    """
    if not already_selected:
        return 0  # first pick has no comparison

    selected_tiers = {
        _classify_price_tier(s.price_cents, budget_min, budget_max)
        for s in already_selected
    }
    selected_types = {s.type for s in already_selected}
    selected_merchants = {
        (s.merchant_name or "").strip().lower()
        for s in already_selected
    }

    score = 0

    # Different price tier?
    candidate_tier = _classify_price_tier(
        candidate.price_cents, budget_min, budget_max,
    )
    if candidate_tier not in selected_tiers:
        score += 1

    # Different type?
    if candidate.type not in selected_types:
        score += 1

    # Different merchant?
    candidate_merchant = (candidate.merchant_name or "").strip().lower()
    if candidate_merchant not in selected_merchants:
        score += 1

    return score


# ======================================================================
# LangGraph node
# ======================================================================

async def select_diverse_three(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Select 3 diverse recommendations from the ranked pool.

    Processing:
    1. Takes filtered_recommendations from the state (already ranked by final_score)
    2. Picks the top-scored candidate first
    3. For each subsequent pick, selects the candidate that maximizes diversity
       (different price tier, type, and merchant) while maintaining a high score.
       Ties in diversity are broken by final_score (higher wins), then by title.
    4. Returns exactly 3 recommendations (or fewer if the pool is smaller)

    Diversity dimensions:
    - Price tier: low / mid / high (budget range split into thirds)
    - Type: gift / experience / date
    - Merchant: unique merchant names

    Args:
        state: The current RecommendationState with filtered_recommendations
               (sorted by final_score DESC) and budget_range.

    Returns:
        A dict with "final_three" key containing list[CandidateRecommendation].
    """
    candidates = list(state.filtered_recommendations)
    budget_min = state.budget_range.min_amount
    budget_max = state.budget_range.max_amount

    logger.info(
        "Selecting %d diverse recommendations from %d candidates "
        "(budget: %d–%d cents)",
        TARGET_COUNT, len(candidates), budget_min, budget_max,
    )

    if not candidates:
        logger.warning(
            "No candidates to select from for vault %s",
            state.vault_data.vault_id,
        )
        return {"final_three": []}

    # --- Greedy diversity selection ---
    selected: list[CandidateRecommendation] = []

    # 1. First pick: highest final_score (candidates are already sorted)
    selected.append(candidates[0])
    remaining = candidates[1:]

    logger.debug(
        "Pick 1: '%s' (score=%.2f, type=%s, price=%s, merchant=%s)",
        selected[0].title, selected[0].final_score, selected[0].type,
        selected[0].price_cents, selected[0].merchant_name,
    )

    # 2. Subsequent picks: maximize diversity, break ties by final_score
    while len(selected) < TARGET_COUNT and remaining:
        best_candidate = None
        best_diversity = -1
        best_score = -1.0
        best_title = ""

        for candidate in remaining:
            div = _diversity_score(candidate, selected, budget_min, budget_max)
            # Break ties: higher diversity > higher final_score > lower title (alpha)
            if (
                div > best_diversity
                or (div == best_diversity and candidate.final_score > best_score)
                or (
                    div == best_diversity
                    and candidate.final_score == best_score
                    and candidate.title < best_title
                )
            ):
                best_candidate = candidate
                best_diversity = div
                best_score = candidate.final_score
                best_title = candidate.title

        if best_candidate is not None:
            selected.append(best_candidate)
            remaining.remove(best_candidate)

            logger.debug(
                "Pick %d: '%s' (score=%.2f, diversity=%d, type=%s, "
                "price=%s, merchant=%s)",
                len(selected), best_candidate.title,
                best_candidate.final_score, best_diversity,
                best_candidate.type, best_candidate.price_cents,
                best_candidate.merchant_name,
            )

    logger.info(
        "Selected %d diverse recommendations: %s",
        len(selected),
        [c.title for c in selected],
    )

    # Log diversity summary
    tiers = [
        _classify_price_tier(c.price_cents, budget_min, budget_max)
        for c in selected
    ]
    types = [c.type for c in selected]
    merchants = [c.merchant_name or "unknown" for c in selected]
    logger.info(
        "Diversity summary — tiers: %s, types: %s, merchants: %s",
        tiers, types, merchants,
    )

    return {"final_three": selected}
