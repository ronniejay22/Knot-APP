"""
Step 15.1 Tests: Unified AI Recommendation Generation Service

Tests for the unified generation service that uses Claude to generate
all 3 recommendations in a single call. Verifies:
- User prompt construction with all personalization data
- Recommendation validation (required fields, idea sections)
- Recommendation normalization (dict → CandidateRecommendation)
- Full generation flow with mocked Claude responses
- Error handling (invalid JSON, missing fields, retries)

Run with: pytest tests/test_unified_generation.py -v
"""

import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RelevantHint,
    VaultData,
)
from app.services.unified_generation import (
    _build_user_prompt,
    _normalize_recommendation,
    _validate_recommendation,
    generate_unified_recommendations,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> VaultData:
    """Returns a complete VaultData instance."""
    data = {
        "vault_id": "vault-unified-test",
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
    return VaultData(**data)


def _sample_hints() -> list[RelevantHint]:
    """Returns a list of sample hints."""
    return [
        RelevantHint(
            id="hint-1",
            hint_text="She mentioned wanting to learn pottery",
            similarity_score=0.9,
        ),
        RelevantHint(
            id="hint-2",
            hint_text="She loved the Italian restaurant we went to last week",
            similarity_score=0.85,
        ),
    ]


def _sample_budget_range() -> BudgetRange:
    return BudgetRange(min_amount=2000, max_amount=5000, currency="USD")


def _sample_claude_response() -> list[dict]:
    """Returns a valid 3-recommendation Claude response."""
    return [
        {
            "title": "Ceramic Pottery Class for Two",
            "description": "A hands-on pottery class where you create pieces together.",
            "recommendation_type": "experience",
            "is_purchasable": True,
            "merchant_name": "Clay Studio Austin",
            "price_cents": 8500,
            "search_query": "Clay Studio Austin pottery class for two booking",
            "personalization_note": "She mentioned wanting to learn pottery — this is the perfect couples activity.",
            "matched_interests": ["Art"],
            "matched_vibes": ["romantic"],
            "matched_love_languages": ["quality_time"],
            "content_sections": None,
        },
        {
            "title": "Handmade Italian Leather Journal",
            "description": "A beautiful leather-bound journal from a Florentine artisan.",
            "recommendation_type": "gift",
            "is_purchasable": True,
            "merchant_name": "Papiro Firenze",
            "price_cents": 4500,
            "search_query": "Papiro Firenze leather journal handmade Italian",
            "personalization_note": "Connects her love of art with a tactile, luxurious keepsake.",
            "matched_interests": ["Art"],
            "matched_vibes": ["quiet_luxury"],
            "matched_love_languages": ["receiving_gifts"],
            "content_sections": None,
        },
        {
            "title": "Starlight Picnic Under the Stars",
            "description": "A curated outdoor picnic with fairy lights and her favorite music.",
            "recommendation_type": "idea",
            "is_purchasable": False,
            "merchant_name": None,
            "price_cents": None,
            "search_query": None,
            "personalization_note": "Combines quality time with her romantic vibe — elevated by the Italian food she loves.",
            "matched_interests": ["Cooking"],
            "matched_vibes": ["romantic"],
            "matched_love_languages": ["quality_time"],
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "A romantic outdoor picnic under the stars."},
                {"type": "steps", "heading": "Steps", "items": ["Find a quiet spot", "Set up fairy lights", "Prepare Italian dishes"]},
                {"type": "tips", "heading": "Pro Tips", "body": "Play her favorite playlist for ambiance."},
            ],
        },
    ]


# ======================================================================
# Prompt construction tests
# ======================================================================

class TestBuildUserPrompt:
    """Test the user prompt builder with various inputs."""

    def test_basic_prompt_contains_partner_info(self):
        vault = _sample_vault_data()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "Alex" in prompt
        assert "Cooking" in prompt
        assert "Gaming" in prompt  # dislikes
        assert "quiet_luxury" in prompt  # vibes
        assert "quality_time" in prompt  # love language
        assert "Austin" in prompt  # location

    def test_prompt_includes_hints(self):
        vault = _sample_vault_data()
        hints = _sample_hints()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=hints,
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "pottery" in prompt
        assert "Italian restaurant" in prompt

    def test_prompt_includes_budget(self):
        vault = _sample_vault_data()
        budget = BudgetRange(min_amount=5000, max_amount=15000, currency="USD")
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="minor_occasion",
            budget_range=budget,
        )
        assert "$50" in prompt
        assert "$150" in prompt

    def test_prompt_includes_exclusion_list(self):
        vault = _sample_vault_data()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
            excluded_titles=["Pottery Class", "Italian Dinner"],
            excluded_descriptions=["A hands-on pottery", "Romantic dinner"],
        )
        assert "DO NOT RECOMMEND" in prompt
        assert "Pottery Class" in prompt
        assert "Italian Dinner" in prompt

    def test_prompt_includes_vibe_override(self):
        vault = _sample_vault_data()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
            vibe_override=["adventurous", "outdoorsy"],
        )
        # Vibe override should replace vault vibes
        assert "adventurous" in prompt
        assert "outdoorsy" in prompt

    def test_prompt_includes_rejection_reason(self):
        vault = _sample_vault_data()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
            rejection_reason="too_expensive",
        )
        assert "LOWER price" in prompt

    def test_prompt_includes_milestone_context(self):
        vault = _sample_vault_data()
        milestone = MilestoneContext(
            id="milestone-1",
            milestone_type="birthday",
            milestone_name="Alex's Birthday",
            milestone_date="2000-03-15",
            recurrence="yearly",
            budget_tier="major_milestone",
            days_until=10,
        )
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="major_milestone",
            budget_range=BudgetRange(min_amount=10000, max_amount=25000),
            milestone_context=milestone,
        )
        assert "Alex's Birthday" in prompt
        assert "birthday" in prompt
        assert "10" in prompt

    def test_prompt_includes_occasion_guidance(self):
        vault = _sample_vault_data()
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "low-cost" in prompt or "personalized" in prompt

    def test_prompt_includes_relationship_tenure(self):
        vault = _sample_vault_data(relationship_tenure_months=36)
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "3 year(s)" in prompt


# ======================================================================
# Validation tests
# ======================================================================

class TestValidateRecommendation:
    """Test the recommendation validator."""

    def test_valid_gift(self):
        rec = {
            "title": "Leather Journal",
            "description": "A handmade journal",
            "recommendation_type": "gift",
            "personalization_note": "She loves writing.",
        }
        assert _validate_recommendation(rec) is True

    def test_valid_experience(self):
        rec = {
            "title": "Pottery Class",
            "description": "A class for two",
            "recommendation_type": "experience",
            "personalization_note": "She mentioned pottery.",
        }
        assert _validate_recommendation(rec) is True

    def test_valid_idea_with_sections(self):
        rec = {
            "title": "Starlight Picnic",
            "description": "Outdoor picnic under the stars",
            "recommendation_type": "idea",
            "personalization_note": "Romantic vibe + quality time.",
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "A romantic picnic."},
                {"type": "steps", "heading": "Steps", "items": ["Step 1", "Step 2"]},
            ],
        }
        assert _validate_recommendation(rec) is True

    def test_invalid_missing_title(self):
        rec = {
            "description": "A gift",
            "recommendation_type": "gift",
            "personalization_note": "Good match.",
        }
        assert _validate_recommendation(rec) is False

    def test_invalid_missing_type(self):
        rec = {
            "title": "Gift",
            "description": "A gift",
            "personalization_note": "Good match.",
        }
        assert _validate_recommendation(rec) is False

    def test_invalid_type_value(self):
        rec = {
            "title": "Gift",
            "description": "A gift",
            "recommendation_type": "unknown_type",
            "personalization_note": "Good match.",
        }
        assert _validate_recommendation(rec) is False

    def test_invalid_idea_missing_sections(self):
        """Ideas must have content_sections with overview + steps."""
        rec = {
            "title": "Picnic",
            "description": "A picnic",
            "recommendation_type": "idea",
            "personalization_note": "Romantic.",
            "content_sections": None,
        }
        assert _validate_recommendation(rec) is False

    def test_invalid_idea_missing_required_section_types(self):
        """Ideas must have both 'overview' and 'steps' sections."""
        rec = {
            "title": "Picnic",
            "description": "A picnic",
            "recommendation_type": "idea",
            "personalization_note": "Romantic.",
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "A picnic."},
                # Missing "steps" section
            ],
        }
        assert _validate_recommendation(rec) is False

    def test_invalid_non_dict(self):
        assert _validate_recommendation("not a dict") is False
        assert _validate_recommendation(None) is False
        assert _validate_recommendation(42) is False


# ======================================================================
# Normalization tests
# ======================================================================

class TestNormalizeRecommendation:
    """Test conversion from raw dict to CandidateRecommendation."""

    def test_normalize_gift(self):
        rec = {
            "title": "Leather Journal",
            "description": "A handmade journal from Florence.",
            "recommendation_type": "gift",
            "is_purchasable": True,
            "merchant_name": "Papiro Firenze",
            "price_cents": 4500,
            "search_query": "Papiro Firenze leather journal",
            "personalization_note": "She loves art and tactile things.",
            "matched_interests": ["Art"],
            "matched_vibes": ["quiet_luxury"],
            "matched_love_languages": ["receiving_gifts"],
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)

        assert isinstance(candidate, CandidateRecommendation)
        assert candidate.type == "gift"
        assert candidate.source == "unified"
        assert candidate.is_idea is False
        assert candidate.price_cents == 4500
        assert candidate.merchant_name == "Papiro Firenze"
        assert candidate.search_query == "Papiro Firenze leather journal"
        assert candidate.personalization_note == "She loves art and tactile things."
        assert candidate.external_url is None  # resolved later

    def test_normalize_idea(self):
        rec = {
            "title": "Starlight Picnic",
            "description": "Outdoor picnic under the stars.",
            "recommendation_type": "idea",
            "is_purchasable": False,
            "merchant_name": None,
            "price_cents": None,
            "search_query": None,
            "personalization_note": "Romantic vibe + quality time.",
            "matched_interests": ["Cooking"],
            "matched_vibes": ["romantic"],
            "matched_love_languages": ["quality_time"],
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "A romantic picnic."},
                {"type": "steps", "heading": "Steps", "items": ["Step 1"]},
            ],
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)

        assert candidate.is_idea is True
        assert candidate.type == "idea"
        assert candidate.price_cents is None
        assert candidate.merchant_name is None
        assert candidate.search_query is None
        assert candidate.content_sections is not None
        assert len(candidate.content_sections) == 2

    def test_normalize_experience_has_location(self):
        rec = {
            "title": "Pottery Class",
            "description": "A class for two.",
            "recommendation_type": "experience",
            "is_purchasable": True,
            "merchant_name": "Clay Studio",
            "price_cents": 8500,
            "search_query": "Clay Studio Austin",
            "personalization_note": "She mentioned pottery.",
            "matched_interests": ["Art"],
            "matched_vibes": [],
            "matched_love_languages": ["quality_time"],
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)

        assert candidate.location is not None
        assert candidate.location.city == "Austin"
        assert candidate.location.state == "TX"

    def test_normalize_truncates_long_title(self):
        rec = {
            "title": "A" * 200,
            "description": "A gift",
            "recommendation_type": "gift",
            "personalization_note": "Good match.",
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert len(candidate.title) <= 100

    def test_normalize_truncates_long_personalization_note(self):
        rec = {
            "title": "Gift",
            "description": "A gift",
            "recommendation_type": "gift",
            "personalization_note": "X" * 500,
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert len(candidate.personalization_note) <= 300

    def test_normalize_filters_invalid_section_types(self):
        rec = {
            "title": "Idea",
            "description": "An idea.",
            "recommendation_type": "idea",
            "is_purchasable": False,
            "personalization_note": "Good.",
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "An overview."},
                {"type": "steps", "heading": "Steps", "items": ["Step 1"]},
                {"type": "invalid_section", "heading": "Bad", "body": "Should be filtered."},
            ],
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert len(candidate.content_sections) == 2  # invalid_section filtered out


# ======================================================================
# Full generation flow tests (mocked Claude)
# ======================================================================

class TestGenerateUnifiedRecommendations:
    """Test the full generation flow with mocked Claude API."""

    @pytest.fixture
    def mock_claude(self):
        """Mock the Anthropic client to return a valid response."""
        mock_response = MagicMock()
        mock_response.content = [MagicMock()]
        mock_response.content[0].text = json.dumps(_sample_claude_response())

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch(
            "app.services.unified_generation.AsyncAnthropic",
            return_value=mock_client,
        ), patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=True,
        ):
            yield mock_client

    async def test_returns_three_recommendations(self, mock_claude):
        vault = _sample_vault_data()
        results = await generate_unified_recommendations(
            vault_data=vault,
            hints=_sample_hints(),
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert len(results) == 3

    async def test_returns_candidate_recommendations(self, mock_claude):
        vault = _sample_vault_data()
        results = await generate_unified_recommendations(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        for rec in results:
            assert isinstance(rec, CandidateRecommendation)
            assert rec.source == "unified"

    async def test_includes_personalization_notes(self, mock_claude):
        vault = _sample_vault_data()
        results = await generate_unified_recommendations(
            vault_data=vault,
            hints=_sample_hints(),
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        for rec in results:
            assert rec.personalization_note is not None
            assert len(rec.personalization_note) > 0

    async def test_idea_has_content_sections(self, mock_claude):
        vault = _sample_vault_data()
        results = await generate_unified_recommendations(
            vault_data=vault,
            hints=_sample_hints(),
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        ideas = [r for r in results if r.is_idea]
        assert len(ideas) >= 1
        for idea in ideas:
            assert idea.content_sections is not None
            assert len(idea.content_sections) >= 2

    async def test_purchasable_has_search_query(self, mock_claude):
        vault = _sample_vault_data()
        results = await generate_unified_recommendations(
            vault_data=vault,
            hints=_sample_hints(),
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        purchasable = [r for r in results if not r.is_idea]
        assert len(purchasable) >= 1
        for rec in purchasable:
            assert rec.search_query is not None
            assert len(rec.search_query) > 0

    async def test_passes_exclusion_context(self, mock_claude):
        vault = _sample_vault_data()
        await generate_unified_recommendations(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
            excluded_titles=["Old Recommendation"],
            excluded_descriptions=["An old one"],
        )
        # Verify Claude was called (the exclusion data is embedded in the prompt)
        mock_claude.messages.create.assert_called_once()

    async def test_passes_vibe_override(self, mock_claude):
        vault = _sample_vault_data()
        await generate_unified_recommendations(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
            vibe_override=["adventurous", "outdoorsy"],
        )
        call_args = mock_claude.messages.create.call_args
        user_msg = call_args.kwargs["messages"][0]["content"]
        assert "adventurous" in user_msg

    async def test_returns_empty_when_not_configured(self):
        with patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=False,
        ):
            vault = _sample_vault_data()
            results = await generate_unified_recommendations(
                vault_data=vault,
                hints=[],
                occasion_type="just_because",
                budget_range=_sample_budget_range(),
            )
            assert results == []

    async def test_handles_invalid_json_with_retry(self):
        """Claude returns invalid JSON on first try, valid on retry."""
        valid_response = MagicMock()
        valid_response.content = [MagicMock()]
        valid_response.content[0].text = json.dumps(_sample_claude_response())

        invalid_response = MagicMock()
        invalid_response.content = [MagicMock()]
        invalid_response.content[0].text = "not valid json {{"

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(
            side_effect=[invalid_response, valid_response]
        )

        with patch(
            "app.services.unified_generation.AsyncAnthropic",
            return_value=mock_client,
        ), patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=True,
        ):
            vault = _sample_vault_data()
            results = await generate_unified_recommendations(
                vault_data=vault,
                hints=[],
                occasion_type="just_because",
                budget_range=_sample_budget_range(),
            )
            assert len(results) == 3
            assert mock_client.messages.create.call_count == 2

    async def test_handles_all_retries_exhausted(self):
        """Claude returns invalid JSON on all attempts."""
        invalid_response = MagicMock()
        invalid_response.content = [MagicMock()]
        invalid_response.content[0].text = "not valid json"

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=invalid_response)

        with patch(
            "app.services.unified_generation.AsyncAnthropic",
            return_value=mock_client,
        ), patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=True,
        ):
            vault = _sample_vault_data()
            results = await generate_unified_recommendations(
                vault_data=vault,
                hints=[],
                occasion_type="just_because",
                budget_range=_sample_budget_range(),
            )
            assert results == []
            # Should have tried MAX_RETRIES + 1 times (3 total)
            assert mock_client.messages.create.call_count == 3

    async def test_handles_code_fenced_json(self):
        """Claude wraps response in markdown code fences."""
        fenced_json = "```json\n" + json.dumps(_sample_claude_response()) + "\n```"

        mock_response = MagicMock()
        mock_response.content = [MagicMock()]
        mock_response.content[0].text = fenced_json

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch(
            "app.services.unified_generation.AsyncAnthropic",
            return_value=mock_client,
        ), patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=True,
        ):
            vault = _sample_vault_data()
            results = await generate_unified_recommendations(
                vault_data=vault,
                hints=_sample_hints(),
                occasion_type="just_because",
                budget_range=_sample_budget_range(),
            )
            assert len(results) == 3

    async def test_filters_invalid_recommendations(self):
        """If Claude returns a mix of valid and invalid recs, only valid ones pass."""
        mixed_response = [
            _sample_claude_response()[0],  # valid gift
            {"title": "Bad Rec"},  # missing required fields
            _sample_claude_response()[2],  # valid idea
        ]

        mock_response = MagicMock()
        mock_response.content = [MagicMock()]
        mock_response.content[0].text = json.dumps(mixed_response)

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)

        with patch(
            "app.services.unified_generation.AsyncAnthropic",
            return_value=mock_client,
        ), patch(
            "app.services.unified_generation.is_anthropic_configured",
            return_value=True,
        ):
            vault = _sample_vault_data()
            results = await generate_unified_recommendations(
                vault_data=vault,
                hints=[],
                occasion_type="just_because",
                budget_range=_sample_budget_range(),
            )
            assert len(results) == 2  # only 2 valid recs
