"""
User Models — Pydantic schemas for user account management.

Defines request/response models for user-related endpoints:
- POST /api/v1/users/device-token — Register device token (Step 7.4)
- DELETE /api/v1/users/me — Account deletion (Step 11.2)

Step 7.4: Push Notification Registration (iOS + Backend)
Step 11.2: Account Deletion (iOS + Backend)
"""

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
