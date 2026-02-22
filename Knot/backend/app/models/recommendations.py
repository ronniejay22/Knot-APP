"""
Recommendation Models — Pydantic schemas for Recommendations API.

Defines request/response models for the recommendation endpoints:
- POST /api/v1/recommendations/generate — Generate Choice-of-Three (Step 5.9)
- POST /api/v1/recommendations/refresh — Refresh/re-roll with exclusions (Step 5.10)
- POST /api/v1/recommendations/feedback — Record user feedback (Step 6.3)

Step 5.9: Create Recommendations API Endpoint
Step 5.10: Implement Refresh (Re-roll) Logic
Step 6.3: Implement Card Selection Flow
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator


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


class RecommendationRefreshRequest(BaseModel):
    """
    Payload for POST /api/v1/recommendations/refresh.

    Accepts the IDs of rejected recommendations and a rejection reason
    that determines what exclusion filters to apply when generating
    replacement recommendations.
    """

    rejected_recommendation_ids: list[str]
    rejection_reason: Literal[
        "too_expensive",
        "too_cheap",
        "not_their_style",
        "already_have_similar",
        "show_different",
    ]

    @field_validator("rejected_recommendation_ids")
    @classmethod
    def validate_non_empty(cls, v: list[str]) -> list[str]:
        if not v:
            raise ValueError("rejected_recommendation_ids must not be empty")
        return v


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
    price_confidence: str = "unknown"
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
    # Matched factors — which specific interests/vibes/love languages caused the match
    matched_interests: list[str] = Field(default_factory=list)
    matched_vibes: list[str] = Field(default_factory=list)
    matched_love_languages: list[str] = Field(default_factory=list)


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


class RecommendationRefreshResponse(BaseModel):
    """
    Response for POST /api/v1/recommendations/refresh.

    Returns 3 new recommendations after applying exclusion filters
    based on the rejection reason.
    """

    recommendations: list[RecommendationItemResponse]
    count: int
    rejection_reason: str


# ======================================================================
# Feedback Models (Step 6.3)
# ======================================================================

class RecommendationFeedbackRequest(BaseModel):
    """
    Payload for POST /api/v1/recommendations/feedback.

    Records a user action on a recommendation (selected, saved, shared, rated, handoff, purchased).
    """

    recommendation_id: str
    action: Literal["selected", "saved", "shared", "rated", "handoff", "purchased"]
    rating: Optional[int] = None
    feedback_text: Optional[str] = None

    @field_validator("rating")
    @classmethod
    def validate_rating(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and (v < 1 or v > 5):
            raise ValueError("rating must be between 1 and 5")
        return v


class RecommendationFeedbackResponse(BaseModel):
    """Response for POST /api/v1/recommendations/feedback."""

    id: str
    recommendation_id: str
    action: str
    created_at: str
