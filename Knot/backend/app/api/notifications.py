"""
Notifications API — QStash webhook endpoint for processing scheduled notifications.

Handles incoming webhook calls from Upstash QStash. Each call represents
a scheduled notification that needs to be processed (e.g., generate
recommendations and send a push notification for an upcoming milestone).

Step 7.1: Set up QStash scheduler — webhook endpoint with signature verification.
"""

import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Header, Request, status

from app.db.supabase_client import get_service_client
from app.models.notifications import (
    NotificationProcessRequest,
    NotificationProcessResponse,
)
from app.services.qstash import verify_qstash_signature

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])


# ===================================================================
# POST /api/v1/notifications/process — QStash Webhook (Step 7.1)
# ===================================================================

@router.post(
    "/process",
    status_code=status.HTTP_200_OK,
    response_model=NotificationProcessResponse,
)
async def process_notification(
    request: Request,
    upstash_signature: str | None = Header(None, alias="Upstash-Signature"),
) -> NotificationProcessResponse:
    """
    Process a scheduled notification delivered by QStash.

    This endpoint is called by QStash when a scheduled notification is due.
    It verifies the QStash signature, validates the payload, and updates
    the notification_queue entry.

    Processing steps:
    1. Verify the Upstash-Signature header (JWT from QStash)
    2. Parse the JSON payload (notification_id, user_id, milestone_id, days_before)
    3. Look up the notification_queue entry and verify it is still 'pending'
    4. Mark the notification as 'sent' (actual push notification in Step 7.5)
    5. Return processing result

    Returns:
        200: Notification processed successfully.
        401: Invalid or missing QStash signature.
        404: Notification not found or already processed.
        422: Invalid payload format.
        500: Unexpected processing error.
    """
    # --- 1. Read raw body for signature verification ---
    body = await request.body()

    # --- 2. Verify QStash signature ---
    # Build the full URL that QStash was configured to call
    request_url = str(request.url)

    try:
        verify_qstash_signature(
            signature=upstash_signature or "",
            body=body,
            url=request_url,
        )
    except ValueError as exc:
        logger.warning(f"QStash signature verification failed: {exc}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid QStash signature: {exc}",
        )

    # --- 3. Parse the payload ---
    try:
        payload_data = json.loads(body)
        payload = NotificationProcessRequest(**payload_data)
    except Exception as exc:
        logger.error(f"Failed to parse notification payload: {exc}")
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Invalid notification payload: {exc}",
        )

    logger.info(
        f"Processing notification: id={payload.notification_id}, "
        f"user={payload.user_id[:8]}..., milestone={payload.milestone_id[:8]}..., "
        f"days_before={payload.days_before}"
    )

    # --- 4. Look up the notification_queue entry ---
    client = get_service_client()

    try:
        notif_result = (
            client.table("notification_queue")
            .select("*")
            .eq("id", payload.notification_id)
            .execute()
        )
    except Exception as exc:
        logger.error(f"Database error looking up notification: {exc}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to look up notification: {exc}",
        )

    if not notif_result.data:
        logger.warning(
            f"Notification {payload.notification_id} not found in database"
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found.",
        )

    notification = notif_result.data[0]

    # --- 5. Check if already processed ---
    if notification["status"] != "pending":
        logger.info(
            f"Notification {payload.notification_id} already has "
            f"status='{notification['status']}' — skipping"
        )
        return NotificationProcessResponse(
            status="skipped",
            notification_id=payload.notification_id,
            message=f"Notification already {notification['status']}.",
        )

    # --- 6. Update status to 'sent' ---
    # In Step 7.3/7.5, this will also generate recommendations
    # and send a push notification via APNs before marking as sent.
    try:
        client.table("notification_queue").update({
            "status": "sent",
            "sent_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", payload.notification_id).execute()
    except Exception as exc:
        logger.error(
            f"Failed to update notification {payload.notification_id}: {exc}"
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update notification status: {exc}",
        )

    logger.info(
        f"Notification {payload.notification_id} processed successfully "
        f"(user={payload.user_id[:8]}..., days_before={payload.days_before})"
    )

    return NotificationProcessResponse(
        status="processed",
        notification_id=payload.notification_id,
        message=(
            f"Notification for milestone {payload.milestone_id[:8]}... "
            f"({payload.days_before} days before) processed."
        ),
    )
