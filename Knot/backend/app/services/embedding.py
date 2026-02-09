"""
Embedding Service — Vertex AI text-embedding-004

Generates 768-dimension text embeddings for hint semantic search.
Uses Google Cloud Vertex AI's text-embedding-004 model.

Graceful degradation: If Vertex AI credentials are not configured or
the API call fails, returns None. The hint will still be saved with a
NULL embedding in the database. Embeddings can be backfilled later.

Step 4.4: Hint Submission with Embedding Generation
"""

import asyncio
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# --- Constants ---
EMBEDDING_MODEL_NAME = "text-embedding-004"
EMBEDDING_DIMENSION = 768
VERTEX_AI_LOCATION = "us-central1"

# --- Module-level lazy initialization ---
_model = None
_initialized = False


def _get_model():
    """
    Lazy-initialize the Vertex AI TextEmbeddingModel.

    Returns the model on success, or None if initialization fails.
    Only attempts initialization once — subsequent calls return the
    cached result (model or None).
    """
    global _model, _initialized

    if _initialized:
        return _model

    _initialized = True

    try:
        from app.core.config import GOOGLE_CLOUD_PROJECT

        if not GOOGLE_CLOUD_PROJECT:
            logger.warning(
                "GOOGLE_CLOUD_PROJECT not set in .env — "
                "embedding generation disabled. Hints will be stored "
                "without embeddings."
            )
            return None

        import vertexai
        from vertexai.language_models import TextEmbeddingModel

        vertexai.init(
            project=GOOGLE_CLOUD_PROJECT,
            location=VERTEX_AI_LOCATION,
        )
        _model = TextEmbeddingModel.from_pretrained(EMBEDDING_MODEL_NAME)
        logger.info(
            f"Vertex AI {EMBEDDING_MODEL_NAME} initialized "
            f"(project={GOOGLE_CLOUD_PROJECT}, location={VERTEX_AI_LOCATION})"
        )
        return _model

    except Exception as exc:
        logger.warning(
            f"Failed to initialize Vertex AI embedding model: {exc}. "
            "Hints will be stored without embeddings."
        )
        return None


def _reset_model():
    """
    Reset the cached model state. Used by tests to force re-initialization.
    Not intended for production use.
    """
    global _model, _initialized
    _model = None
    _initialized = False


async def generate_embedding(text: str) -> Optional[list[float]]:
    """
    Generate a 768-dimension embedding for the given text using
    Vertex AI text-embedding-004.

    Uses asyncio.to_thread() to run the synchronous Vertex AI SDK
    call without blocking the FastAPI event loop.

    Args:
        text: The text to generate an embedding for.

    Returns:
        A list of 768 floats representing the text embedding,
        or None if embedding generation fails for any reason
        (Vertex AI not configured, API error, etc.).
    """
    model = _get_model()
    if model is None:
        return None

    try:
        # Run the synchronous Vertex AI call in a thread pool
        # to avoid blocking the async event loop
        embeddings = await asyncio.to_thread(
            model.get_embeddings, [text]
        )

        if not embeddings or len(embeddings) == 0:
            logger.warning("Vertex AI returned empty embeddings list")
            return None

        vector = embeddings[0].values

        if len(vector) != EMBEDDING_DIMENSION:
            logger.warning(
                f"Expected {EMBEDDING_DIMENSION}-dimension vector, "
                f"got {len(vector)}"
            )
            return None

        return vector

    except Exception as exc:
        logger.warning(f"Embedding generation failed for hint: {exc}")
        return None


def format_embedding_for_pgvector(embedding: list[float]) -> str:
    """
    Format a list of floats into a pgvector-compatible string.

    PostgREST expects vector values as a string: "[0.1,0.2,...,0.768]"

    Args:
        embedding: List of floats (768 dimensions).

    Returns:
        A pgvector-compatible string representation.
    """
    return "[" + ",".join(str(v) for v in embedding) + "]"
