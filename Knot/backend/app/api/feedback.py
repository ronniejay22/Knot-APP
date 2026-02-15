"""
Feedback Analysis API — Webhook endpoint for the weekly feedback analysis job.

Provides the endpoint for QStash to trigger the weekly feedback analysis
job, which computes user preference weights from recommendation feedback.
Also supports manual triggering for testing and ad-hoc analysis.

POST /api/v1/feedback/analyze — Run feedback analysis (QStash or manual)

Step 10.2: Create Feedback Analysis Job (Backend)
"""

import json
import logging

from fastapi import APIRouter, HTTPException, Header, Request, status

from app.models.feedback_analysis import (
    FeedbackAnalysisResponse,
)
from app.services.feedback_analysis import run_feedback_analysis
from app.services.qstash import verify_qstash_signature

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/feedback", tags=["feedback"])


# ===================================================================
# POST /api/v1/feedback/analyze — Weekly Feedback Analysis Job
# ===================================================================

@router.post(
    "/analyze",
    status_code=status.HTTP_200_OK,
    response_model=FeedbackAnalysisResponse,
)
async def analyze_feedback(
    request: Request,
    upstash_signature: str | None = Header(None, alias="Upstash-Signature"),
) -> FeedbackAnalysisResponse:
    """
    Run the feedback analysis job.

    When called by QStash (weekly cron), verifies the signature.
    When called without a signature (manual/testing), runs directly.
    Optionally accepts a user_id in the body to analyze a single user.

    Processing steps:
    1. Verify QStash signature if present
    2. Parse optional payload for target user_id
    3. Run feedback analysis across all eligible users (or single user)
    4. Return summary of results

    Returns:
        200: Analysis completed successfully.
        401: Invalid QStash signature.
        500: Analysis job failed.
    """
    body = await request.body()

    # --- 1. Verify QStash signature if present ---
    if upstash_signature:
        try:
            verify_qstash_signature(
                signature=upstash_signature,
                body=body,
                url=str(request.url),
            )
            logger.info("QStash signature verified for feedback analysis trigger")
        except ValueError as exc:
            logger.warning("QStash signature verification failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid QStash signature: {exc}",
            )

    # --- 2. Parse optional payload ---
    target_user_id = None
    if body:
        try:
            payload_data = json.loads(body)
            target_user_id = payload_data.get("user_id")
        except (json.JSONDecodeError, AttributeError):
            # Empty body or invalid JSON is OK — analyze all users
            pass

    # --- 3. Run feedback analysis ---
    try:
        result = await run_feedback_analysis(target_user_id=target_user_id)
    except Exception as exc:
        logger.error("Feedback analysis failed: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Feedback analysis failed. Check server logs.",
        )

    # --- 4. Return results ---
    return FeedbackAnalysisResponse(
        status=result.get("status", "completed"),
        users_analyzed=result.get("users_analyzed", 0),
        message=result.get("message", ""),
    )
