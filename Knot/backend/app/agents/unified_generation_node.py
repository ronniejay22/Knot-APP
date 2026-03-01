"""
Unified Generation Node — LangGraph node wrapping the unified generation service.

Calls Claude to generate all 3 recommendations in a single call,
producing a mix of purchasable items and personalized ideas.

Step 15.1: Unified AI Recommendation System
"""

import logging
from typing import Any

from app.agents.state import RecommendationState
from app.services.unified_generation import generate_unified_recommendations

logger = logging.getLogger(__name__)


async def generate_unified(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Generate 3 unified recommendations via Claude.

    Takes the vault data, hints, occasion, budget, and exclusion context
    from the state and passes them to Claude for recommendation generation.

    Args:
        state: The current RecommendationState with vault_data, relevant_hints,
               budget_range, occasion_type, and excluded_titles populated.

    Returns:
        A dict with "final_three" containing the 3 generated recommendations,
        or "error" if generation failed.
    """
    logger.info(
        "Generating unified recommendations for vault %s",
        state.vault_data.vault_id,
    )

    recommendations = await generate_unified_recommendations(
        vault_data=state.vault_data,
        hints=state.relevant_hints,
        occasion_type=state.occasion_type,
        budget_range=state.budget_range,
        milestone_context=state.milestone_context,
        excluded_titles=state.excluded_titles,
        excluded_descriptions=state.excluded_descriptions,
        vibe_override=state.vibe_override,
        rejection_reason=state.rejection_reason,
    )

    if not recommendations:
        logger.error(
            "Unified generation produced 0 recommendations for vault %s",
            state.vault_data.vault_id,
        )
        return {
            "final_three": [],
            "error": "Unable to generate recommendations. Please try again.",
        }

    logger.info(
        "Unified generation produced %d recommendations: %s",
        len(recommendations),
        [f"{r.title} ({r.type})" for r in recommendations],
    )

    return {"final_three": recommendations}
