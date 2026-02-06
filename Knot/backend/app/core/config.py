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
