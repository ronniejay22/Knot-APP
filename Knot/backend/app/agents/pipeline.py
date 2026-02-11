"""
Recommendation Pipeline — Full LangGraph graph composing all 6 nodes.

Chains the recommendation generation nodes into an executable graph:
1. retrieve_relevant_hints — Fetch semantically similar hints from pgvector
2. aggregate_external_data — Call external APIs (Yelp, Ticketmaster, Amazon, etc.)
3. filter_by_interests — Remove candidates matching dislikes, boost matches
4. match_vibes_and_love_languages — Apply vibe and love language scoring
5. select_diverse_three — Pick 3 diverse recommendations
6. verify_availability — Confirm URLs are valid, replace if not

Conditional edges short-circuit the pipeline on error:
- If aggregate_external_data returns 0 candidates → END with error
- If filter_by_interests filters all candidates → END with error
- verify_availability returns partial results (with warning) on its own

Step 5.8: Compose Full LangGraph Pipeline
"""

import logging
from typing import Any

from langgraph.graph import END, START, StateGraph

from app.agents.aggregation import aggregate_external_data
from app.agents.availability import verify_availability
from app.agents.filtering import filter_by_interests
from app.agents.hint_retrieval import retrieve_relevant_hints
from app.agents.matching import match_vibes_and_love_languages
from app.agents.selection import select_diverse_three
from app.agents.state import RecommendationState

logger = logging.getLogger(__name__)


# ======================================================================
# Conditional edge functions
# ======================================================================

def _check_after_aggregation(state: RecommendationState) -> str:
    """
    Route after aggregate_external_data.

    If no candidates were found (empty list), short-circuit to END.
    The aggregation node already sets the error message in this case.
    """
    if not state.candidate_recommendations:
        logger.warning("Pipeline short-circuit: no candidates after aggregation")
        return "error"
    return "continue"


def _check_after_filtering(state: RecommendationState) -> str:
    """
    Route after filter_by_interests.

    If all candidates were filtered out (empty list), short-circuit to END.
    The filtering node already sets the error message in this case.
    """
    if not state.filtered_recommendations:
        logger.warning("Pipeline short-circuit: no candidates after filtering")
        return "error"
    return "continue"


# ======================================================================
# Graph construction
# ======================================================================

def build_recommendation_graph() -> StateGraph:
    """
    Build the LangGraph StateGraph for the recommendation pipeline.

    Returns the uncompiled StateGraph (call .compile() to get the
    executable CompiledStateGraph).

    Node names:
    - "retrieve_hints"
    - "aggregate_data"
    - "filter_interests"
    - "match_vibes_ll"
    - "select_diverse"
    - "verify_urls"
    """
    graph = StateGraph(RecommendationState)

    # --- Add nodes ---
    graph.add_node("retrieve_hints", retrieve_relevant_hints)
    graph.add_node("aggregate_data", aggregate_external_data)
    graph.add_node("filter_interests", filter_by_interests)
    graph.add_node("match_vibes_ll", match_vibes_and_love_languages)
    graph.add_node("select_diverse", select_diverse_three)
    graph.add_node("verify_urls", verify_availability)

    # --- Define edges ---

    # START → retrieve_hints → aggregate_data
    graph.add_edge(START, "retrieve_hints")
    graph.add_edge("retrieve_hints", "aggregate_data")

    # aggregate_data → (conditional) filter_interests or END
    graph.add_conditional_edges(
        "aggregate_data",
        _check_after_aggregation,
        {"continue": "filter_interests", "error": END},
    )

    # filter_interests → (conditional) match_vibes_ll or END
    graph.add_conditional_edges(
        "filter_interests",
        _check_after_filtering,
        {"continue": "match_vibes_ll", "error": END},
    )

    # match_vibes_ll → select_diverse → verify_urls → END
    graph.add_edge("match_vibes_ll", "select_diverse")
    graph.add_edge("select_diverse", "verify_urls")
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
