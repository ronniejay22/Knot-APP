"""
Knot Backend — FastAPI Entry Point

This is the main application module for the Knot backend.
It initializes the FastAPI app and registers all route handlers.
"""

from fastapi import Depends, FastAPI

from app.api.hints import router as hints_router
from app.api.vault import router as vault_router
from app.core.security import get_current_user_id

app = FastAPI(
    title="Knot API",
    description="Relational Excellence on Autopilot — Backend API",
    version="0.1.0",
)

# --- Register API routers ---
app.include_router(vault_router)
app.include_router(hints_router)


@app.get("/health")
async def health_check():
    """Health check endpoint. Returns service status."""
    return {"status": "ok"}


@app.get("/api/v1/me")
async def get_current_user(user_id: str = Depends(get_current_user_id)):
    """
    Protected endpoint — returns the authenticated user's ID.

    Requires a valid Supabase Bearer token in the Authorization header.
    Used to verify that the auth middleware is working correctly.
    """
    return {"user_id": user_id}
