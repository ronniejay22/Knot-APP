"""
User Models — Pydantic schemas for user account management.

Defines request/response models for user-related endpoints:
- POST /api/v1/users/device-token — Register device token (Step 7.4)
- DELETE /api/v1/users/me — Account deletion (Step 11.2)
- GET /api/v1/users/me/export — Data export (Step 11.3)

Step 7.4: Push Notification Registration (iOS + Backend)
Step 11.2: Account Deletion (iOS + Backend)
Step 11.3: Data Export (Backend)
"""

from typing import Optional

from pydantic import BaseModel, Field, field_validator


class DeviceTokenRequest(BaseModel):
    """
    Payload for POST /api/v1/users/device-token.

    Sent by the iOS app after successfully registering for
    remote notifications. The token is the hex-encoded APNs
    device token.
    """

    device_token: str = Field(
        ...,
        min_length=1,
        max_length=200,
        description="Hex-encoded APNs device token string.",
    )
    platform: str = Field(
        default="ios",
        description="Device platform: 'ios' or 'android'.",
    )

    @field_validator("device_token")
    @classmethod
    def validate_device_token(cls, v: str) -> str:
        """Strip whitespace and validate non-empty."""
        v = v.strip()
        if not v:
            raise ValueError("Device token cannot be empty.")
        return v

    @field_validator("platform")
    @classmethod
    def validate_platform(cls, v: str) -> str:
        """Ensure platform is a supported value."""
        if v not in ("ios", "android"):
            raise ValueError("Platform must be 'ios' or 'android'.")
        return v


class DeviceTokenResponse(BaseModel):
    """
    Response from POST /api/v1/users/device-token.
    """

    status: str = Field(
        default="registered",
        description="Result: 'registered' (new) or 'updated' (existing token replaced).",
    )
    device_token: str = Field(
        ...,
        description="The device token that was stored (echoed back for confirmation).",
    )
    platform: str = Field(
        ...,
        description="The platform that was stored.",
    )


class AccountDeleteResponse(BaseModel):
    """
    Response from DELETE /api/v1/users/me.

    Returned after the user's account and all associated data
    have been permanently deleted via Supabase Admin API cascade.
    """

    status: str = Field(
        default="deleted",
        description="Always 'deleted' on success.",
    )
    message: str = Field(
        default="Account and all associated data have been permanently deleted.",
        description="Human-readable confirmation message.",
    )


# ======================================================================
# Data Export (Step 11.3)
# ======================================================================


class DataExportResponse(BaseModel):
    """
    Complete user data export returned by GET /api/v1/users/me/export.

    Compiles all user data (vault, hints, recommendations, feedback,
    notifications) into a single JSON response for GDPR/privacy compliance.

    Uses `dict` types for nested data to keep the export flexible
    and avoid creating many single-use Pydantic models. The JSON output
    is for user consumption (download/share), not API interop.
    """

    exported_at: str = Field(
        ...,
        description="ISO 8601 timestamp of when the export was generated.",
    )
    user: dict = Field(
        ...,
        description="User account info: id, email, created_at.",
    )
    partner_vault: Optional[dict] = Field(
        default=None,
        description=(
            "Full partner vault data including basic info, interests, "
            "dislikes, vibes, budgets, and love languages. "
            "None if onboarding not completed."
        ),
    )
    milestones: list[dict] = Field(
        default_factory=list,
        description="All partner milestones (birthday, anniversary, holidays, custom).",
    )
    hints: list[dict] = Field(
        default_factory=list,
        description="All captured hints (text, source, is_used, created_at). Excludes embeddings.",
    )
    recommendations: list[dict] = Field(
        default_factory=list,
        description="All AI-generated recommendations with type, title, price, merchant.",
    )
    feedback: list[dict] = Field(
        default_factory=list,
        description="All recommendation feedback (selections, ratings, refreshes).",
    )
    notifications: list[dict] = Field(
        default_factory=list,
        description="All notification queue entries with schedule, status, and sent timestamps.",
    )
