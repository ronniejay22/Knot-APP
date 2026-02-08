"""
Vault API — Partner Vault CRUD operations.

Handles creation, retrieval, and updates of the Partner Vault,
including interests, milestones, vibes, budgets, and love languages.

Step 3.10: POST /api/v1/vault — Create Partner Vault
"""

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.vault import VaultCreateRequest, VaultCreateResponse

router = APIRouter(prefix="/api/v1/vault", tags=["vault"])


@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=VaultCreateResponse,
)
async def create_vault(
    payload: VaultCreateRequest,
    user_id: str = Depends(get_current_user_id),
) -> VaultCreateResponse:
    """
    Create a complete Partner Vault with all related data.

    Accepts the full onboarding payload and inserts into all relevant
    tables: partner_vaults, partner_interests, partner_milestones,
    partner_vibes, partner_budgets, partner_love_languages.

    Requires authentication. Each user can have only one vault.

    Returns:
        201: Vault created successfully with summary counts.
        401: Missing or invalid authentication token.
        409: User already has a vault.
        422: Validation error in the request payload.
        500: Unexpected database error.
    """
    client = get_service_client()
    vault_id: str | None = None

    try:
        # =============================================================
        # 1. Create the partner vault
        # =============================================================
        vault_data = {
            "user_id": user_id,
            "partner_name": payload.partner_name,
            "relationship_tenure_months": payload.relationship_tenure_months,
            "cohabitation_status": payload.cohabitation_status,
            "location_city": payload.location_city,
            "location_state": payload.location_state,
            "location_country": payload.location_country or "US",
        }
        vault_result = (
            client.table("partner_vaults").insert(vault_data).execute()
        )

        if not vault_result.data:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create vault — no data returned from database.",
            )

        vault_id = vault_result.data[0]["id"]

        # =============================================================
        # 2. Insert interests (5 likes + 5 dislikes)
        # =============================================================
        interest_rows = [
            {
                "vault_id": vault_id,
                "interest_type": "like",
                "interest_category": category,
            }
            for category in payload.interests
        ]
        interest_rows += [
            {
                "vault_id": vault_id,
                "interest_type": "dislike",
                "interest_category": category,
            }
            for category in payload.dislikes
        ]
        client.table("partner_interests").insert(interest_rows).execute()

        # =============================================================
        # 3. Insert milestones
        # =============================================================
        milestone_rows = [
            {
                "vault_id": vault_id,
                "milestone_type": m.milestone_type,
                "milestone_name": m.milestone_name,
                "milestone_date": m.milestone_date,
                "recurrence": m.recurrence,
                # None → DB trigger sets default for birthday/anniversary/holiday.
                # Explicit value used for custom milestones and holiday overrides.
                "budget_tier": m.budget_tier,
            }
            for m in payload.milestones
        ]
        if milestone_rows:
            client.table("partner_milestones").insert(milestone_rows).execute()

        # =============================================================
        # 4. Insert vibes
        # =============================================================
        vibe_rows = [
            {"vault_id": vault_id, "vibe_tag": vibe}
            for vibe in payload.vibes
        ]
        client.table("partner_vibes").insert(vibe_rows).execute()

        # =============================================================
        # 5. Insert budgets
        # =============================================================
        budget_rows = [
            {
                "vault_id": vault_id,
                "occasion_type": b.occasion_type,
                "min_amount": b.min_amount,
                "max_amount": b.max_amount,
                "currency": b.currency,
            }
            for b in payload.budgets
        ]
        client.table("partner_budgets").insert(budget_rows).execute()

        # =============================================================
        # 6. Insert love languages
        # =============================================================
        love_language_rows = [
            {
                "vault_id": vault_id,
                "language": payload.love_languages.primary,
                "priority": 1,
            },
            {
                "vault_id": vault_id,
                "language": payload.love_languages.secondary,
                "priority": 2,
            },
        ]
        client.table("partner_love_languages").insert(love_language_rows).execute()

        # =============================================================
        # Build response
        # =============================================================
        return VaultCreateResponse(
            vault_id=vault_id,
            partner_name=payload.partner_name,
            interests_count=len(payload.interests),
            dislikes_count=len(payload.dislikes),
            milestones_count=len(payload.milestones),
            vibes_count=len(payload.vibes),
            budgets_count=len(payload.budgets),
            love_languages={
                "primary": payload.love_languages.primary,
                "secondary": payload.love_languages.secondary,
            },
        )

    except HTTPException:
        # Re-raise HTTP exceptions as-is (don't wrap them)
        raise

    except Exception as exc:
        error_str = str(exc)

        # Handle UNIQUE constraint violation (user already has a vault)
        if any(
            marker in error_str.lower()
            for marker in ["duplicate", "unique", "23505"]
        ):
            # Clean up partial vault if one was created
            _cleanup_vault(client, vault_id)
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=(
                    "A partner vault already exists for this user. "
                    "Use PUT /api/v1/vault to update."
                ),
            )

        # For any other database error, clean up and report
        _cleanup_vault(client, vault_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create vault: {error_str}",
        )


def _cleanup_vault(client, vault_id: str | None) -> None:
    """
    Delete a partially-created vault to avoid orphaned data.

    CASCADE on partner_vaults automatically removes all child rows
    (interests, milestones, vibes, budgets, love languages).
    """
    if vault_id is None:
        return
    try:
        client.table("partner_vaults").delete().eq("id", vault_id).execute()
    except Exception:
        # Best-effort cleanup — don't mask the original error
        pass
