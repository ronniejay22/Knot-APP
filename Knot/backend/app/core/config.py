"""
Application Configuration

Loads environment variables and provides typed settings
for the application. Uses python-dotenv to load from .env file.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file from the backend directory
_env_path = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(dotenv_path=_env_path)

# --- App Settings ---
API_V1_PREFIX = "/api/v1"
PROJECT_NAME = "Knot"

# --- Supabase ---
SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY: str = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

# --- Vertex AI (future steps) ---
GOOGLE_CLOUD_PROJECT: str = os.getenv("GOOGLE_CLOUD_PROJECT", "")
GOOGLE_APPLICATION_CREDENTIALS: str = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")


def validate_supabase_config() -> bool:
    """Check that all required Supabase credentials are present and non-empty."""
    missing = []
    if not SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not SUPABASE_ANON_KEY:
        missing.append("SUPABASE_ANON_KEY")
    if not SUPABASE_SERVICE_ROLE_KEY:
        missing.append("SUPABASE_SERVICE_ROLE_KEY")
    if missing:
        raise EnvironmentError(
            f"Missing required Supabase environment variables: {', '.join(missing)}. "
            f"Please fill in your .env file at: {_env_path}"
        )
    return True


def validate_vertex_ai_config() -> bool:
    """
    Check that Vertex AI credentials are configured.

    Only GOOGLE_CLOUD_PROJECT is required. GOOGLE_APPLICATION_CREDENTIALS
    is optional — when absent, the Vertex AI SDK falls back to Application
    Default Credentials (ADC) configured via `gcloud auth application-default login`.

    Returns True if configured, False if not (non-fatal — embedding
    generation will be disabled but the app will still function).
    """
    if not GOOGLE_CLOUD_PROJECT:
        return False
    return True


def is_vertex_ai_configured() -> bool:
    """
    Check if Vertex AI is available without raising exceptions.

    Used by tests and services to conditionally enable embedding features.
    """
    return bool(GOOGLE_CLOUD_PROJECT)
