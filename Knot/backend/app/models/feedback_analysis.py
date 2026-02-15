"""
Feedback Analysis Models — Pydantic schemas for the feedback analysis job.

Defines request/response models for:
- POST /api/v1/feedback/analyze — QStash webhook trigger for weekly analysis
- Internal data structures for weight computation

Step 10.2: Create Feedback Analysis Job (Backend)
"""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


# ======================================================================
# Weight Data Models
# ======================================================================

class UserPreferencesWeights(BaseModel):
    """
    Learned preference weights for a single user.

    Weight values are multipliers centered around 1.0:
      - 1.0 = neutral (no adjustment)
      - >1.0 = boost (user prefers this dimension)
      - <1.0 = penalty (user dislikes this dimension)
      - Clamped to [0.5, 2.0]
    """

    user_id: str
    vibe_weights: dict[str, float] = Field(default_factory=dict)
    interest_weights: dict[str, float] = Field(default_factory=dict)
    type_weights: dict[str, float] = Field(default_factory=dict)
    love_language_weights: dict[str, float] = Field(default_factory=dict)
    feedback_count: int = 0


# ======================================================================
# API Request/Response Models
# ======================================================================

class FeedbackAnalysisRequest(BaseModel):
    """
    Optional payload for POST /api/v1/feedback/analyze.

    When triggered by QStash, the body may be empty or contain
    an optional user_id to analyze a single user (for testing).
    """

    user_id: Optional[str] = None


class FeedbackAnalysisResponse(BaseModel):
    """Response from POST /api/v1/feedback/analyze."""

    status: str = Field(
        ...,
        description="Processing result: 'completed', 'no_feedback', or 'error'.",
    )
    users_analyzed: int = Field(
        default=0,
        description="Number of users whose weights were updated.",
    )
    message: str = Field(
        default="",
        description="Human-readable description of the analysis result.",
    )
