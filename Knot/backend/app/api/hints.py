"""
Hints API — Hint capture and retrieval.

Handles creating, listing, and deleting hints.
Hint embeddings are generated via Vertex AI text-embedding-004.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/api/v1/hints", tags=["hints"])
