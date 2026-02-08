"""
Hints API — Hint capture and retrieval.

Handles creating, listing, and deleting hints.
Hint embeddings are generated via Vertex AI text-embedding-004 (Step 4.4).

Step 4.2: POST /api/v1/hints — Create hint (text stored, embedding deferred to 4.4)
          GET /api/v1/hints — List hints for the authenticated user
Step 4.6: DELETE /api/v1/hints/{hint_id} — Delete a hint
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.hints import (
    HintCreateRequest,
    HintCreateResponse,
    HintListResponse,
    HintResponse,
)

router = APIRouter(prefix="/api/v1/hints", tags=["hints"])


# ===================================================================
# POST /api/v1/hints — Create Hint (Step 4.2)
# ===================================================================

@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=HintCreateResponse,
)
async def create_hint(
    payload: HintCreateRequest,
    user_id: str = Depends(get_current_user_id),
) -> HintCreateResponse:
    """
    Create a new hint for the authenticated user's partner vault.

    Validates hint_text is not empty and <= 500 characters.
    Looks up the user's vault_id, then inserts into the hints table.

    Embedding generation (Vertex AI text-embedding-004) will be added
    in Step 4.4. For now, hint_embedding is stored as NULL.

    Returns:
        201: Hint created successfully.
        401: Missing or invalid authentication token.
        404: User has no partner vault (must complete onboarding first).
        422: Validation error (empty text, text too long).
        500: Unexpected database error.
    """
    client = get_service_client()

    # --- 1. Look up the user's vault_id ---
    vault_result = (
        client.table("partner_vaults")
        .select("id")
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    vault_id = vault_result.data[0]["id"]

    # --- 2. Insert the hint ---
    hint_data = {
        "vault_id": vault_id,
        "hint_text": payload.hint_text,
        "source": payload.source,
        "is_used": False,
        # hint_embedding: NULL for now — Step 4.4 adds Vertex AI embedding
    }

    try:
        hint_result = (
            client.table("hints")
            .insert(hint_data)
            .execute()
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create hint: {exc}",
        )

    if not hint_result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create hint — no data returned from database.",
        )

    hint = hint_result.data[0]

    return HintCreateResponse(
        id=hint["id"],
        hint_text=hint["hint_text"],
        source=hint["source"],
        is_used=hint["is_used"],
        created_at=hint["created_at"],
    )


# ===================================================================
# GET /api/v1/hints — List Hints (Step 4.2)
# ===================================================================

@router.get(
    "",
    status_code=status.HTTP_200_OK,
    response_model=HintListResponse,
)
async def list_hints(
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> HintListResponse:
    """
    List all hints for the authenticated user's partner vault.

    Returns hints in reverse chronological order (newest first).
    Supports pagination via limit/offset query parameters.

    Returns:
        200: List of hints with total count.
        401: Missing or invalid authentication token.
        404: User has no partner vault.
    """
    client = get_service_client()

    # --- 1. Look up the user's vault_id ---
    vault_result = (
        client.table("partner_vaults")
        .select("id")
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )

    vault_id = vault_result.data[0]["id"]

    # --- 2. Fetch hints (newest first) ---
    # Select all columns except hint_embedding (large vector, not needed for display)
    hints_result = (
        client.table("hints")
        .select("id, hint_text, source, is_used, created_at")
        .eq("vault_id", vault_id)
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )

    # --- 3. Get total count ---
    count_result = (
        client.table("hints")
        .select("id", count="exact")
        .eq("vault_id", vault_id)
        .execute()
    )

    total = count_result.count if count_result.count is not None else len(hints_result.data or [])

    hints = [
        HintResponse(
            id=row["id"],
            hint_text=row["hint_text"],
            source=row["source"],
            is_used=row["is_used"],
            created_at=row["created_at"],
        )
        for row in (hints_result.data or [])
    ]

    return HintListResponse(hints=hints, total=total)
