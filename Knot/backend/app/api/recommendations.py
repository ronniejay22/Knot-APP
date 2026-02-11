"""
Recommendations API — AI-powered recommendation generation and refresh.

Handles generating the Choice-of-Three recommendations,
refresh/re-roll with exclusion logic, and feedback collection.

Step 5.9: POST /api/v1/recommendations/generate — Generate recommendations
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.agents.pipeline import run_recommendation_pipeline
from app.agents.state import (
    BudgetRange,
    MilestoneContext,
    RecommendationState,
    VaultBudget,
    VaultData,
)
from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.recommendations import (
    LocationResponse,
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationItemResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/recommendations", tags=["recommendations"])


# ===================================================================
# POST /api/v1/recommendations/generate — Generate Recommendations
# ===================================================================

@router.post(
    "/generate",
    status_code=status.HTTP_200_OK,
    response_model=RecommendationGenerateResponse,
)
async def generate_recommendations(
    payload: RecommendationGenerateRequest,
    user_id: str = Depends(get_current_user_id),
) -> RecommendationGenerateResponse:
    """
    Generate Choice-of-Three recommendations for the authenticated user.

    Processing steps:
    1. Load the user's vault data from all 6 tables
    2. Optionally load milestone context if milestone_id is provided
    3. Determine the budget range from the vault's budget tiers
    4. Build the RecommendationState and run the LangGraph pipeline
    5. Store the 3 recommendations in the database
    6. Return the recommendations as JSON

    Returns:
        200: 3 recommendations with all required fields.
        401: Missing or invalid authentication token.
        404: No vault exists for this user, or milestone not found.
        422: Validation error in the request payload.
        500: Pipeline error or unexpected failure.
    """
    client = get_service_client()

    # =================================================================
    # 1. Load the user's vault
    # =================================================================
    vault_result = (
        client.table("partner_vaults")
        .select("*")
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    vault = vault_result.data[0]
    vault_id = vault["id"]

    # =================================================================
    # 2. Load all related vault data
    # =================================================================
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

    # =================================================================
    # 3. Determine budget range for this occasion
    # =================================================================
    budget_range = _find_budget_range(vault_budgets, payload.occasion_type)

    # =================================================================
    # 4. Load milestone context (if milestone_id provided)
    # =================================================================
    milestone_context = None
    if payload.milestone_id:
        milestone_result = (
            client.table("partner_milestones")
            .select("*")
            .eq("id", payload.milestone_id)
            .eq("vault_id", vault_id)
            .execute()
        )

        if not milestone_result.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Milestone not found or does not belong to this vault.",
            )

        ms = milestone_result.data[0]
        milestone_context = MilestoneContext(
            id=ms["id"],
            milestone_type=ms["milestone_type"],
            milestone_name=ms["milestone_name"],
            milestone_date=ms["milestone_date"],
            recurrence=ms["recurrence"],
            budget_tier=ms["budget_tier"],
        )

    # =================================================================
    # 5. Build state and run pipeline
    # =================================================================
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

    state = RecommendationState(
        vault_data=vault_data,
        occasion_type=payload.occasion_type,
        milestone_context=milestone_context,
        budget_range=budget_range,
    )

    try:
        result = await run_recommendation_pipeline(state)
    except Exception as exc:
        logger.error(
            "Pipeline failed for vault %s: %s",
            vault_id,
            exc,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to find recommendations right now. Please try again.",
        )

    # Check for pipeline error
    error = result.get("error")
    if error:
        logger.warning(
            "Pipeline returned error for vault %s: %s",
            vault_id,
            error,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=error,
        )

    final_three = result.get("final_three", [])

    if not final_three:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="No recommendations found for this location.",
        )

    # =================================================================
    # 6. Store recommendations in the database
    # =================================================================
    rec_rows = []
    for candidate in final_three:
        rec_rows.append({
            "vault_id": vault_id,
            "milestone_id": payload.milestone_id,
            "recommendation_type": candidate.type,
            "title": candidate.title,
            "description": candidate.description,
            "external_url": candidate.external_url,
            "price_cents": candidate.price_cents,
            "merchant_name": candidate.merchant_name,
            "image_url": candidate.image_url,
        })

    try:
        db_result = client.table("recommendations").insert(rec_rows).execute()
    except Exception as exc:
        logger.error(
            "Failed to store recommendations for vault %s: %s",
            vault_id,
            exc,
        )
        # Still return the recommendations even if DB storage fails
        db_result = None

    # =================================================================
    # 7. Build response
    # =================================================================
    response_items = []
    for i, candidate in enumerate(final_three):
        # Use the DB-generated ID if available, otherwise use the candidate ID
        db_id = candidate.id
        if db_result and db_result.data and i < len(db_result.data):
            db_id = db_result.data[i]["id"]

        location_resp = None
        if candidate.location:
            location_resp = LocationResponse(
                city=candidate.location.city,
                state=candidate.location.state,
                country=candidate.location.country,
                address=candidate.location.address,
            )

        response_items.append(
            RecommendationItemResponse(
                id=db_id,
                recommendation_type=candidate.type,
                title=candidate.title,
                description=candidate.description,
                price_cents=candidate.price_cents,
                currency=candidate.currency,
                external_url=candidate.external_url,
                image_url=candidate.image_url,
                merchant_name=candidate.merchant_name,
                source=candidate.source,
                location=location_resp,
                interest_score=candidate.interest_score,
                vibe_score=candidate.vibe_score,
                love_language_score=candidate.love_language_score,
                final_score=candidate.final_score,
            )
        )

    return RecommendationGenerateResponse(
        recommendations=response_items,
        count=len(response_items),
        milestone_id=payload.milestone_id,
        occasion_type=payload.occasion_type,
    )


# ===================================================================
# Helper functions
# ===================================================================

def _find_budget_range(
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
        "just_because": (2000, 5000),    # $20 - $50
        "minor_occasion": (5000, 15000), # $50 - $150
        "major_milestone": (10000, 50000),  # $100 - $500
    }
    min_amt, max_amt = defaults.get(occasion_type, (2000, 10000))
    return BudgetRange(min_amount=min_amt, max_amount=max_amt)
