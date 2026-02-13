"""
Recommendation State Schema — Pydantic models for the LangGraph recommendation pipeline.

Defines the state that flows through the recommendation generation graph:
1. retrieve_relevant_hints — Semantic search for related hints
2. aggregate_external_data — Fetch candidates from external APIs
3. filter_by_interests — Remove disliked categories, boost liked ones
4. match_vibes_and_love_languages — Apply vibe and love language scoring
5. select_diverse_three — Pick 3 diverse, high-scoring recommendations
6. verify_availability — Confirm external URLs are valid

Step 5.1: Define Recommendation State Schema
"""

from __future__ import annotations

from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


# ======================================================================
# Sub-models: Vault profile data
# ======================================================================

class BudgetRange(BaseModel):
    """Min/max budget for a specific occasion type."""

    min_amount: int  # in cents (e.g., 2000 = $20.00)
    max_amount: int  # in cents (e.g., 5000 = $50.00)
    currency: str = "USD"


class VaultBudget(BaseModel):
    """A budget tier from the partner vault (includes occasion_type label)."""

    occasion_type: Literal["just_because", "minor_occasion", "major_milestone"]
    min_amount: int  # in cents
    max_amount: int  # in cents
    currency: str = "USD"


class VaultData(BaseModel):
    """
    Full partner profile loaded from the database.

    Contains all vault data needed by the recommendation pipeline:
    basic info, interests/dislikes, vibes, love languages, and budgets.
    """

    vault_id: str
    partner_name: str
    relationship_tenure_months: Optional[int] = None
    cohabitation_status: Optional[
        Literal["living_together", "separate", "long_distance"]
    ] = None
    location_city: Optional[str] = None
    location_state: Optional[str] = None
    location_country: str = "US"

    interests: list[str]   # 5 liked categories
    dislikes: list[str]    # 5 disliked categories
    vibes: list[str]       # 1–8 aesthetic vibe tags

    primary_love_language: str
    secondary_love_language: str

    budgets: list[VaultBudget]  # all 3 budget tiers


# ======================================================================
# Sub-models: Hints and milestones
# ======================================================================

class RelevantHint(BaseModel):
    """A hint retrieved via pgvector semantic similarity search."""

    id: str
    hint_text: str
    similarity_score: float = 0.0
    source: Literal["text_input", "voice_transcription"] = "text_input"
    is_used: bool = False
    created_at: Optional[str] = None  # ISO 8601 timestamp


class MilestoneContext(BaseModel):
    """Details of the milestone being planned for."""

    id: str
    milestone_type: Literal["birthday", "anniversary", "holiday", "custom"]
    milestone_name: str
    milestone_date: str  # "2000-MM-DD" format from DB
    recurrence: Literal["yearly", "one_time"]
    budget_tier: Literal["just_because", "minor_occasion", "major_milestone"]
    days_until: Optional[int] = None  # computed at runtime


# ======================================================================
# Sub-models: Recommendation candidates
# ======================================================================

class LocationData(BaseModel):
    """Location info for experience/date recommendations."""

    city: Optional[str] = None
    state: Optional[str] = None
    country: Optional[str] = None
    address: Optional[str] = None


class CandidateRecommendation(BaseModel):
    """
    A recommendation candidate from an external API.

    Starts as a raw result from aggregate_external_data, then accumulates
    scores as it passes through filtering and matching nodes.
    """

    id: str
    source: Literal["yelp", "ticketmaster", "amazon", "shopify", "firecrawl", "opentable", "resy"]
    type: Literal["gift", "experience", "date"]
    title: str
    description: Optional[str] = None
    price_cents: Optional[int] = None
    currency: str = "USD"
    external_url: str
    image_url: Optional[str] = None
    merchant_name: Optional[str] = None
    location: Optional[LocationData] = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    # Scoring fields — populated by filtering/matching nodes
    interest_score: float = 0.0
    vibe_score: float = 0.0
    love_language_score: float = 0.0
    final_score: float = 0.0


# ======================================================================
# Main LangGraph State
# ======================================================================

class RecommendationState(BaseModel):
    """
    Complete state for the LangGraph recommendation pipeline.

    Flows through 6 nodes:
    1. retrieve_relevant_hints → populates relevant_hints
    2. aggregate_external_data → populates candidate_recommendations
    3. filter_by_interests → populates filtered_recommendations
    4. match_vibes_and_love_languages → re-scores filtered_recommendations
    5. select_diverse_three → populates final_three
    6. verify_availability → validates/replaces final_three URLs
    """

    # --- Input data (set before graph execution) ---
    vault_data: VaultData
    occasion_type: Literal["just_because", "minor_occasion", "major_milestone"]
    milestone_context: Optional[MilestoneContext] = None
    budget_range: BudgetRange

    # --- Populated by graph nodes ---
    relevant_hints: list[RelevantHint] = Field(default_factory=list)
    candidate_recommendations: list[CandidateRecommendation] = Field(
        default_factory=list
    )
    filtered_recommendations: list[CandidateRecommendation] = Field(
        default_factory=list
    )
    final_three: list[CandidateRecommendation] = Field(default_factory=list)

    # --- Error/status tracking ---
    error: Optional[str] = None
