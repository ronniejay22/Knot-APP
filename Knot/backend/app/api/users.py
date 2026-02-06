"""
Users API — User account management.

Handles device token registration, data export, and account deletion.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/api/v1/users", tags=["users"])
