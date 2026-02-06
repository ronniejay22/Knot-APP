"""
Supabase Client

Provides initialized Supabase clients for the application.
Uses the anon key for user-context operations (respects RLS)
and the service role key for admin operations (bypasses RLS).
"""

from supabase import create_client, Client
from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
    validate_supabase_config,
)

# Module-level clients — initialized lazily
_anon_client: Client | None = None
_service_client: Client | None = None


def get_supabase_client() -> Client:
    """
    Get the Supabase client using the anon (public) key.

    This client respects Row Level Security (RLS) policies.
    Use this for all user-facing operations where the user's
    JWT is set on the client to enforce access controls.
    """
    global _anon_client
    if _anon_client is None:
        validate_supabase_config()
        _anon_client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    return _anon_client


def get_service_client() -> Client:
    """
    Get the Supabase client using the service_role (admin) key.

    WARNING: This client BYPASSES Row Level Security.
    Only use for administrative operations (migrations, background jobs,
    notification processing) that need access across all users.
    """
    global _service_client
    if _service_client is None:
        validate_supabase_config()
        _service_client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    return _service_client


def test_connection() -> dict:
    """
    Test the Supabase connection by attempting a query.

    Returns a dict with connection status and project URL.
    Raises EnvironmentError if credentials are missing.
    Raises Exception if the connection fails.
    """
    validate_supabase_config()
    client = get_service_client()

    # Attempt a table query to verify connectivity.
    # Even querying a nonexistent table proves auth + network work.
    try:
        result = client.table("_knot_connection_test").select("*").limit(1).execute()
        return {
            "status": "connected",
            "supabase_url": SUPABASE_URL,
        }
    except Exception as e:
        error_str = str(e)
        # "Not found" / "relation does not exist" means we connected
        # successfully — the table just doesn't exist yet. That's fine.
        if any(kw in error_str for kw in [
            "404", "does not exist", "Not Found", "relation",
            "42P01", "PGRST205", "Could not find",
        ]):
            return {
                "status": "connected",
                "supabase_url": SUPABASE_URL,
            }
        raise
