"""
Users API — User account management.

Handles device token registration, account deletion, data export,
and notification preferences.

Step 7.4: POST /api/v1/users/device-token — Register APNs device token.
Step 11.2: DELETE /api/v1/users/me — Schedule account for deletion (60-day grace).
Step 11.3: GET /api/v1/users/me/export — Export all user data as JSON.
Step 11.4: GET/PUT /api/v1/users/me/notification-preferences — Notification preferences.
Step 15.5: GET  /api/v1/users/me — Lightweight account-status probe.
           POST /api/v1/users/me/restore — Cancel a pending deletion.
           POST /api/v1/users/process-deletion — QStash purge worker.
"""

import json
import logging
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from app.core.config import (
    DEV_RESET_ENABLED,
    SUPABASE_SERVICE_ROLE_KEY,
    SUPABASE_URL,
    WEBHOOK_BASE_URL,
    is_qstash_configured,
)
from app.core.security import get_active_user_id, get_current_user_id
from app.db.supabase_client import get_service_client
from app.models.users import (
    AccountDeleteResponse,
    AccountRestoreResponse,
    AccountStatusResponse,
    DataExportResponse,
    DeviceTokenRequest,
    DeviceTokenResponse,
    NotificationPreferencesRequest,
    NotificationPreferencesResponse,
)
from app.services.qstash import publish_to_qstash, verify_qstash_signature

DELETION_GRACE_DAYS = 60

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.post(
    "/device-token",
    status_code=status.HTTP_200_OK,
    response_model=DeviceTokenResponse,
)
async def register_device_token(
    payload: DeviceTokenRequest,
    user_id: str = Depends(get_active_user_id),
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


async def _hard_delete_auth_user(user_id: str) -> None:
    """
    Permanently delete the auth.users row for `user_id` via the Supabase
    Admin API. CASCADE removes public.users and every downstream table.

    Raises HTTPException(500) on network or admin-API failure. The caller
    should treat that as "leave scheduled_deletion_at in place and rely on
    the next QStash retry" — QStash retries failed webhooks automatically.
    """
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

    # 404 from the admin API means the user is already gone — treat as success
    # so QStash retries don't loop forever.
    if resp.status_code not in (200, 204, 404):
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


@router.get(
    "/me",
    status_code=status.HTTP_200_OK,
    response_model=AccountStatusResponse,
)
async def get_account_status(
    user_id: str = Depends(get_current_user_id),
) -> AccountStatusResponse:
    """
    Lightweight account-status probe for the iOS client to call after sign-in.

    Uses get_current_user_id (not get_active_user_id) so it can also return a
    200 with scheduled_deletion_at populated when the account is pending. The
    iOS app then chooses between PendingDeletionView and the normal app shell.
    """
    client = get_service_client()
    try:
        result = (
            client.table("users")
            .select("scheduled_deletion_at")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to read account status for %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to read account status.",
        )

    if not result.data:
        return AccountStatusResponse(user_id=user_id, scheduled_deletion_at=None)

    return AccountStatusResponse(
        user_id=user_id,
        scheduled_deletion_at=result.data[0].get("scheduled_deletion_at"),
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
    Schedule the authenticated user's account for deletion in 60 days.

    Sets public.users.scheduled_deletion_at and enqueues a QStash purge
    job that calls POST /api/v1/users/process-deletion at the scheduled
    time. The auth user and all CASCADE-linked rows remain intact during
    the grace window so the user can sign back in and restore.

    Idempotent: if the user is already pending deletion, the column is
    refreshed to now() + 60 days and a fresh QStash job is enqueued. The
    purge worker is itself idempotent so a stale (earlier) QStash message
    that fires after a re-schedule will simply re-read the column and act
    on whichever value is current.

    Returns:
        200: Deletion scheduled. Body includes scheduled_deletion_at.
        401: Missing or invalid authentication token.
        404: User not found.
        500: Database or QStash error.
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

    scheduled_at = datetime.now(timezone.utc) + timedelta(days=DELETION_GRACE_DAYS)
    scheduled_iso = scheduled_at.isoformat()

    # 2. Mark the user as pending deletion.
    try:
        client.table("users").update(
            {"scheduled_deletion_at": scheduled_iso}
        ).eq("id", user_id).execute()
    except Exception as exc:
        logger.error(
            "Failed to set scheduled_deletion_at for user %s: %s",
            user_id[:8], exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to schedule account deletion.",
        )

    # 3. Enqueue the QStash purge job. 60 days exceeds the 7-day delay_seconds
    #    cap, so we use not_before with the Unix timestamp.
    if is_qstash_configured():
        webhook_url = f"{WEBHOOK_BASE_URL}/api/v1/users/process-deletion"
        try:
            await publish_to_qstash(
                destination_url=webhook_url,
                body={"user_id": user_id},
                not_before=int(scheduled_at.timestamp()),
                deduplication_id=f"account-deletion-{user_id}-{int(scheduled_at.timestamp())}",
            )
        except Exception as exc:
            # We deliberately don't roll back the column update — the worker
            # is also reachable via a manual/admin trigger and the user still
            # benefits from the gate. But we surface the error so the iOS
            # client can retry the call (which is idempotent).
            logger.error(
                "Failed to publish QStash deletion job for user %s: %s",
                user_id[:8], exc,
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to schedule the deletion job. Please try again.",
            )
    else:
        # In dev/CI without QStash configured, log loudly. The column is
        # still set so the gate works; tests bypass the worker directly.
        logger.warning(
            "QStash not configured — account deletion for user %s is "
            "scheduled in DB only and will not auto-purge.",
            user_id[:8],
        )

    logger.info(
        "Account scheduled for deletion: user=%s scheduled_at=%s",
        user_id[:8], scheduled_iso,
    )

    return AccountDeleteResponse(scheduled_deletion_at=scheduled_iso)


@router.post(
    "/me/restore",
    status_code=status.HTTP_200_OK,
    response_model=AccountRestoreResponse,
)
async def restore_account(
    user_id: str = Depends(get_current_user_id),
) -> AccountRestoreResponse:
    """
    Cancel a pending account deletion.

    Idempotent — clears public.users.scheduled_deletion_at unconditionally.
    Any stale QStash purge message that fires later will read the now-null
    column and noop.

    Uses get_current_user_id (not get_active_user_id) so a pending user
    can call it.
    """
    client = get_service_client()
    try:
        client.table("users").update(
            {"scheduled_deletion_at": None}
        ).eq("id", user_id).execute()
    except Exception as exc:
        logger.error(
            "Failed to clear scheduled_deletion_at for user %s: %s",
            user_id[:8], exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to restore account.",
        )

    logger.info("Account restored: user=%s", user_id[:8])
    return AccountRestoreResponse()


@router.post(
    "/me/dev-reset",
    status_code=status.HTTP_200_OK,
)
async def dev_reset_account(
    user_id: str = Depends(get_current_user_id),
) -> dict:
    """
    DEV-ONLY: wipe partner_vaults + scheduled_deletion_at for the caller so
    the iOS app routes the user back to onboarding on the next vault-exists
    check. CASCADE removes interests, milestones, vibes, budgets, love
    languages, hints, and recommendations. The auth user stays signed in,
    and the users row (device token, quiet hours, etc.) is left intact.

    Gated by KNOT_DEV_RESET_ENABLED=true. Returns 403 when unset so this
    can never wipe data in production by accident.

    Uses get_current_user_id (not get_active_user_id) so the route also
    works when the account is currently pending deletion.
    """
    if not DEV_RESET_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="dev-reset is disabled in this environment.",
        )

    client = get_service_client()

    try:
        client.table("users").update(
            {"scheduled_deletion_at": None}
        ).eq("id", user_id).execute()
    except Exception as exc:
        logger.error(
            "dev-reset: failed to clear scheduled_deletion_at for %s: %s",
            user_id[:8], exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to clear pending deletion.",
        )

    try:
        client.table("partner_vaults").delete().eq("user_id", user_id).execute()
    except Exception as exc:
        logger.error(
            "dev-reset: failed to delete vault for %s: %s", user_id[:8], exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete vault.",
        )

    logger.info(
        "dev-reset: cleared pending deletion + vault for user=%s", user_id[:8],
    )
    return {"status": "reset", "user_id": user_id}


@router.post(
    "/process-deletion",
    status_code=status.HTTP_200_OK,
)
async def process_account_deletion(
    request: Request,
    upstash_signature: str | None = Header(None, alias="Upstash-Signature"),
) -> dict:
    """
    QStash webhook that runs the actual hard-delete after the 60-day grace
    window has elapsed.

    Idempotent and race-safe:
      - Verifies the Upstash-Signature JWT before doing anything.
      - Re-reads public.users.scheduled_deletion_at. If NULL (user restored)
        or in the future (concurrent re-schedule), returns 200 noop and
        leaves the user intact.
      - Otherwise calls the Supabase Admin API to delete auth.users, which
        cascades to every public table.
    """
    body = await request.body()
    request_url = str(request.url)

    try:
        verify_qstash_signature(
            signature=upstash_signature or "",
            body=body,
            url=request_url,
        )
    except ValueError as exc:
        logger.warning("QStash signature verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid QStash signature: {exc}",
        )

    try:
        payload = json.loads(body)
        user_id = payload["user_id"]
    except (ValueError, KeyError, TypeError) as exc:
        logger.error("Bad process-deletion payload: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid payload: user_id is required.",
        )

    client = get_service_client()
    try:
        result = (
            client.table("users")
            .select("scheduled_deletion_at")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error(
            "process-deletion: failed to look up user %s: %s",
            user_id[:8], exc,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to look up user.",
        )

    if not result.data:
        # Auth.users may still exist but public.users is gone — try the
        # admin delete anyway so we don't leave orphaned auth rows.
        logger.info(
            "process-deletion: public.users row already absent for %s — "
            "still attempting auth deletion to be safe.",
            user_id[:8],
        )
        await _hard_delete_auth_user(user_id)
        return {"status": "deleted", "user_id": user_id}

    scheduled = result.data[0].get("scheduled_deletion_at")
    if scheduled is None:
        logger.info(
            "process-deletion: user %s has been restored — skipping purge.",
            user_id[:8],
        )
        return {"status": "skipped", "reason": "restored", "user_id": user_id}

    try:
        scheduled_dt = datetime.fromisoformat(scheduled.replace("Z", "+00:00"))
    except ValueError:
        logger.error(
            "process-deletion: unparseable scheduled_deletion_at=%r for user %s",
            scheduled, user_id[:8],
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Invalid scheduled_deletion_at value.",
        )

    if scheduled_dt > datetime.now(timezone.utc):
        # A re-schedule pushed the date out. Leave the user; the newer
        # QStash message will fire at the right time.
        logger.info(
            "process-deletion: user %s scheduled for %s — not yet due, skipping.",
            user_id[:8], scheduled,
        )
        return {"status": "skipped", "reason": "rescheduled", "user_id": user_id}

    await _hard_delete_auth_user(user_id)
    logger.info(
        "process-deletion: hard-deleted user=%s scheduled_at=%s",
        user_id[:8], scheduled,
    )
    return {"status": "deleted", "user_id": user_id}


# ===================================================================
# GET /api/v1/users/me/export (Step 11.3)
# ===================================================================


@router.get(
    "/me/export",
    status_code=status.HTTP_200_OK,
    response_model=DataExportResponse,
)
async def export_user_data(
    user_id: str = Depends(get_active_user_id),
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


# ===================================================================
# GET /api/v1/users/me/notification-preferences (Step 11.4)
# ===================================================================


@router.get(
    "/me/notification-preferences",
    status_code=status.HTTP_200_OK,
    response_model=NotificationPreferencesResponse,
)
async def get_notification_preferences(
    user_id: str = Depends(get_active_user_id),
) -> NotificationPreferencesResponse:
    """
    Retrieve the authenticated user's notification preferences.

    Returns the global notifications toggle, quiet hours range,
    and timezone setting. These values are stored on the users
    table and control how the notification webhook processes
    scheduled notifications.

    Returns:
        200: Current notification preferences.
        401: Missing or invalid authentication token.
        404: User not found.
        500: Database error.
    """
    client = get_service_client()

    try:
        result = (
            client.table("users")
            .select("notifications_enabled, quiet_hours_start, quiet_hours_end, timezone")
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        logger.error("Failed to fetch notification preferences for %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load notification preferences.",
        )

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    user = result.data[0]

    return NotificationPreferencesResponse(
        notifications_enabled=user.get("notifications_enabled", True),
        quiet_hours_start=user.get("quiet_hours_start", 22),
        quiet_hours_end=user.get("quiet_hours_end", 8),
        timezone=user.get("timezone"),
    )


# ===================================================================
# PUT /api/v1/users/me/notification-preferences (Step 11.4)
# ===================================================================


@router.put(
    "/me/notification-preferences",
    status_code=status.HTTP_200_OK,
    response_model=NotificationPreferencesResponse,
)
async def update_notification_preferences(
    payload: NotificationPreferencesRequest,
    user_id: str = Depends(get_active_user_id),
) -> NotificationPreferencesResponse:
    """
    Update the authenticated user's notification preferences.

    Accepts partial updates — only provided fields are changed.
    For example, sending only `quiet_hours_start` will update
    that field while preserving all other preferences.

    Returns:
        200: Updated notification preferences.
        401: Missing or invalid authentication token.
        404: User not found.
        422: Invalid field values (hour out of range, bad timezone).
        500: Database error.
    """
    client = get_service_client()

    # Verify user exists
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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    # Build update dict from provided fields only
    update_data: dict = {}
    if payload.notifications_enabled is not None:
        update_data["notifications_enabled"] = payload.notifications_enabled
    if payload.quiet_hours_start is not None:
        update_data["quiet_hours_start"] = payload.quiet_hours_start
    if payload.quiet_hours_end is not None:
        update_data["quiet_hours_end"] = payload.quiet_hours_end
    # timezone can be explicitly set to None (to clear it)
    if "timezone" in payload.model_fields_set:
        update_data["timezone"] = payload.timezone

    if not update_data:
        # Nothing to update — just return current preferences
        return await get_notification_preferences(user_id)

    # Apply update
    try:
        client.table("users").update(update_data).eq("id", user_id).execute()
    except Exception as exc:
        logger.error("Failed to update notification preferences for %s: %s", user_id[:8], exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update notification preferences.",
        )

    logger.info(
        "Notification preferences updated for user %s: %s",
        user_id[:8],
        update_data,
    )

    # Return the updated preferences
    return await get_notification_preferences(user_id)
