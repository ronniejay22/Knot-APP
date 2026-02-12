"""
Users API — User account management.

Handles device token registration, data export, and account deletion.

Step 7.4: POST /api/v1/users/device-token — Register APNs device token.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.users import DeviceTokenRequest, DeviceTokenResponse

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
