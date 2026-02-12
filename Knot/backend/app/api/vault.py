"""
Vault API — Partner Vault CRUD operations.

Handles creation, retrieval, and updates of the Partner Vault,
including interests, milestones, vibes, budgets, and love languages.

Step 3.10: POST /api/v1/vault — Create Partner Vault
Step 3.12: GET /api/v1/vault — Retrieve Partner Vault
           PUT /api/v1/vault — Update Partner Vault
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.vault import (
    BudgetResponse,
    LoveLanguageResponse,
    MilestoneResponse,
    VaultCreateRequest,
    VaultCreateResponse,
    VaultGetResponse,
    VaultUpdateResponse,
)

from app.services.notification_scheduler import schedule_notifications_for_milestones

logger = logging.getLogger(__name__)

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
        milestone_result = None
        if milestone_rows:
            milestone_result = (
                client.table("partner_milestones")
                .insert(milestone_rows)
                .execute()
            )

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
        # 7. Schedule milestone notifications (best-effort)
        # =============================================================
        if milestone_result and milestone_result.data:
            try:
                await schedule_notifications_for_milestones(
                    milestones=milestone_result.data,
                    user_id=user_id,
                )
            except Exception as exc:
                logger.warning(
                    f"Failed to schedule notifications for vault "
                    f"{vault_id}: {exc}",
                    exc_info=True,
                )

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


# ===================================================================
# GET /api/v1/vault — Retrieve Partner Vault (Step 3.12)
# ===================================================================

@router.get(
    "",
    status_code=status.HTTP_200_OK,
    response_model=VaultGetResponse,
)
async def get_vault(
    user_id: str = Depends(get_current_user_id),
) -> VaultGetResponse:
    """
    Retrieve the authenticated user's Partner Vault with all related data.

    Loads data from all 6 tables: partner_vaults, partner_interests,
    partner_milestones, partner_vibes, partner_budgets, partner_love_languages.

    Returns:
        200: Full vault data.
        401: Missing or invalid authentication token.
        404: No vault exists for this user.
    """
    client = get_service_client()

    # --- 1. Fetch the vault ---
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

    # --- 2. Fetch all related data in parallel-ish (sequential for PostgREST) ---
    interests_result = (
        client.table("partner_interests")
        .select("*")
        .eq("vault_id", vault_id)
        .execute()
    )

    milestones_result = (
        client.table("partner_milestones")
        .select("*")
        .eq("vault_id", vault_id)
        .execute()
    )

    vibes_result = (
        client.table("partner_vibes")
        .select("*")
        .eq("vault_id", vault_id)
        .execute()
    )

    budgets_result = (
        client.table("partner_budgets")
        .select("*")
        .eq("vault_id", vault_id)
        .execute()
    )

    love_languages_result = (
        client.table("partner_love_languages")
        .select("*")
        .eq("vault_id", vault_id)
        .execute()
    )

    # --- 3. Build response ---
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

    milestones = [
        MilestoneResponse(
            id=row["id"],
            milestone_type=row["milestone_type"],
            milestone_name=row["milestone_name"],
            milestone_date=row["milestone_date"],
            recurrence=row["recurrence"],
            budget_tier=row.get("budget_tier"),
        )
        for row in (milestones_result.data or [])
    ]

    vibes = [
        row["vibe_tag"]
        for row in (vibes_result.data or [])
    ]

    budgets = [
        BudgetResponse(
            id=row["id"],
            occasion_type=row["occasion_type"],
            min_amount=row["min_amount"],
            max_amount=row["max_amount"],
            currency=row["currency"],
        )
        for row in (budgets_result.data or [])
    ]

    love_languages = [
        LoveLanguageResponse(
            language=row["language"],
            priority=row["priority"],
        )
        for row in (love_languages_result.data or [])
    ]

    return VaultGetResponse(
        vault_id=vault_id,
        partner_name=vault["partner_name"],
        relationship_tenure_months=vault.get("relationship_tenure_months"),
        cohabitation_status=vault.get("cohabitation_status"),
        location_city=vault.get("location_city"),
        location_state=vault.get("location_state"),
        location_country=vault.get("location_country"),
        interests=likes,
        dislikes=dislikes,
        milestones=milestones,
        vibes=vibes,
        budgets=budgets,
        love_languages=love_languages,
    )


# ===================================================================
# PUT /api/v1/vault — Update Partner Vault (Step 3.12)
# ===================================================================

@router.put(
    "",
    status_code=status.HTTP_200_OK,
    response_model=VaultUpdateResponse,
)
async def update_vault(
    payload: VaultCreateRequest,
    user_id: str = Depends(get_current_user_id),
) -> VaultUpdateResponse:
    """
    Update the authenticated user's Partner Vault with new data.

    Uses a "replace all" strategy: updates the vault row and replaces
    all child data (interests, milestones, vibes, budgets, love languages)
    by deleting existing rows and inserting new ones.

    Accepts the same payload schema as POST /api/v1/vault.

    Returns:
        200: Vault updated successfully with summary counts.
        401: Missing or invalid authentication token.
        404: No vault exists for this user.
        422: Validation error in the request payload.
        500: Unexpected database error.
    """
    client = get_service_client()

    # --- 1. Verify vault exists ---
    vault_result = (
        client.table("partner_vaults")
        .select("id")
        .eq("user_id", user_id)
        .execute()
    )

    if not vault_result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Create one first with POST /api/v1/vault.",
        )

    vault_id = vault_result.data[0]["id"]

    # =================================================================
    # 2. Snapshot existing data before any mutations.
    #    If any step fails, we restore from this snapshot.
    # =================================================================
    snapshot = _snapshot_vault_children(client, vault_id)
    original_vault = (
        client.table("partner_vaults")
        .select("partner_name, relationship_tenure_months, cohabitation_status, "
                "location_city, location_state, location_country")
        .eq("id", vault_id)
        .execute()
    )
    original_vault_data = original_vault.data[0] if original_vault.data else None

    try:
        # =============================================================
        # 3. Update the partner vault row
        # =============================================================
        vault_update = {
            "partner_name": payload.partner_name,
            "relationship_tenure_months": payload.relationship_tenure_months,
            "cohabitation_status": payload.cohabitation_status,
            "location_city": payload.location_city,
            "location_state": payload.location_state,
            "location_country": payload.location_country or "US",
        }
        client.table("partner_vaults").update(vault_update).eq("id", vault_id).execute()

        # =============================================================
        # 4. Replace interests (delete old, insert new)
        # =============================================================
        client.table("partner_interests").delete().eq("vault_id", vault_id).execute()

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
        # 5. Replace milestones (delete old, insert new)
        # =============================================================
        client.table("partner_milestones").delete().eq("vault_id", vault_id).execute()

        milestone_rows = [
            {
                "vault_id": vault_id,
                "milestone_type": m.milestone_type,
                "milestone_name": m.milestone_name,
                "milestone_date": m.milestone_date,
                "recurrence": m.recurrence,
                "budget_tier": m.budget_tier,
            }
            for m in payload.milestones
        ]
        milestone_result = None
        if milestone_rows:
            milestone_result = (
                client.table("partner_milestones")
                .insert(milestone_rows)
                .execute()
            )

        # =============================================================
        # 6. Replace vibes (delete old, insert new)
        # =============================================================
        client.table("partner_vibes").delete().eq("vault_id", vault_id).execute()

        vibe_rows = [
            {"vault_id": vault_id, "vibe_tag": vibe}
            for vibe in payload.vibes
        ]
        client.table("partner_vibes").insert(vibe_rows).execute()

        # =============================================================
        # 7. Replace budgets (delete old, insert new)
        # =============================================================
        client.table("partner_budgets").delete().eq("vault_id", vault_id).execute()

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
        # 8. Replace love languages (delete old, insert new)
        # =============================================================
        client.table("partner_love_languages").delete().eq("vault_id", vault_id).execute()

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
        # 9. Schedule milestone notifications (best-effort)
        # =============================================================
        # Old notification_queue entries were automatically removed by
        # CASCADE when partner_milestones rows were deleted above.
        if milestone_result and milestone_result.data:
            try:
                await schedule_notifications_for_milestones(
                    milestones=milestone_result.data,
                    user_id=user_id,
                )
            except Exception as exc:
                logger.warning(
                    f"Failed to schedule notifications for vault "
                    f"{vault_id}: {exc}",
                    exc_info=True,
                )

        # =============================================================
        # Build response
        # =============================================================
        return VaultUpdateResponse(
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
        raise

    except Exception as exc:
        error_str = str(exc)
        # Attempt to restore the vault to its pre-update state
        _restore_vault_from_snapshot(
            client, vault_id, snapshot, original_vault_data,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update vault: {error_str}",
        )


def _snapshot_vault_children(client, vault_id: str) -> dict:
    """
    Capture a snapshot of all child table rows for a vault.

    Called before any mutations in update_vault() so the data can be
    restored if a subsequent insert fails after a delete succeeded.

    Returns a dict keyed by table name, each containing the list of rows
    with only the columns needed for re-insertion (no id/created_at).
    """
    interests = (
        client.table("partner_interests")
        .select("vault_id, interest_type, interest_category")
        .eq("vault_id", vault_id)
        .execute()
    )
    milestones = (
        client.table("partner_milestones")
        .select("vault_id, milestone_type, milestone_name, "
                "milestone_date, recurrence, budget_tier")
        .eq("vault_id", vault_id)
        .execute()
    )
    vibes = (
        client.table("partner_vibes")
        .select("vault_id, vibe_tag")
        .eq("vault_id", vault_id)
        .execute()
    )
    budgets = (
        client.table("partner_budgets")
        .select("vault_id, occasion_type, min_amount, max_amount, currency")
        .eq("vault_id", vault_id)
        .execute()
    )
    love_languages = (
        client.table("partner_love_languages")
        .select("vault_id, language, priority")
        .eq("vault_id", vault_id)
        .execute()
    )

    return {
        "partner_interests": interests.data or [],
        "partner_milestones": milestones.data or [],
        "partner_vibes": vibes.data or [],
        "partner_budgets": budgets.data or [],
        "partner_love_languages": love_languages.data or [],
    }


def _restore_vault_from_snapshot(
    client,
    vault_id: str,
    snapshot: dict,
    original_vault_data: dict | None,
) -> None:
    """
    Best-effort restore of vault data from a pre-update snapshot.

    Called when update_vault() fails partway through. Deletes any
    partially-written new data and re-inserts the original rows.

    If the restore itself fails, the error is suppressed to avoid
    masking the original exception. The vault may be left in an
    inconsistent state — this is logged for monitoring.
    """
    try:
        # Restore the vault row to its original values
        if original_vault_data:
            client.table("partner_vaults").update(
                original_vault_data
            ).eq("id", vault_id).execute()

        # Wipe any partial new data and re-insert originals
        for table_name, rows in snapshot.items():
            client.table(table_name).delete().eq(
                "vault_id", vault_id
            ).execute()
            if rows:
                client.table(table_name).insert(rows).execute()

    except Exception:
        # Best-effort — don't mask the original error.
        # In production, send this to an error monitoring service.
        import logging
        logging.getLogger("knot.vault").error(
            f"CRITICAL: Failed to restore vault {vault_id} from snapshot. "
            "Vault may be in an inconsistent state.",
            exc_info=True,
        )
