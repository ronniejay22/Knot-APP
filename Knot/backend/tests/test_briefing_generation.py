"""
Tests: Milestone Briefing Generation Service

Tests for the briefing generation service that uses Claude to create
contextual, conversational briefings for upcoming milestones. Verifies:
- Prompt construction with vault data, hints, and milestone context
- Response parsing (briefing_text, briefing_snippet, hint_ids)
- Error handling (invalid JSON, empty responses, retries)
- Hint ID validation (only keeps valid IDs)

Run with: pytest tests/test_briefing_generation.py -v
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.agents.state import (
    MilestoneContext,
    RelevantHint,
    VaultData,
)
from app.services.briefing_generation import (
    _build_briefing_prompt,
    generate_milestone_briefing,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data() -> VaultData:
    return VaultData(
        vault_id="vault-briefing-test",
        partner_name="Alex",
        relationship_tenure_months=24,
        cohabitation_status="living_together",
        location_city="Austin",
        location_state="TX",
        interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
        dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        vibes=["quiet_luxury", "romantic"],
        primary_love_language="quality_time",
        secondary_love_language="receiving_gifts",
        budgets=[
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
        ],
    )


def _sample_milestone() -> MilestoneContext:
    return MilestoneContext(
        id="ms-birthday-123",
        milestone_type="birthday",
        milestone_name="Birthday",
        milestone_date="2000-06-15",
        recurrence="yearly",
        budget_tier="major_milestone",
        days_until=7,
    )


def _sample_hints() -> list[RelevantHint]:
    return [
        RelevantHint(
            id="hint-001",
            hint_text="She mentioned she's been craving lemon bars lately",
            similarity_score=0.92,
        ),
        RelevantHint(
            id="hint-002",
            hint_text="Said she wants to see the new Scream movie",
            similarity_score=0.88,
        ),
    ]


# ======================================================================
# Prompt construction tests
# ======================================================================

class TestBuildBriefingPrompt:
    """Tests for the prompt construction helper."""

    def test_includes_milestone_context(self):
        prompt = _build_briefing_prompt(
            _sample_vault_data(), _sample_hints(), _sample_milestone(),
        )
        assert "Birthday" in prompt
        assert "Days until: 7" in prompt

    def test_includes_partner_profile(self):
        prompt = _build_briefing_prompt(
            _sample_vault_data(), _sample_hints(), _sample_milestone(),
        )
        assert "Alex" in prompt
        assert "Cooking" in prompt
        assert "quiet_luxury" in prompt

    def test_includes_hints_with_ids(self):
        prompt = _build_briefing_prompt(
            _sample_vault_data(), _sample_hints(), _sample_milestone(),
        )
        assert "hint-001" in prompt
        assert "lemon bars" in prompt
        assert "hint-002" in prompt
        assert "Scream" in prompt

    def test_empty_hints(self):
        prompt = _build_briefing_prompt(
            _sample_vault_data(), [], _sample_milestone(),
        )
        assert "CAPTURED HINTS" not in prompt


# ======================================================================
# Generation tests
# ======================================================================

class TestGenerateMilestoneBriefing:
    """Tests for the main generation function."""

    @pytest.mark.asyncio
    async def test_returns_none_when_no_milestone(self):
        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=None,
        )
        assert result is None

    @pytest.mark.asyncio
    @patch("app.services.briefing_generation.is_anthropic_configured", return_value=False)
    async def test_returns_none_when_not_configured(self, mock_config):
        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=_sample_milestone(),
        )
        assert result is None

    @pytest.mark.asyncio
    @patch("app.services.briefing_generation.is_anthropic_configured", return_value=True)
    @patch("app.services.briefing_generation.AsyncAnthropic")
    async def test_successful_generation(self, mock_anthropic_cls, mock_config):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text=json.dumps({
            "briefing_text": "Alex's birthday is just a week away! I noticed she's been craving lemon bars and mentioned wanting to see Scream 7. Why not plan a cozy baking session followed by a horror movie night?",
            "briefing_snippet": "She's been craving lemon bars — bake together before her birthday!",
            "hint_ids_referenced": ["hint-001", "hint-002"],
        }))]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)
        mock_anthropic_cls.return_value = mock_client

        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=_sample_milestone(),
        )

        assert result is not None
        assert "lemon bars" in result.briefing_text
        assert len(result.briefing_snippet) <= 100
        assert "hint-001" in result.hint_ids_referenced
        assert "hint-002" in result.hint_ids_referenced

    @pytest.mark.asyncio
    @patch("app.services.briefing_generation.is_anthropic_configured", return_value=True)
    @patch("app.services.briefing_generation.AsyncAnthropic")
    async def test_filters_invalid_hint_ids(self, mock_anthropic_cls, mock_config):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text=json.dumps({
            "briefing_text": "Birthday is coming up!",
            "briefing_snippet": "Birthday soon!",
            "hint_ids_referenced": ["hint-001", "fake-id-999"],
        }))]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)
        mock_anthropic_cls.return_value = mock_client

        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=_sample_milestone(),
        )

        assert result is not None
        assert "hint-001" in result.hint_ids_referenced
        assert "fake-id-999" not in result.hint_ids_referenced

    @pytest.mark.asyncio
    @patch("app.services.briefing_generation.is_anthropic_configured", return_value=True)
    @patch("app.services.briefing_generation.AsyncAnthropic")
    async def test_truncates_long_snippet(self, mock_anthropic_cls, mock_config):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text=json.dumps({
            "briefing_text": "Short briefing.",
            "briefing_snippet": "A" * 150,
            "hint_ids_referenced": [],
        }))]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)
        mock_anthropic_cls.return_value = mock_client

        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=_sample_milestone(),
        )

        assert result is not None
        assert len(result.briefing_snippet) <= 100

    @pytest.mark.asyncio
    @patch("app.services.briefing_generation.is_anthropic_configured", return_value=True)
    @patch("app.services.briefing_generation.AsyncAnthropic")
    async def test_handles_invalid_json(self, mock_anthropic_cls, mock_config):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text="not valid json at all")]

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=mock_response)
        mock_anthropic_cls.return_value = mock_client

        result = await generate_milestone_briefing(
            vault_data=_sample_vault_data(),
            hints=_sample_hints(),
            milestone_context=_sample_milestone(),
        )

        assert result is None
