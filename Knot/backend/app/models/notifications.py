"""
Notification Models — Pydantic schemas for notification webhook payloads.

Defines the request and response models for the QStash webhook endpoint
that processes scheduled milestone notifications.

Step 7.1: Set up QStash scheduler — webhook payload models.
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
