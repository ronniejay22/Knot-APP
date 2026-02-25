"""
Ideas API — Knot Originals AI-generated idea endpoints.

Handles generating, listing, and fetching personalized ideas
that live entirely in-app with no external links.

Step 14.4: Create Ideas API Endpoints
Step 14.11: Add background generation webhook for QStash triggers
"""

import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.recommendations import (
    IdeaContentSection,
    IdeaGenerateRequest,
    IdeaGenerateResponse,
    IdeaItemResponse,
    IdeaListResponse,
)
from app.services.idea_generation import generate_ideas
from app.services.vault_loader import load_vault_data

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/ideas", tags=["ideas"])


# ===================================================================
# Shared helper: load recent hints for idea generation context
# ===================================================================

async def _load_recent_hints(vault_id: str, max_count: int = 10):
    """
    Load recent hints for the vault as context for idea generation.

    Uses chronological ordering (most recent first) rather than
    semantic search, since idea generation benefits from broad context.
    Returns RelevantHint-compatible dicts.
    """
    from app.agents.state import RelevantHint

    client = get_service_client()
    try:
        response = (
            client.table("hints")
            .select("id, hint_text, source, is_used, created_at")
            .eq("vault_id", vault_id)
            .order("created_at", desc=True)
            .limit(max_count)
            .execute()
        )
        if not response.data:
            return []
        return [
            RelevantHint(
                id=str(row["id"]),
                hint_text=row["hint_text"],
                similarity_score=0.0,
                source=row.get("source", "text_input"),
                is_used=row.get("is_used", False),
                created_at=row.get("created_at"),
            )
            for row in response.data
        ]
    except Exception as exc:
        logger.warning("Failed to load hints for idea generation: %s", exc)
        return []


# ===================================================================
# Shared helper: convert DB row to IdeaItemResponse
# ===================================================================

def _row_to_idea_response(row: dict) -> IdeaItemResponse:
    """Convert a database recommendation row (with is_idea=True) to IdeaItemResponse."""
    content_sections_raw = row.get("content_sections") or []

    # Parse content_sections — may be a JSON string or already a list
    if isinstance(content_sections_raw, str):
        try:
            content_sections_raw = json.loads(content_sections_raw)
        except json.JSONDecodeError:
            content_sections_raw = []

    content_sections = [
        IdeaContentSection(**section)
        for section in content_sections_raw
        if isinstance(section, dict) and "type" in section and "heading" in section
    ]

    return IdeaItemResponse(
        id=row["id"],
        title=row["title"],
        description=row.get("description"),
        recommendation_type="idea",
        content_sections=content_sections,
        matched_interests=[],
        matched_vibes=[],
        matched_love_languages=[],
        created_at=row["created_at"],
    )


# ===================================================================
# POST /api/v1/ideas/generate — Generate Knot Original Ideas
# ===================================================================

@router.post(
    "/generate",
    status_code=status.HTTP_200_OK,
    response_model=IdeaGenerateResponse,
)
async def generate_knot_ideas(
    payload: IdeaGenerateRequest,
    user_id: str = Depends(get_current_user_id),
) -> IdeaGenerateResponse:
    """
    Generate personalized Knot Original ideas.

    Uses the partner's vault data, captured hints, and occasion context
    to generate rich, structured idea content via Claude. Ideas are
    stored in the recommendations table with is_idea=True.

    Returns:
        200: Generated ideas with content sections.
        401: Missing or invalid authentication token.
        404: No vault exists for this user.
        500: Generation failed.
    """
    # 1. Load vault data
    try:
        vault_data, vault_id = await load_vault_data(user_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    # 2. Load recent hints for context
    hints = await _load_recent_hints(vault_id)

    # 3. Generate ideas via Claude
    try:
        raw_ideas = await generate_ideas(
            vault_data=vault_data,
            hints=hints,
            occasion_type=payload.occasion_type,
            count=payload.count,
            category=payload.category,
        )
    except Exception as exc:
        logger.error(
            "Idea generation failed for vault %s: %s",
            vault_id, exc, exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to generate ideas right now. Please try again.",
        )

    if not raw_ideas:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to generate ideas right now. Please try again.",
        )

    # 4. Store ideas in the recommendations table
    client = get_service_client()
    rec_rows = []
    for idea in raw_ideas:
        rec_rows.append({
            "vault_id": vault_id,
            "recommendation_type": "idea",
            "title": idea["title"],
            "description": idea.get("description"),
            "external_url": None,
            "price_cents": None,
            "merchant_name": None,
            "image_url": None,
            "is_idea": True,
            "content_sections": json.dumps(idea["content_sections"]),
        })

    try:
        db_result = client.table("recommendations").insert(rec_rows).execute()
    except Exception as exc:
        logger.error(
            "Failed to store ideas for vault %s: %s", vault_id, exc,
        )
        db_result = None

    # 5. Build response
    response_ideas = []
    for i, idea in enumerate(raw_ideas):
        db_id = idea["id"]
        if db_result and db_result.data and i < len(db_result.data):
            db_id = db_result.data[i]["id"]

        response_ideas.append(
            IdeaItemResponse(
                id=db_id,
                title=idea["title"],
                description=idea.get("description"),
                recommendation_type="idea",
                content_sections=[
                    IdeaContentSection(**s)
                    for s in idea["content_sections"]
                ],
                matched_interests=idea.get("matched_interests", []),
                matched_vibes=idea.get("matched_vibes", []),
                matched_love_languages=idea.get("matched_love_languages", []),
                created_at=db_result.data[i]["created_at"] if db_result and db_result.data and i < len(db_result.data) else "",
            )
        )

    return IdeaGenerateResponse(
        ideas=response_ideas,
        count=len(response_ideas),
    )


# ===================================================================
# GET /api/v1/ideas — List User's Ideas (Paginated)
# ===================================================================

@router.get(
    "/",
    status_code=status.HTTP_200_OK,
    response_model=IdeaListResponse,
)
async def list_ideas(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user_id: str = Depends(get_current_user_id),
) -> IdeaListResponse:
    """
    List the user's Knot Original ideas, most recent first.

    Returns:
        200: Paginated list of ideas.
        401: Missing or invalid authentication token.
        404: No vault exists for this user.
    """
    client = get_service_client()

    # 1. Get vault_id
    try:
        vault_result = (
            client.table("partner_vaults")
            .select("id")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to look up vault: %s", exc)
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

    # 2. Fetch ideas (is_idea=True recommendations)
    try:
        ideas_result = (
            client.table("recommendations")
            .select("*", count="exact")
            .eq("vault_id", vault_id)
            .eq("is_idea", True)
            .order("created_at", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to load ideas for vault %s: %s", vault_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load ideas.",
        )

    items = [_row_to_idea_response(r) for r in (ideas_result.data or [])]
    total = ideas_result.count if ideas_result.count is not None else len(items)

    return IdeaListResponse(
        ideas=items,
        count=len(items),
        total=total,
    )


# ===================================================================
# GET /api/v1/ideas/{idea_id} — Get Single Idea
# ===================================================================

@router.get(
    "/{idea_id}",
    status_code=status.HTTP_200_OK,
    response_model=IdeaItemResponse,
)
async def get_idea(
    idea_id: str,
    user_id: str = Depends(get_current_user_id),
) -> IdeaItemResponse:
    """
    Fetch a single Knot Original idea by its database ID.

    Returns:
        200: The idea with full content sections.
        401: Missing or invalid authentication token.
        404: Idea not found or not owned by this user.
    """
    client = get_service_client()

    # 1. Get vault_id
    try:
        vault_result = (
            client.table("partner_vaults")
            .select("id")
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to look up vault: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to look up vault.",
        )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found.",
        )

    vault_id = vault_result.data[0]["id"]

    # 2. Fetch the idea
    try:
        rec_result = (
            client.table("recommendations")
            .select("*")
            .eq("id", idea_id)
            .eq("is_idea", True)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to fetch idea %s: %s", idea_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load idea.",
        )

    if not rec_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idea not found.",
        )

    row = rec_result.data[0]

    # 3. Verify ownership
    if row.get("vault_id") != vault_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Idea not found.",
        )

    return _row_to_idea_response(row)


# ===================================================================
# POST /api/v1/ideas/generate-background — QStash Webhook (Step 14.11)
# ===================================================================

@router.post(
    "/generate-background",
    status_code=status.HTTP_200_OK,
    include_in_schema=False,
)
async def generate_ideas_background(
    request: Request,
) -> dict:
    """
    QStash webhook endpoint for background idea generation.

    Triggered automatically after a new hint is created (with a 30-second
    delay and daily deduplication). Generates 3 ideas for the user and
    stores them in the database.

    The endpoint verifies the QStash signature before processing.
    """
    from app.services.qstash import verify_qstash_signature
    from app.core.config import is_qstash_configured

    if not is_qstash_configured():
        logger.warning("QStash not configured — rejecting background generation")
        return {"status": "skipped", "reason": "qstash_not_configured"}

    # Verify QStash signature
    body = await request.body()
    signature = request.headers.get("upstash-signature", "")
    destination_url = str(request.url)

    try:
        verify_qstash_signature(signature, body, destination_url)
    except ValueError as exc:
        logger.warning("QStash signature verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid QStash signature.",
        )

    # Parse the payload
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid JSON payload.",
        )

    user_id = payload.get("user_id")
    vault_id = payload.get("vault_id")

    if not user_id or not vault_id:
        logger.warning("Background idea generation: missing user_id or vault_id")
        return {"status": "skipped", "reason": "missing_ids"}

    # Load vault data
    try:
        vault_data, _ = await load_vault_data(user_id)
    except ValueError:
        logger.warning("Background idea generation: no vault for user %s", user_id[:8])
        return {"status": "skipped", "reason": "no_vault"}

    # Load recent hints
    hints = await _load_recent_hints(vault_id)

    # Generate ideas
    try:
        raw_ideas = await generate_ideas(
            vault_data=vault_data,
            hints=hints,
            occasion_type="just_because",
            count=3,
        )
    except Exception as exc:
        logger.error(
            "Background idea generation failed for vault %s: %s",
            vault_id, exc, exc_info=True,
        )
        return {"status": "error", "reason": str(exc)}

    if not raw_ideas:
        return {"status": "completed", "ideas_generated": 0}

    # Store ideas
    client = get_service_client()
    rec_rows = []
    for idea in raw_ideas:
        rec_rows.append({
            "vault_id": vault_id,
            "recommendation_type": "idea",
            "title": idea["title"],
            "description": idea.get("description"),
            "external_url": None,
            "price_cents": None,
            "merchant_name": None,
            "image_url": None,
            "is_idea": True,
            "content_sections": json.dumps(idea["content_sections"]),
        })

    try:
        client.table("recommendations").insert(rec_rows).execute()
    except Exception as exc:
        logger.error("Failed to store background ideas: %s", exc)
        return {"status": "error", "reason": f"db_insert_failed: {exc}"}

    logger.info(
        "Background idea generation complete: %d ideas for vault %s",
        len(raw_ideas), vault_id,
    )

    return {"status": "completed", "ideas_generated": len(raw_ideas)}
