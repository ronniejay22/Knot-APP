"""
Tests for the idea generation service (Knot Originals).

Focused on location grounding: the system prompt must instruct Claude to make
out-and-about ideas specific to the partner's city, and the user prompt must add
that directive only when a city is present.

Run with: pytest tests/test_idea_generation.py -v
"""

from app.agents.state import VaultData
from app.services.idea_generation import (
    IDEA_SYSTEM_PROMPT,
    _build_user_prompt,
)


def _sample_vault_data(**overrides) -> VaultData:
    """Returns a complete VaultData instance."""
    data = {
        "vault_id": "vault-idea-test",
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


class TestSystemPrompt:
    """The idea system prompt must steer Claude to ground ideas in the city."""

    def test_prompt_requests_location_grounding(self):
        assert "LOCATION" in IDEA_SYSTEM_PROMPT
        assert "neighborhood" in IDEA_SYSTEM_PROMPT
        # Steps should reference concrete local places.
        assert "local" in IDEA_SYSTEM_PROMPT


class TestLocationGroundingPrompt:
    """The user prompt reinforces city grounding only when a city is set."""

    def test_directive_present_when_city_set(self):
        vault = _sample_vault_data(location_city="Austin", location_state="TX")
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            count=3,
        )
        assert "Austin" in prompt
        assert "Ground out-and-about ideas in this city" in prompt

    def test_directive_absent_when_no_city(self):
        vault = _sample_vault_data(location_city=None, location_state=None)
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            count=3,
        )
        assert "Ground out-and-about ideas in this city" not in prompt
