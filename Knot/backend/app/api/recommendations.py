"""
Recommendations API — AI-powered recommendation generation and refresh.

Handles generating the Choice-of-Three recommendations,
refresh/re-roll with exclusion logic, and feedback collection.

Step 5.9: POST /api/v1/recommendations/generate — Generate recommendations
Step 5.10: POST /api/v1/recommendations/refresh — Refresh/re-roll with exclusions
Step 6.3: POST /api/v1/recommendations/feedback — Record user feedback
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.agents.pipeline import run_recommendation_pipeline
from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultBudget,
    VaultData,
)
from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.recommendations import (
    LocationResponse,
    RecommendationFeedbackRequest,
    RecommendationFeedbackResponse,
    RecommendationGenerateRequest,
    RecommendationGenerateResponse,
    RecommendationItemResponse,
    RecommendationRefreshRequest,
    RecommendationRefreshResponse,
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

    # TODO: Remove mock fallback once external integrations (Phase 8) are live
    if not final_three:
        logger.info("Pipeline returned no results for vault %s — using mock data", vault_id)
        final_three = [
            CandidateRecommendation(
                id="mock-gift-001",
                source="amazon",
                type="gift",
                title="Handmade Ceramic Mug Set",
                description="A beautiful set of 2 hand-thrown ceramic mugs in earth tones. Perfect for cozy mornings together.",
                price_cents=4500,
                currency="USD",
                external_url="https://example.com/ceramic-mugs",
                image_url="https://images.unsplash.com/photo-1514228742587-6b1558fcca3d?w=800",
                merchant_name="Artisan Pottery Co.",
                interest_score=0.85,
                vibe_score=0.78,
                love_language_score=0.72,
                final_score=0.80,
            ),
            CandidateRecommendation(
                id="mock-experience-002",
                source="yelp",
                type="experience",
                title="Private Sunset Sailing on the Bay",
                description="A 2-hour private sailing trip with champagne and charcuterie as the sun sets. Includes a professional skipper.",
                price_cents=24900,
                currency="USD",
                external_url="https://example.com/sunset-sailing",
                image_url="https://images.unsplash.com/photo-1500514966906-fe245eea9344?w=800",
                merchant_name="Bay Sailing Co.",
                interest_score=0.90,
                vibe_score=0.85,
                love_language_score=0.70,
                final_score=0.83,
            ),
            CandidateRecommendation(
                id="mock-date-003",
                source="yelp",
                type="date",
                title="Candlelit Italian Dinner for Two",
                description="An intimate 5-course tasting menu at a hidden gem Italian restaurant. Includes wine pairings and a private corner table.",
                price_cents=18000,
                currency="USD",
                external_url="https://example.com/italian-dinner",
                image_url="https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=800",
                merchant_name="Trattoria Luna",
                interest_score=0.75,
                vibe_score=0.92,
                love_language_score=0.88,
                final_score=0.84,
            ),
        ]

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
    response_items = _build_response_items(final_three, db_result)

    return RecommendationGenerateResponse(
        recommendations=response_items,
        count=len(response_items),
        milestone_id=payload.milestone_id,
        occasion_type=payload.occasion_type,
    )


# ===================================================================
# POST /api/v1/recommendations/refresh — Refresh (Re-roll) Logic
# ===================================================================

@router.post(
    "/refresh",
    status_code=status.HTTP_200_OK,
    response_model=RecommendationRefreshResponse,
)
async def refresh_recommendations(
    payload: RecommendationRefreshRequest,
    user_id: str = Depends(get_current_user_id),
) -> RecommendationRefreshResponse:
    """
    Refresh (re-roll) recommendations with exclusion filters.

    Processing steps:
    1. Validate the rejected recommendation IDs belong to this user
    2. Store feedback with action='refreshed' for each rejected recommendation
    3. Load the user's vault data and determine the budget/occasion from
       the original recommendations
    4. Re-run the pipeline with the full candidate pool
    5. Apply exclusion filters based on the rejection reason
    6. Re-run diversity selection and availability verification
    7. Store and return 3 new recommendations

    Exclusion logic by rejection_reason:
    - too_expensive: Exclude candidates at or above the rejected price tier
    - too_cheap: Exclude candidates at or below the rejected price tier
    - not_their_style: Exclude candidates matching the vibe category of rejected items
    - already_have_similar: Exclude same merchant and product category
    - show_different: Exclude only the exact same items

    Returns:
        200: 3 new recommendations after applying exclusion filters.
        401: Missing or invalid authentication token.
        404: No vault found, or rejected recommendations not found.
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
    # 2. Load rejected recommendations from the database
    # =================================================================
    rejected_recs = (
        client.table("recommendations")
        .select("*")
        .eq("vault_id", vault_id)
        .in_("id", payload.rejected_recommendation_ids)
        .execute()
    )

    if not rejected_recs.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rejected recommendations not found or do not belong to this user.",
        )

    # =================================================================
    # 3. Store feedback with action='refreshed'
    # =================================================================
    for rec in rejected_recs.data:
        try:
            client.table("recommendation_feedback").insert({
                "recommendation_id": rec["id"],
                "user_id": user_id,
                "action": "refreshed",
                "feedback_text": payload.rejection_reason,
            }).execute()
        except Exception as exc:
            logger.warning(
                "Failed to store refresh feedback for rec %s: %s",
                rec["id"], exc,
            )

    # =================================================================
    # 4. Load all vault data for pipeline re-run
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

    primary_ll = ""
    secondary_ll = ""
    for row in (love_languages_result.data or []):
        if row["priority"] == 1:
            primary_ll = row["language"]
        elif row["priority"] == 2:
            secondary_ll = row["language"]

    vault_budgets = [
        VaultBudget(
            occasion_type=row["occasion_type"],
            min_amount=row["min_amount"],
            max_amount=row["max_amount"],
            currency=row.get("currency", "USD"),
        )
        for row in (budgets_result.data or [])
    ]

    # Determine occasion type from the original recommendation's budget tier
    # Default to "just_because" if not determinable
    occasion_type = "just_because"
    if rejected_recs.data[0].get("milestone_id"):
        ms_result = (
            client.table("partner_milestones")
            .select("budget_tier")
            .eq("id", rejected_recs.data[0]["milestone_id"])
            .execute()
        )
        if ms_result.data:
            occasion_type = ms_result.data[0]["budget_tier"]

    budget_range = _find_budget_range(vault_budgets, occasion_type)

    # =================================================================
    # 5. Build state and run pipeline to get fresh candidate pool
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
        occasion_type=occasion_type,
        budget_range=budget_range,
    )

    try:
        result = await run_recommendation_pipeline(state)
    except Exception as exc:
        logger.error(
            "Refresh pipeline failed for vault %s: %s",
            vault_id, exc, exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to find recommendations right now. Please try again.",
        )

    error = result.get("error")
    if error:
        logger.warning(
            "Refresh pipeline returned error for vault %s: %s",
            vault_id, error,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=error,
        )

    # =================================================================
    # 6. Apply exclusion filters based on rejection reason
    # =================================================================
    candidates = result.get("final_three", [])
    # Use the filtered pool for replacements (broader candidate set)
    filtered_pool = result.get("filtered_recommendations", [])

    # Combine final_three and filtered_pool for re-selection
    all_candidates = list(filtered_pool) if filtered_pool else list(candidates)

    # Apply exclusion filters
    excluded = _apply_exclusion_filters(
        all_candidates,
        rejected_recs.data,
        payload.rejection_reason,
        budget_range,
    )

    if not excluded:
        # TODO: Remove mock fallback once external integrations (Phase 8) are live
        logger.info("Refresh returned no results for vault %s — using mock data", vault_id)
        excluded = [
            CandidateRecommendation(
                id="mock-refresh-gift-001",
                source="shopify",
                type="gift",
                title="Personalized Star Map Print",
                description="A custom star map showing the night sky on a date that matters to you. Framed and ready to hang.",
                price_cents=6500,
                currency="USD",
                external_url="https://example.com/star-map",
                image_url="https://images.unsplash.com/photo-1519681393784-d120267933ba?w=800",
                merchant_name="Night Sky Prints",
                interest_score=0.82,
                vibe_score=0.88,
                love_language_score=0.75,
                final_score=0.82,
            ),
            CandidateRecommendation(
                id="mock-refresh-exp-002",
                source="yelp",
                type="experience",
                title="Couples Cooking Class — Thai Cuisine",
                description="Learn to cook authentic Thai dishes together with a professional chef. Includes all ingredients and a recipe booklet.",
                price_cents=15000,
                currency="USD",
                external_url="https://example.com/thai-cooking",
                image_url="https://images.unsplash.com/photo-1556910103-1c02745aae4d?w=800",
                merchant_name="Chef's Table Studio",
                interest_score=0.78,
                vibe_score=0.80,
                love_language_score=0.85,
                final_score=0.81,
            ),
            CandidateRecommendation(
                id="mock-refresh-date-003",
                source="yelp",
                type="date",
                title="Rooftop Jazz & Cocktails Night",
                description="An evening of live jazz on a rooftop bar with craft cocktails and city views. Reservations for a private table.",
                price_cents=12000,
                currency="USD",
                external_url="https://example.com/jazz-night",
                image_url="https://images.unsplash.com/photo-1415201364774-f6f0bb35f28f?w=800",
                merchant_name="The Skyline Lounge",
                interest_score=0.80,
                vibe_score=0.90,
                love_language_score=0.82,
                final_score=0.84,
            ),
        ]

    # Select top 3 from the filtered candidates
    excluded.sort(key=lambda c: c.final_score, reverse=True)
    new_three = excluded[:3]

    # =================================================================
    # 7. Store new recommendations in the database
    # =================================================================
    rec_rows = []
    for candidate in new_three:
        rec_rows.append({
            "vault_id": vault_id,
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
            "Failed to store refreshed recommendations for vault %s: %s",
            vault_id, exc,
        )
        db_result = None

    # =================================================================
    # 8. Build response
    # =================================================================
    response_items = _build_response_items(new_three, db_result)

    return RecommendationRefreshResponse(
        recommendations=response_items,
        count=len(response_items),
        rejection_reason=payload.rejection_reason,
    )


# ===================================================================
# POST /api/v1/recommendations/feedback — Record User Feedback
# ===================================================================

@router.post(
    "/feedback",
    status_code=status.HTTP_201_CREATED,
    response_model=RecommendationFeedbackResponse,
)
async def record_feedback(
    payload: RecommendationFeedbackRequest,
    user_id: str = Depends(get_current_user_id),
) -> RecommendationFeedbackResponse:
    """
    Record user feedback on a recommendation.

    Stores the user's action (selected, saved, shared, rated) in the
    recommendation_feedback table. Used to track user engagement and
    improve future recommendations.

    Returns:
        201: Feedback recorded successfully.
        401: Missing or invalid authentication token.
        404: Recommendation not found or does not belong to this user.
        422: Validation error in the request payload.
    """
    client = get_service_client()

    # Verify the recommendation exists and belongs to this user's vault
    rec_result = (
        client.table("recommendations")
        .select("id, vault_id")
        .eq("id", payload.recommendation_id)
        .execute()
    )

    if not rec_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Recommendation not found.",
        )

    # Verify the vault belongs to this user
    vault_result = (
        client.table("partner_vaults")
        .select("id")
        .eq("id", rec_result.data[0]["vault_id"])
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Recommendation does not belong to this user.",
        )

    # Store the feedback
    feedback_row = {
        "recommendation_id": payload.recommendation_id,
        "user_id": user_id,
        "action": payload.action,
        "rating": payload.rating,
        "feedback_text": payload.feedback_text,
    }

    try:
        result = (
            client.table("recommendation_feedback")
            .insert(feedback_row)
            .execute()
        )
    except Exception as exc:
        logger.error(
            "Failed to store feedback for rec %s: %s",
            payload.recommendation_id,
            exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record feedback.",
        )

    row = result.data[0]
    return RecommendationFeedbackResponse(
        id=row["id"],
        recommendation_id=row["recommendation_id"],
        action=row["action"],
        created_at=row["created_at"],
    )


# ===================================================================
# Exclusion filter logic (Step 5.10)
# ===================================================================

def _classify_price_tier(
    price_cents: int | None,
    budget_range: BudgetRange,
) -> str:
    """Classify a price into low/mid/high within the budget range."""
    if price_cents is None:
        return "mid"

    range_size = budget_range.max_amount - budget_range.min_amount
    if range_size <= 0:
        return "mid"

    third = range_size / 3
    if price_cents < budget_range.min_amount + third:
        return "low"
    elif price_cents < budget_range.min_amount + 2 * third:
        return "mid"
    else:
        return "high"


# Tier ordering for price-based exclusions
_TIER_ORDER = {"low": 0, "mid": 1, "high": 2}


def _apply_exclusion_filters(
    candidates: list[CandidateRecommendation],
    rejected_recs: list[dict],
    rejection_reason: str,
    budget_range: BudgetRange,
) -> list[CandidateRecommendation]:
    """
    Apply exclusion filters based on the rejection reason.

    Exclusion logic:
    - too_expensive: Exclude candidates at or above the rejected price tier;
      favor lower prices.
    - too_cheap: Exclude candidates at or below the rejected price tier;
      favor higher prices.
    - not_their_style: Exclude candidates matching the vibe category
      of rejected items (via metadata.matched_vibe).
    - already_have_similar: Exclude same merchant AND same recommendation type
      as rejected items.
    - show_different: Exclude only the exact same items (by title).

    Args:
        candidates: The full candidate pool to filter.
        rejected_recs: The rejected recommendation DB rows.
        rejection_reason: The reason for rejection.
        budget_range: The budget range for price tier classification.

    Returns:
        A filtered list of candidates.
    """
    rejected_titles = {rec["title"] for rec in rejected_recs}

    if rejection_reason == "show_different":
        # Only exclude the exact same items
        return [c for c in candidates if c.title not in rejected_titles]

    if rejection_reason == "too_expensive":
        # Get the highest price tier among rejected items
        rejected_tiers = [
            _classify_price_tier(rec.get("price_cents"), budget_range)
            for rec in rejected_recs
        ]
        max_rejected_tier = max(
            rejected_tiers, key=lambda t: _TIER_ORDER.get(t, 1),
        )
        max_tier_level = _TIER_ORDER.get(max_rejected_tier, 1)

        # Exclude candidates at or above the rejected tier
        filtered = []
        for c in candidates:
            if c.title in rejected_titles:
                continue
            candidate_tier = _classify_price_tier(c.price_cents, budget_range)
            if _TIER_ORDER.get(candidate_tier, 1) < max_tier_level:
                filtered.append(c)
        return filtered

    if rejection_reason == "too_cheap":
        # Get the lowest price tier among rejected items
        rejected_tiers = [
            _classify_price_tier(rec.get("price_cents"), budget_range)
            for rec in rejected_recs
        ]
        min_rejected_tier = min(
            rejected_tiers, key=lambda t: _TIER_ORDER.get(t, 1),
        )
        min_tier_level = _TIER_ORDER.get(min_rejected_tier, 1)

        # Exclude candidates at or below the rejected tier
        filtered = []
        for c in candidates:
            if c.title in rejected_titles:
                continue
            candidate_tier = _classify_price_tier(c.price_cents, budget_range)
            if _TIER_ORDER.get(candidate_tier, 1) > min_tier_level:
                filtered.append(c)
        return filtered

    if rejection_reason == "not_their_style":
        # Exclude candidates with the same vibe as rejected items
        rejected_vibes: set[str] = set()
        for rec in rejected_recs:
            # Look up the candidate's vibe from the candidate pool
            for c in candidates:
                if c.title == rec["title"]:
                    vibe = c.metadata.get("matched_vibe", "")
                    if vibe:
                        rejected_vibes.add(vibe.strip().lower())
                    break

        filtered = []
        for c in candidates:
            if c.title in rejected_titles:
                continue
            candidate_vibe = c.metadata.get("matched_vibe", "").strip().lower()
            if candidate_vibe and candidate_vibe in rejected_vibes:
                continue
            filtered.append(c)
        return filtered

    if rejection_reason == "already_have_similar":
        # Exclude same merchant AND same recommendation type
        rejected_merchants: set[tuple[str, str]] = set()
        for rec in rejected_recs:
            merchant = (rec.get("merchant_name") or "").strip().lower()
            rec_type = rec.get("recommendation_type", "")
            rejected_merchants.add((merchant, rec_type))

        filtered = []
        for c in candidates:
            if c.title in rejected_titles:
                continue
            candidate_merchant = (c.merchant_name or "").strip().lower()
            if (candidate_merchant, c.type) in rejected_merchants:
                continue
            filtered.append(c)
        return filtered

    # Fallback: exclude only exact matches (same as show_different)
    return [c for c in candidates if c.title not in rejected_titles]


# ===================================================================
# Shared helper: build response items from candidates
# ===================================================================

def _build_response_items(
    candidates: list[CandidateRecommendation],
    db_result=None,
) -> list[RecommendationItemResponse]:
    """Build RecommendationItemResponse list from candidates with optional DB IDs."""
    response_items = []
    for i, candidate in enumerate(candidates):
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
    return response_items


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
