"""
Knot Backend — FastAPI Entry Point

This is the main application module for the Knot backend.
It initializes the FastAPI app and registers all route handlers.
"""

from fastapi import FastAPI

app = FastAPI(
    title="Knot API",
    description="Relational Excellence on Autopilot — Backend API",
    version="0.1.0",
)


@app.get("/health")
async def health_check():
    """Health check endpoint. Returns service status."""
    return {"status": "ok"}
