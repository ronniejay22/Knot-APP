"""
Recommendations API — AI-powered recommendation generation and refresh.

Handles generating the Choice-of-Three recommendations,
refresh/re-roll with exclusion logic, and feedback collection.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/api/v1/recommendations", tags=["recommendations"])
