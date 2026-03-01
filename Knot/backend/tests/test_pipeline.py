"""
Step 15.1 Verification: Unified LangGraph Recommendation Pipeline

Tests that the composed RecommendationGraph correctly:
1. Chains all 4 nodes in order (hints → generate_unified → resolve_urls → verify_urls)
2. Short-circuits on empty generation results (error state)
3. Returns exactly 3 recommendations for a valid full run
4. Preserves all state fields across the pipeline

Replaces Step 5.8 tests for the previous 6-node pipeline.

Test categories:
- Graph structure: Verify nodes, edges, and conditional routing exist
- Conditional edges: Verify _check_after_generation routing
- Full pipeline (mocked): End-to-end tests with all external calls mocked
- Error handling: Generation empty, API errors
- Convenience runner: Verify run_recommendation_pipeline

Run with: pytest tests/test_pipeline.py -v
"""

import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    RelevantHint,
    VaultData,
)
from app.agents.pipeline import (
    _check_after_generation,
    build_recommendation_graph,
    recommendation_graph,
    run_recommendation_pipeline,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-pipeline-test",
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
        "secondary_love_language": "receiving_gifts",
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
        "id": "milestone-pipe-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(
    occasion_type="major_milestone",
    budget_min=2000,
    budget_max=25000,
    with_milestone=True,
    **overrides,
) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": occasion_type,
        "budget_range": BudgetRange(min_amount=budget_min, max_amount=budget_max),
    }
    if with_milestone:
        defaults["milestone_context"] = MilestoneContext(**_sample_milestone())
    defaults.update(overrides)
    return RecommendationState(**defaults)


def _make_candidate(
    title: str = "Test Gift",
    rec_type: str = "gift",
    source: str = "unified",
    price_cents: int = 5000,
    merchant_name: str = "Test Merchant",
    external_url: str | None = None,
    is_idea: bool = False,
    candidate_id: str | None = None,
    **overrides,
) -> CandidateRecommendation:
    """Build a CandidateRecommendation with sensible defaults."""
    cid = candidate_id or str(uuid.uuid4())
    data = {
        "id": cid,
        "source": source,
        "type": rec_type,
        "title": title,
        "description": f"A {rec_type} recommendation",
        "price_cents": price_cents,
        "external_url": external_url or f"https://example.com/products/{cid}",
        "image_url": "https://images.example.com/test.jpg",
        "merchant_name": merchant_name,
        "metadata": {"generation_model": "claude-sonnet-4-20250514"},
        "is_idea": is_idea,
        "personalization_note": "Specifically picked for this partner.",
        "search_query": f"buy {title}" if not is_idea else None,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


# ======================================================================
# Shared fixtures
# ======================================================================

@pytest.fixture
def mock_embedding():
    """Mock Vertex AI embedding to return None (forces chronological fallback)."""
    with patch(
        "app.agents.hint_retrieval.generate_embedding",
        new_callable=AsyncMock,
        return_value=None,
    ) as m:
        yield m


@pytest.fixture
def mock_hint_db():
    """Mock Supabase hint queries to return empty results."""
    mock_client = AsyncMock()
    mock_response = AsyncMock()
    mock_response.data = []

    mock_table = AsyncMock()
    mock_table.select.return_value = mock_table
    mock_table.eq.return_value = mock_table
    mock_table.order.return_value = mock_table
    mock_table.limit.return_value = mock_table
    mock_table.execute.return_value = mock_response

    mock_client.table.return_value = mock_table

    with patch(
        "app.agents.hint_retrieval.get_service_client",
        return_value=mock_client,
    ):
        yield mock_client


@pytest.fixture
def mock_unified_generation():
    """Mock the unified generation service to return 3 candidates."""
    candidates = [
        _make_candidate(title="Pottery Class for Two", rec_type="experience", price_cents=8500),
        _make_candidate(title="Italian Leather Journal", rec_type="gift", price_cents=4500),
        _make_candidate(
            title="Starlight Picnic",
            rec_type="idea",
            is_idea=True,
            price_cents=None,
            external_url=None,
            merchant_name=None,
            content_sections=[
                {"type": "overview", "heading": "Overview", "body": "A romantic picnic."},
                {"type": "steps", "heading": "Steps", "items": ["Step 1"]},
            ],
        ),
    ]
    with patch(
        "app.agents.unified_generation_node.generate_unified_recommendations",
        new_callable=AsyncMock,
        return_value=candidates,
    ) as m:
        yield m


@pytest.fixture
def mock_brave_search():
    """Mock Brave Search API to prevent real HTTP calls during URL resolution."""
    with patch(
        "app.agents.url_resolution.is_brave_search_configured",
        return_value=False,
    ) as m:
        yield m


@pytest.fixture
def mock_url_check():
    """Mock URL availability checks to always return True with page content."""
    with patch(
        "app.agents.availability._fetch_page",
        new_callable=AsyncMock,
        return_value=(True, ""),
    ), patch(
        "app.agents.availability._check_url",
        new_callable=AsyncMock,
        return_value=True,
    ) as check_m:
        yield check_m


# ======================================================================
# Graph structure tests
# ======================================================================

class TestGraphStructure:
    """Verify the graph has the correct nodes and edges."""

    def test_graph_has_all_four_nodes(self):
        """The compiled graph should contain all 4 pipeline nodes."""
        node_names = set(recommendation_graph.nodes.keys())
        expected = {
            "__start__",
            "retrieve_hints",
            "generate_unified",
            "resolve_urls",
            "verify_urls",
        }
        assert expected.issubset(node_names), (
            f"Missing nodes: {expected - node_names}"
        )

    def test_graph_node_count(self):
        """Exactly 4 user-defined nodes plus __start__."""
        user_nodes = {
            k for k in recommendation_graph.nodes.keys()
            if not k.startswith("__")
        }
        assert len(user_nodes) == 4

    def test_build_returns_state_graph(self):
        """build_recommendation_graph returns an uncompiled StateGraph."""
        from langgraph.graph import StateGraph as SG
        graph = build_recommendation_graph()
        assert isinstance(graph, SG)

    def test_compiled_graph_is_cached(self):
        """The module-level recommendation_graph should be a CompiledStateGraph."""
        from langgraph.graph.state import CompiledStateGraph
        assert isinstance(recommendation_graph, CompiledStateGraph)

    def test_build_produces_compilable_graph(self):
        """build_recommendation_graph().compile() should succeed."""
        graph = build_recommendation_graph()
        compiled = graph.compile()
        assert compiled is not None


# ======================================================================
# Conditional edge tests
# ======================================================================

class TestConditionalEdges:
    """Verify routing functions for conditional edges."""

    def test_generation_check_with_results(self):
        """If final_three has items, return 'continue'."""
        state = _make_state()
        state = state.model_copy(update={
            "final_three": [_make_candidate()],
        })
        assert _check_after_generation(state) == "continue"

    def test_generation_check_empty(self):
        """If final_three is empty, return 'error'."""
        state = _make_state()
        # final_three defaults to empty list
        assert _check_after_generation(state) == "error"


# ======================================================================
# Full pipeline tests (all external calls mocked)
# ======================================================================

class TestFullPipeline:
    """End-to-end pipeline tests with mocked external dependencies."""

    async def test_full_pipeline_returns_three_recommendations(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """A complete pipeline run should return exactly 3 recommendations."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        final = result.get("final_three", [])
        assert len(final) == 3

    async def test_full_pipeline_no_error_on_success(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """A successful pipeline run should not set an error."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        assert result.get("error") is None

    async def test_full_pipeline_recommendations_have_source_unified(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """All recommendations should have source='unified'."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        for rec in result["final_three"]:
            assert rec.source == "unified"

    async def test_full_pipeline_includes_personalization_notes(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """Every recommendation should have a personalization_note."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        for rec in result["final_three"]:
            assert rec.personalization_note is not None
            assert len(rec.personalization_note) > 0

    async def test_full_pipeline_preserves_vault_data(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """Vault data should be preserved unchanged through the pipeline."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        vault = result["vault_data"]
        assert vault.vault_id == "vault-pipeline-test"
        assert vault.partner_name == "Alex"

    async def test_full_pipeline_without_milestone(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """Pipeline should work without a milestone context."""
        state = _make_state(
            with_milestone=False,
            occasion_type="just_because",
            budget_min=2000,
            budget_max=5000,
        )
        result = await recommendation_graph.ainvoke(state)

        final = result.get("final_three", [])
        assert len(final) == 3
        assert result.get("error") is None

    async def test_full_pipeline_mix_of_types(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """The unified pipeline should return a mix of recommendation types."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        types = {rec.type for rec in result["final_three"]}
        # Our mock returns experience, gift, and idea
        assert len(types) >= 2


# ======================================================================
# Error handling tests
# ======================================================================

class TestPipelineErrors:
    """Test pipeline behavior when nodes encounter errors."""

    async def test_generation_empty_short_circuits(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """If unified generation returns 0 candidates, pipeline ends with error."""
        with patch(
            "app.agents.unified_generation_node.generate_unified_recommendations",
            new_callable=AsyncMock,
            return_value=[],
        ):
            state = _make_state(budget_min=2000, budget_max=30000)
            result = await recommendation_graph.ainvoke(state)

            assert result.get("error") is not None
            assert len(result.get("final_three", [])) == 0


# ======================================================================
# Convenience runner tests
# ======================================================================

class TestRunRecommendationPipeline:
    """Test the run_recommendation_pipeline convenience function."""

    async def test_runner_returns_dict(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """run_recommendation_pipeline should return a dict."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await run_recommendation_pipeline(state)
        assert isinstance(result, dict)

    async def test_runner_returns_final_three(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """Runner result should contain final_three with 3 items."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await run_recommendation_pipeline(state)
        assert len(result.get("final_three", [])) == 3


# ======================================================================
# State compatibility tests
# ======================================================================

class TestStateCompatibility:
    """Verify the pipeline result is compatible with RecommendationState."""

    async def test_result_has_all_state_keys(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """Result dict should contain essential state keys."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        expected_keys = {
            "vault_data",
            "occasion_type",
            "budget_range",
            "relevant_hints",
            "final_three",
        }
        for key in expected_keys:
            assert key in result, f"Missing state key: {key}"

    async def test_result_can_reconstruct_state(
        self, mock_embedding, mock_hint_db, mock_unified_generation,
        mock_brave_search, mock_url_check,
    ):
        """The result dict should be deserializable back to RecommendationState."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        reconstructed = RecommendationState(**result)
        assert reconstructed.vault_data.vault_id == "vault-pipeline-test"
        assert len(reconstructed.final_three) == 3
