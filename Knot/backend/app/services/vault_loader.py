"""
Vault Data Loader — Reusable service for loading partner vault data.

Extracts the vault data loading logic that is shared between the
recommendations API and the notification processing endpoint.

Step 7.3: Extract vault loading into a shared service.
"""

import logging
from typing import Optional

from app.agents.state import (
    BudgetRange,
    MilestoneContext,
    VaultBudget,
    VaultData,
)
from app.db.supabase_client import get_service_client

logger = logging.getLogger(__name__)


# ===================================================================
# Vault Data Loading
# ===================================================================

async def load_vault_data(user_id: str) -> tuple[VaultData, str]:
    """
    Load complete vault data for a user.

    Queries partner_vaults, partner_interests, partner_vibes,
    partner_budgets, and partner_love_languages tables.

    Args:
        user_id: The user's UUID.

    Returns:
        Tuple of (VaultData, vault_id).

    Raises:
        ValueError: If no vault is found for the user.
    """
    client = get_service_client()

    # 1. Load the vault
    vault_result = (
        client.table("partner_vaults")
        .select("*")
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise ValueError(f"No partner vault found for user {user_id[:8]}...")

    vault = vault_result.data[0]
    vault_id = vault["id"]

    # 2. Load all related data
    interests_result = (
        client.table("partner_interests")
        .select("interest_type, interest_category")
        .eq("vault_id", vault_id)
        .execute()
    )

    vibes_result = (
        client.table("partner_vibes")
        .select("vibe_tag")
        .eq("vault_id", vault_id)
        .execute()
    )

    budgets_result = (
        client.table("partner_budgets")
        .select("occasion_type, min_amount, max_amount, currency")
        .eq("vault_id", vault_id)
        .execute()
    )

    love_languages_result = (
        client.table("partner_love_languages")
        .select("language, priority")
        .eq("vault_id", vault_id)
        .execute()
    )

    # Parse interests into likes/dislikes
    likes = [
        row["interest_category"]
        for row in (interests_result.data or [])
        if row["interest_type"] == "like"
    ]
    dislikes = [
        row["interest_category"]
        for row in (interests_result.data or [])
        if row["interest_type"] == "dislike"
    ]

    vibes = [row["vibe_tag"] for row in (vibes_result.data or [])]

    # Parse love languages
    primary_ll = ""
    secondary_ll = ""
    for row in (love_languages_result.data or []):
        if row["priority"] == 1:
            primary_ll = row["language"]
        elif row["priority"] == 2:
            secondary_ll = row["language"]

    # Parse budgets
    vault_budgets = [
        VaultBudget(
            occasion_type=row["occasion_type"],
            min_amount=row["min_amount"],
            max_amount=row["max_amount"],
            currency=row.get("currency", "USD"),
        )
        for row in (budgets_result.data or [])
    ]

    vault_data = VaultData(
        vault_id=vault_id,
        partner_name=vault["partner_name"],
        relationship_tenure_months=vault.get("relationship_tenure_months"),
        cohabitation_status=vault.get("cohabitation_status"),
        location_city=vault.get("location_city"),
        location_state=vault.get("location_state"),
        location_country=vault.get("location_country", "US"),
        interests=likes,
        dislikes=dislikes,
        vibes=vibes,
        primary_love_language=primary_ll,
        secondary_love_language=secondary_ll,
        budgets=vault_budgets,
    )

    return vault_data, vault_id


# ===================================================================
# Milestone Context Loading
# ===================================================================

async def load_milestone_context(
    milestone_id: str,
    vault_id: str,
) -> Optional[MilestoneContext]:
    """
    Load milestone details and build MilestoneContext.

    Args:
        milestone_id: UUID of the milestone.
        vault_id: UUID of the vault (for ownership verification).

    Returns:
        MilestoneContext if found, None otherwise.
    """
    client = get_service_client()

    milestone_result = (
        client.table("partner_milestones")
        .select("*")
        .eq("id", milestone_id)
        .eq("vault_id", vault_id)
        .execute()
    )

    if not milestone_result.data:
        return None

    ms = milestone_result.data[0]
    return MilestoneContext(
        id=ms["id"],
        milestone_type=ms["milestone_type"],
        milestone_name=ms["milestone_name"],
        milestone_date=ms["milestone_date"],
        recurrence=ms["recurrence"],
        budget_tier=ms["budget_tier"],
    )


# ===================================================================
# Budget Range Helper
# ===================================================================

def find_budget_range(
    budgets: list[VaultBudget],
    occasion_type: str,
) -> BudgetRange:
    """
    Find the budget range for the given occasion type.

    Falls back to sensible defaults if no matching budget tier
    is found in the user's vault data.
    """
    for budget in budgets:
        if budget.occasion_type == occasion_type:
            return BudgetRange(
                min_amount=budget.min_amount,
                max_amount=budget.max_amount,
                currency=budget.currency,
            )

    # Fallback defaults (in cents)
    defaults = {
        "just_because": (2000, 5000),      # $20 - $50
        "minor_occasion": (5000, 15000),   # $50 - $150
        "major_milestone": (10000, 50000), # $100 - $500
    }
    min_amt, max_amt = defaults.get(occasion_type, (2000, 10000))
    return BudgetRange(min_amount=min_amt, max_amount=max_amt)
