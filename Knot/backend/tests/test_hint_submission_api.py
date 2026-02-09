"""
Step 4.4 Verification: Hint Submission API with Embedding Generation

Tests the POST /api/v1/hints endpoint with Vertex AI text-embedding-004
embedding generation.

Tests cover:
1. Submit a hint → 201 response with hint data
2. Database verification: hint_text and hint_embedding (768-dim vector) populated
3. Submit empty text → 422 validation error
4. Submit 501 characters → 422 error with "Hint too long" message
5. Submit exactly 500 characters → 201 success
6. Source types: text_input and voice_transcription
7. Auth required → 401 without token
8. No partner vault → 404
9. Graceful degradation when Vertex AI is unavailable
10. Embedding format verification (768 dimensions via pgvector)
11. Multiple hints have independent embeddings
12. Unit tests for embedding service and pgvector formatting

Prerequisites:
- Complete Steps 0.6-3.10 (Supabase + all tables + vault API)
- Backend server NOT required (uses FastAPI TestClient)
- For embedding tests: GOOGLE_CLOUD_PROJECT set in .env with valid GCP credentials

Run with: pytest tests/test_hint_submission_api.py -v
"""

import pytest
import httpx
import uuid
import time
from unittest.mock import patch, AsyncMock

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Helper: check if Supabase / Vertex AI credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


def _vertex_ai_configured() -> bool:
    """Return True if Vertex AI credentials are configured."""
    from app.core.config import is_vertex_ai_configured
    return is_vertex_ai_configured()


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)

requires_vertex_ai = pytest.mark.skipif(
    not _vertex_ai_configured(),
    reason="Vertex AI credentials not configured (GOOGLE_CLOUD_PROJECT empty)",
)


# ---------------------------------------------------------------------------
# Helpers: auth user management (same pattern as test_vault_api.py)
# ---------------------------------------------------------------------------

def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _service_headers() -> dict:
    """Headers for direct Supabase PostgREST queries (service role)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
    }


def _create_auth_user(email: str, password: str) -> str:
    """Create a test user via Supabase Admin API. Returns user ID."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={
            "email": email,
            "password": password,
            "email_confirm": True,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to create test auth user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()["id"]


def _delete_auth_user(user_id: str):
    """Delete a test user via Supabase Admin API."""
    import warnings
    try:
        resp = httpx.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_admin_headers(),
        )
        if resp.status_code != 200:
            warnings.warn(
                f"Failed to delete test auth user {user_id}: "
                f"HTTP {resp.status_code} — {resp.text}",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}",
            stacklevel=2,
        )


def _sign_in_user(email: str, password: str) -> dict:
    """Sign in a test user. Returns full session response with access_token."""
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/token?grant_type=password",
        headers={
            "apikey": SUPABASE_ANON_KEY,
            "Content-Type": "application/json",
        },
        json={
            "email": email,
            "password": password,
        },
    )
    assert resp.status_code == 200, (
        f"Failed to sign in test user: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


# ---------------------------------------------------------------------------
# Helper: build a valid vault payload
# ---------------------------------------------------------------------------

def _valid_vault_payload() -> dict:
    """Return a complete, valid vault creation payload."""
    return {
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "San Francisco",
        "location_state": "CA",
        "location_country": "US",
        "interests": ["Travel", "Cooking", "Movies", "Music", "Reading"],
        "dislikes": ["Sports", "Gaming", "Cars", "Skiing", "Karaoke"],
        "milestones": [
            {
                "milestone_type": "birthday",
                "milestone_name": "Birthday",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
            },
        ],
        "vibes": ["quiet_luxury", "minimalist"],
        "budgets": [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 15000, "currency": "USD"},
            {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 50000, "currency": "USD"},
        ],
        "love_languages": {"primary": "quality_time", "secondary": "receiving_gifts"},
    }


# ---------------------------------------------------------------------------
# Helper: query hints directly via PostgREST (service role, bypasses RLS)
# ---------------------------------------------------------------------------

def _query_hints(vault_id: str) -> list[dict]:
    """Query the hints table directly for all hints in a vault."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/hints"
        f"?vault_id=eq.{vault_id}&order=created_at.desc"
        f"&select=id,vault_id,hint_text,hint_embedding,source,is_used,created_at",
        headers=_service_headers(),
    )
    assert resp.status_code == 200, (
        f"Failed to query hints: HTTP {resp.status_code} — {resp.text}"
    )
    return resp.json()


def _get_vault_id(user_id: str) -> str:
    """Get the vault_id for a user via PostgREST."""
    resp = httpx.get(
        f"{SUPABASE_URL}/rest/v1/partner_vaults"
        f"?user_id=eq.{user_id}&select=id",
        headers=_service_headers(),
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1, f"Expected 1 vault, got {len(data)}"
    return data[0]["id"]


def _delete_hints(vault_id: str):
    """Delete all hints for a vault (cleanup)."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/hints?vault_id=eq.{vault_id}",
        headers={
            **_service_headers(),
            "Content-Type": "application/json",
        },
    )


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """Create a FastAPI test client."""
    from fastapi.testclient import TestClient
    from app.main import app
    return TestClient(app)


@pytest.fixture
def test_auth_user_with_vault(client):
    """
    Create a test user, sign them in, create a vault, and yield context.
    Cleanup deletes the auth user (CASCADE removes all data).
    """
    test_email = f"knot-hint-test-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)  # wait for handle_new_user trigger

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    # Create a vault via the API
    vault_resp = client.post(
        "/api/v1/vault",
        json=_valid_vault_payload(),
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert vault_resp.status_code == 201, (
        f"Failed to create vault: HTTP {vault_resp.status_code} — {vault_resp.text}"
    )
    vault_id = vault_resp.json()["vault_id"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
        "vault_id": vault_id,
    }

    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user_no_vault():
    """
    Create a test user with NO vault (to test 404 handling).
    """
    test_email = f"knot-hint-novault-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)

    session = _sign_in_user(test_email, test_password)
    access_token = session["access_token"]

    yield {
        "id": user_id,
        "email": test_email,
        "access_token": access_token,
    }

    _delete_auth_user(user_id)


def _auth_headers(token: str) -> dict:
    """Build Authorization headers for API requests."""
    return {"Authorization": f"Bearer {token}"}


# ===================================================================
# 1. Valid hint submission — 201 response
# ===================================================================

@requires_supabase
class TestValidHintSubmission:
    """Verify POST /api/v1/hints succeeds with valid payloads."""

    def test_submit_hint_returns_201(self, client, test_auth_user_with_vault):
        """A valid hint payload should return 201 Created."""
        resp = client.post(
            "/api/v1/hints",
            json={
                "hint_text": "She mentioned wanting a new yoga mat",
                "source": "text_input",
            },
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201, (
            f"Expected 201, got {resp.status_code}. Response: {resp.text}"
        )
        print("  Valid hint → HTTP 201")

    def test_submit_hint_returns_hint_data(self, client, test_auth_user_with_vault):
        """The response should include the hint's id, text, source, and timestamps."""
        resp = client.post(
            "/api/v1/hints",
            json={
                "hint_text": "He really wants tickets to that concert",
                "source": "text_input",
            },
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        data = resp.json()

        assert "id" in data, "Response missing 'id'"
        assert data["hint_text"] == "He really wants tickets to that concert"
        assert data["source"] == "text_input"
        assert data["is_used"] is False
        assert "created_at" in data
        print(f"  Response contains: id={data['id'][:8]}..., text, source, is_used, created_at")

    def test_submit_hint_text_input_source(self, client, test_auth_user_with_vault):
        """Hint with source 'text_input' should be accepted."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "She likes those earrings", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        assert resp.json()["source"] == "text_input"
        print("  source='text_input' accepted")

    def test_submit_hint_voice_transcription_source(self, client, test_auth_user_with_vault):
        """Hint with source 'voice_transcription' should be accepted."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "He wants a new coffee machine", "source": "voice_transcription"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        assert resp.json()["source"] == "voice_transcription"
        print("  source='voice_transcription' accepted")

    def test_submit_hint_default_source(self, client, test_auth_user_with_vault):
        """When source is omitted, it should default to 'text_input'."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "She mentioned a spa day"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        assert resp.json()["source"] == "text_input"
        print("  Default source is 'text_input'")

    def test_submit_exactly_500_chars(self, client, test_auth_user_with_vault):
        """A hint of exactly 500 characters should be accepted."""
        hint_text = "x" * 500
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": hint_text, "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        assert len(resp.json()["hint_text"]) == 500
        print("  500-character hint accepted (boundary)")

    def test_hint_stored_in_database(self, client, test_auth_user_with_vault):
        """The hint should be queryable from the database after creation."""
        vault_id = test_auth_user_with_vault["vault_id"]

        # Clean up any existing hints
        _delete_hints(vault_id)

        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "She wants a pottery class", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        # Query directly via PostgREST
        hints = _query_hints(vault_id)
        assert len(hints) >= 1, "Hint not found in database"

        hint = next(h for h in hints if h["id"] == hint_id)
        assert hint["hint_text"] == "She wants a pottery class"
        assert hint["source"] == "text_input"
        assert hint["is_used"] is False
        print(f"  Hint stored in database: id={hint_id[:8]}...")

    def test_multiple_hints_stored(self, client, test_auth_user_with_vault):
        """Multiple hints should all be stored independently."""
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        hints_to_create = [
            "She mentioned wanting a new book",
            "He said he'd love to try surfing",
            "She liked that restaurant we passed",
        ]

        for hint_text in hints_to_create:
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": hint_text, "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )
            assert resp.status_code == 201

        hints = _query_hints(vault_id)
        assert len(hints) >= 3, f"Expected at least 3 hints, got {len(hints)}"
        print(f"  {len(hints)} hints stored independently")


# ===================================================================
# 2. Embedding generation and storage
# ===================================================================

@requires_supabase
@requires_vertex_ai
class TestEmbeddingGeneration:
    """
    Verify that Vertex AI embeddings are generated and stored.

    These tests ONLY run when GOOGLE_CLOUD_PROJECT is configured
    with valid GCP credentials.
    """

    def test_hint_has_embedding(self, client, test_auth_user_with_vault):
        """
        Submit a hint and confirm the database has a non-NULL hint_embedding.
        This is the core Step 4.4 verification.
        """
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        resp = client.post(
            "/api/v1/hints",
            json={
                "hint_text": "She really wants a spa day for her birthday",
                "source": "text_input",
            },
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        hints = _query_hints(vault_id)
        hint = next(h for h in hints if h["id"] == hint_id)

        assert hint["hint_embedding"] is not None, (
            "hint_embedding should NOT be NULL when Vertex AI is configured. "
            "Check GOOGLE_CLOUD_PROJECT and GCP credentials."
        )
        assert hint["hint_text"] == "She really wants a spa day for her birthday"
        print(f"  hint_text AND hint_embedding both populated (id={hint_id[:8]}...)")

    def test_embedding_is_768_dimensions(self, client, test_auth_user_with_vault):
        """
        The stored embedding should be a 768-dimension vector
        (text-embedding-004 output dimension).
        """
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        resp = client.post(
            "/api/v1/hints",
            json={
                "hint_text": "He mentioned he wants new running shoes",
                "source": "text_input",
            },
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        hints = _query_hints(vault_id)
        hint = next(h for h in hints if h["id"] == hint_id)

        embedding = hint["hint_embedding"]
        assert embedding is not None, "Embedding should not be NULL"

        # pgvector returns the embedding as a string "[0.1,0.2,...,0.768]"
        # Parse it to verify dimension count
        if isinstance(embedding, str):
            # Remove brackets and split by comma
            values = embedding.strip("[]").split(",")
            dimension = len(values)
        elif isinstance(embedding, list):
            dimension = len(embedding)
        else:
            pytest.fail(f"Unexpected embedding type: {type(embedding)}")

        assert dimension == 768, (
            f"Expected 768-dimension vector, got {dimension}. "
            f"Model text-embedding-004 should always produce 768 dims."
        )
        print(f"  Embedding has {dimension} dimensions (768 expected)")

    def test_different_hints_have_different_embeddings(self, client, test_auth_user_with_vault):
        """Different hint texts should produce different embedding vectors."""
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        # Submit two very different hints
        resp1 = client.post(
            "/api/v1/hints",
            json={"hint_text": "She loves gardening and wants flower seeds", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp1.status_code == 201

        resp2 = client.post(
            "/api/v1/hints",
            json={"hint_text": "He wants a new gaming keyboard for his PC", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp2.status_code == 201

        hints = _query_hints(vault_id)
        assert len(hints) >= 2

        embeddings = [h["hint_embedding"] for h in hints if h["hint_embedding"] is not None]
        assert len(embeddings) >= 2, "Both hints should have embeddings"

        # Embeddings for different texts should differ
        assert embeddings[0] != embeddings[1], (
            "Different hint texts should produce different embeddings"
        )
        print("  Different hints produce different embeddings")

    def test_voice_transcription_gets_embedding(self, client, test_auth_user_with_vault):
        """Voice transcription hints should also get embeddings."""
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        resp = client.post(
            "/api/v1/hints",
            json={
                "hint_text": "She said she wants to visit Japan",
                "source": "voice_transcription",
            },
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        hints = _query_hints(vault_id)
        hint = next(h for h in hints if h["id"] == hint_id)

        assert hint["hint_embedding"] is not None, (
            "Voice transcription hints should also get embeddings"
        )
        print("  Voice transcription hint has embedding")


# ===================================================================
# 3. Graceful degradation (embedding service mocked as unavailable)
# ===================================================================

@requires_supabase
class TestGracefulDegradation:
    """
    Verify hints are saved even when embedding generation fails.

    Mocks the embedding service to simulate Vertex AI being unavailable.
    The hint should still be saved with a NULL embedding.
    """

    def test_hint_saved_without_embedding_when_vertex_ai_unavailable(
        self, client, test_auth_user_with_vault
    ):
        """
        When Vertex AI is unavailable, the hint should still be saved
        with hint_embedding = NULL.
        """
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        # Mock the embedding service to return None (simulates Vertex AI failure)
        with patch(
            "app.api.hints.generate_embedding",
            new_callable=AsyncMock,
            return_value=None,
        ):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "She wants a cooking class", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201, (
            f"Hint should still be created even without embedding. "
            f"Got {resp.status_code}: {resp.text}"
        )

        # Verify hint is in the database with NULL embedding
        hints = _query_hints(vault_id)
        assert len(hints) >= 1
        hint = hints[0]  # newest first
        assert hint["hint_text"] == "She wants a cooking class"
        assert hint["hint_embedding"] is None, (
            "hint_embedding should be NULL when Vertex AI is unavailable"
        )
        print("  Hint saved with NULL embedding (graceful degradation)")

    def test_201_response_unchanged_without_embedding(
        self, client, test_auth_user_with_vault
    ):
        """
        The API response should be the same whether or not an embedding
        was generated — the response doesn't include the embedding.
        """
        with patch(
            "app.api.hints.generate_embedding",
            new_callable=AsyncMock,
            return_value=None,
        ):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "He wants new headphones", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201
        data = resp.json()
        assert "id" in data
        assert data["hint_text"] == "He wants new headphones"
        assert data["source"] == "text_input"
        assert data["is_used"] is False
        assert "created_at" in data
        print("  Response structure unchanged without embedding")


# ===================================================================
# 4. Validation errors — 422 responses
# ===================================================================

@requires_supabase
class TestValidationErrors:
    """Verify POST /api/v1/hints rejects invalid payloads."""

    def test_empty_hint_text_returns_422(self, client, test_auth_user_with_vault):
        """An empty hint text should return 422."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for empty hint, got {resp.status_code}: {resp.text}"
        )
        print("  Empty hint_text → 422")

    def test_whitespace_only_hint_returns_422(self, client, test_auth_user_with_vault):
        """A hint containing only whitespace should return 422."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "   \t\n  ", "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for whitespace-only hint, got {resp.status_code}"
        )
        print("  Whitespace-only hint_text → 422")

    def test_501_chars_returns_422(self, client, test_auth_user_with_vault):
        """A 501-character hint should return 422 with 'Hint too long'."""
        hint_text = "x" * 501
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": hint_text, "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for 501-char hint, got {resp.status_code}: {resp.text}"
        )

        # Verify the error message mentions the hint being too long
        detail = resp.json().get("detail", "")
        detail_str = str(detail).lower()
        assert "hint too long" in detail_str or "500" in detail_str, (
            f"Error should mention hint length limit. Got: {detail}"
        )
        print("  501-character hint → 422 with 'Hint too long'")

    def test_1000_chars_returns_422(self, client, test_auth_user_with_vault):
        """A 1000-character hint should return 422."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "a" * 1000, "source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422
        print("  1000-character hint → 422")

    def test_missing_hint_text_returns_422(self, client, test_auth_user_with_vault):
        """A payload without hint_text should return 422."""
        resp = client.post(
            "/api/v1/hints",
            json={"source": "text_input"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for missing hint_text, got {resp.status_code}"
        )
        print("  Missing hint_text → 422")

    def test_invalid_source_returns_422(self, client, test_auth_user_with_vault):
        """An invalid source value should return 422."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "A valid hint", "source": "telepathy"},
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert resp.status_code == 422, (
            f"Expected 422 for invalid source, got {resp.status_code}"
        )
        print("  Invalid source 'telepathy' → 422")


# ===================================================================
# 5. Authentication — 401 responses
# ===================================================================

@requires_supabase
class TestAuthRequired:
    """Verify POST /api/v1/hints requires authentication."""

    def test_no_token_returns_401(self, client):
        """A request with no auth token should return 401."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "Some hint", "source": "text_input"},
        )
        assert resp.status_code == 401, (
            f"Expected 401 with no token, got {resp.status_code}"
        )
        print("  No auth token → 401")

    def test_invalid_token_returns_401(self, client):
        """A request with an invalid token should return 401."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "Some hint", "source": "text_input"},
            headers={"Authorization": "Bearer invalid-token-12345"},
        )
        assert resp.status_code == 401, (
            f"Expected 401 with invalid token, got {resp.status_code}"
        )
        print("  Invalid token → 401")

    def test_malformed_auth_header_returns_401(self, client):
        """A malformed Authorization header should return 401."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "Some hint", "source": "text_input"},
            headers={"Authorization": "NotBearer token"},
        )
        assert resp.status_code == 401, (
            f"Expected 401 with malformed header, got {resp.status_code}"
        )
        print("  Malformed auth header → 401")


# ===================================================================
# 6. No vault — 404 response
# ===================================================================

@requires_supabase
class TestNoVault:
    """Verify POST /api/v1/hints returns 404 when user has no vault."""

    def test_no_vault_returns_404(self, client, test_auth_user_no_vault):
        """A user without a vault should get 404."""
        resp = client.post(
            "/api/v1/hints",
            json={"hint_text": "Some hint text", "source": "text_input"},
            headers=_auth_headers(test_auth_user_no_vault["access_token"]),
        )
        assert resp.status_code == 404, (
            f"Expected 404 for user without vault, got {resp.status_code}: {resp.text}"
        )
        detail = resp.json().get("detail", "")
        assert "vault" in detail.lower(), (
            f"Error should mention missing vault. Got: {detail}"
        )
        print("  No vault → 404 with 'vault' in message")


# ===================================================================
# 7. Embedding with mocked Vertex AI (always runs)
# ===================================================================

@requires_supabase
class TestEmbeddingWithMock:
    """
    Test embedding integration using mocked Vertex AI.
    These tests always run (no GCP credentials required).
    """

    def test_embedding_stored_in_database_when_available(
        self, client, test_auth_user_with_vault
    ):
        """
        When the embedding service returns a vector, it should be stored
        in the hint_embedding column.
        """
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        # Create a fake 768-dim embedding
        fake_embedding = [0.1 * (i % 10) for i in range(768)]

        with patch(
            "app.api.hints.generate_embedding",
            new_callable=AsyncMock,
            return_value=fake_embedding,
        ):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "She wants concert tickets", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        # Verify embedding is stored in the database
        hints = _query_hints(vault_id)
        hint = next(h for h in hints if h["id"] == hint_id)

        assert hint["hint_embedding"] is not None, (
            "hint_embedding should be stored when embedding service returns a vector"
        )
        print("  Mocked embedding stored in database")

    def test_embedding_has_correct_dimensions_in_db(
        self, client, test_auth_user_with_vault
    ):
        """Verify the stored embedding has exactly 768 dimensions."""
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        fake_embedding = [float(i) / 768.0 for i in range(768)]

        with patch(
            "app.api.hints.generate_embedding",
            new_callable=AsyncMock,
            return_value=fake_embedding,
        ):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "He wants a watch", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201
        hint_id = resp.json()["id"]

        hints = _query_hints(vault_id)
        hint = next(h for h in hints if h["id"] == hint_id)
        embedding = hint["hint_embedding"]

        assert embedding is not None

        # Parse pgvector string to verify dimensions
        if isinstance(embedding, str):
            values = embedding.strip("[]").split(",")
            assert len(values) == 768, (
                f"Expected 768 dimensions, got {len(values)}"
            )
        print("  Stored embedding has 768 dimensions")

    def test_generate_embedding_called_with_hint_text(
        self, client, test_auth_user_with_vault
    ):
        """The embedding service should be called with the exact hint text."""
        mock_embedding = AsyncMock(return_value=[0.0] * 768)

        with patch("app.api.hints.generate_embedding", mock_embedding):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "She wants a spa day", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201
        mock_embedding.assert_called_once_with("She wants a spa day")
        print("  generate_embedding() called with exact hint text")

    def test_stripped_text_used_for_embedding(
        self, client, test_auth_user_with_vault
    ):
        """Hint text is stripped before embedding (Pydantic validator)."""
        mock_embedding = AsyncMock(return_value=[0.0] * 768)

        with patch("app.api.hints.generate_embedding", mock_embedding):
            resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "  She wants flowers  ", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )

        assert resp.status_code == 201
        # Pydantic strips whitespace, so the embedding should receive stripped text
        mock_embedding.assert_called_once_with("She wants flowers")
        print("  Stripped text passed to embedding service")


# ===================================================================
# 8. Unit tests for embedding utilities
# ===================================================================

class TestEmbeddingUtilities:
    """Unit tests for the embedding service helper functions."""

    def test_format_embedding_for_pgvector(self):
        """format_embedding_for_pgvector should produce a valid pgvector string."""
        from app.services.embedding import format_embedding_for_pgvector

        embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
        result = format_embedding_for_pgvector(embedding)

        assert result.startswith("["), "Should start with ["
        assert result.endswith("]"), "Should end with ]"
        assert "0.1" in result
        assert "0.5" in result

        # Parse back and verify
        values = result.strip("[]").split(",")
        assert len(values) == 5
        assert float(values[0]) == 0.1
        assert float(values[4]) == 0.5
        print("  format_embedding_for_pgvector produces valid pgvector string")

    def test_format_768_dim_embedding(self):
        """A 768-dimension embedding should format correctly."""
        from app.services.embedding import format_embedding_for_pgvector

        embedding = [float(i) / 768.0 for i in range(768)]
        result = format_embedding_for_pgvector(embedding)

        values = result.strip("[]").split(",")
        assert len(values) == 768, f"Expected 768 values, got {len(values)}"
        print("  768-dimension embedding formats correctly")

    def test_format_empty_embedding(self):
        """An empty list should produce '[]'."""
        from app.services.embedding import format_embedding_for_pgvector

        result = format_embedding_for_pgvector([])
        assert result == "[]"
        print("  Empty embedding formats as '[]'")

    def test_embedding_constants(self):
        """Verify embedding service constants match the implementation plan."""
        from app.services.embedding import EMBEDDING_DIMENSION, EMBEDDING_MODEL_NAME

        assert EMBEDDING_DIMENSION == 768, (
            f"Expected 768-dim embedding (text-embedding-004), got {EMBEDDING_DIMENSION}"
        )
        assert EMBEDDING_MODEL_NAME == "text-embedding-004", (
            f"Expected text-embedding-004, got {EMBEDDING_MODEL_NAME}"
        )
        print("  Constants: 768 dimensions, text-embedding-004")

    def test_reset_model_clears_state(self):
        """_reset_model should clear the cached model state."""
        from app.services.embedding import _reset_model, _initialized, _model

        _reset_model()
        from app.services import embedding as emb
        assert emb._initialized is False
        assert emb._model is None
        print("  _reset_model clears cached state")


# ===================================================================
# 9. GET /api/v1/hints still works after embedding changes
# ===================================================================

@requires_supabase
class TestHintListAfterEmbedding:
    """Verify GET /api/v1/hints works correctly alongside embedding storage."""

    def test_list_hints_excludes_embedding(self, client, test_auth_user_with_vault):
        """
        GET /api/v1/hints should NOT return the hint_embedding field
        (it's large and not needed for display).
        """
        # Create a hint (with or without embedding)
        with patch(
            "app.api.hints.generate_embedding",
            new_callable=AsyncMock,
            return_value=[0.0] * 768,
        ):
            create_resp = client.post(
                "/api/v1/hints",
                json={"hint_text": "Test hint for listing", "source": "text_input"},
                headers=_auth_headers(test_auth_user_with_vault["access_token"]),
            )
        assert create_resp.status_code == 201

        # List hints
        list_resp = client.get(
            "/api/v1/hints",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert list_resp.status_code == 200
        data = list_resp.json()

        assert "hints" in data
        assert "total" in data
        assert len(data["hints"]) >= 1

        # Verify hint_embedding is NOT in the response
        hint = data["hints"][0]
        assert "hint_embedding" not in hint, (
            "hint_embedding should NOT be in the list response"
        )
        assert "hint_text" in hint
        assert "source" in hint
        print("  GET /api/v1/hints excludes hint_embedding from response")

    def test_list_hints_returns_correct_count(self, client, test_auth_user_with_vault):
        """Total count should include all hints regardless of embedding status."""
        vault_id = test_auth_user_with_vault["vault_id"]
        _delete_hints(vault_id)

        # Create hints — some with embedding, some without
        for i in range(3):
            mock_return = [0.0] * 768 if i % 2 == 0 else None
            with patch(
                "app.api.hints.generate_embedding",
                new_callable=AsyncMock,
                return_value=mock_return,
            ):
                resp = client.post(
                    "/api/v1/hints",
                    json={"hint_text": f"Hint number {i + 1}", "source": "text_input"},
                    headers=_auth_headers(test_auth_user_with_vault["access_token"]),
                )
                assert resp.status_code == 201

        list_resp = client.get(
            "/api/v1/hints?limit=50",
            headers=_auth_headers(test_auth_user_with_vault["access_token"]),
        )
        assert list_resp.status_code == 200
        data = list_resp.json()
        assert data["total"] >= 3
        print(f"  Total count includes all hints: {data['total']}")
