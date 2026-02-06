"""
Step 1.8 Verification: Hints Table with Vector Embedding

Tests that:
1. The hints table exists and is accessible via PostgREST
2. The table has the correct columns (id, vault_id, hint_text, hint_embedding, source, created_at, is_used)
3. source CHECK constraint enforces 'text_input' and 'voice_transcription' only
4. hint_embedding accepts 768-dimension vectors and NULL
5. is_used defaults to false
6. Row Level Security (RLS) blocks anonymous access
7. Service client (admin) can read all rows (bypasses RLS)
8. CASCADE delete removes hints when vault is deleted
9. Full CASCADE chain: auth.users → users → partner_vaults → hints
10. Foreign key to partner_vaults is enforced
11. match_hints() RPC function returns results ordered by cosine similarity
12. Similarity search respects threshold parameter

Prerequisites:
- Complete Steps 0.6-1.2 (Supabase project + pgvector + users table + partner_vaults table)
- Run the migration in the Supabase SQL Editor:
    backend/supabase/migrations/00009_create_hints_table.sql

Run with: pytest tests/test_hints_table.py -v
"""

import pytest
import httpx
import uuid
import time

from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ---------------------------------------------------------------------------
# Helper: check if Supabase credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Helpers: HTTP headers for PostgREST and Admin API
# ---------------------------------------------------------------------------

def _service_headers() -> dict:
    """Headers for service-role (admin) PostgREST access. Bypasses RLS."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _anon_headers() -> dict:
    """Headers for anon (public) PostgREST access. No user JWT."""
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type": "application/json",
    }


def _admin_headers() -> dict:
    """Headers for Supabase Admin Auth API (user management)."""
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


# ---------------------------------------------------------------------------
# Helper: create and delete test auth users
# ---------------------------------------------------------------------------

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
                f"HTTP {resp.status_code} — {resp.text}. "
                "This user may be orphaned in auth.users.",
                stacklevel=2,
            )
    except Exception as exc:
        warnings.warn(
            f"Exception deleting test auth user {user_id}: {exc}. "
            "This user may be orphaned in auth.users.",
            stacklevel=2,
        )


# ---------------------------------------------------------------------------
# Helpers: insert/delete vault and hint rows via service client
# ---------------------------------------------------------------------------

def _insert_vault(vault_data: dict) -> dict:
    """Insert a vault row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=vault_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert vault: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _delete_vault(vault_id: str):
    """Delete a vault row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        params={"id": f"eq.{vault_id}"},
    )


def _insert_hint(hint_data: dict) -> dict:
    """Insert a hint row via service client (bypasses RLS). Returns the row."""
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/hints",
        headers=_service_headers(),
        json=hint_data,
    )
    assert resp.status_code in (200, 201), (
        f"Failed to insert hint: HTTP {resp.status_code} — {resp.text}"
    )
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_hint_raw(hint_data: dict) -> httpx.Response:
    """Insert a hint row and return the raw response (for testing failures)."""
    return httpx.post(
        f"{SUPABASE_URL}/rest/v1/hints",
        headers=_service_headers(),
        json=hint_data,
    )


def _delete_hint(hint_id: str):
    """Delete a hint row via service client."""
    httpx.delete(
        f"{SUPABASE_URL}/rest/v1/hints",
        headers=_service_headers(),
        params={"id": f"eq.{hint_id}"},
    )


# ---------------------------------------------------------------------------
# Helper: create a 768-dimension vector string for pgvector
# ---------------------------------------------------------------------------

def _make_vector(values: list[float], dim: int = 768) -> str:
    """
    Create a 768-dim vector string for pgvector, padding remaining
    positions with zeros.

    Example: _make_vector([1.0, 0.5]) → "[1.0,0.5,0.0,0.0,...,0.0]"
    """
    padded = values + [0.0] * (dim - len(values))
    return "[" + ",".join(str(v) for v in padded[:dim]) + "]"


# ---------------------------------------------------------------------------
# Fixtures: test auth user, vault, and vault with hints
# ---------------------------------------------------------------------------

@pytest.fixture
def test_auth_user():
    """
    Create a test user in auth.users and yield its info.

    The handle_new_user trigger auto-creates a row in public.users.
    Cleanup deletes the auth user (CASCADE removes public.users,
    partner_vaults, and hints rows).
    """
    test_email = f"knot-hint-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_id = _create_auth_user(test_email, test_password)

    # Give the trigger a moment to fire
    time.sleep(0.5)

    yield {"id": user_id, "email": test_email}

    # Cleanup: delete auth user (CASCADE deletes everything)
    _delete_auth_user(user_id)


@pytest.fixture
def test_auth_user_pair():
    """
    Create TWO test users for testing RLS isolation between users.
    Yields a tuple of (user_a_info, user_b_info).
    """
    email_a = f"knot-hintA-{uuid.uuid4().hex[:8]}@test.example"
    email_b = f"knot-hintB-{uuid.uuid4().hex[:8]}@test.example"
    password = f"TestPass!{uuid.uuid4().hex[:12]}"

    user_a_id = _create_auth_user(email_a, password)
    user_b_id = _create_auth_user(email_b, password)

    time.sleep(0.5)

    yield (
        {"id": user_a_id, "email": email_a},
        {"id": user_b_id, "email": email_b},
    )

    _delete_auth_user(user_a_id)
    _delete_auth_user(user_b_id)


@pytest.fixture
def test_vault(test_auth_user):
    """
    Create a test vault for the test user and yield both user and vault info.
    Vault is auto-cleaned when the auth user is deleted (CASCADE).
    """
    user_id = test_auth_user["id"]
    vault_data = {
        "user_id": user_id,
        "partner_name": "Hints Test Partner",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
    }
    vault_row = _insert_vault(vault_data)

    yield {
        "user": test_auth_user,
        "vault": vault_row,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_hints(test_vault):
    """
    Create a vault with 3 hints pre-populated:
    - "She mentioned wanting a new yoga mat" (text_input)
    - "He really liked that Italian restaurant downtown" (text_input)
    - "Said she's been wanting to try pottery classes" (voice_transcription)

    Hints are inserted WITHOUT embeddings (embedding is nullable).
    Yields user, vault, and hints info.
    All cleaned up via CASCADE when auth user is deleted.
    """
    vault_id = test_vault["vault"]["id"]
    hints = []

    hint_entries = [
        {
            "hint_text": "She mentioned wanting a new yoga mat",
            "source": "text_input",
        },
        {
            "hint_text": "He really liked that Italian restaurant downtown",
            "source": "text_input",
        },
        {
            "hint_text": "Said she's been wanting to try pottery classes",
            "source": "voice_transcription",
        },
    ]

    for entry in hint_entries:
        row = _insert_hint({
            "vault_id": vault_id,
            **entry,
        })
        hints.append(row)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "hints": hints,
    }
    # No explicit cleanup — CASCADE handles it


@pytest.fixture
def test_vault_with_embedded_hints(test_vault):
    """
    Create a vault with 3 hints that have vector embeddings.

    Uses carefully crafted 768-dim vectors for testing similarity search:
    - Hint A: vector dominated by position 0  → [1.0, 0.0, 0.0, ...]
    - Hint B: vector with mix of pos 0 and 1  → [0.7, 0.7, 0.0, ...]
    - Hint C: vector dominated by position 1  → [0.1, 0.9, 0.0, ...]

    When querying with [1.0, 0.0, ...], expected similarity order: A > B > C

    Cosine similarities to query [1.0, 0, ...]:
      - A: cos = 1.0 / (1.0 * 1.0) = 1.0
      - B: cos = 0.7 / (1.0 * sqrt(0.98)) ≈ 0.707
      - C: cos = 0.1 / (1.0 * sqrt(0.82)) ≈ 0.110
    """
    vault_id = test_vault["vault"]["id"]
    hints = []

    hint_entries = [
        {
            "hint_text": "She loves gardening and wants new tools",
            "source": "text_input",
            "hint_embedding": _make_vector([1.0]),
        },
        {
            "hint_text": "He mentioned enjoying cooking shows lately",
            "source": "text_input",
            "hint_embedding": _make_vector([0.7, 0.7]),
        },
        {
            "hint_text": "She said she wants to go to a spa",
            "source": "voice_transcription",
            "hint_embedding": _make_vector([0.1, 0.9]),
        },
    ]

    for entry in hint_entries:
        row = _insert_hint({
            "vault_id": vault_id,
            **entry,
        })
        hints.append(row)

    yield {
        "user": test_vault["user"],
        "vault": test_vault["vault"],
        "hints": hints,
    }
    # No explicit cleanup — CASCADE handles it


# ===================================================================
# 1. Table existence
# ===================================================================

@requires_supabase
class TestHintsTableExists:
    """Verify the hints table exists and is accessible via PostgREST."""

    def test_table_is_accessible(self):
        """
        The hints table should exist in the public schema and be
        accessible via the PostgREST API.

        If this fails, run the migration:
            backend/supabase/migrations/00009_create_hints_table.sql
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"select": "*", "limit": "0"},
        )
        assert resp.status_code == 200, (
            f"hints table not accessible (HTTP {resp.status_code}). "
            "Run the migration at: "
            "backend/supabase/migrations/00009_create_hints_table.sql "
            "in the Supabase SQL Editor."
        )
        print("  hints table exists and is accessible via PostgREST")


# ===================================================================
# 2. Schema verification
# ===================================================================

@requires_supabase
class TestHintsSchema:
    """Verify the hints table has the correct columns, types, and constraints."""

    def test_columns_exist(self, test_vault_with_hints):
        """
        The hints table should have exactly these columns:
        id, vault_id, hint_text, hint_embedding, source, created_at, is_used.
        """
        vault_id = test_vault_with_hints["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1, "No hint rows found"

        row = rows[0]
        expected_columns = {
            "id", "vault_id", "hint_text", "hint_embedding",
            "source", "created_at", "is_used",
        }
        actual_columns = set(row.keys())
        assert expected_columns.issubset(actual_columns), (
            f"Missing columns: {expected_columns - actual_columns}. "
            f"Found: {sorted(actual_columns)}"
        )
        print(f"  All columns present: {sorted(actual_columns)}")

    def test_id_is_auto_generated_uuid(self, test_vault_with_hints):
        """The id column should be an auto-generated valid UUID."""
        hint_id = test_vault_with_hints["hints"][0]["id"]
        parsed = uuid.UUID(hint_id)
        assert str(parsed) == hint_id
        print(f"  id is auto-generated UUID: {hint_id[:8]}...")

    def test_created_at_auto_populated(self, test_vault_with_hints):
        """created_at should be automatically populated with a timestamp."""
        vault_id = test_vault_with_hints["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "created_at", "limit": "1"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) >= 1
        assert rows[0]["created_at"] is not None, (
            "created_at should be auto-populated with DEFAULT now()"
        )
        print(f"  created_at auto-populated: {rows[0]['created_at']}")

    def test_source_check_constraint_rejects_invalid(self, test_vault):
        """
        source must be 'text_input' or 'voice_transcription'.
        Invalid values should be rejected by the CHECK constraint.
        """
        vault_id = test_vault["vault"]["id"]

        resp = _insert_hint_raw({
            "vault_id": vault_id,
            "hint_text": "Test hint",
            "source": "siri_dictation",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for invalid source 'siri_dictation', "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  source CHECK constraint rejects invalid value 'siri_dictation'")

    def test_source_accepts_text_input(self, test_vault):
        """source 'text_input' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "She wants a new book",
            "source": "text_input",
        })
        try:
            assert row["source"] == "text_input"
            print("  source 'text_input' accepted")
        finally:
            _delete_hint(row["id"])

    def test_source_accepts_voice_transcription(self, test_vault):
        """source 'voice_transcription' should be accepted."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "He mentioned wanting a new guitar",
            "source": "voice_transcription",
        })
        try:
            assert row["source"] == "voice_transcription"
            print("  source 'voice_transcription' accepted")
        finally:
            _delete_hint(row["id"])

    def test_hint_text_not_null(self, test_vault):
        """hint_text is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_hint_raw({
            "vault_id": vault_id,
            # hint_text intentionally omitted
            "source": "text_input",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing hint_text, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  hint_text NOT NULL constraint enforced")

    def test_source_not_null(self, test_vault):
        """source is NOT NULL — inserting without it should fail."""
        vault_id = test_vault["vault"]["id"]

        resp = _insert_hint_raw({
            "vault_id": vault_id,
            "hint_text": "Test hint",
            # source intentionally omitted
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for missing source, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  source NOT NULL constraint enforced")

    def test_is_used_defaults_to_false(self, test_vault):
        """is_used should default to false when not provided."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "She likes the color blue",
            "source": "text_input",
            # is_used intentionally omitted — should default to false
        })
        try:
            assert row["is_used"] is False, (
                f"is_used should default to false, got {row['is_used']}"
            )
            print("  is_used defaults to false")
        finally:
            _delete_hint(row["id"])

    def test_hint_embedding_nullable(self, test_vault):
        """
        hint_embedding is nullable — a hint can be stored without an embedding
        (e.g., if embedding generation fails or is pending).
        """
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "She wants a spa day",
            "source": "text_input",
            # hint_embedding intentionally omitted
        })
        try:
            assert row["hint_embedding"] is None, (
                f"hint_embedding should be NULL when not provided, "
                f"got {type(row['hint_embedding'])}"
            )
            print("  hint_embedding is nullable (NULL when not provided)")
        finally:
            _delete_hint(row["id"])

    def test_hint_embedding_accepts_768_dim_vector(self, test_vault):
        """hint_embedding should accept a valid 768-dimension vector."""
        vault_id = test_vault["vault"]["id"]

        embedding = _make_vector([0.1, 0.2, 0.3, 0.4, 0.5])
        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "He wants a new watch",
            "source": "text_input",
            "hint_embedding": embedding,
        })
        try:
            assert row["hint_embedding"] is not None, (
                "hint_embedding should be stored when provided"
            )
            print("  hint_embedding accepts 768-dimension vector")
        finally:
            _delete_hint(row["id"])


# ===================================================================
# 3. Row Level Security (RLS)
# ===================================================================

@requires_supabase
class TestHintsRLS:
    """Verify Row Level Security is configured correctly."""

    def test_anon_client_cannot_read_hints(self, test_vault_with_hints):
        """
        The anon client (no user JWT) should not see any hints.
        With RLS enabled, auth.uid() is NULL for the anon key.
        """
        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_anon_headers(),
            params={"select": "*"},
        )
        assert resp.status_code == 200, (
            f"Unexpected status: HTTP {resp.status_code}. "
            "Expected 200 with empty results."
        )
        rows = resp.json()
        assert len(rows) == 0, (
            f"Anon client can see {len(rows)} hint(s)! "
            "RLS is not properly configured. Ensure the migration includes: "
            "ALTER TABLE public.hints ENABLE ROW LEVEL SECURITY;"
        )
        print("  Anon client (no JWT): 0 hints visible — RLS enforced")

    def test_service_client_can_read_hints(self, test_vault_with_hints):
        """
        The service client (bypasses RLS) should see the test hints.
        """
        vault_id = test_vault_with_hints["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "*"},
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, (
            f"Service client should see 3 hints, got {len(rows)} rows."
        )
        print(f"  Service client: found {len(rows)} hints — RLS bypassed")

    def test_user_isolation_between_hints(self, test_auth_user_pair):
        """
        Two different users should not be able to see each other's hints.
        Using service client to verify data isolation.
        """
        user_a, user_b = test_auth_user_pair

        # Create vaults for both users
        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "User A's Partner",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "User B's Partner",
        })

        # Add hints to both vaults
        hint_a = _insert_hint({
            "vault_id": vault_a["id"],
            "hint_text": "User A's partner hint",
            "source": "text_input",
        })
        hint_b = _insert_hint({
            "vault_id": vault_b["id"],
            "hint_text": "User B's partner hint",
            "source": "text_input",
        })

        try:
            # Query hints for vault A — should only return vault A's data
            resp_a = httpx.get(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_a['id']}", "select": "*"},
            )
            assert resp_a.status_code == 200
            rows_a = resp_a.json()
            assert len(rows_a) == 1
            assert rows_a[0]["hint_text"] == "User A's partner hint"

            # Query hints for vault B — should only return vault B's data
            resp_b = httpx.get(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"vault_id": f"eq.{vault_b['id']}", "select": "*"},
            )
            assert resp_b.status_code == 200
            rows_b = resp_b.json()
            assert len(rows_b) == 1
            assert rows_b[0]["hint_text"] == "User B's partner hint"

            print("  User isolation verified: each vault sees only its own hints")
        finally:
            _delete_hint(hint_a["id"])
            _delete_hint(hint_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])


# ===================================================================
# 4. Data integrity: hints stored correctly
# ===================================================================

@requires_supabase
class TestHintsDataIntegrity:
    """Verify hints are stored with correct data across all fields."""

    def test_multiple_hints_per_vault(self, test_vault_with_hints):
        """A vault can have multiple hints (no cardinality limit at DB level)."""
        vault_id = test_vault_with_hints["vault"]["id"]

        resp = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={
                "vault_id": f"eq.{vault_id}",
                "select": "*",
                "order": "created_at.asc",
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 hints, got {len(rows)}"
        print(f"  Multiple hints per vault: {len(rows)} hints stored correctly")

    def test_hint_field_values(self, test_vault_with_hints):
        """Verify hint rows have correct vault_id and are non-empty."""
        vault_id = test_vault_with_hints["vault"]["id"]
        hints = test_vault_with_hints["hints"]

        for hint in hints:
            assert hint["vault_id"] == vault_id, (
                f"Hint {hint['id']} has wrong vault_id: "
                f"expected {vault_id}, got {hint['vault_id']}"
            )
            assert hint["hint_text"] is not None and len(hint["hint_text"]) > 0

        print("  Hint field values verified (vault_id, hint_text)")

    def test_mixed_sources(self, test_vault_with_hints):
        """Hints with different sources should be stored correctly."""
        hints = test_vault_with_hints["hints"]

        sources = {h["source"] for h in hints}
        assert "text_input" in sources, "Expected at least one text_input hint"
        assert "voice_transcription" in sources, (
            "Expected at least one voice_transcription hint"
        )
        print("  Mixed sources stored: text_input and voice_transcription")

    def test_is_used_can_be_updated(self, test_vault):
        """is_used can be updated from false to true (marks hint as used in recommendation)."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "She wants new hiking boots",
            "source": "text_input",
        })

        try:
            # Verify initial value
            assert row["is_used"] is False

            # Update to true
            update_resp = httpx.patch(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"id": f"eq.{row['id']}"},
                json={"is_used": True},
            )
            assert update_resp.status_code == 200

            # Verify update
            check = httpx.get(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"id": f"eq.{row['id']}", "select": "is_used"},
            )
            assert check.status_code == 200
            rows = check.json()
            assert len(rows) == 1
            assert rows[0]["is_used"] is True
            print("  is_used updated from false to true successfully")
        finally:
            _delete_hint(row["id"])

    def test_hint_without_embedding_stored(self, test_vault):
        """A hint can be stored without an embedding (embedding is nullable)."""
        vault_id = test_vault["vault"]["id"]

        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "She loves sunflowers",
            "source": "text_input",
        })

        try:
            assert row["hint_embedding"] is None
            assert row["hint_text"] == "She loves sunflowers"
            assert row["source"] == "text_input"
            print("  Hint stored without embedding (nullable)")
        finally:
            _delete_hint(row["id"])

    def test_hint_with_embedding_stored(self, test_vault):
        """A hint stored with an embedding should persist the vector."""
        vault_id = test_vault["vault"]["id"]

        embedding = _make_vector([0.5, 0.3, 0.8, 0.1])
        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "He wants a coffee subscription",
            "source": "text_input",
            "hint_embedding": embedding,
        })

        try:
            assert row["hint_embedding"] is not None
            assert row["hint_text"] == "He wants a coffee subscription"
            print("  Hint stored with embedding vector (768-dim)")
        finally:
            _delete_hint(row["id"])


# ===================================================================
# 5. Vector similarity search via match_hints() RPC
# ===================================================================

@requires_supabase
class TestHintsVectorSearch:
    """Verify the match_hints() RPC function for semantic similarity search."""

    def test_similarity_search_returns_results(self, test_vault_with_embedded_hints):
        """
        match_hints() should return hints with embeddings, ordered by similarity.
        """
        vault_id = test_vault_with_embedded_hints["vault"]["id"]

        # Query with a vector similar to Hint A [1.0, 0, 0, ...]
        query_vector = _make_vector([1.0])

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
            headers=_service_headers(),
            json={
                "query_embedding": query_vector,
                "query_vault_id": vault_id,
                "match_threshold": 0.0,
                "match_count": 10,
            },
        )
        assert resp.status_code == 200, (
            f"match_hints RPC failed: HTTP {resp.status_code} — {resp.text}. "
            "Ensure the migration creates the match_hints() function."
        )
        rows = resp.json()
        assert len(rows) >= 1, (
            "match_hints should return at least 1 result"
        )
        print(f"  match_hints returned {len(rows)} results")

    def test_similarity_search_ordered_by_similarity(self, test_vault_with_embedded_hints):
        """
        Results should be ordered by cosine similarity (most similar first).

        Hints:
          A: [1.0, 0, ...] → similarity to [1, 0, ...] = 1.0
          B: [0.7, 0.7, ...] → similarity to [1, 0, ...] ≈ 0.707
          C: [0.1, 0.9, ...] → similarity to [1, 0, ...] ≈ 0.110

        Expected order: A, B, C
        """
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_vector = _make_vector([1.0])

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
            headers=_service_headers(),
            json={
                "query_embedding": query_vector,
                "query_vault_id": vault_id,
                "match_threshold": 0.0,
                "match_count": 10,
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 3, f"Expected 3 results, got {len(rows)}"

        # Verify descending similarity order
        similarities = [r["similarity"] for r in rows]
        assert similarities == sorted(similarities, reverse=True), (
            f"Results not ordered by similarity. "
            f"Similarities: {similarities}"
        )

        # Verify specific ordering: A (gardening) > B (cooking) > C (spa)
        assert rows[0]["hint_text"] == "She loves gardening and wants new tools", (
            f"Most similar hint should be 'gardening' (vector [1,0,...]), "
            f"got: '{rows[0]['hint_text']}'"
        )
        assert rows[1]["hint_text"] == "He mentioned enjoying cooking shows lately", (
            f"Second most similar should be 'cooking' (vector [0.7,0.7,...]), "
            f"got: '{rows[1]['hint_text']}'"
        )
        assert rows[2]["hint_text"] == "She said she wants to go to a spa", (
            f"Least similar should be 'spa' (vector [0.1,0.9,...]), "
            f"got: '{rows[2]['hint_text']}'"
        )

        # Verify approximate similarity values
        assert rows[0]["similarity"] > 0.99, (
            f"Hint A should have similarity ~1.0, got {rows[0]['similarity']}"
        )
        assert 0.6 < rows[1]["similarity"] < 0.8, (
            f"Hint B should have similarity ~0.707, got {rows[1]['similarity']}"
        )
        assert 0.05 < rows[2]["similarity"] < 0.2, (
            f"Hint C should have similarity ~0.110, got {rows[2]['similarity']}"
        )

        print(
            f"  Similarity search ordered correctly: "
            f"{similarities[0]:.3f} > {similarities[1]:.3f} > {similarities[2]:.3f}"
        )

    def test_similarity_threshold_filters_results(self, test_vault_with_embedded_hints):
        """
        Setting match_threshold > 0 should filter out hints below that threshold.

        With threshold 0.5, only Hint A (~1.0) and Hint B (~0.707) should return.
        Hint C (~0.110) should be excluded.
        """
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_vector = _make_vector([1.0])

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
            headers=_service_headers(),
            json={
                "query_embedding": query_vector,
                "query_vault_id": vault_id,
                "match_threshold": 0.5,
                "match_count": 10,
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 2, (
            f"Expected 2 results above threshold 0.5, got {len(rows)}. "
            f"Similarities: {[r['similarity'] for r in rows]}"
        )

        # All returned results should be above threshold
        for row in rows:
            assert row["similarity"] >= 0.5, (
                f"Result below threshold: similarity={row['similarity']}"
            )
        print(f"  Threshold 0.5 filtered to {len(rows)} results (excluded low-similarity)")

    def test_similarity_search_match_count_limits_results(self, test_vault_with_embedded_hints):
        """match_count parameter should limit the number of returned results."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_vector = _make_vector([1.0])

        resp = httpx.post(
            f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
            headers=_service_headers(),
            json={
                "query_embedding": query_vector,
                "query_vault_id": vault_id,
                "match_threshold": 0.0,
                "match_count": 1,
            },
        )
        assert resp.status_code == 200
        rows = resp.json()
        assert len(rows) == 1, f"Expected 1 result with match_count=1, got {len(rows)}"
        assert rows[0]["hint_text"] == "She loves gardening and wants new tools", (
            "With match_count=1, the most similar hint should be returned"
        )
        print("  match_count=1 correctly limits to 1 result (most similar)")

    def test_similarity_search_scoped_to_vault(self, test_auth_user_pair):
        """
        match_hints() should only return hints belonging to the specified vault,
        not hints from other vaults.
        """
        user_a, user_b = test_auth_user_pair

        vault_a = _insert_vault({
            "user_id": user_a["id"],
            "partner_name": "Vault A",
        })
        vault_b = _insert_vault({
            "user_id": user_b["id"],
            "partner_name": "Vault B",
        })

        embedding = _make_vector([1.0])
        hint_a = _insert_hint({
            "vault_id": vault_a["id"],
            "hint_text": "Vault A hint",
            "source": "text_input",
            "hint_embedding": embedding,
        })
        hint_b = _insert_hint({
            "vault_id": vault_b["id"],
            "hint_text": "Vault B hint",
            "source": "text_input",
            "hint_embedding": embedding,
        })

        try:
            # Search within vault A only
            resp = httpx.post(
                f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
                headers=_service_headers(),
                json={
                    "query_embedding": embedding,
                    "query_vault_id": vault_a["id"],
                    "match_threshold": 0.0,
                    "match_count": 10,
                },
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 1, (
                f"Expected 1 result for vault A, got {len(rows)}"
            )
            assert rows[0]["hint_text"] == "Vault A hint"
            print("  Similarity search scoped to vault (other vault's hints excluded)")
        finally:
            _delete_hint(hint_a["id"])
            _delete_hint(hint_b["id"])
            _delete_vault(vault_a["id"])
            _delete_vault(vault_b["id"])

    def test_similarity_search_skips_hints_without_embedding(self, test_vault):
        """
        match_hints() should skip hints that have NULL embeddings.
        Only hints with actual embeddings should appear in results.
        """
        vault_id = test_vault["vault"]["id"]

        # Insert one hint WITH embedding, one WITHOUT
        hint_with = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "Hint with embedding",
            "source": "text_input",
            "hint_embedding": _make_vector([1.0]),
        })
        hint_without = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "Hint without embedding",
            "source": "text_input",
            # hint_embedding intentionally omitted
        })

        try:
            resp = httpx.post(
                f"{SUPABASE_URL}/rest/v1/rpc/match_hints",
                headers=_service_headers(),
                json={
                    "query_embedding": _make_vector([1.0]),
                    "query_vault_id": vault_id,
                    "match_threshold": 0.0,
                    "match_count": 10,
                },
            )
            assert resp.status_code == 200
            rows = resp.json()
            assert len(rows) == 1, (
                f"Expected 1 result (only hint with embedding), got {len(rows)}"
            )
            assert rows[0]["hint_text"] == "Hint with embedding"
            print("  Similarity search correctly skips hints without embeddings")
        finally:
            _delete_hint(hint_with["id"])
            _delete_hint(hint_without["id"])


# ===================================================================
# 6. Triggers and cascades
# ===================================================================

@requires_supabase
class TestHintsCascades:
    """Verify CASCADE delete behavior and foreign key constraints."""

    def test_cascade_delete_with_vault(self, test_auth_user):
        """
        When a vault is deleted, all its hints should be
        automatically removed via CASCADE.
        """
        user_id = test_auth_user["id"]

        # Create vault
        vault = _insert_vault({
            "user_id": user_id,
            "partner_name": "Cascade Hint Test",
        })
        vault_id = vault["id"]

        # Insert hints
        hint1 = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "Hint 1 for cascade test",
            "source": "text_input",
        })
        hint2 = _insert_hint({
            "vault_id": vault_id,
            "hint_text": "Hint 2 for cascade test",
            "source": "voice_transcription",
        })

        # Verify hints exist
        check1 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check1.status_code == 200
        assert len(check1.json()) == 2, "Hints should exist before vault deletion"

        # Delete the vault
        _delete_vault(vault_id)

        # Give CASCADE time to propagate
        time.sleep(0.3)

        # Verify hints are gone
        check2 = httpx.get(
            f"{SUPABASE_URL}/rest/v1/hints",
            headers=_service_headers(),
            params={"vault_id": f"eq.{vault_id}", "select": "id"},
        )
        assert check2.status_code == 200
        assert len(check2.json()) == 0, (
            "hints rows still exist after vault deletion. "
            "Check that vault_id has ON DELETE CASCADE."
        )
        print("  CASCADE delete verified: vault deletion removed hint rows")

    def test_cascade_delete_from_auth_user(self):
        """
        When an auth user is deleted, the full CASCADE chain should remove:
        auth.users → public.users → partner_vaults → hints.
        """
        # Create temp auth user
        temp_email = f"knot-hint-cascade-{uuid.uuid4().hex[:8]}@test.example"
        temp_password = f"CascadeHint!{uuid.uuid4().hex[:12]}"
        temp_user_id = _create_auth_user(temp_email, temp_password)

        try:
            time.sleep(0.5)

            # Create vault
            vault = _insert_vault({
                "user_id": temp_user_id,
                "partner_name": "Full Cascade Hint Test",
            })
            vault_id = vault["id"]

            # Add hint
            hint = _insert_hint({
                "vault_id": vault_id,
                "hint_text": "Cascade chain test hint",
                "source": "text_input",
            })
            hint_id = hint["id"]

            # Verify hint exists
            check1 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"id": f"eq.{hint_id}", "select": "id"},
            )
            assert len(check1.json()) == 1

            # Delete the auth user
            del_resp = httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{temp_user_id}",
                headers=_admin_headers(),
            )
            assert del_resp.status_code == 200

            time.sleep(0.5)

            # Verify hint is gone
            check2 = httpx.get(
                f"{SUPABASE_URL}/rest/v1/hints",
                headers=_service_headers(),
                params={"id": f"eq.{hint_id}", "select": "id"},
            )
            assert check2.status_code == 200
            assert len(check2.json()) == 0, (
                "Hint row still exists after auth user deletion. "
                "Check full CASCADE chain: auth.users → users → partner_vaults → hints"
            )
            print("  Full CASCADE delete verified: auth deletion removed hint rows")
        except Exception:
            _delete_auth_user(temp_user_id)
            raise

    def test_foreign_key_enforced_invalid_vault_id(self):
        """
        Inserting a hint with a non-existent vault_id should fail
        because of the foreign key constraint to partner_vaults.
        """
        fake_vault_id = str(uuid.uuid4())

        resp = _insert_hint_raw({
            "vault_id": fake_vault_id,
            "hint_text": "This should fail",
            "source": "text_input",
        })
        assert resp.status_code in (400, 409), (
            f"Expected 400/409 for non-existent vault_id FK, "
            f"got HTTP {resp.status_code}. Response: {resp.text}"
        )
        print("  Foreign key constraint enforced (non-existent vault_id rejected)")
