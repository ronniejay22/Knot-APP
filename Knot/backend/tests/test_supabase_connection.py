"""
Step 0.6 Verification: Supabase Connection Tests

Tests that:
1. Environment variables are loaded from .env
2. Supabase client connects successfully using stored credentials
3. pgvector Python library works for 768-dimension embeddings
4. Simple queries execute correctly against the live database

Prerequisites:
- Create a Supabase project at https://supabase.com/dashboard
- Enable pgvector: SQL Editor → run the migration at
    backend/supabase/migrations/00001_enable_pgvector.sql
- Fill in SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY in backend/.env

Run with: pytest tests/test_supabase_connection.py -v
"""

import pytest
from pathlib import Path


# ---------------------------------------------------------------------------
# Helper: check if Supabase credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all three Supabase env vars are non-empty."""
    from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env — fill them in to run these tests",
)


# ---------------------------------------------------------------------------
# 1. Environment variable loading
# ---------------------------------------------------------------------------

class TestEnvironmentConfig:
    """Verify that .env file exists and Supabase credentials are loaded."""

    def test_env_file_exists(self):
        """The .env file should exist in the backend directory."""
        from app.core.config import _env_path
        assert _env_path.exists(), (
            f".env file not found at {_env_path}. "
            "Copy .env.example to .env and fill in your Supabase credentials."
        )

    def test_supabase_url_is_set(self):
        """SUPABASE_URL must be set and non-empty."""
        from app.core.config import SUPABASE_URL
        assert SUPABASE_URL, (
            "SUPABASE_URL is empty. Fill it in your .env file. "
            "Find it at: Supabase Dashboard → Settings → API → Project URL"
        )
        assert SUPABASE_URL.startswith("https://"), (
            f"SUPABASE_URL should start with https://, got: {SUPABASE_URL[:30]}..."
        )

    def test_supabase_anon_key_is_set(self):
        """SUPABASE_ANON_KEY must be set and non-empty."""
        from app.core.config import SUPABASE_ANON_KEY
        assert SUPABASE_ANON_KEY, (
            "SUPABASE_ANON_KEY is empty. Fill it in your .env file. "
            "Find it at: Supabase Dashboard → Settings → API → anon (public) key"
        )
        assert len(SUPABASE_ANON_KEY) > 30, (
            "SUPABASE_ANON_KEY looks too short. Verify you copied the full key."
        )

    def test_supabase_service_role_key_is_set(self):
        """SUPABASE_SERVICE_ROLE_KEY must be set and non-empty."""
        from app.core.config import SUPABASE_SERVICE_ROLE_KEY
        assert SUPABASE_SERVICE_ROLE_KEY, (
            "SUPABASE_SERVICE_ROLE_KEY is empty. Fill it in your .env file. "
            "Find it at: Supabase Dashboard → Settings → API → service_role (secret) key"
        )
        assert len(SUPABASE_SERVICE_ROLE_KEY) > 30, (
            "SUPABASE_SERVICE_ROLE_KEY looks too short. Verify you copied the full key."
        )

    def test_validate_supabase_config_succeeds(self):
        """validate_supabase_config() should succeed when all vars are set."""
        from app.core.config import validate_supabase_config
        assert validate_supabase_config() is True


# ---------------------------------------------------------------------------
# 2. Supabase client connectivity (requires live credentials)
# ---------------------------------------------------------------------------

@requires_supabase
class TestSupabaseConnection:
    """Verify that the Supabase client can connect and execute queries."""

    def test_anon_client_initializes(self):
        """The anon client should initialize without errors."""
        from app.db.supabase_client import get_supabase_client
        client = get_supabase_client()
        assert client is not None, "Anon client returned None"
        print("  Anon client initialized successfully")

    def test_service_client_initializes(self):
        """The service role client should initialize without errors."""
        from app.db.supabase_client import get_service_client
        client = get_service_client()
        assert client is not None, "Service client returned None"
        print("  Service client initialized successfully")

    def test_simple_query_select_one(self):
        """
        Execute a query against Supabase to verify the connection is live.

        We attempt to query a nonexistent table. The important thing is that
        the Supabase client authenticates and communicates with the server.
        A "relation does not exist" or empty result means connection works.
        An auth error or timeout means credentials/URL are wrong.
        """
        from app.db.supabase_client import get_service_client
        client = get_service_client()

        try:
            # Query a table that doesn't exist yet — we expect an empty
            # result or a "not found" error, both of which prove connectivity.
            result = client.table("_knot_connection_test").select("*").limit(1).execute()
            # If we get here without error, connection is working
            assert result is not None
            print("  Connection verified: query executed successfully")
        except Exception as e:
            error_str = str(e)
            # These errors mean we connected but the table doesn't exist — that's fine
            if any(keyword in error_str for keyword in [
                "404", "does not exist", "Not Found", "relation",
                "42P01",  # PostgreSQL: undefined_table
                "PGRST205",  # PostgREST: table not in schema cache
                "Could not find",
            ]):
                print("  Connection verified: authenticated and reached database")
            else:
                pytest.fail(
                    f"Supabase connection failed: {error_str}. "
                    "Verify your SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env"
                )


# ---------------------------------------------------------------------------
# 3. pgvector Python library verification (no Supabase credentials needed)
# ---------------------------------------------------------------------------

class TestPgvectorLibrary:
    """Verify the pgvector Python library works for vector encoding."""

    def test_pgvector_import(self):
        """pgvector Vector type should be importable."""
        from pgvector import Vector
        assert Vector is not None
        print("  pgvector.Vector imported successfully")

    def test_pgvector_768_dimension_vector(self):
        """Create a 768-dimension vector matching Vertex AI text-embedding-004 output."""
        from pgvector import Vector

        # Simulate a Vertex AI text-embedding-004 embedding (768 dimensions)
        dummy_embedding = [0.01 * i for i in range(768)]
        vec = Vector(dummy_embedding)

        assert vec is not None
        vec_list = vec.to_list()
        assert len(vec_list) == 768, f"Expected 768 dimensions, got {len(vec_list)}"
        assert abs(vec_list[0] - 0.0) < 0.001
        assert abs(vec_list[100] - 1.0) < 0.001
        print("  768-dimension embedding vector created and validated")

    def test_pgvector_string_representation(self):
        """Vector should serialize to a string format compatible with PostgreSQL."""
        from pgvector import Vector

        vec = Vector([1.0, 2.0, 3.0])
        vec_str = str(vec)
        # pgvector uses the format [1.0,2.0,3.0] for PostgreSQL
        assert "1" in vec_str and "2" in vec_str and "3" in vec_str, (
            f"Unexpected vector string format: {vec_str}"
        )
        print(f"  Vector string representation: {vec_str}")
