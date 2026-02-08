"""
Hint Models — Pydantic schemas for Hint Capture API.

Defines request/response models for the hint CRUD endpoints:
- POST /api/v1/hints — Create hint (Step 4.2)
- GET /api/v1/hints — List hints (Step 4.2)
- DELETE /api/v1/hints/{hint_id} — Delete hint (Step 4.6)

Step 4.2: Text Hint Capture
Step 4.4: Hint Submission with Embedding Generation (adds Vertex AI embedding)
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, field_validator


# Maximum hint length — enforced in both iOS UI and backend API.
MAX_HINT_LENGTH = 500


# ======================================================================
# Request Models
# ======================================================================

class HintCreateRequest(BaseModel):
    """
    Payload for POST /api/v1/hints.

    Accepts a hint text string and its source (text input or voice transcription).
    Validates that hint_text is non-empty and within the 500-character limit.
    """

    hint_text: str
    source: Literal["text_input", "voice_transcription"] = "text_input"

    @field_validator("hint_text")
    @classmethod
    def validate_hint_text(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("hint_text cannot be empty")
        if len(v) > MAX_HINT_LENGTH:
            raise ValueError(
                f"Hint too long. Maximum {MAX_HINT_LENGTH} characters allowed, "
                f"got {len(v)}."
            )
        return v


# ======================================================================
# Response Models
# ======================================================================

class HintResponse(BaseModel):
    """A single hint in API responses."""

    id: str
    hint_text: str
    source: str
    is_used: bool
    created_at: str  # ISO 8601 timestamp string


class HintCreateResponse(BaseModel):
    """Response after successful hint creation."""

    id: str
    hint_text: str
    source: str
    is_used: bool
    created_at: str


class HintListResponse(BaseModel):
    """Response for GET /api/v1/hints — list of hints."""

    hints: list[HintResponse]
    total: int
