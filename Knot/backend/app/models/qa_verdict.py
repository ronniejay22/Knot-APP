"""
Pydantic models for recommendation QA verdicts.

Mirrors the `rec_qa_verdicts` table (migration 00027). A verdict is the internal
reviewer's like/dislike on one generated recommendation, plus the rubric
dimensions and free-text reason behind it.

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


class QAVerdict(BaseModel):
    """A stored QA verdict row."""

    id: Optional[str] = None
    evaluator: str = "qa"
    profile_id: Optional[str] = None
    rec_snapshot: dict[str, Any] = Field(default_factory=dict)
    verdict: Literal["like", "dislike"]
    reason_dimensions: list[str] = Field(default_factory=list)
    reason_text: Optional[str] = None
    generation_config: dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[str] = None
