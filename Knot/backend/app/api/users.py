"""
Users API — User account management.

Handles device token registration and account deletion.

Step 7.4: POST /api/v1/users/device-token — Register APNs device token.
Step 11.2: DELETE /api/v1/users/me — Permanently delete account and all data.
"""

import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.users import (
    AccountDeleteResponse,
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
