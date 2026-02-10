"""
Step 5.2 Verification: Hint Retrieval Node

Tests that the retrieve_relevant_hints LangGraph node:
1. Builds correct query text from milestone context and occasion type
2. Performs semantic search via match_hints() RPC when embeddings are available
3. Falls back to chronological hints when embedding generation is unavailable
4. Returns RelevantHint objects with correct fields
5. Respects vault scoping (only returns hints for the specified vault)
6. Handles empty results gracefully
7. Maps RPC response rows to RelevantHint models correctly

Test categories:
- Unit tests: _build_query_text (no external dependencies)
- Integration tests with mocked embeddings: retrieve_relevant_hints with
  crafted vectors in Supabase (no Vertex AI required)
- Integration tests: chronological fallback with real Supabase

Prerequisites:
- Complete Steps 0.6–1.8 (Supabase + pgvector + hints table + match_hints RPC)
- Backend .env configured with Supabase credentials

Run with: pytest tests/test_hint_retrieval_node.py -v
"""

import uuid
import time
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.agents.state import (
    BudgetRange,
    MilestoneContext,
    RecommendationState,
    RelevantHint,
    VaultBudget,
    VaultData,
)
from app.agents.hint_retrieval import (
    _build_query_text,
    _chronological_fallback,
    _semantic_search,
    retrieve_relevant_hints,
)
from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY


# ======================================================================
# Helpers: Supabase credentials check
# ======================================================================

def _supabase_configured() -> bool:
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ======================================================================
# Helpers: HTTP headers and DB operations
# ======================================================================

def _service_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def _admin_headers() -> dict:
    return {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }


def _create_auth_user(email: str, password: str) -> str:
    resp = httpx.post(
        f"{SUPABASE_URL}/auth/v1/admin/users",
        headers=_admin_headers(),
        json={"email": email, "password": password, "email_confirm": True},
    )
    assert resp.status_code == 200, f"Failed to create auth user: {resp.text}"
    return resp.json()["id"]


def _delete_auth_user(user_id: str):
    import warnings
    try:
        resp = httpx.delete(
            f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
            headers=_admin_headers(),
        )
        if resp.status_code != 200:
            warnings.warn(f"Failed to delete auth user {user_id}: {resp.text}", stacklevel=2)
    except Exception as exc:
        warnings.warn(f"Exception deleting auth user {user_id}: {exc}", stacklevel=2)


def _insert_vault(vault_data: dict) -> dict:
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/partner_vaults",
        headers=_service_headers(),
        json=vault_data,
    )
    assert resp.status_code in (200, 201), f"Failed to insert vault: {resp.text}"
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _insert_hint(hint_data: dict) -> dict:
    resp = httpx.post(
        f"{SUPABASE_URL}/rest/v1/hints",
        headers=_service_headers(),
        json=hint_data,
    )
    assert resp.status_code in (200, 201), f"Failed to insert hint: {resp.text}"
    rows = resp.json()
    return rows[0] if isinstance(rows, list) else rows


def _make_vector(values: list[float], dim: int = 768) -> str:
    padded = values + [0.0] * (dim - len(values))
    return "[" + ",".join(str(v) for v in padded[:dim]) + "]"


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    data = {
        "vault_id": "vault-test-123",
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
        "interests": ["Cooking", "Travel", "Music", "Art", "Hiking"],
        "dislikes": ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        "vibes": ["quiet_luxury", "romantic"],
        "primary_love_language": "quality_time",
        "secondary_love_language": "acts_of_service",
        "budgets": [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 10000, "currency": "USD"},
            {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 25000, "currency": "USD"},
        ],
    }
    data.update(overrides)
    return data


def _sample_milestone(**overrides) -> dict:
    data = {
        "id": "milestone-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(**overrides) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=10000, max_amount=25000),
    }
    defaults.update(overrides)
    return RecommendationState(**defaults)


# ======================================================================
# Fixtures: test auth user, vault, and hints
# ======================================================================

@pytest.fixture
def test_auth_user():
    test_email = f"knot-hr-{uuid.uuid4().hex[:8]}@test.example"
    test_password = f"TestPass!{uuid.uuid4().hex[:12]}"
    user_id = _create_auth_user(test_email, test_password)
    time.sleep(0.5)
    yield {"id": user_id, "email": test_email}
    _delete_auth_user(user_id)


@pytest.fixture
def test_vault(test_auth_user):
    vault_row = _insert_vault({
        "user_id": test_auth_user["id"],
        "partner_name": "Hint Retrieval Test Partner",
        "relationship_tenure_months": 18,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
    })
    yield {"user": test_auth_user, "vault": vault_row}


@pytest.fixture
def test_vault_with_embedded_hints(test_vault):
    """
    Create a vault with 3 hints that have crafted vector embeddings.

    Vectors are designed so similarity to query [1.0, 0, ...] is:
      Hint A (gardening tools): [1.0, 0, ...] → similarity ~1.0
      Hint B (cooking shows):   [0.7, 0.7, ...] → similarity ~0.707
      Hint C (spa visit):       [0.1, 0.9, ...] → similarity ~0.110
    """
    vault_id = test_vault["vault"]["id"]
    hints = []

    entries = [
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

    for entry in entries:
        row = _insert_hint({"vault_id": vault_id, **entry})
        hints.append(row)

    yield {"user": test_vault["user"], "vault": test_vault["vault"], "hints": hints}


@pytest.fixture
def test_vault_with_many_hints(test_vault):
    """
    Create a vault with 15 hints (no embeddings) for chronological fallback testing.
    Inserted sequentially with small delays to ensure distinct created_at timestamps.
    """
    vault_id = test_vault["vault"]["id"]
    hints = []

    for i in range(15):
        row = _insert_hint({
            "vault_id": vault_id,
            "hint_text": f"Test hint number {i + 1}: some gift idea about topic {i + 1}",
            "source": "text_input" if i % 2 == 0 else "voice_transcription",
        })
        hints.append(row)
        time.sleep(0.05)  # ensure distinct timestamps

    yield {"user": test_vault["user"], "vault": test_vault["vault"], "hints": hints}


@pytest.fixture
def test_vault_with_mixed_hints(test_vault):
    """
    Create a vault with hints that have mixed embedding states:
    some with embeddings, some without. For testing semantic search
    properly skips NULL embeddings.
    """
    vault_id = test_vault["vault"]["id"]
    hints = []

    entries = [
        {
            "hint_text": "She wants a pottery class",
            "source": "text_input",
            "hint_embedding": _make_vector([1.0]),
        },
        {
            "hint_text": "He likes board games",
            "source": "text_input",
            # no embedding — should be skipped by semantic search
        },
        {
            "hint_text": "She mentioned liking jazz music",
            "source": "voice_transcription",
            "hint_embedding": _make_vector([0.5, 0.5]),
        },
    ]

    for entry in entries:
        row = _insert_hint({"vault_id": vault_id, **entry})
        hints.append(row)

    yield {"user": test_vault["user"], "vault": test_vault["vault"], "hints": hints}


# ======================================================================
# 1. Unit tests: _build_query_text
# ======================================================================

class TestBuildQueryText:
    """Verify query text construction from recommendation state."""

    def test_with_milestone_context(self):
        """Query should include milestone name, type, and occasion label."""
        state = _make_state()
        query = _build_query_text(state)

        assert "Alex's Birthday" in query
        assert "birthday gift ideas" in query
        assert "special gift or memorable experience" in query

    def test_with_milestone_includes_interests(self):
        """Query should append top 3 interests for better semantic matching."""
        state = _make_state()
        query = _build_query_text(state)

        assert "Cooking" in query
        assert "Travel" in query
        assert "Music" in query

    def test_without_milestone_context(self):
        """When no milestone, query uses occasion type and interests only."""
        state = _make_state(milestone_context=None)
        query = _build_query_text(state)

        assert "Alex's Birthday" not in query
        assert "birthday gift ideas" not in query
        # Should still include occasion and interests
        assert "special gift or memorable experience" in query
        assert "Cooking" in query

    def test_just_because_occasion(self):
        """Just-because occasion should use casual language."""
        state = _make_state(
            occasion_type="just_because",
            milestone_context=None,
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
        )
        query = _build_query_text(state)
        assert "casual date or small gift" in query

    def test_minor_occasion(self):
        state = _make_state(
            occasion_type="minor_occasion",
            milestone_context=MilestoneContext(
                id="m1",
                milestone_type="holiday",
                milestone_name="Mother's Day",
                milestone_date="2000-05-11",
                recurrence="yearly",
                budget_tier="minor_occasion",
            ),
            budget_range=BudgetRange(min_amount=5000, max_amount=10000),
        )
        query = _build_query_text(state)
        assert "Mother's Day" in query
        assert "thoughtful gift or fun outing" in query

    def test_empty_interests(self):
        """Query should still work when interests list is empty."""
        vault = _sample_vault_data(interests=[])
        state = _make_state(vault_data=VaultData(**vault))
        query = _build_query_text(state)
        # Should not crash and should not contain "interests:"
        assert "interests:" not in query
        assert "Alex's Birthday" in query

    def test_few_interests(self):
        """With fewer than 3 interests, should use all available."""
        vault = _sample_vault_data(interests=["Cooking"])
        state = _make_state(vault_data=VaultData(**vault))
        query = _build_query_text(state)
        assert "Cooking" in query


# ======================================================================
# 2. Integration tests: _semantic_search via match_hints() RPC
# ======================================================================

@requires_supabase
class TestSemanticSearch:
    """
    Verify _semantic_search queries pgvector via match_hints() RPC
    using crafted embedding vectors (no Vertex AI needed).
    """

    async def test_returns_hints_ordered_by_similarity(self, test_vault_with_embedded_hints):
        """Hints should be returned with highest similarity first."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767  # matches Hint A best

        results = await _semantic_search(vault_id, query_embedding)

        assert len(results) == 3
        assert all(isinstance(r, RelevantHint) for r in results)

        # Verify ordering: A (gardening) > B (cooking) > C (spa)
        assert results[0].hint_text == "She loves gardening and wants new tools"
        assert results[1].hint_text == "He mentioned enjoying cooking shows lately"
        assert results[2].hint_text == "She said she wants to go to a spa"

        # Verify similarity scores are descending
        scores = [r.similarity_score for r in results]
        assert scores == sorted(scores, reverse=True)
        assert scores[0] > 0.99  # ~1.0
        assert 0.6 < scores[1] < 0.8  # ~0.707
        assert 0.05 < scores[2] < 0.2  # ~0.110

    async def test_returns_relevant_hint_objects(self, test_vault_with_embedded_hints):
        """Results should be properly typed RelevantHint instances."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(vault_id, query_embedding)

        hint = results[0]
        assert isinstance(hint, RelevantHint)
        assert hint.id  # non-empty UUID string
        assert hint.hint_text == "She loves gardening and wants new tools"
        assert hint.source == "text_input"
        assert hint.is_used is False
        assert hint.created_at is not None

    async def test_max_count_limits_results(self, test_vault_with_embedded_hints):
        """max_count parameter should limit the number of returned results."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(vault_id, query_embedding, max_count=1)

        assert len(results) == 1
        assert results[0].hint_text == "She loves gardening and wants new tools"

    async def test_threshold_filters_low_similarity(self, test_vault_with_embedded_hints):
        """Hints below the similarity threshold should be excluded."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(vault_id, query_embedding, threshold=0.5)

        assert len(results) == 2  # Hint C (~0.110) excluded
        for r in results:
            assert r.similarity_score >= 0.5

    async def test_skips_hints_without_embeddings(self, test_vault_with_mixed_hints):
        """Semantic search should skip hints with NULL embeddings."""
        vault_id = test_vault_with_mixed_hints["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(vault_id, query_embedding)

        # Only 2 hints have embeddings (pottery class and jazz music)
        assert len(results) == 2
        texts = {r.hint_text for r in results}
        assert "He likes board games" not in texts

    async def test_empty_vault_returns_empty_list(self, test_vault):
        """A vault with no hints should return an empty list."""
        vault_id = test_vault["vault"]["id"]
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(vault_id, query_embedding)
        assert results == []

    async def test_nonexistent_vault_returns_empty_list(self):
        """A nonexistent vault_id should return an empty list (not error)."""
        fake_vault_id = str(uuid.uuid4())
        query_embedding = [1.0] + [0.0] * 767

        results = await _semantic_search(fake_vault_id, query_embedding)
        assert results == []


# ======================================================================
# 3. Integration tests: _chronological_fallback
# ======================================================================

@requires_supabase
class TestChronologicalFallback:
    """Verify the chronological fallback returns recent hints."""

    async def test_returns_hints_in_reverse_chronological_order(self, test_vault_with_many_hints):
        """Hints should be ordered by created_at DESC (most recent first)."""
        vault_id = test_vault_with_many_hints["vault"]["id"]

        results = await _chronological_fallback(vault_id)

        assert len(results) == 10  # MAX_HINTS default
        assert all(isinstance(r, RelevantHint) for r in results)

        # All should have similarity_score 0.0 (no semantic ranking)
        for r in results:
            assert r.similarity_score == 0.0

        # Most recent hint should be first (hint 15)
        assert "15" in results[0].hint_text

    async def test_max_count_limits_results(self, test_vault_with_many_hints):
        """max_count parameter should limit returned hints."""
        vault_id = test_vault_with_many_hints["vault"]["id"]

        results = await _chronological_fallback(vault_id, max_count=3)
        assert len(results) == 3

    async def test_returns_correct_fields(self, test_vault_with_many_hints):
        """Each result should have all RelevantHint fields populated."""
        vault_id = test_vault_with_many_hints["vault"]["id"]

        results = await _chronological_fallback(vault_id, max_count=1)
        assert len(results) == 1

        hint = results[0]
        assert hint.id  # non-empty UUID string
        assert hint.hint_text  # non-empty
        assert hint.source in ("text_input", "voice_transcription")
        assert hint.is_used is False
        assert hint.created_at is not None

    async def test_empty_vault_returns_empty_list(self, test_vault):
        """A vault with no hints should return an empty list."""
        vault_id = test_vault["vault"]["id"]

        results = await _chronological_fallback(vault_id)
        assert results == []

    async def test_nonexistent_vault_returns_empty_list(self):
        """A nonexistent vault_id should return an empty list."""
        results = await _chronological_fallback(str(uuid.uuid4()))
        assert results == []


# ======================================================================
# 4. Integration tests: retrieve_relevant_hints (full node)
# ======================================================================

@requires_supabase
class TestRetrieveRelevantHintsNode:
    """
    Verify the full retrieve_relevant_hints LangGraph node.
    Uses mocked generate_embedding to test with crafted vectors
    (no Vertex AI credentials needed).
    """

    async def test_semantic_path_with_mocked_embedding(self, test_vault_with_embedded_hints):
        """
        When embedding generation succeeds, the node should use semantic search.
        Mock generate_embedding to return [1.0, 0, ...] (matches Hint A best).
        """
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        state = _make_state(vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)))

        mock_embedding = [1.0] + [0.0] * 767

        with patch(
            "app.agents.hint_retrieval.generate_embedding",
            new_callable=AsyncMock,
            return_value=mock_embedding,
        ):
            result = await retrieve_relevant_hints(state)

        assert "relevant_hints" in result
        hints = result["relevant_hints"]
        assert len(hints) == 3
        assert all(isinstance(h, RelevantHint) for h in hints)

        # Highest similarity first
        assert hints[0].hint_text == "She loves gardening and wants new tools"
        assert hints[0].similarity_score > 0.99

    async def test_fallback_path_when_embedding_fails(self, test_vault_with_many_hints):
        """
        When embedding generation returns None, the node should fall back
        to chronological hints.
        """
        vault_id = test_vault_with_many_hints["vault"]["id"]
        state = _make_state(vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)))

        with patch(
            "app.agents.hint_retrieval.generate_embedding",
            new_callable=AsyncMock,
            return_value=None,
        ):
            result = await retrieve_relevant_hints(state)

        assert "relevant_hints" in result
        hints = result["relevant_hints"]
        assert len(hints) == 10  # MAX_HINTS
        # All chronological → similarity_score = 0.0
        for h in hints:
            assert h.similarity_score == 0.0

    async def test_returns_empty_for_vault_with_no_hints(self, test_vault):
        """Node should return empty list when vault has no hints."""
        vault_id = test_vault["vault"]["id"]
        state = _make_state(vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)))

        mock_embedding = [1.0] + [0.0] * 767
        with patch(
            "app.agents.hint_retrieval.generate_embedding",
            new_callable=AsyncMock,
            return_value=mock_embedding,
        ):
            result = await retrieve_relevant_hints(state)

        assert result["relevant_hints"] == []

    async def test_result_dict_compatible_with_state_update(self, test_vault_with_embedded_hints):
        """
        The node should return a dict that can be used to update the state.
        Verify the key name and value type match RecommendationState.relevant_hints.
        """
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        state = _make_state(vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)))

        mock_embedding = [1.0] + [0.0] * 767
        with patch(
            "app.agents.hint_retrieval.generate_embedding",
            new_callable=AsyncMock,
            return_value=mock_embedding,
        ):
            result = await retrieve_relevant_hints(state)

        # Should be usable to construct a new state
        updated_state = state.model_copy(update=result)
        assert len(updated_state.relevant_hints) == 3
        assert updated_state.relevant_hints[0].hint_text == "She loves gardening and wants new tools"

    async def test_node_calls_embedding_with_query_text(self, test_vault_with_embedded_hints):
        """Verify the node passes the constructed query text to generate_embedding."""
        vault_id = test_vault_with_embedded_hints["vault"]["id"]
        state = _make_state(vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)))

        mock_fn = AsyncMock(return_value=[1.0] + [0.0] * 767)

        with patch("app.agents.hint_retrieval.generate_embedding", mock_fn):
            await retrieve_relevant_hints(state)

        mock_fn.assert_called_once()
        query_text = mock_fn.call_args[0][0]
        assert "Alex's Birthday" in query_text
        assert "birthday gift ideas" in query_text

    async def test_node_without_milestone(self, test_vault_with_many_hints):
        """
        Node should work for 'just_because' browsing (no milestone context).
        Falls back to chronological since embedding mock returns None.
        """
        vault_id = test_vault_with_many_hints["vault"]["id"]
        state = _make_state(
            vault_data=VaultData(**_sample_vault_data(vault_id=vault_id)),
            occasion_type="just_because",
            milestone_context=None,
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
        )

        with patch(
            "app.agents.hint_retrieval.generate_embedding",
            new_callable=AsyncMock,
            return_value=None,
        ):
            result = await retrieve_relevant_hints(state)

        assert "relevant_hints" in result
        assert len(result["relevant_hints"]) == 10


# ======================================================================
# 5. Unit tests: edge cases and error handling
# ======================================================================

class TestEdgeCases:
    """Verify graceful handling of edge cases."""

    def test_build_query_text_with_anniversary_milestone(self):
        """Anniversary milestone should produce appropriate query."""
        state = _make_state(
            milestone_context=MilestoneContext(
                id="m2",
                milestone_type="anniversary",
                milestone_name="Our 2-Year Anniversary",
                milestone_date="2000-06-15",
                recurrence="yearly",
                budget_tier="major_milestone",
            ),
        )
        query = _build_query_text(state)
        assert "Our 2-Year Anniversary" in query
        assert "anniversary gift ideas" in query

    def test_build_query_text_with_custom_milestone(self):
        """Custom milestones should include their name in the query."""
        state = _make_state(
            occasion_type="minor_occasion",
            milestone_context=MilestoneContext(
                id="m3",
                milestone_type="custom",
                milestone_name="First Date Anniversary",
                milestone_date="2000-09-20",
                recurrence="yearly",
                budget_tier="minor_occasion",
            ),
            budget_range=BudgetRange(min_amount=5000, max_amount=10000),
        )
        query = _build_query_text(state)
        assert "First Date Anniversary" in query
        assert "custom gift ideas" in query

    def test_build_query_text_with_holiday_milestone(self):
        """Holiday milestones should include the holiday name."""
        state = _make_state(
            occasion_type="major_milestone",
            milestone_context=MilestoneContext(
                id="m4",
                milestone_type="holiday",
                milestone_name="Valentine's Day",
                milestone_date="2000-02-14",
                recurrence="yearly",
                budget_tier="major_milestone",
            ),
        )
        query = _build_query_text(state)
        assert "Valentine's Day" in query
        assert "holiday gift ideas" in query

    def test_relevant_hint_model_round_trip(self):
        """RelevantHint created from RPC-like data should serialize cleanly."""
        hint = RelevantHint(
            id="abc-123",
            hint_text="She mentioned pottery",
            similarity_score=0.87,
            source="text_input",
            is_used=False,
            created_at="2026-02-09T10:30:00+00:00",
        )
        data = hint.model_dump()
        restored = RelevantHint(**data)
        assert restored.hint_text == "She mentioned pottery"
        assert restored.similarity_score == 0.87
