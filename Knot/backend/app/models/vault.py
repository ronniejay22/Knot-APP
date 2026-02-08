"""
Vault Models — Pydantic schemas for Partner Vault API.

Defines request/response models for the POST /api/v1/vault endpoint.
Validates all partner profile data against predefined categories, counts,
and business rules before database insertion.

Step 3.10: Create Vault Submission API Endpoint (Backend)
"""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, field_validator, model_validator


# ======================================================================
# Valid enum values (mirror database CHECK constraints)
# ======================================================================

VALID_INTEREST_CATEGORIES: set[str] = {
    "Travel", "Cooking", "Movies", "Music", "Reading",
    "Sports", "Gaming", "Art", "Photography", "Fitness",
    "Fashion", "Technology", "Nature", "Food", "Coffee",
    "Wine", "Dancing", "Theater", "Concerts", "Museums",
    "Shopping", "Yoga", "Hiking", "Beach", "Pets",
    "Cars", "DIY", "Gardening", "Meditation", "Podcasts",
    "Baking", "Camping", "Cycling", "Running", "Swimming",
    "Skiing", "Surfing", "Painting", "Board Games", "Karaoke",
}

VALID_VIBE_TAGS: set[str] = {
    "quiet_luxury", "street_urban", "outdoorsy", "vintage",
    "minimalist", "bohemian", "romantic", "adventurous",
}

VALID_LOVE_LANGUAGES: set[str] = {
    "words_of_affirmation", "acts_of_service", "receiving_gifts",
    "quality_time", "physical_touch",
}


# ======================================================================
# Sub-models
# ======================================================================

class MilestoneCreate(BaseModel):
    """A single milestone in the vault submission payload."""

    milestone_type: Literal["birthday", "anniversary", "holiday", "custom"]
    milestone_name: str
    milestone_date: str  # ISO date format: "2000-03-15"
    recurrence: Literal["yearly", "one_time"]
    budget_tier: Optional[
        Literal["just_because", "minor_occasion", "major_milestone"]
    ] = None

    @field_validator("milestone_name")
    @classmethod
    def validate_milestone_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("milestone_name cannot be empty")
        return v

    @model_validator(mode="after")
    def validate_budget_tier_for_custom(self) -> MilestoneCreate:
        """Custom milestones must have an explicit budget_tier."""
        if self.milestone_type == "custom" and self.budget_tier is None:
            raise ValueError(
                "budget_tier is required for custom milestones. "
                "Choose 'just_because', 'minor_occasion', or 'major_milestone'."
            )
        return self


class BudgetCreate(BaseModel):
    """A single budget tier in the vault submission payload."""

    occasion_type: Literal["just_because", "minor_occasion", "major_milestone"]
    min_amount: int  # in cents (e.g., 2000 = $20.00)
    max_amount: int  # in cents (e.g., 5000 = $50.00)
    currency: str = "USD"

    @model_validator(mode="after")
    def validate_amounts(self) -> BudgetCreate:
        """Ensure min_amount >= 0 and max_amount >= min_amount."""
        if self.min_amount < 0:
            raise ValueError("min_amount must be >= 0")
        if self.max_amount < self.min_amount:
            raise ValueError(
                f"max_amount ({self.max_amount}) must be >= min_amount ({self.min_amount})"
            )
        return self


class LoveLanguagesCreate(BaseModel):
    """Primary and secondary love language selections."""

    primary: Literal[
        "words_of_affirmation", "acts_of_service", "receiving_gifts",
        "quality_time", "physical_touch",
    ]
    secondary: Literal[
        "words_of_affirmation", "acts_of_service", "receiving_gifts",
        "quality_time", "physical_touch",
    ]

    @model_validator(mode="after")
    def validate_different(self) -> LoveLanguagesCreate:
        """Primary and secondary love languages must be different."""
        if self.primary == self.secondary:
            raise ValueError(
                "Primary and secondary love languages must be different."
            )
        return self


# ======================================================================
# Main Vault Request Model
# ======================================================================

class VaultCreateRequest(BaseModel):
    """
    Complete Partner Vault submission payload.

    Accepts all partner profile data from the onboarding flow:
    basic info, interests, dislikes, milestones, vibes, budgets,
    and love languages.

    Validated rules:
    - partner_name: required, non-empty
    - interests: exactly 5, from predefined list, no duplicates
    - dislikes: exactly 5, from predefined list, no duplicates, no overlap with interests
    - milestones: at least 1 (birthday required)
    - vibes: 1–8, from predefined list, no duplicates
    - budgets: exactly 3 (one per occasion type)
    - love_languages: primary and secondary, must be different
    """

    # --- Basic info ---
    partner_name: str
    relationship_tenure_months: Optional[int] = None
    cohabitation_status: Optional[
        Literal["living_together", "separate", "long_distance"]
    ] = None
    location_city: Optional[str] = None
    location_state: Optional[str] = None
    location_country: Optional[str] = "US"

    # --- Interests and dislikes ---
    interests: list[str]  # exactly 5 likes
    dislikes: list[str]   # exactly 5 hard avoids

    # --- Milestones ---
    milestones: list[MilestoneCreate]

    # --- Vibes ---
    vibes: list[str]  # 1–8 valid vibe tags

    # --- Budgets ---
    budgets: list[BudgetCreate]  # exactly 3 (one per occasion type)

    # --- Love languages ---
    love_languages: LoveLanguagesCreate

    # ------------------------------------------------------------------
    # Field validators
    # ------------------------------------------------------------------

    @field_validator("partner_name")
    @classmethod
    def validate_partner_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("partner_name cannot be empty")
        return v

    @field_validator("interests")
    @classmethod
    def validate_interests(cls, v: list[str]) -> list[str]:
        if len(v) != 5:
            raise ValueError(f"Exactly 5 interests are required, got {len(v)}")
        if len(set(v)) != 5:
            raise ValueError("Interests must be unique — no duplicates allowed")
        invalid = set(v) - VALID_INTEREST_CATEGORIES
        if invalid:
            raise ValueError(f"Invalid interest categories: {sorted(invalid)}")
        return v

    @field_validator("dislikes")
    @classmethod
    def validate_dislikes(cls, v: list[str]) -> list[str]:
        if len(v) != 5:
            raise ValueError(f"Exactly 5 dislikes are required, got {len(v)}")
        if len(set(v)) != 5:
            raise ValueError("Dislikes must be unique — no duplicates allowed")
        invalid = set(v) - VALID_INTEREST_CATEGORIES
        if invalid:
            raise ValueError(f"Invalid dislike categories: {sorted(invalid)}")
        return v

    @field_validator("milestones")
    @classmethod
    def validate_milestones(cls, v: list[MilestoneCreate]) -> list[MilestoneCreate]:
        if len(v) < 1:
            raise ValueError("At least 1 milestone (birthday) is required")
        birthday_count = sum(1 for m in v if m.milestone_type == "birthday")
        if birthday_count < 1:
            raise ValueError("A birthday milestone is required")
        return v

    @field_validator("vibes")
    @classmethod
    def validate_vibes(cls, v: list[str]) -> list[str]:
        if len(v) < 1:
            raise ValueError("At least 1 vibe is required")
        if len(v) > 8:
            raise ValueError(f"Maximum 8 vibes allowed, got {len(v)}")
        if len(set(v)) != len(v):
            raise ValueError("Vibes must be unique — no duplicates allowed")
        invalid = set(v) - VALID_VIBE_TAGS
        if invalid:
            raise ValueError(f"Invalid vibe tags: {sorted(invalid)}")
        return v

    @field_validator("budgets")
    @classmethod
    def validate_budgets(cls, v: list[BudgetCreate]) -> list[BudgetCreate]:
        if len(v) != 3:
            raise ValueError(
                f"Exactly 3 budget tiers are required "
                f"(one per occasion type), got {len(v)}"
            )
        occasion_types = {b.occasion_type for b in v}
        expected = {"just_because", "minor_occasion", "major_milestone"}
        if occasion_types != expected:
            missing = expected - occasion_types
            raise ValueError(
                f"Budgets must include one entry for each occasion type. "
                f"Missing: {sorted(missing)}"
            )
        return v

    # ------------------------------------------------------------------
    # Model-level validators (cross-field)
    # ------------------------------------------------------------------

    @model_validator(mode="after")
    def validate_no_interest_overlap(self) -> VaultCreateRequest:
        """Ensure no interest appears in both likes and dislikes."""
        overlap = set(self.interests) & set(self.dislikes)
        if overlap:
            raise ValueError(
                f"Interests and dislikes must not overlap. "
                f"These appear in both: {sorted(overlap)}"
            )
        return self


# ======================================================================
# Response Models
# ======================================================================

class VaultCreateResponse(BaseModel):
    """Response after successful vault creation."""

    vault_id: str
    partner_name: str
    interests_count: int
    dislikes_count: int
    milestones_count: int
    vibes_count: int
    budgets_count: int
    love_languages: dict[str, str]
