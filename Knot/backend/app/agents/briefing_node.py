"""
Briefing Generation Node — LangGraph node for milestone briefing generation.

Generates a contextual, conversational briefing that accompanies milestone-triggered
recommendations. Only runs when milestone_context is present in the state.
"""

import logging

from app.agents.state import RecommendationState
from app.services.briefing_generation import generate_milestone_briefing

logger = logging.getLogger(__name__)


async def generate_briefing(state: RecommendationState) -> dict:
    """
    LangGraph node: Generate a milestone briefing if milestone context is present.

    Reads vault_data, relevant_hints, and milestone_context from state.
    Writes briefing_text, briefing_snippet, and briefing_hint_ids back to state.

    Skips silently if no milestone context is provided (non-milestone
    recommendations don't need a briefing).
    """
    if not state.milestone_context:
        logger.debug("No milestone context — skipping briefing generation")
        return {}

    result = await generate_milestone_briefing(
        vault_data=state.vault_data,
        hints=state.relevant_hints,
        milestone_context=state.milestone_context,
    )

    if result is None:
        logger.info("Briefing generation returned None — continuing without briefing")
        return {}

    return {
        "briefing_text": result.briefing_text,
        "briefing_snippet": result.briefing_snippet,
        "briefing_hint_ids": result.hint_ids_referenced,
    }
