"""
Users API — User account management.

Handles device token registration, account deletion, and data export.

Step 7.4: POST /api/v1/users/device-token — Register APNs device token.
Step 11.2: DELETE /api/v1/users/me — Permanently delete account and all data.
Step 11.3: GET /api/v1/users/me/export — Export all user data as JSON.
"""

import logging
from datetime import datetime, timezone

import httpx
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.users import (
    AccountDeleteResponse,
    DataExportResponse,
    DeviceTokenRequest,
    DeviceTokenResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.post(
    "/device-token",
    status_code=status.HTTP_200_OK,
    response_model=DeviceTokenResponse,
)
async def register_device_token(
    payload: DeviceTokenRequest,
    user_id: str = Depends(get_current_user_id),
) -> DeviceTokenResponse:
    """
    Register or update the device token for push notifications.

    Called by the iOS app on every launch after the user grants
    notification permissions. The token is stored in the users table
    and used by Step 7.5 to deliver APNs push notifications.

    The endpoint uses the service role client to update the users
    table directly, bypassing RLS (the authenticated user_id from
    the JWT identifies which row to update).

    Returns:
        200: Token registered/updated successfully.
        401: Missing or invalid authentication token.
        404: User not found.
        422: Invalid payload (empty token, bad platform).
        500: Database error.
    """
    client = get_service_client()

    # Check if user already has a device token stored
    try:
        existing = (
            client.table("users")
            .select("device_token")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Database error looking up user %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to look up user: {exc}",
        )

    if not existing.data:
        logger.error("User %s not found in users table", user_id[:8])
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    previous_token = existing.data[0].get("device_token")
    result_status = "updated" if previous_token else "registered"

    # Upsert the device token
    try:
        client.table("users").update({
            "device_token": payload.device_token,
            "device_platform": payload.platform,
        }).eq("id", user_id).execute()
    except Exception as exc:
        logger.error(
            "Failed to store device token for user %s: %s", user_id[:8], exc
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to store device token: {exc}",
        )

    logger.info(
        "Device token %s for user %s (platform=%s, token=%s...)",
        result_status,
        user_id[:8],
        payload.platform,
        payload.device_token[:16],
    )

    return DeviceTokenResponse(
        status=result_status,
        device_token=payload.device_token,
        platform=payload.platform,
    )


@router.delete(
    "/me",
    status_code=status.HTTP_200_OK,
    response_model=AccountDeleteResponse,
)
async def delete_account(
    user_id: str = Depends(get_current_user_id),
) -> AccountDeleteResponse:
    """
    Permanently delete the authenticated user's account and all associated data.

    Deletes the auth.users record via Supabase Admin API, which triggers
    CASCADE deletion through all public tables (users, partner_vaults,
    hints, recommendations, notification_queue, user_preferences_weights,
    and all child tables).

    The iOS client enforces re-authentication (Apple Sign-In) before
    calling this endpoint. The backend requires a valid JWT.

    Returns:
        200: Account deleted successfully.
        401: Missing or invalid authentication token.
        404: User not found.
        500: Deletion failed (database or Admin API error).
    """
    client = get_service_client()

    # 1. Verify user exists in public.users
    try:
        existing = (
            client.table("users")
            .select("id")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Database error looking up user %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to look up user: {exc}",
        )

    if not existing.data:
        logger.error("User %s not found in users table", user_id[:8])
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    # 2. Delete the auth user via Supabase Admin API.
    #    CASCADE delete removes public.users and all child tables.
    try:
        async with httpx.AsyncClient() as http_client:
            resp = await http_client.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
                headers={
                    "apikey": SUPABASE_SERVICE_ROLE_KEY,
                    "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
                },
                timeout=30.0,
            )
    except httpx.RequestError as exc:
        logger.error(
            "Network error deleting auth user %s: %s", user_id[:8], exc
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to connect to authentication service.",
        )

    if resp.status_code != 200:
        logger.error(
            "Supabase Admin API returned %d for user %s deletion: %s",
            resp.status_code,
            user_id[:8],
            resp.text,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete authentication record (status {resp.status_code}).",
        )

    logger.info(
        "Account deleted for user %s — all data removed via CASCADE",
        user_id[:8],
    )

    return AccountDeleteResponse()


# ===================================================================
# GET /api/v1/users/me/export (Step 11.3)
# ===================================================================


@router.get(
    "/me/export",
    status_code=status.HTTP_200_OK,
    response_model=DataExportResponse,
)
async def export_user_data(
    user_id: str = Depends(get_current_user_id),
) -> DataExportResponse:
    """
    Export all user data as a JSON response.

    Compiles data from all tables the user owns: account info,
    partner vault (with interests, vibes, budgets, love languages),
    milestones, hints (excluding embeddings), recommendations,
    feedback, and notification history.

    Returns 200 even if the user has no vault (export still includes
    account info with empty collections).

    Returns:
        200: Full data export.
        401: Missing or invalid authentication token.
        500: Database error during export.
    """
    client = get_service_client()

    # --- 1. Fetch user account info ---
    try:
        user_result = (
            client.table("users")
            .select("id, email, created_at")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Export: failed to fetch user %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to export user data.",
        )

    user_data = user_result.data[0] if user_result.data else {
        "id": user_id, "email": None, "created_at": None,
    }

    # --- 2. Fetch partner vault (if exists) ---
    try:
        vault_result = (
            client.table("partner_vaults")
            .select("*")
            .eq("user_id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Export: failed to fetch vault for %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to export user data.",
        )

    vault_data = None
    milestones_data: list[dict] = []
    hints_data: list[dict] = []
    recommendations_data: list[dict] = []

    if vault_result.data:
        vault = vault_result.data[0]
        vault_id = vault["id"]

        # --- 3. Fetch all vault child tables ---
        try:
            interests_result = (
                client.table("partner_interests")
                .select("interest_type, interest_category, created_at")
                .eq("vault_id", vault_id)
                .execute()
            )
            milestones_result = (
                client.table("partner_milestones")
                .select("id, milestone_type, milestone_name, milestone_date, recurrence, budget_tier, created_at")
                .eq("vault_id", vault_id)
                .execute()
            )
            vibes_result = (
                client.table("partner_vibes")
                .select("vibe_tag, created_at")
                .eq("vault_id", vault_id)
                .execute()
            )
            budgets_result = (
                client.table("partner_budgets")
                .select("occasion_type, min_amount, max_amount, currency, created_at")
                .eq("vault_id", vault_id)
                .execute()
            )
            love_languages_result = (
                client.table("partner_love_languages")
                .select("language, priority, created_at")
                .eq("vault_id", vault_id)
                .execute()
            )
            hints_result = (
                client.table("hints")
                .select("id, hint_text, source, is_used, created_at")
                .eq("vault_id", vault_id)
                .order("created_at", desc=True)
                .execute()
            )
            rec_result = (
                client.table("recommendations")
                .select("id, milestone_id, recommendation_type, title, description, external_url, price_cents, merchant_name, image_url, created_at")
                .eq("vault_id", vault_id)
                .order("created_at", desc=True)
                .execute()
            )
        except Exception as exc:
            logger.error("Export: failed to fetch vault data for %s: %s", user_id[:8], exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to export user data.",
            )

        # Build vault section
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

        vault_data = {
            "partner_name": vault["partner_name"],
            "relationship_tenure_months": vault.get("relationship_tenure_months"),
            "cohabitation_status": vault.get("cohabitation_status"),
            "location_city": vault.get("location_city"),
            "location_state": vault.get("location_state"),
            "location_country": vault.get("location_country"),
            "interests": likes,
            "dislikes": dislikes,
            "vibes": [row["vibe_tag"] for row in (vibes_result.data or [])],
            "budgets": budgets_result.data or [],
            "love_languages": love_languages_result.data or [],
            "created_at": vault.get("created_at"),
        }

        milestones_data = milestones_result.data or []
        hints_data = hints_result.data or []
        recommendations_data = rec_result.data or []

    # --- 4. Fetch user-level data (not vault-scoped) ---
    try:
        feedback_result = (
            client.table("recommendation_feedback")
            .select("id, recommendation_id, action, rating, feedback_text, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        notification_result = (
            client.table("notification_queue")
            .select("id, milestone_id, scheduled_for, days_before, status, sent_at, created_at")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
    except Exception as exc:
        logger.error("Export: failed to fetch feedback/notifications for %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to export user data.",
        )

    logger.info(
        "Data export completed for user %s — vault=%s, hints=%d, recs=%d, feedback=%d, notifications=%d",
        user_id[:8],
        "yes" if vault_data else "no",
        len(hints_data),
        len(recommendations_data),
        len(feedback_result.data or []),
        len(notification_result.data or []),
    )

    return DataExportResponse(
        exported_at=datetime.now(timezone.utc).isoformat(),
        user=user_data,
        partner_vault=vault_data,
        milestones=milestones_data,
        hints=hints_data,
        recommendations=recommendations_data,
        feedback=feedback_result.data or [],
        notifications=notification_result.data or [],
    )
