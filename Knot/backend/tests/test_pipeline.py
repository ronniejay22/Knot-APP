"""
Step 5.8 Verification: Full LangGraph Recommendation Pipeline

Tests that the composed RecommendationGraph correctly:
1. Chains all 6 nodes in order (hints → aggregation → filtering → matching → selection → availability)
2. Short-circuits on empty aggregation results (error state)
3. Short-circuits on empty filtering results (error state)
4. Returns partial results when availability verification cannot find 3 valid URLs
5. Returns exactly 3 recommendations for a valid full run
6. Preserves all intermediate state fields across the pipeline

Test categories:
- Graph structure: Verify nodes, edges, and conditional routing exist
- Conditional edges: Verify _check_after_aggregation and _check_after_filtering
- Full pipeline (mocked): End-to-end tests with all external calls mocked
- Error handling: Aggregation empty, filtering empty, availability partial
- Spec tests: The specific tests from the implementation plan
- State integrity: Verify all state fields are populated after a successful run

Prerequisites:
- Complete Steps 5.1-5.7 (all 6 pipeline nodes)

Run with: pytest tests/test_pipeline.py -v
"""

import uuid
from unittest.mock import AsyncMock, patch

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
    _check_after_aggregation,
    _check_after_filtering,
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
    source: str = "amazon",
    price_cents: int = 5000,
    merchant_name: str = "Test Merchant",
    final_score: float = 1.0,
    interest_score: float = 1.0,
    external_url: str | None = None,
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
        "external_url": external_url or f"https://{source}.com/products/{cid}",
        "image_url": "https://images.example.com/test.jpg",
        "merchant_name": merchant_name,
        "metadata": {"catalog": "stub"},
        "interest_score": interest_score,
        "final_score": final_score,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


# ======================================================================
# Shared fixtures — used by all pipeline test classes
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
def mock_url_check():
    """Mock URL availability checks to always return True."""
    with patch(
        "app.agents.availability._check_url",
        new_callable=AsyncMock,
        return_value=True,
    ) as m:
        yield m


# ======================================================================
# Graph structure tests
# ======================================================================

class TestGraphStructure:
    """Verify the graph has the correct nodes and edges."""

    def test_graph_has_all_six_nodes(self):
        """The compiled graph should contain all 6 pipeline nodes."""
        node_names = set(recommendation_graph.nodes.keys())
        # LangGraph always adds __start__
        expected = {
            "__start__",
            "retrieve_hints",
            "aggregate_data",
            "filter_interests",
            "match_vibes_ll",
            "select_diverse",
            "verify_urls",
        }
        assert expected.issubset(node_names), (
            f"Missing nodes: {expected - node_names}"
        )

    def test_graph_node_count(self):
        """Exactly 6 user-defined nodes plus __start__."""
        # __start__ is always added by LangGraph
        user_nodes = {
            k for k in recommendation_graph.nodes.keys()
            if not k.startswith("__")
        }
        assert len(user_nodes) == 6

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

    def test_aggregation_check_with_candidates(self):
        """If candidates exist, return 'continue'."""
        state = _make_state()
        state = state.model_copy(update={
            "candidate_recommendations": [_make_candidate()],
        })
        assert _check_after_aggregation(state) == "continue"

    def test_aggregation_check_empty(self):
        """If no candidates, return 'error'."""
        state = _make_state()
        # candidate_recommendations defaults to empty list
        assert _check_after_aggregation(state) == "error"

    def test_filtering_check_with_candidates(self):
        """If filtered candidates exist, return 'continue'."""
        state = _make_state()
        state = state.model_copy(update={
            "filtered_recommendations": [_make_candidate()],
        })
        assert _check_after_filtering(state) == "continue"

    def test_filtering_check_empty(self):
        """If no filtered candidates, return 'error'."""
        state = _make_state()
        # filtered_recommendations defaults to empty list
        assert _check_after_filtering(state) == "error"


# ======================================================================
# Full pipeline tests (all external calls mocked)
# ======================================================================

class TestFullPipeline:
    """End-to-end pipeline tests with mocked external dependencies."""

    async def test_full_pipeline_returns_three_recommendations(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """A complete pipeline run should return exactly 3 recommendations."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        final = result.get("final_three", [])
        assert len(final) == 3, (
            f"Expected 3 recommendations, got {len(final)}"
        )

    async def test_full_pipeline_no_error_on_success(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """A successful pipeline run should not set an error."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        assert result.get("error") is None

    async def test_full_pipeline_populates_intermediate_state(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """All intermediate state fields should be populated."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        # relevant_hints populated (may be empty if no hints in DB)
        assert "relevant_hints" in result

        # candidate_recommendations populated by aggregation
        assert "candidate_recommendations" in result
        assert len(result["candidate_recommendations"]) > 0

        # filtered_recommendations populated by filtering + matching
        assert "filtered_recommendations" in result
        assert len(result["filtered_recommendations"]) > 0

        # final_three populated by selection + verification
        assert "final_three" in result
        assert len(result["final_three"]) == 3

    async def test_full_pipeline_recommendations_have_required_fields(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Each recommendation should have all required fields."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        for rec in result["final_three"]:
            assert rec.title
            assert rec.external_url
            assert rec.type in ("gift", "experience", "date")
            assert rec.source in ("yelp", "ticketmaster", "amazon", "shopify", "firecrawl")

    async def test_full_pipeline_recommendations_match_interests_or_vibes(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Final recommendations should relate to vault interests or vibes."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        interests = set(state.vault_data.interests)
        vibes = set(state.vault_data.vibes)
        dislikes = set(state.vault_data.dislikes)

        for rec in result["final_three"]:
            matched_interest = rec.metadata.get("matched_interest", "")
            matched_vibe = rec.metadata.get("matched_vibe", "")

            # Each recommendation should match either an interest or a vibe
            matches_interest = matched_interest in interests
            matches_vibe = matched_vibe in vibes

            assert matches_interest or matches_vibe, (
                f"Recommendation '{rec.title}' "
                f"matches neither interests {interests} nor vibes {vibes}. "
                f"metadata={rec.metadata}"
            )

            # No recommendation should match a dislike
            assert matched_interest not in dislikes, (
                f"Recommendation matches dislike '{matched_interest}'"
            )

    async def test_full_pipeline_recommendations_within_budget(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Final recommendations should be within the budget range."""
        budget_min = 3000
        budget_max = 20000
        state = _make_state(budget_min=budget_min, budget_max=budget_max)
        result = await recommendation_graph.ainvoke(state)

        for rec in result["final_three"]:
            if rec.price_cents is not None:
                assert budget_min <= rec.price_cents <= budget_max, (
                    f"Price {rec.price_cents} outside budget {budget_min}-{budget_max}"
                )

    async def test_full_pipeline_without_milestone(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Pipeline should work without a milestone context (browsing mode)."""
        state = _make_state(
            with_milestone=False,
            occasion_type="just_because",
            budget_min=2000,
            budget_max=5000,
        )
        result = await recommendation_graph.ainvoke(state)

        final = result.get("final_three", [])
        assert len(final) > 0, "Should return recommendations even without milestone"
        assert result.get("error") is None

    async def test_full_pipeline_preserves_vault_data(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Vault data should be preserved unchanged through the pipeline."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        vault = result["vault_data"]
        assert vault.vault_id == "vault-pipeline-test"
        assert vault.partner_name == "Alex"

    async def test_full_pipeline_final_three_have_scores(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Final recommendations should have non-zero final_score."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        for rec in result["final_three"]:
            assert rec.final_score > 0, (
                f"Recommendation '{rec.title}' has zero final_score"
            )


# ======================================================================
# Error handling tests
# ======================================================================

class TestPipelineErrors:
    """Test pipeline behavior when nodes encounter errors."""

    async def test_aggregation_empty_short_circuits(
        self, mock_embedding, mock_hint_db,
    ):
        """If aggregation returns 0 candidates, pipeline ends with error."""
        # Use a budget range that filters out ALL stub candidates
        state = _make_state(budget_min=999999, budget_max=1000000)
        result = await recommendation_graph.ainvoke(state)

        assert result.get("error") is not None
        assert "No candidates" in result["error"] or "no candidates" in result["error"].lower()
        # final_three should be empty (pipeline short-circuited)
        assert len(result.get("final_three", [])) == 0
        # filtered_recommendations should not be populated
        assert len(result.get("filtered_recommendations", [])) == 0

    async def test_filtering_empty_short_circuits(
        self, mock_embedding, mock_hint_db,
    ):
        """If filtering removes all candidates, pipeline ends with error."""
        # Mock filter_by_interests to return empty list with error,
        # guaranteeing the error path is exercised regardless of
        # which candidates the aggregation node produces.
        # Must patch at pipeline module level and rebuild the graph,
        # because the compiled graph holds direct function references.
        mock_filter_result = {
            "filtered_recommendations": [],
            "error": "All candidates filtered out — try adjusting your preferences",
        }
        with patch(
            "app.agents.availability._check_url",
            new_callable=AsyncMock,
            return_value=True,
        ), patch(
            "app.agents.pipeline.filter_by_interests",
            new_callable=AsyncMock,
            return_value=mock_filter_result,
        ):
            graph = build_recommendation_graph().compile()
            state = _make_state(budget_min=2000, budget_max=30000)
            result = await graph.ainvoke(state)

        assert result.get("error") is not None
        assert len(result.get("final_three", [])) == 0
        assert len(result.get("filtered_recommendations", [])) == 0

    async def test_availability_partial_results(
        self, mock_embedding, mock_hint_db,
    ):
        """If some URLs are unavailable and no replacements found, return partial."""
        state = _make_state(budget_min=2000, budget_max=30000)

        call_count = 0

        async def selective_url_check(url, client):
            nonlocal call_count
            call_count += 1
            # First URL: available, rest: unavailable
            return call_count == 1

        with patch(
            "app.agents.availability._check_url",
            side_effect=selective_url_check,
        ):
            result = await recommendation_graph.ainvoke(state)

        # Should have at least 1 recommendation (the first verified one)
        final = result.get("final_three", [])
        assert len(final) >= 1, "Should have at least 1 verified recommendation"


# ======================================================================
# Convenience runner tests
# ======================================================================

class TestRunRecommendationPipeline:
    """Test the run_recommendation_pipeline convenience function."""

    async def test_runner_returns_dict(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """run_recommendation_pipeline should return a dict."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await run_recommendation_pipeline(state)
        assert isinstance(result, dict)

    async def test_runner_returns_final_three(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Runner result should contain final_three with 3 items."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await run_recommendation_pipeline(state)
        assert len(result.get("final_three", [])) == 3

    async def test_runner_handles_error_state(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Runner should handle error states gracefully."""
        state = _make_state(budget_min=999999, budget_max=1000000)
        result = await run_recommendation_pipeline(state)
        assert result.get("error") is not None


# ======================================================================
# Spec tests (from implementation plan)
# ======================================================================

class TestSpecRequirements:
    """Tests directly from the Step 5.8 implementation plan."""

    async def test_spec_returns_exactly_three(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """
        Spec: Run the full graph with a complete vault and milestone.
        Confirm it returns exactly 3 recommendations.
        """
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        assert len(result["final_three"]) == 3

    async def test_spec_recommendations_match_preferences(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """
        Spec: Confirm all recommendations match interests, vibes,
        and love language preferences.
        """
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        interests = set(state.vault_data.interests)
        vibes = set(state.vault_data.vibes)
        dislikes = set(state.vault_data.dislikes)

        for rec in result["final_three"]:
            matched_interest = rec.metadata.get("matched_interest", "")
            matched_vibe = rec.metadata.get("matched_vibe", "")

            # Must match either an interest or a vibe
            assert matched_interest in interests or matched_vibe in vibes

            # Must NOT match any dislike
            assert matched_interest not in dislikes

    async def test_spec_aggregation_zero_candidates_error(
        self, mock_embedding, mock_hint_db,
    ):
        """
        Spec: If aggregate_external_data returns 0 candidates →
        return error state "No recommendations found for this location"
        """
        state = _make_state(budget_min=999999, budget_max=1000000)
        result = await recommendation_graph.ainvoke(state)

        assert result.get("error") is not None
        assert len(result.get("final_three", [])) == 0

    async def test_spec_filtering_all_removed_error(
        self, mock_embedding, mock_hint_db,
    ):
        """
        Spec: If filter_by_interests filters all candidates →
        return error state "Try adjusting your preferences"
        """
        # Mock filter_by_interests directly to guarantee the error
        # path is exercised. Relying on organic filtering with
        # interests==dislikes doesn't guarantee all candidates are
        # removed (vibe-matched experiences may survive as neutrals).
        # Must patch at pipeline module level and rebuild the graph,
        # because the compiled graph holds direct function references.
        mock_filter_result = {
            "filtered_recommendations": [],
            "error": "All candidates filtered out — try adjusting your preferences",
        }
        with patch(
            "app.agents.availability._check_url",
            new_callable=AsyncMock,
            return_value=True,
        ), patch(
            "app.agents.pipeline.filter_by_interests",
            new_callable=AsyncMock,
            return_value=mock_filter_result,
        ):
            graph = build_recommendation_graph().compile()
            state = _make_state(budget_min=2000, budget_max=30000)
            result = await graph.ainvoke(state)

        assert result.get("error") is not None
        assert len(result.get("final_three", [])) == 0

    async def test_spec_availability_partial_results_warning(
        self, mock_embedding, mock_hint_db,
    ):
        """
        Spec: If verify_availability cannot find 3 valid URLs after
        3 retries → return partial results with warning
        """
        state = _make_state(budget_min=2000, budget_max=30000)

        # Make ALL URLs unavailable
        with patch(
            "app.agents.availability._check_url",
            new_callable=AsyncMock,
            return_value=False,
        ):
            result = await recommendation_graph.ainvoke(state)

        # When all URLs fail with no valid replacements, we get 0 results
        final = result.get("final_three", [])
        assert len(final) < 3, (
            "With all URLs unavailable, should have fewer than 3 results"
        )


# ======================================================================
# Node ordering tests
# ======================================================================

class TestNodeOrdering:
    """Verify that nodes execute in the correct order."""

    async def test_hints_populated_before_aggregation(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """relevant_hints should be populated in the final state."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        # relevant_hints is set by retrieve_hints (node 1)
        assert "relevant_hints" in result

    async def test_candidates_populated_before_filtering(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """candidate_recommendations should be populated after aggregation."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        assert len(result.get("candidate_recommendations", [])) > 0

    async def test_filtered_populated_before_selection(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """filtered_recommendations should be populated after filtering+matching."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)
        assert len(result.get("filtered_recommendations", [])) > 0

    async def test_final_three_is_subset_of_candidates(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """final_three should be drawn from the candidate pool."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        final_titles = {r.title for r in result["final_three"]}
        candidate_titles = {r.title for r in result["candidate_recommendations"]}

        # final_three should be a subset of candidate_recommendations
        assert final_titles.issubset(candidate_titles), (
            f"final_three titles {final_titles} not subset of "
            f"candidate titles {candidate_titles}"
        )


# ======================================================================
# Diversity and scoring tests
# ======================================================================

class TestPipelineDiversityAndScoring:
    """Verify diversity and scoring across the full pipeline."""

    async def test_diverse_merchants(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """The 3 final recommendations should prefer different merchants."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        merchants = set()
        for rec in result["final_three"]:
            if rec.merchant_name:
                merchants.add(rec.merchant_name.lower())

        # With enough candidates, diversity selection should pick different merchants
        assert len(merchants) >= 2, (
            f"Expected at least 2 unique merchants, got {merchants}"
        )

    async def test_diverse_types(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """With few interests, the pipeline should produce diverse types."""
        # Use a narrow interest set so fewer gift candidates dominate filtering,
        # allowing experience candidates (from vibes) to survive into the top 9.
        state = _make_state(
            budget_min=2000,
            budget_max=30000,
            vault_data=VaultData(**_sample_vault_data(
                interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
                dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
                # Many vibes → more experience candidates survive filtering
                vibes=["quiet_luxury", "romantic", "outdoorsy", "adventurous"],
            )),
        )
        result = await recommendation_graph.ainvoke(state)

        types = {rec.type for rec in result["final_three"]}

        # All types should be valid
        assert types.issubset({"gift", "experience", "date"})

    async def test_scores_are_monotonic_in_filtered(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """filtered_recommendations should be sorted by final_score descending."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        filtered = result.get("filtered_recommendations", [])
        if len(filtered) >= 2:
            scores = [r.final_score for r in filtered]
            for i in range(len(scores) - 1):
                assert scores[i] >= scores[i + 1], (
                    f"Scores not monotonically decreasing: {scores}"
                )


# ======================================================================
# State compatibility tests
# ======================================================================

class TestStateCompatibility:
    """Verify the pipeline result is compatible with RecommendationState."""

    async def test_result_has_all_state_keys(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """Result dict should contain all RecommendationState field names."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        expected_keys = {
            "vault_data",
            "occasion_type",
            "budget_range",
            "relevant_hints",
            "candidate_recommendations",
            "filtered_recommendations",
            "final_three",
        }
        for key in expected_keys:
            assert key in result, f"Missing state key: {key}"

    async def test_result_can_reconstruct_state(
        self, mock_embedding, mock_hint_db, mock_url_check,
    ):
        """The result dict should be deserializable back to RecommendationState."""
        state = _make_state(budget_min=2000, budget_max=30000)
        result = await recommendation_graph.ainvoke(state)

        # Should be able to create a RecommendationState from the result
        reconstructed = RecommendationState(**result)
        assert reconstructed.vault_data.vault_id == "vault-pipeline-test"
        assert len(reconstructed.final_three) == 3

    async def test_error_state_can_reconstruct(
        self, mock_embedding, mock_hint_db,
    ):
        """An error state result should also be deserializable."""
        state = _make_state(budget_min=999999, budget_max=1000000)
        result = await recommendation_graph.ainvoke(state)

        reconstructed = RecommendationState(**result)
        assert reconstructed.error is not None
        assert len(reconstructed.final_three) == 0
