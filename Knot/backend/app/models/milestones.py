"""
Milestone Models — Pydantic schemas for Milestones CRUD API.

Defines request/response models for post-onboarding milestone management:
- POST /api/v1/milestones — Add a milestone
- GET /api/v1/milestones — List milestones with days_until
- PUT /api/v1/milestones/{id} — Update a milestone
- DELETE /api/v1/milestones/{id} — Delete a milestone
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


class MilestoneCreateRequest(BaseModel):
    """Payload for POST /api/v1/milestones."""

    milestone_type: Literal["birthday", "anniversary", "holiday", "custom"]
    milestone_name: str = Field(..., min_length=1, max_length=100)
    milestone_date: str = Field(
        ...,
        description='Date in "2000-MM-DD" format for yearly, or full date for one_time',
    )
    recurrence: Literal["yearly", "one_time"] = "yearly"
    budget_tier: Optional[
        Literal["just_because", "minor_occasion", "major_milestone"]
    ] = None


class MilestoneUpdateRequest(BaseModel):
    """Payload for PUT /api/v1/milestones/{id}."""

    milestone_name: Optional[str] = Field(None, min_length=1, max_length=100)
    milestone_date: Optional[str] = None
    recurrence: Optional[Literal["yearly", "one_time"]] = None
    budget_tier: Optional[
        Literal["just_because", "minor_occasion", "major_milestone"]
    ] = None


class MilestoneItemResponse(BaseModel):
    """A single milestone in API responses."""

    id: str
    milestone_type: str
    milestone_name: str
    milestone_date: str
    recurrence: str
    budget_tier: Optional[str] = None
    days_until: Optional[int] = None
    created_at: str


class MilestoneListResponse(BaseModel):
    """Response for GET /api/v1/milestones."""

    milestones: list[MilestoneItemResponse]
    count: int
