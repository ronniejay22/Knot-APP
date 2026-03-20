"""
Milestones API — Post-onboarding milestone management.

Provides CRUD endpoints for managing partner milestones after onboarding.
Handles notification rescheduling when milestones are added, updated, or deleted.

- POST /api/v1/milestones — Add a new milestone
- GET /api/v1/milestones — List all milestones with computed days_until
- PUT /api/v1/milestones/{id} — Update a milestone
- DELETE /api/v1/milestones/{id} — Delete a milestone
"""

import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.milestones import (
    MilestoneCreateRequest,
    MilestoneItemResponse,
    MilestoneListResponse,
    MilestoneUpdateRequest,
)
from app.services.notification_scheduler import (
    compute_next_occurrence,
    schedule_milestone_notifications,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/milestones", tags=["milestones"])


# ===================================================================
# Helpers
# ===================================================================

def _get_vault_id(client, user_id: str) -> str:
    """Look up the user's vault ID. Raises 404 if not found."""
    result = (
        client.table("partner_vaults")
        .select("id")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No partner vault found. Complete onboarding first.",
        )
    return result.data[0]["id"]


def _compute_days_until(milestone: dict) -> int | None:
    """Compute days until the next occurrence of a milestone."""
    try:
        ms_date = milestone["milestone_date"]
        if isinstance(ms_date, str):
            ms_date = date.fromisoformat(ms_date)

        next_occ = compute_next_occurrence(
            milestone_date=ms_date,
            milestone_name=milestone["milestone_name"],
            recurrence=milestone["recurrence"],
        )
        if next_occ is None:
            return None
        return (next_occ - date.today()).days
    except Exception:
        return None


def _build_milestone_response(milestone: dict) -> MilestoneItemResponse:
    """Convert a DB row dict to a MilestoneItemResponse."""
    return MilestoneItemResponse(
        id=milestone["id"],
        milestone_type=milestone["milestone_type"],
        milestone_name=milestone["milestone_name"],
        milestone_date=str(milestone["milestone_date"]),
        recurrence=milestone["recurrence"],
        budget_tier=milestone.get("budget_tier"),
        days_until=_compute_days_until(milestone),
        created_at=str(milestone["created_at"]),
    )


# ===================================================================
# GET /api/v1/milestones — List milestones
# ===================================================================

@router.get(
    "",
    status_code=status.HTTP_200_OK,
    response_model=MilestoneListResponse,
)
async def list_milestones(
    user_id: str = Depends(get_current_user_id),
) -> MilestoneListResponse:
    """
    List all milestones for the authenticated user's vault.

    Each milestone includes a computed `days_until` field showing how
    many days remain until the next occurrence.
    """
    client = get_service_client()
    vault_id = _get_vault_id(client, user_id)

    try:
        result = (
            client.table("partner_milestones")
            .select("*")
            .eq("vault_id", vault_id)
            .order("milestone_date", desc=False)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to list milestones for vault %s: %s", vault_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load milestones.",
        )

    items = [_build_milestone_response(m) for m in (result.data or [])]

    # Sort by days_until (None values last)
    items.sort(key=lambda m: m.days_until if m.days_until is not None else 9999)

    return MilestoneListResponse(milestones=items, count=len(items))


# ===================================================================
# POST /api/v1/milestones — Add a milestone
# ===================================================================

@router.post(
    "",
    status_code=status.HTTP_201_CREATED,
    response_model=MilestoneItemResponse,
)
async def create_milestone(
    payload: MilestoneCreateRequest,
    user_id: str = Depends(get_current_user_id),
) -> MilestoneItemResponse:
    """
    Add a new milestone to the authenticated user's vault.

    Automatically schedules 14/7/3-day notifications for the milestone.
    If budget_tier is not provided, defaults based on milestone_type:
    - birthday/anniversary → major_milestone
    - holiday → minor_occasion
    - custom → just_because
    """
    client = get_service_client()
    vault_id = _get_vault_id(client, user_id)

    # Default budget tier based on milestone type
    budget_tier = payload.budget_tier
    if budget_tier is None:
        tier_defaults = {
            "birthday": "major_milestone",
            "anniversary": "major_milestone",
            "holiday": "minor_occasion",
            "custom": "just_because",
        }
        budget_tier = tier_defaults.get(payload.milestone_type, "just_because")

    row = {
        "vault_id": vault_id,
        "milestone_type": payload.milestone_type,
        "milestone_name": payload.milestone_name,
        "milestone_date": payload.milestone_date,
        "recurrence": payload.recurrence,
        "budget_tier": budget_tier,
    }

    try:
        result = client.table("partner_milestones").insert(row).execute()
    except Exception as exc:
        logger.error("Failed to create milestone for vault %s: %s", vault_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create milestone.",
        )

    milestone = result.data[0]

    # Schedule notifications for the new milestone
    try:
        await schedule_milestone_notifications(
            milestone_id=milestone["id"],
            user_id=user_id,
            milestone_date=date.fromisoformat(str(milestone["milestone_date"])),
            milestone_name=milestone["milestone_name"],
            recurrence=milestone["recurrence"],
        )
    except Exception as exc:
        logger.warning(
            "Failed to schedule notifications for new milestone %s: %s",
            milestone["id"][:8], exc,
        )

    return _build_milestone_response(milestone)


# ===================================================================
# PUT /api/v1/milestones/{milestone_id} — Update a milestone
# ===================================================================

@router.put(
    "/{milestone_id}",
    status_code=status.HTTP_200_OK,
    response_model=MilestoneItemResponse,
)
async def update_milestone(
    milestone_id: str,
    payload: MilestoneUpdateRequest,
    user_id: str = Depends(get_current_user_id),
) -> MilestoneItemResponse:
    """
    Update an existing milestone.

    If the date or recurrence changes, pending notifications are deleted
    and new ones are scheduled.
    """
    client = get_service_client()
    vault_id = _get_vault_id(client, user_id)

    # Verify milestone belongs to this vault
    existing = (
        client.table("partner_milestones")
        .select("*")
        .eq("id", milestone_id)
        .eq("vault_id", vault_id)
        .execute()
    )

    if not existing.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Milestone not found.",
        )

    old_milestone = existing.data[0]

    # Build update dict from non-None fields
    update_data = {}
    if payload.milestone_name is not None:
        update_data["milestone_name"] = payload.milestone_name
    if payload.milestone_date is not None:
        update_data["milestone_date"] = payload.milestone_date
    if payload.recurrence is not None:
        update_data["recurrence"] = payload.recurrence
    if payload.budget_tier is not None:
        update_data["budget_tier"] = payload.budget_tier

    if not update_data:
        return _build_milestone_response(old_milestone)

    try:
        result = (
            client.table("partner_milestones")
            .update(update_data)
            .eq("id", milestone_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to update milestone %s: %s", milestone_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update milestone.",
        )

    updated_milestone = result.data[0]

    # Reschedule notifications if date or recurrence changed
    date_changed = payload.milestone_date is not None and payload.milestone_date != str(old_milestone["milestone_date"])
    recurrence_changed = payload.recurrence is not None and payload.recurrence != old_milestone["recurrence"]

    if date_changed or recurrence_changed:
        # Delete pending notifications for this milestone
        try:
            client.table("notification_queue").delete().eq(
                "milestone_id", milestone_id
            ).eq("status", "pending").execute()
        except Exception as exc:
            logger.warning(
                "Failed to delete pending notifications for milestone %s: %s",
                milestone_id[:8], exc,
            )

        # Schedule new notifications
        try:
            await schedule_milestone_notifications(
                milestone_id=milestone_id,
                user_id=user_id,
                milestone_date=date.fromisoformat(str(updated_milestone["milestone_date"])),
                milestone_name=updated_milestone["milestone_name"],
                recurrence=updated_milestone["recurrence"],
            )
        except Exception as exc:
            logger.warning(
                "Failed to reschedule notifications for milestone %s: %s",
                milestone_id[:8], exc,
            )

    return _build_milestone_response(updated_milestone)


# ===================================================================
# DELETE /api/v1/milestones/{milestone_id} — Delete a milestone
# ===================================================================

@router.delete(
    "/{milestone_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_milestone(
    milestone_id: str,
    user_id: str = Depends(get_current_user_id),
) -> None:
    """
    Delete a milestone and its pending notifications.

    The notification_queue entries are deleted via CASCADE.
    """
    client = get_service_client()
    vault_id = _get_vault_id(client, user_id)

    # Verify milestone belongs to this vault
    existing = (
        client.table("partner_milestones")
        .select("id")
        .eq("id", milestone_id)
        .eq("vault_id", vault_id)
        .execute()
    )

    if not existing.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Milestone not found.",
        )

    try:
        client.table("partner_milestones").delete().eq("id", milestone_id).execute()
    except Exception as exc:
        logger.error("Failed to delete milestone %s: %s", milestone_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete milestone.",
        )
