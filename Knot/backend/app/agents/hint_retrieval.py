"""
Hint Retrieval Node — LangGraph node for semantic hint search.

Queries pgvector via the match_hints() RPC function to find hints
semantically related to the current milestone or occasion.

If Vertex AI embedding generation is unavailable, falls back to
returning the most recent hints in chronological order.

Step 5.2: Create Hint Retrieval Node
"""

import logging
from typing import Any

from app.agents.state import RecommendationState, RelevantHint
from app.db.supabase_client import get_service_client
from app.services.embedding import generate_embedding, format_embedding_for_pgvector

logger = logging.getLogger(__name__)

# --- Constants ---
MAX_HINTS = 10
DEFAULT_SIMILARITY_THRESHOLD = 0.0


def _build_query_text(state: RecommendationState) -> str:
    """
    Build the query text for semantic search from the recommendation state.

    Strategy:
    - If a milestone context exists, use the milestone name and type
      (e.g., "Alex's Birthday birthday gift ideas")
    - Always include the occasion type for context
    - Append top interests to improve semantic matching

    Returns a natural-language query string for embedding generation.
    """
    parts = []

    if state.milestone_context:
        parts.append(state.milestone_context.milestone_name)
        parts.append(f"{state.milestone_context.milestone_type} gift ideas")

    occasion_labels = {
        "just_because": "casual date or small gift",
        "minor_occasion": "thoughtful gift or fun outing",
        "major_milestone": "special gift or memorable experience",
    }
    parts.append(occasion_labels.get(state.occasion_type, "gift ideas"))

    # Add top interests for better semantic matching
    if state.vault_data.interests:
        interests_str = ", ".join(state.vault_data.interests[:3])
        parts.append(f"interests: {interests_str}")

    return " ".join(parts)


async def retrieve_relevant_hints(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Retrieve semantically relevant hints from pgvector.

    1. Builds a query from the milestone context or occasion type
    2. Generates an embedding for the query via Vertex AI
    3. Calls match_hints() RPC to find the top 10 similar hints
    4. Returns the hints as RelevantHint objects in the state update

    If embedding generation fails, falls back to returning the most recent
    hints for the vault (chronological, no semantic ranking).

    Args:
        state: The current RecommendationState with vault_data and
               optional milestone_context.

    Returns:
        A dict with "relevant_hints" key containing list[RelevantHint].
    """
    vault_id = state.vault_data.vault_id

    # Step 1: Build query text
    query_text = _build_query_text(state)
    logger.info(f"Hint retrieval query: '{query_text}' for vault {vault_id}")

    # Step 2: Generate embedding for the query
    embedding = await generate_embedding(query_text)

    if embedding is not None:
        # Step 3a: Semantic search via match_hints() RPC
        hints = await _semantic_search(vault_id, embedding)
    else:
        # Step 3b: Fallback to chronological hints
        logger.warning(
            "Embedding generation unavailable — "
            "falling back to chronological hints"
        )
        hints = await _chronological_fallback(vault_id)

    logger.info(f"Retrieved {len(hints)} relevant hints for vault {vault_id}")

    return {"relevant_hints": hints}


async def _semantic_search(
    vault_id: str,
    query_embedding: list[float],
    max_count: int = MAX_HINTS,
    threshold: float = DEFAULT_SIMILARITY_THRESHOLD,
) -> list[RelevantHint]:
    """
    Query pgvector via match_hints() RPC for semantically similar hints.

    Args:
        vault_id: The vault to search within.
        query_embedding: 768-dim embedding vector for the query.
        max_count: Maximum number of hints to return.
        threshold: Minimum cosine similarity (0.0–1.0).

    Returns:
        List of RelevantHint objects ordered by similarity (highest first).
    """
    client = get_service_client()
    embedding_str = format_embedding_for_pgvector(query_embedding)

    try:
        response = client.rpc(
            "match_hints",
            {
                "query_embedding": embedding_str,
                "query_vault_id": vault_id,
                "match_threshold": threshold,
                "match_count": max_count,
            },
        ).execute()

        if not response.data:
            return []

        return [
            RelevantHint(
                id=str(row["id"]),
                hint_text=row["hint_text"],
                similarity_score=row.get("similarity", 0.0),
                source=row.get("source", "text_input"),
                is_used=row.get("is_used", False),
                created_at=row.get("created_at"),
            )
            for row in response.data
        ]
    except Exception as exc:
        logger.error(f"Semantic hint search failed: {exc}")
        return []


async def _chronological_fallback(
    vault_id: str,
    max_count: int = MAX_HINTS,
) -> list[RelevantHint]:
    """
    Fallback: Return the most recent hints ordered by created_at DESC.

    Used when embedding generation is unavailable (Vertex AI not configured
    or API call failed). Returns hints without semantic ranking.
    """
    client = get_service_client()

    try:
        response = (
            client.table("hints")
            .select("id, hint_text, source, is_used, created_at")
            .eq("vault_id", vault_id)
            .order("created_at", desc=True)
            .limit(max_count)
            .execute()
        )

        if not response.data:
            return []

        return [
            RelevantHint(
                id=str(row["id"]),
                hint_text=row["hint_text"],
                similarity_score=0.0,  # no semantic score for chronological
                source=row.get("source", "text_input"),
                is_used=row.get("is_used", False),
                created_at=row.get("created_at"),
            )
            for row in response.data
        ]
    except Exception as exc:
        logger.error(f"Chronological hint fallback failed: {exc}")
        return []
