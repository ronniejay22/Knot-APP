"""
Notifications API — QStash webhook endpoint for processing scheduled notifications.

Handles incoming webhook calls from Upstash QStash. Each call represents
a scheduled notification that needs to be processed (e.g., generate
recommendations and send a push notification for an upcoming milestone).

Step 7.1: Set up QStash scheduler — webhook endpoint with signature verification.
Step 7.3: Generate recommendations when notification fires.
Step 7.5: Deliver APNs push notifications after recommendation generation.
"""

import json
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Header, Request, status

from app.agents.pipeline import run_recommendation_pipeline
from app.agents.state import RecommendationState
from app.db.supabase_client import get_service_client
from app.models.notifications import (
    NotificationProcessRequest,
    NotificationProcessResponse,
)
from app.core.config import is_apns_configured
from app.services.apns import deliver_push_notification
from app.services.qstash import verify_qstash_signature
from app.services.vault_loader import (
    find_budget_range,
    load_milestone_context,
    load_vault_data,
)

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
    4. Generate recommendations for the upcoming milestone (Step 7.3)
    5. Deliver APNs push notification to the user's device (Step 7.5)
    6. Mark the notification as 'sent'
    7. Return processing result

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

    # --- 6. Generate recommendations for this milestone (Step 7.3) ---
    recommendations_count = 0
    vault_data = None
    milestone_context = None
    try:
        vault_data, vault_id = await load_vault_data(payload.user_id)
        milestone_context = await load_milestone_context(
            payload.milestone_id, vault_id,
        )

        if milestone_context is None:
            logger.warning(
                f"Milestone {payload.milestone_id[:8]}... not found for "
                f"vault {vault_id[:8]}... — skipping recommendation generation"
            )
        else:
            occasion_type = milestone_context.budget_tier
            budget_range = find_budget_range(vault_data.budgets, occasion_type)

            state = RecommendationState(
                vault_data=vault_data,
                occasion_type=occasion_type,
                milestone_context=milestone_context,
                budget_range=budget_range,
            )

            result = await run_recommendation_pipeline(state)

            error = result.get("error")
            if error:
                logger.warning(
                    "Pipeline returned error for notification %s: %s",
                    payload.notification_id, error,
                )
            else:
                final_three = result.get("final_three", [])

                if final_three:
                    rec_rows = [
                        {
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
                        for candidate in final_three
                    ]
                    client.table("recommendations").insert(rec_rows).execute()
                    recommendations_count = len(final_three)

                    logger.info(
                        "Generated %d recommendations for notification %s "
                        "(milestone %s)",
                        recommendations_count,
                        payload.notification_id[:8],
                        payload.milestone_id[:8],
                    )
                else:
                    logger.info(
                        "Pipeline returned no results for notification %s",
                        payload.notification_id,
                    )

    except Exception as exc:
        logger.warning(
            "Failed to generate recommendations for notification %s: %s",
            payload.notification_id, exc,
        )

    # --- 7. Deliver push notification (Step 7.5) ---
    push_result = None
    if is_apns_configured() and recommendations_count > 0:
        try:
            push_result = await deliver_push_notification(
                user_id=payload.user_id,
                notification_id=payload.notification_id,
                milestone_id=payload.milestone_id,
                partner_name=(
                    vault_data.partner_name if vault_data else "Your partner"
                ),
                milestone_name=(
                    milestone_context.milestone_name
                    if milestone_context
                    else "upcoming milestone"
                ),
                days_before=payload.days_before,
                vibes=vault_data.vibes if vault_data else [],
                recommendations_count=recommendations_count,
            )

            if push_result and push_result.get("success"):
                logger.info(
                    "Push notification delivered for %s (apns_id=%s)",
                    payload.notification_id[:8],
                    push_result.get("apns_id"),
                )
            else:
                logger.warning(
                    "Push notification failed for %s: %s",
                    payload.notification_id[:8],
                    push_result.get("reason") if push_result else "unknown",
                )
        except Exception as exc:
            logger.warning(
                "Failed to deliver push notification for %s: %s",
                payload.notification_id,
                exc,
            )
    elif not is_apns_configured():
        logger.debug(
            "APNs not configured — skipping push delivery for %s",
            payload.notification_id[:8],
        )

    # --- 8. Update status to 'sent' ---
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
        f"(user={payload.user_id[:8]}..., days_before={payload.days_before}, "
        f"recommendations={recommendations_count})"
    )

    return NotificationProcessResponse(
        status="processed",
        notification_id=payload.notification_id,
        message=(
            f"Notification for milestone {payload.milestone_id[:8]}... "
            f"({payload.days_before} days before) processed."
        ),
        recommendations_generated=recommendations_count,
        push_delivered=bool(push_result and push_result.get("success")),
    )
