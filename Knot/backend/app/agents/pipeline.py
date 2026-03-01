"""
Recommendation Pipeline — LangGraph graph for the unified recommendation system.

Chains the recommendation generation nodes into an executable graph:
1. retrieve_hints — Fetch semantically similar hints from pgvector
2. generate_unified — Claude generates 3 personalized recommendations
3. resolve_urls — Find real purchase URLs for purchasable items via Brave Search
4. verify_urls — Confirm URLs are valid, enrich prices via page scraping

Conditional edges short-circuit the pipeline on error:
- If generate_unified returns 0 recommendations → END with error

Step 5.8: Compose Full LangGraph Pipeline
Step 15.1: Unified AI Recommendation System — simplified 4-node pipeline
"""

import logging
from typing import Any

from langgraph.graph import END, START, StateGraph

from app.agents.availability import verify_availability
from app.agents.hint_retrieval import retrieve_relevant_hints
from app.agents.state import RecommendationState
from app.agents.unified_generation_node import generate_unified
from app.agents.url_resolution import resolve_purchase_urls

logger = logging.getLogger(__name__)


# ======================================================================
# Conditional edge functions
# ======================================================================

def _check_after_generation(state: RecommendationState) -> str:
    """
    Route after generate_unified.

    If Claude failed to produce any recommendations, short-circuit to END.
    """
    if not state.final_three:
        logger.warning("Pipeline short-circuit: no recommendations after unified generation")
        return "error"
    return "continue"


# ======================================================================
# Graph construction
# ======================================================================

def build_recommendation_graph() -> StateGraph:
    """
    Build the LangGraph StateGraph for the unified recommendation pipeline.

    Returns the uncompiled StateGraph (call .compile() to get the
    executable CompiledStateGraph).

    Node names:
    - "retrieve_hints"
    - "generate_unified"
    - "resolve_urls"
    - "verify_urls"
    """
    graph = StateGraph(RecommendationState)

    # --- Add nodes ---
    graph.add_node("retrieve_hints", retrieve_relevant_hints)
    graph.add_node("generate_unified", generate_unified)
    graph.add_node("resolve_urls", resolve_purchase_urls)
    graph.add_node("verify_urls", verify_availability)

    # --- Define edges ---

    # START → retrieve_hints → generate_unified
    graph.add_edge(START, "retrieve_hints")
    graph.add_edge("retrieve_hints", "generate_unified")

    # generate_unified → (conditional) resolve_urls or END
    graph.add_conditional_edges(
        "generate_unified",
        _check_after_generation,
        {"continue": "resolve_urls", "error": END},
    )

    # resolve_urls → verify_urls → END
    graph.add_edge("resolve_urls", "verify_urls")
    graph.add_edge("verify_urls", END)

    return graph


# Pre-built compiled graph — import and use directly
recommendation_graph = build_recommendation_graph().compile()


# ======================================================================
# Convenience runner
# ======================================================================

async def run_recommendation_pipeline(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    Run the full recommendation pipeline asynchronously.

    This is the main entry point for generating recommendations.
    Accepts a fully populated RecommendationState and returns the
    final state as a dict (including final_three recommendations
    and any error messages).

    Args:
        state: A RecommendationState with vault_data, occasion_type,
               budget_range, and optional milestone_context populated.

    Returns:
        A dict with the final pipeline state, including:
        - "final_three": list of 3 verified recommendations (or fewer)
        - "error": error message string if the pipeline short-circuited
        - All intermediate state fields (relevant_hints, etc.)
    """
    logger.info(
        "Starting recommendation pipeline for vault %s (occasion: %s)",
        state.vault_data.vault_id,
        state.occasion_type,
    )

    result = await recommendation_graph.ainvoke(state)

    # Log outcome
    final_three = result.get("final_three", [])
    error = result.get("error")

    if error:
        logger.warning(
            "Pipeline completed with error for vault %s: %s",
            state.vault_data.vault_id,
            error,
        )
    else:
        logger.info(
            "Pipeline completed for vault %s: %d recommendations — %s",
            state.vault_data.vault_id,
            len(final_three),
            [r.title for r in final_three],
        )

    return result
