"""
Tests for the Recommendation State Schema (Step 5.1).

Verifies:
- All Pydantic models instantiate with sample data
- Fields are accessible and properly typed
- JSON serialization produces valid output
- Optional fields default correctly
- Validation rejects invalid data
"""

import json

import pytest
from pydantic import ValidationError

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    LocationData,
    MilestoneContext,
    RecommendationState,
    RelevantHint,
    VaultBudget,
    VaultData,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-abc-123",
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


def _sample_hint(**overrides) -> dict:
    """Returns a complete RelevantHint dict."""
    data = {
        "id": "hint-001",
        "hint_text": "She mentioned wanting to try pottery classes",
        "similarity_score": 0.87,
        "source": "text_input",
        "is_used": False,
        "created_at": "2026-02-09T10:30:00Z",
    }
    data.update(overrides)
    return data


def _sample_milestone(**overrides) -> dict:
    """Returns a complete MilestoneContext dict."""
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


def _sample_candidate(**overrides) -> dict:
    """Returns a complete CandidateRecommendation dict."""
    data = {
        "id": "rec-001",
        "source": "yelp",
        "type": "experience",
        "title": "Pottery Workshop at Austin Clay Studio",
        "description": "2-hour couples pottery class in downtown Austin",
        "price_cents": 8500,
        "currency": "USD",
        "external_url": "https://yelp.com/biz/austin-clay-studio",
        "image_url": "https://example.com/pottery.jpg",
        "merchant_name": "Austin Clay Studio",
        "location": {
            "city": "Austin",
            "state": "TX",
            "country": "US",
            "address": "123 Main St",
        },
        "metadata": {"rating": 4.5, "review_count": 128},
    }
    data.update(overrides)
    return data


def _sample_state(**overrides) -> dict:
    """Returns a complete RecommendationState dict."""
    data = {
        "vault_data": _sample_vault_data(),
        "occasion_type": "major_milestone",
        "milestone_context": _sample_milestone(),
        "budget_range": {"min_amount": 10000, "max_amount": 25000, "currency": "USD"},
        "relevant_hints": [_sample_hint()],
        "candidate_recommendations": [_sample_candidate()],
        "filtered_recommendations": [_sample_candidate(id="rec-002", title="Filtered rec")],
        "final_three": [
            _sample_candidate(id="rec-f1", title="Final 1"),
            _sample_candidate(id="rec-f2", title="Final 2", source="ticketmaster", type="date"),
            _sample_candidate(id="rec-f3", title="Final 3", source="amazon", type="gift"),
        ],
    }
    data.update(overrides)
    return data


# ======================================================================
# Test: BudgetRange
# ======================================================================

class TestBudgetRange:
    """Verify BudgetRange model."""

    def test_instantiate_with_all_fields(self):
        b = BudgetRange(min_amount=2000, max_amount=5000, currency="USD")
        assert b.min_amount == 2000
        assert b.max_amount == 5000
        assert b.currency == "USD"

    def test_currency_defaults_to_usd(self):
        b = BudgetRange(min_amount=0, max_amount=1000)
        assert b.currency == "USD"

    def test_serializes_to_json(self):
        b = BudgetRange(min_amount=2000, max_amount=5000)
        data = json.loads(b.model_dump_json())
        assert data == {"min_amount": 2000, "max_amount": 5000, "currency": "USD"}


# ======================================================================
# Test: VaultBudget
# ======================================================================

class TestVaultBudget:
    """Verify VaultBudget model."""

    def test_instantiate(self):
        vb = VaultBudget(occasion_type="just_because", min_amount=2000, max_amount=5000)
        assert vb.occasion_type == "just_because"

    def test_rejects_invalid_occasion_type(self):
        with pytest.raises(ValidationError):
            VaultBudget(occasion_type="invalid", min_amount=2000, max_amount=5000)


# ======================================================================
# Test: VaultData
# ======================================================================

class TestVaultData:
    """Verify VaultData model with full partner profile."""

    def test_instantiate_full_profile(self):
        v = VaultData(**_sample_vault_data())
        assert v.partner_name == "Alex"
        assert v.vault_id == "vault-abc-123"
        assert v.relationship_tenure_months == 24
        assert v.cohabitation_status == "living_together"
        assert v.location_city == "Austin"
        assert v.location_state == "TX"
        assert v.location_country == "US"
        assert len(v.interests) == 5
        assert len(v.dislikes) == 5
        assert len(v.vibes) == 2
        assert v.primary_love_language == "quality_time"
        assert v.secondary_love_language == "acts_of_service"
        assert len(v.budgets) == 3

    def test_optional_fields_default_to_none(self):
        v = VaultData(
            vault_id="v1",
            partner_name="Pat",
            interests=["Cooking", "Travel", "Music", "Art", "Hiking"],
            dislikes=["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
            vibes=["romantic"],
            primary_love_language="quality_time",
            secondary_love_language="acts_of_service",
            budgets=[],
        )
        assert v.relationship_tenure_months is None
        assert v.cohabitation_status is None
        assert v.location_city is None
        assert v.location_state is None
        assert v.location_country == "US"

    def test_rejects_invalid_cohabitation_status(self):
        with pytest.raises(ValidationError):
            VaultData(**_sample_vault_data(cohabitation_status="married"))

    def test_budgets_are_vault_budget_instances(self):
        v = VaultData(**_sample_vault_data())
        for b in v.budgets:
            assert isinstance(b, VaultBudget)

    def test_serializes_to_json(self):
        v = VaultData(**_sample_vault_data())
        data = json.loads(v.model_dump_json())
        assert data["partner_name"] == "Alex"
        assert len(data["interests"]) == 5
        assert len(data["budgets"]) == 3
        assert data["budgets"][0]["occasion_type"] == "just_because"


# ======================================================================
# Test: RelevantHint
# ======================================================================

class TestRelevantHint:
    """Verify RelevantHint model."""

    def test_instantiate_full(self):
        h = RelevantHint(**_sample_hint())
        assert h.hint_text == "She mentioned wanting to try pottery classes"
        assert h.similarity_score == 0.87
        assert h.source == "text_input"
        assert h.is_used is False

    def test_defaults(self):
        h = RelevantHint(id="h1", hint_text="some hint")
        assert h.similarity_score == 0.0
        assert h.source == "text_input"
        assert h.is_used is False
        assert h.created_at is None

    def test_rejects_invalid_source(self):
        with pytest.raises(ValidationError):
            RelevantHint(id="h1", hint_text="test", source="email")

    def test_serializes_to_json(self):
        h = RelevantHint(**_sample_hint())
        data = json.loads(h.model_dump_json())
        assert data["id"] == "hint-001"
        assert isinstance(data["similarity_score"], float)


# ======================================================================
# Test: MilestoneContext
# ======================================================================

class TestMilestoneContext:
    """Verify MilestoneContext model."""

    def test_instantiate_full(self):
        m = MilestoneContext(**_sample_milestone())
        assert m.milestone_name == "Alex's Birthday"
        assert m.milestone_type == "birthday"
        assert m.budget_tier == "major_milestone"
        assert m.days_until == 10

    def test_days_until_defaults_to_none(self):
        m = MilestoneContext(**_sample_milestone(days_until=None))
        assert m.days_until is None

    def test_rejects_invalid_milestone_type(self):
        with pytest.raises(ValidationError):
            MilestoneContext(**_sample_milestone(milestone_type="graduation"))

    def test_rejects_invalid_budget_tier(self):
        with pytest.raises(ValidationError):
            MilestoneContext(**_sample_milestone(budget_tier="extravagant"))

    def test_rejects_invalid_recurrence(self):
        with pytest.raises(ValidationError):
            MilestoneContext(**_sample_milestone(recurrence="monthly"))

    def test_serializes_to_json(self):
        m = MilestoneContext(**_sample_milestone())
        data = json.loads(m.model_dump_json())
        assert data["milestone_type"] == "birthday"
        assert data["days_until"] == 10


# ======================================================================
# Test: LocationData
# ======================================================================

class TestLocationData:
    """Verify LocationData model."""

    def test_all_fields_optional(self):
        loc = LocationData()
        assert loc.city is None
        assert loc.state is None
        assert loc.country is None
        assert loc.address is None

    def test_instantiate_full(self):
        loc = LocationData(city="Austin", state="TX", country="US", address="123 Main St")
        assert loc.city == "Austin"


# ======================================================================
# Test: CandidateRecommendation
# ======================================================================

class TestCandidateRecommendation:
    """Verify CandidateRecommendation model."""

    def test_instantiate_full(self):
        c = CandidateRecommendation(**_sample_candidate())
        assert c.title == "Pottery Workshop at Austin Clay Studio"
        assert c.source == "yelp"
        assert c.type == "experience"
        assert c.price_cents == 8500
        assert c.merchant_name == "Austin Clay Studio"
        assert c.location is not None
        assert c.location.city == "Austin"
        assert c.metadata["rating"] == 4.5

    def test_scoring_defaults_to_zero(self):
        c = CandidateRecommendation(**_sample_candidate())
        assert c.interest_score == 0.0
        assert c.vibe_score == 0.0
        assert c.love_language_score == 0.0
        assert c.final_score == 0.0

    def test_optional_fields_default(self):
        c = CandidateRecommendation(
            id="r1",
            source="amazon",
            type="gift",
            title="A gift",
            external_url="https://amazon.com/item",
        )
        assert c.description is None
        assert c.price_cents is None
        assert c.image_url is None
        assert c.merchant_name is None
        assert c.location is None
        assert c.metadata == {}

    def test_rejects_invalid_source(self):
        with pytest.raises(ValidationError):
            CandidateRecommendation(**_sample_candidate(source="google"))

    def test_rejects_invalid_type(self):
        with pytest.raises(ValidationError):
            CandidateRecommendation(**_sample_candidate(type="concert"))

    def test_location_is_location_data_instance(self):
        c = CandidateRecommendation(**_sample_candidate())
        assert isinstance(c.location, LocationData)

    def test_serializes_to_json(self):
        c = CandidateRecommendation(**_sample_candidate())
        data = json.loads(c.model_dump_json())
        assert data["source"] == "yelp"
        assert data["location"]["city"] == "Austin"
        assert data["metadata"]["rating"] == 4.5


# ======================================================================
# Test: RecommendationState (main LangGraph state)
# ======================================================================

class TestRecommendationState:
    """Verify the complete RecommendationState model."""

    def test_instantiate_full_state(self):
        s = RecommendationState(**_sample_state())
        assert s.vault_data.partner_name == "Alex"
        assert s.occasion_type == "major_milestone"
        assert s.milestone_context is not None
        assert s.milestone_context.milestone_name == "Alex's Birthday"
        assert s.budget_range.min_amount == 10000
        assert len(s.relevant_hints) == 1
        assert len(s.candidate_recommendations) == 1
        assert len(s.filtered_recommendations) == 1
        assert len(s.final_three) == 3

    def test_minimal_state_with_defaults(self):
        """State can be created with only required fields — lists default to empty."""
        s = RecommendationState(
            vault_data=VaultData(**_sample_vault_data()),
            occasion_type="just_because",
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
        )
        assert s.milestone_context is None
        assert s.relevant_hints == []
        assert s.candidate_recommendations == []
        assert s.filtered_recommendations == []
        assert s.final_three == []
        assert s.error is None

    def test_rejects_invalid_occasion_type(self):
        with pytest.raises(ValidationError):
            RecommendationState(
                vault_data=VaultData(**_sample_vault_data()),
                occasion_type="huge_event",
                budget_range=BudgetRange(min_amount=0, max_amount=1000),
            )

    def test_error_field(self):
        s = RecommendationState(
            vault_data=VaultData(**_sample_vault_data()),
            occasion_type="just_because",
            budget_range=BudgetRange(min_amount=2000, max_amount=5000),
            error="External API timeout",
        )
        assert s.error == "External API timeout"

    def test_serializes_to_json(self):
        s = RecommendationState(**_sample_state())
        json_str = s.model_dump_json()
        data = json.loads(json_str)

        # Top-level fields
        assert data["occasion_type"] == "major_milestone"
        assert data["error"] is None

        # Nested vault_data
        assert data["vault_data"]["partner_name"] == "Alex"
        assert len(data["vault_data"]["interests"]) == 5

        # Nested lists
        assert len(data["relevant_hints"]) == 1
        assert data["relevant_hints"][0]["hint_text"].startswith("She mentioned")
        assert len(data["final_three"]) == 3

        # Milestone context
        assert data["milestone_context"]["milestone_type"] == "birthday"

        # Budget range
        assert data["budget_range"]["min_amount"] == 10000

    def test_round_trip_json_serialization(self):
        """Serialize to JSON and deserialize back — should produce identical state."""
        original = RecommendationState(**_sample_state())
        json_str = original.model_dump_json()
        restored = RecommendationState.model_validate_json(json_str)

        assert restored.vault_data.partner_name == original.vault_data.partner_name
        assert restored.occasion_type == original.occasion_type
        assert len(restored.final_three) == len(original.final_three)
        assert restored.final_three[0].title == original.final_three[0].title
        assert restored.milestone_context.days_until == original.milestone_context.days_until
        assert restored.relevant_hints[0].similarity_score == original.relevant_hints[0].similarity_score

    def test_model_dump_dict(self):
        """model_dump() returns a plain dict suitable for LangGraph state passing."""
        s = RecommendationState(**_sample_state())
        d = s.model_dump()
        assert isinstance(d, dict)
        assert isinstance(d["vault_data"], dict)
        assert isinstance(d["final_three"], list)
        assert isinstance(d["final_three"][0], dict)

    def test_final_three_diverse_types(self):
        """Verify final_three can hold mixed recommendation types and sources."""
        s = RecommendationState(**_sample_state())
        types = {r.type for r in s.final_three}
        sources = {r.source for r in s.final_three}
        assert len(types) >= 2   # experience, date, gift
        assert len(sources) >= 2  # yelp, ticketmaster, amazon
