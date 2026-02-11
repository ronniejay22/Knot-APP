"""
Recommendation Models — Pydantic schemas for Recommendations API.

Defines request/response models for the recommendation endpoints:
- POST /api/v1/recommendations/generate — Generate Choice-of-Three (Step 5.9)

Step 5.9: Create Recommendations API Endpoint
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel


# ======================================================================
# Request Models
# ======================================================================

class RecommendationGenerateRequest(BaseModel):
    """
    Payload for POST /api/v1/recommendations/generate.

    Accepts an optional milestone_id (to generate recommendations
    for a specific milestone) and a required occasion_type that
    determines the budget tier to use.
    """

    milestone_id: Optional[str] = None
    occasion_type: Literal["just_because", "minor_occasion", "major_milestone"]


# ======================================================================
# Response Models
# ======================================================================

class LocationResponse(BaseModel):
    """Location info for experience/date recommendations."""

    city: Optional[str] = None
    state: Optional[str] = None
    country: Optional[str] = None
    address: Optional[str] = None


class RecommendationItemResponse(BaseModel):
    """A single recommendation in the Choice-of-Three response."""

    id: str
    recommendation_type: Literal["gift", "experience", "date"]
    title: str
    description: Optional[str] = None
    price_cents: Optional[int] = None
    currency: str = "USD"
    external_url: str
    image_url: Optional[str] = None
    merchant_name: Optional[str] = None
    source: str
    location: Optional[LocationResponse] = None
    # Scoring metadata (useful for debugging / transparency)
    interest_score: float = 0.0
    vibe_score: float = 0.0
    love_language_score: float = 0.0
    final_score: float = 0.0


class RecommendationGenerateResponse(BaseModel):
    """
    Response for POST /api/v1/recommendations/generate.

    Returns exactly 3 recommendations (or fewer if the pipeline
    could not find enough valid candidates).
    """

    recommendations: list[RecommendationItemResponse]
    count: int
    milestone_id: Optional[str] = None
    occasion_type: str
