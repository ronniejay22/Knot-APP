"""
Notification Models — Pydantic schemas for notification webhook payloads.

Defines the request and response models for the QStash webhook endpoint
that processes scheduled milestone notifications.

Step 7.1: Set up QStash scheduler — webhook payload models.
Step 7.7: Added notification history and milestone recommendation models.
"""

from datetime import datetime
from pydantic import BaseModel, Field


class NotificationProcessRequest(BaseModel):
    """
    Payload delivered by QStash to the /api/v1/notifications/process webhook.

    Contains the notification_queue entry ID and associated metadata
    needed to process the notification (generate recommendations,
    send push notification).
    """
    notification_id: str = Field(
        ...,
        description="UUID of the notification_queue entry to process.",
    )
    user_id: str = Field(
        ...,
        description="UUID of the user to notify.",
    )
    milestone_id: str = Field(
        ...,
        description="UUID of the milestone this notification is for.",
    )
    days_before: int = Field(
        ...,
        description="Number of days before the milestone (14, 7, or 3).",
    )


class NotificationProcessResponse(BaseModel):
    """
    Response returned after successfully processing a notification webhook.
    """
    status: str = Field(
        ...,
        description="Processing result: 'processed', 'skipped', 'rescheduled', or 'failed'.",
    )
    notification_id: str = Field(
        ...,
        description="UUID of the notification_queue entry that was processed.",
    )
    message: str = Field(
        default="",
        description="Human-readable description of the processing result.",
    )
    recommendations_generated: int = Field(
        default=0,
        description="Number of recommendations generated for this milestone.",
    )
    push_delivered: bool = Field(
        default=False,
        description="Whether the APNs push notification was successfully delivered.",
    )


# ===================================================================
# Notification History Models (Step 7.7)
# ===================================================================


class NotificationHistoryItem(BaseModel):
    """A single notification in the user's notification history."""
    id: str = Field(
        ...,
        description="UUID of the notification_queue entry.",
    )
    milestone_id: str = Field(
        ...,
        description="UUID of the associated milestone.",
    )
    milestone_name: str = Field(
        default="Unknown Milestone",
        description="Display name of the milestone (e.g., 'Partner Birthday').",
    )
    milestone_type: str = Field(
        default="custom",
        description="Type: birthday, anniversary, holiday, custom.",
    )
    milestone_date: str | None = Field(
        default=None,
        description="Date string of the milestone (YYYY-MM-DD).",
    )
    days_before: int = Field(
        ...,
        description="14, 7, or 3 — how many days before the milestone.",
    )
    status: str = Field(
        ...,
        description="Delivery status: pending, sent, failed, cancelled.",
    )
    sent_at: str | None = Field(
        default=None,
        description="ISO 8601 timestamp when the notification was sent.",
    )
    viewed_at: str | None = Field(
        default=None,
        description="ISO 8601 timestamp when the user viewed recommendations.",
    )
    created_at: str = Field(
        ...,
        description="ISO 8601 timestamp when the notification was scheduled.",
    )
    recommendations_count: int = Field(
        default=0,
        description="Number of recommendations generated for this milestone.",
    )


class NotificationHistoryResponse(BaseModel):
    """Response for GET /api/v1/notifications/history."""
    notifications: list[NotificationHistoryItem] = Field(
        default_factory=list,
        description="List of notification history items.",
    )
    total: int = Field(
        ...,
        description="Total number of sent/failed notifications for this user.",
    )


# ===================================================================
# Milestone Recommendation Models (Step 7.7)
# ===================================================================


class MilestoneRecommendationItem(BaseModel):
    """A stored recommendation for a milestone, returned from the history view."""
    id: str = Field(..., description="UUID of the recommendation.")
    recommendation_type: str = Field(..., description="gift, experience, or date.")
    title: str = Field(..., description="Display title of the recommendation.")
    description: str | None = Field(default=None, description="Short description.")
    external_url: str | None = Field(default=None, description="Merchant/booking URL.")
    price_cents: int | None = Field(default=None, description="Price in cents (e.g., 4999 = $49.99).")
    merchant_name: str | None = Field(default=None, description="Name of the merchant or venue.")
    image_url: str | None = Field(default=None, description="Hero image URL.")
    created_at: str = Field(..., description="ISO 8601 timestamp when the recommendation was generated.")


class MilestoneRecommendationsResponse(BaseModel):
    """Response for GET /api/v1/recommendations/by-milestone/{milestone_id}."""
    recommendations: list[MilestoneRecommendationItem] = Field(
        default_factory=list,
        description="List of pre-generated recommendations for the milestone.",
    )
    count: int = Field(..., description="Number of recommendations returned.")
    milestone_id: str = Field(..., description="UUID of the milestone.")
