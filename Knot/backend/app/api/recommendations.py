"""
Recommendations API — AI-powered recommendation generation and refresh.

Handles generating the Choice-of-Three recommendations,
refresh/re-roll with exclusion logic, and feedback collection.

Step 5.9: POST /api/v1/recommendations/generate — Generate recommendations
Step 5.10: POST /api/v1/recommendations/refresh — Refresh/re-roll with exclusions
Step 6.3: POST /api/v1/recommendations/feedback — Record user feedback
Step 7.7: GET /api/v1/recommendations/by-milestone/{milestone_id} — Fetch stored recommendations
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.agents.pipeline import run_recommendation_pipeline
from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    RecommendationState,
)
from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.notifications import (
    MilestoneRecommendationItem,
    MilestoneRecommendationsResponse,
)
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
from app.services.vault_loader import (
    find_budget_range,
    load_learned_weights,
    load_milestone_context,
    load_vault_data,
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
    # =================================================================
    # 1. Load the user's vault data
    # =================================================================
    try:
        vault_data, vault_id = await load_vault_data(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    # =================================================================
    # 2. Load milestone context (if milestone_id provided)
    # =================================================================
    milestone_context = None
    if payload.milestone_id:
        milestone_context = await load_milestone_context(
            payload.milestone_id, vault_id,
        )
        if milestone_context is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Milestone not found or does not belong to this vault.",
            )

    # =================================================================
    # 3. Determine budget range for this occasion
    # =================================================================
    budget_range = find_budget_range(vault_data.budgets, payload.occasion_type)

    # =================================================================
    # 4. Load learned weights, history, and build pipeline state
    # =================================================================
    client = get_service_client()

    learned_weights = await load_learned_weights(user_id)

    # Load recent recommendation titles + descriptions to exclude from new results
    excluded_titles = _load_recent_titles(client, vault_id)
    excluded_descriptions = _load_recent_descriptions(client, vault_id)

    state = RecommendationState(
        vault_data=vault_data,
        occasion_type=payload.occasion_type,
        milestone_context=milestone_context,
        budget_range=budget_range,
        learned_weights=learned_weights,
        excluded_titles=excluded_titles,
        excluded_descriptions=excluded_descriptions,
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
        logger.warning("Pipeline returned no results for vault %s", vault_id)

    # =================================================================
    # 5. Store recommendations in the database
    # =================================================================
    rec_rows = []
    for candidate in final_three:
        row = {
            "vault_id": vault_id,
            "milestone_id": payload.milestone_id,
            "recommendation_type": candidate.type,
            "title": candidate.title,
            "description": candidate.description,
            "external_url": candidate.external_url,
            "price_cents": candidate.price_cents,
            "merchant_name": candidate.merchant_name,
            "image_url": candidate.image_url,
        }
        # Include idea-specific fields only when the candidate is an idea (Step 14.4)
        if getattr(candidate, "is_idea", False):
            row["is_idea"] = True
            if getattr(candidate, "content_sections", None):
                import json
                row["content_sections"] = json.dumps(candidate.content_sections)
        # Include personalization note (Step 15.1)
        if getattr(candidate, "personalization_note", None):
            row["personalization_note"] = candidate.personalization_note
        rec_rows.append(row)

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
    # 6. Build response
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
    # =================================================================
    # 1. Load the user's vault data
    # =================================================================
    try:
        vault_data, vault_id = await load_vault_data(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    client = get_service_client()

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
    # 4. Determine occasion type and build pipeline state
    # =================================================================
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

    # Apply session-scoped vibe override if provided (Step 6.5)
    if payload.vibe_override:
        vault_data.vibes = payload.vibe_override

    budget_range = find_budget_range(vault_data.budgets, occasion_type)

    learned_weights = await load_learned_weights(user_id)

    # Load recent recommendation titles + descriptions to exclude from new results
    excluded_titles = _load_recent_titles(client, vault_id)
    excluded_descriptions = _load_recent_descriptions(client, vault_id)

    state = RecommendationState(
        vault_data=vault_data,
        occasion_type=occasion_type,
        budget_range=budget_range,
        learned_weights=learned_weights,
        excluded_titles=excluded_titles,
        excluded_descriptions=excluded_descriptions,
        vibe_override=payload.vibe_override,
        rejection_reason=payload.rejection_reason,
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
    # 5. Use the unified pipeline results directly
    # =================================================================
    candidates = result.get("final_three", [])

    if not candidates:
        logger.warning("Refresh returned no results for vault %s", vault_id)

    new_three = candidates[:3]

    # =================================================================
    # 6. Store new recommendations in the database
    # =================================================================
    rec_rows = []
    for candidate in new_three:
        row = {
            "vault_id": vault_id,
            "recommendation_type": candidate.type,
            "title": candidate.title,
            "description": candidate.description,
            "external_url": candidate.external_url,
            "price_cents": candidate.price_cents,
            "merchant_name": candidate.merchant_name,
            "image_url": candidate.image_url,
        }
        if getattr(candidate, "is_idea", False):
            row["is_idea"] = True
            if getattr(candidate, "content_sections", None):
                import json
                row["content_sections"] = json.dumps(candidate.content_sections)
        if getattr(candidate, "personalization_note", None):
            row["personalization_note"] = candidate.personalization_note
        rec_rows.append(row)

    try:
        db_result = client.table("recommendations").insert(rec_rows).execute()
    except Exception as exc:
        logger.error(
            "Failed to store refreshed recommendations for vault %s: %s",
            vault_id, exc,
        )
        db_result = None

    # =================================================================
    # 7. Build response
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
# GET /api/v1/recommendations/by-milestone/{milestone_id} (Step 7.7)
# ===================================================================

@router.get(
    "/by-milestone/{milestone_id}",
    status_code=status.HTTP_200_OK,
    response_model=MilestoneRecommendationsResponse,
)
async def get_recommendations_by_milestone(
    milestone_id: str,
    user_id: str = Depends(get_current_user_id),
) -> MilestoneRecommendationsResponse:
    """
    Fetch existing (pre-generated) recommendations for a specific milestone.

    Used by the Notification History screen to display the recommendations
    that were generated when the notification fired. Does NOT generate new
    recommendations — it only returns what already exists in the database.

    Returns:
        200: List of stored recommendations for the milestone.
        401: Missing or invalid authentication token.
        404: No partner vault found for this user.
        500: Database error.
    """
    client = get_service_client()

    # 1. Get the user's vault_id
    try:
        vault_result = (
            client.table("partner_vaults")
            .select("id")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error(f"Failed to look up vault: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to look up vault.",
        )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    vault_id = vault_result.data[0]["id"]

    # 2. Fetch recommendations for this milestone + vault
    try:
        rec_result = (
            client.table("recommendations")
            .select("*")
            .eq("vault_id", vault_id)
            .eq("milestone_id", milestone_id)
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        )
    except Exception as exc:
        logger.error(f"Failed to load recommendations for milestone {milestone_id}: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load recommendations.",
        )

    items = [
        MilestoneRecommendationItem(
            id=r["id"],
            recommendation_type=r["recommendation_type"],
            title=r["title"],
            description=r.get("description"),
            external_url=r.get("external_url"),
            price_cents=r.get("price_cents"),
            merchant_name=r.get("merchant_name"),
            image_url=r.get("image_url"),
            created_at=r["created_at"],
        )
        for r in (rec_result.data or [])
    ]

    return MilestoneRecommendationsResponse(
        recommendations=items,
        count=len(items),
        milestone_id=milestone_id,
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
# GET /api/v1/recommendations/{recommendation_id} (Step 9.2)
# ===================================================================
#
# IMPORTANT: This route MUST remain the LAST route registered on the
# router because /{recommendation_id} is a catch-all path parameter.
# If placed before /generate, /refresh, /feedback, or /by-milestone/,
# those paths would be captured as recommendation IDs.


@router.get(
    "/{recommendation_id}",
    status_code=status.HTTP_200_OK,
    response_model=MilestoneRecommendationItem,
)
async def get_recommendation_by_id(
    recommendation_id: str,
    user_id: str = Depends(get_current_user_id),
) -> MilestoneRecommendationItem:
    """
    Fetch a single recommendation by its database ID.

    Used by the deep link handler to load a recommendation that was shared
    via Universal Links (https://api.knot-app.com/recommendation/{id}).

    Returns:
        200: The recommendation details.
        401: Missing or invalid authentication token.
        404: Recommendation not found or does not belong to this user.
        500: Database error.
    """
    client = get_service_client()

    # 1. Get the user's vault_id
    try:
        vault_result = (
            client.table("partner_vaults")
            .select("id")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error(f"Failed to look up vault: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to look up vault.",
        )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    vault_id = vault_result.data[0]["id"]

    # 2. Fetch the recommendation by ID
    try:
        rec_result = (
            client.table("recommendations")
            .select("*")
            .eq("id", recommendation_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error(
            f"Failed to fetch recommendation {recommendation_id}: {exc}"
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load recommendation.",
        )

    if not rec_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Recommendation not found.",
        )

    rec = rec_result.data[0]

    # 3. Verify the recommendation belongs to this user's vault
    if rec.get("vault_id") != vault_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Recommendation not found.",
        )

    return MilestoneRecommendationItem(
        id=rec["id"],
        recommendation_type=rec["recommendation_type"],
        title=rec["title"],
        description=rec.get("description"),
        external_url=rec.get("external_url"),
        price_cents=rec.get("price_cents"),
        merchant_name=rec.get("merchant_name"),
        image_url=rec.get("image_url"),
        created_at=rec["created_at"],
    )


# ===================================================================
# Shared helpers
# ===================================================================


def _load_recent_titles(client, vault_id: str, limit: int = 200) -> list[str]:
    """Load titles of recent recommendations for a vault to exclude from new results."""
    try:
        result = (
            client.table("recommendations")
            .select("title")
            .eq("vault_id", vault_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return [row["title"] for row in (result.data or []) if row.get("title")]
    except Exception as exc:
        logger.warning(
            "Failed to load recent titles for vault %s: %s", vault_id, exc,
        )
        return []


def _load_recent_descriptions(client, vault_id: str, limit: int = 200) -> list[str]:
    """Load description snippets of recent recommendations for semantic dedup."""
    try:
        result = (
            client.table("recommendations")
            .select("description")
            .eq("vault_id", vault_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return [
            row["description"][:100]
            for row in (result.data or [])
            if row.get("description")
        ]
    except Exception as exc:
        logger.warning(
            "Failed to load recent descriptions for vault %s: %s", vault_id, exc,
        )
        return []


def _fallback_image_url(candidate: CandidateRecommendation) -> str | None:
    """Return a fallback Unsplash image based on matched interests or vibes."""
    from app.agents.aggregation import _INTEREST_IMAGES, _VIBE_IMAGES

    for interest in candidate.matched_interests:
        url = _INTEREST_IMAGES.get(interest)
        if url:
            return url
    for vibe in candidate.matched_vibes:
        url = _VIBE_IMAGES.get(vibe)
        if url:
            return url
    return None


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

        # Build content_sections for ideas (Step 14.4)
        content_sections_resp = None
        is_idea = getattr(candidate, "is_idea", False)
        if is_idea and getattr(candidate, "content_sections", None):
            from app.models.recommendations import IdeaContentSection
            content_sections_resp = [
                IdeaContentSection(**s) if isinstance(s, dict) else s
                for s in candidate.content_sections
            ]

        # Use candidate image_url, falling back to interest/vibe-based image
        image_url = candidate.image_url or _fallback_image_url(candidate)

        response_items.append(
            RecommendationItemResponse(
                id=db_id,
                recommendation_type=candidate.type,
                title=candidate.title,
                description=candidate.description,
                price_cents=candidate.price_cents,
                currency=candidate.currency,
                price_confidence=candidate.price_confidence,
                external_url=candidate.external_url,
                image_url=image_url,
                merchant_name=candidate.merchant_name,
                source=candidate.source,
                location=location_resp,
                is_idea=is_idea,
                content_sections=content_sections_resp,
                interest_score=candidate.interest_score,
                vibe_score=candidate.vibe_score,
                love_language_score=candidate.love_language_score,
                final_score=candidate.final_score,
                matched_interests=candidate.matched_interests,
                matched_vibes=candidate.matched_vibes,
                matched_love_languages=candidate.matched_love_languages,
                personalization_note=getattr(candidate, "personalization_note", None),
            )
        )
    return response_items


