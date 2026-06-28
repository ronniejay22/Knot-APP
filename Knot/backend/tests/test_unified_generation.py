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
from app.services.text_cleanup import is_incomplete_sentence
from app.services.unified_generation import (
    UNIFIED_SYSTEM_PROMPT,
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

    def test_prompt_renders_unlimited_budget_as_open_ended(self):
        """A sentinel max ("no upper limit") renders as "$X and up", not "$1,000,000"."""
        from app.agents.state import UNLIMITED_BUDGET_MAX_CENTS

        vault = _sample_vault_data()
        budget = BudgetRange(
            min_amount=5000,
            max_amount=UNLIMITED_BUDGET_MAX_CENTS,
            currency="USD",
        )
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="major_milestone",
            budget_range=budget,
        )
        assert "$50 and up" in prompt
        # The raw sentinel must not leak into the prompt as a literal dollar amount.
        assert "1000000" not in prompt
        assert "1,000,000" not in prompt

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
# System prompt content tests
# ======================================================================

class TestSystemPrompt:
    """The system prompt must steer Claude toward richer date/experience content."""

    def test_prompt_requests_fuller_date_experience_descriptions(self):
        """Dates/experiences should get a fuller 3-4 sentence description."""
        assert "3-4 sentence" in UNIFIED_SYSTEM_PROMPT
        assert '"date" and "experience"' in UNIFIED_SYSTEM_PROMPT

    def test_prompt_requests_stronger_personalization_note(self):
        """The personalization note should be 2-3 sentences tied to the partner."""
        assert "2-3 sentences" in UNIFIED_SYSTEM_PROMPT
        assert "love language" in UNIFIED_SYSTEM_PROMPT

    def test_prompt_separates_description_from_partner_relevance(self):
        """The description (what/why-good) must be distinct from the note (why-fits)."""
        assert "SEPARATE from the personalization_note" in UNIFIED_SYSTEM_PROMPT

    def test_prompt_requests_location_grounding(self):
        """Date/experience/plan suggestions must be grounded in the partner's city."""
        assert "LOCATION GROUNDING" in UNIFIED_SYSTEM_PROMPT
        assert "neighborhood" in UNIFIED_SYSTEM_PROMPT
        # The search_query spec must steer location-bound experiences to be local.
        assert "include the partner's city and state" in UNIFIED_SYSTEM_PROMPT

    def test_prompt_strongly_favors_local_recommendations(self):
        """When a city is known, the mix should lean toward locally-grounded options."""
        assert "STRONGLY FAVOR" in UNIFIED_SYSTEM_PROMPT
        assert "locally-grounded experiences, dates, and ideas" in UNIFIED_SYSTEM_PROMPT

    def test_prompt_requires_specific_local_store(self):
        """At-home supply runs must name a specific local store, not a placeholder."""
        assert "a SPECIFIC real store" in UNIFIED_SYSTEM_PROMPT
        # The generic placeholder must be cited as the anti-pattern.
        assert '"a local grocery store"' in UNIFIED_SYSTEM_PROMPT

    def test_prompt_requests_natural_prose(self):
        """Prose must avoid raw tag identifiers / underscores."""
        assert "NATURAL PROSE" in UNIFIED_SYSTEM_PROMPT
        assert "quiet_luxury" in UNIFIED_SYSTEM_PROMPT  # cited as the anti-example


class TestLocationGroundingPrompt:
    """The user prompt must reinforce city grounding only when a city is set."""

    def test_directive_present_when_city_set(self):
        vault = _sample_vault_data(location_city="Austin", location_state="TX")
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "Austin" in prompt
        assert "Strongly favor experiences, dates, and ideas grounded in Austin" in prompt
        # At-home supply runs must name a specific local store, not a placeholder.
        assert "specific local store in Austin" in prompt
        assert 'never "a local grocery store"' in prompt

    def test_directive_absent_when_no_city(self):
        vault = _sample_vault_data(location_city=None, location_state=None)
        prompt = _build_user_prompt(
            vault_data=vault,
            hints=[],
            occasion_type="just_because",
            budget_range=_sample_budget_range(),
        )
        assert "Strongly favor experiences, dates, and ideas grounded in" not in prompt
        assert "specific local store" not in prompt


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

    def test_rejects_incomplete_personalization_note(self):
        """A note that trails off mid-sentence must fail validation (forces a retry)."""
        rec = {
            "title": "Cozy Movie Night",
            "description": "An intimate evening in.",
            "recommendation_type": "gift",
            "personalization_note": "It's intimate, low-pressure, and works perfectly for a",
        }
        assert _validate_recommendation(rec) is False

    def test_rejects_empty_personalization_note(self):
        rec = {
            "title": "Cozy Movie Night",
            "description": "An intimate evening in.",
            "recommendation_type": "gift",
            "personalization_note": "   ",
        }
        assert _validate_recommendation(rec) is False

    def test_accepts_complete_personalization_note(self):
        """A complete note on the same rec passes — guards against false positives."""
        rec = {
            "title": "Cozy Movie Night",
            "description": "An intimate evening in.",
            "recommendation_type": "gift",
            "personalization_note": "It's intimate, low-pressure, and works perfectly for a quiet night in.",
        }
        assert _validate_recommendation(rec) is True


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
        """A very long note is trimmed to the ~600 cap (plus the ellipsis)."""
        rec = {
            "title": "Gift",
            "description": "A gift",
            "recommendation_type": "gift",
            "personalization_note": "X" * 800,
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert len(candidate.personalization_note) <= 601

    def test_normalize_trims_note_on_word_boundary(self):
        """An over-long note is cut at a word boundary, not mid-word, with an ellipsis."""
        rec = {
            "title": "Gift",
            "description": "A gift",
            "recommendation_type": "gift",
            "personalization_note": "lovely " * 200,  # ~1400 chars, no sentence ends
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        note = candidate.personalization_note
        assert note.endswith("…")
        assert "lovel…" not in note  # never cut mid-word

    def test_normalize_humanizes_leaked_love_language_tags_on_plan(self):
        """Reproduces the 'Dinner & Film' plan: love-language tags + mid-word cut."""
        long_note = (
            "This plan weaves together three of Ronnie's core loves — cooking, movies, "
            "and travel — while delivering acts_of_service (you're planning the entire "
            "evening structure and choosing the pairing) and words_of_affirmation (you "
            "can share why you think they'll love each specific element). The quiet, "
            "intimate setting plays directly into their love of slow, considered evenings "
            "at home together, far from any crowd or noise or rush of the outside world."
        )
        rec = {
            "title": "Dinner & Film Pairing Evening",
            "description": "An intimate at-home date combining cooking and movies.",
            "recommendation_type": "plan",
            "is_purchasable": False,
            "personalization_note": long_note,
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "An at-home evening."},
                {"type": "steps", "heading": "Steps", "items": ["Cook together", "Watch the film"]},
            ],
        }
        vault = _sample_vault_data(
            primary_love_language="acts_of_service",
            secondary_love_language="words_of_affirmation",
        )
        candidate = _normalize_recommendation(rec, vault)
        note = candidate.personalization_note
        assert "acts_of_service" not in note
        assert "words_of_affirmation" not in note
        assert "acts of service" in note
        # If trimmed, it must end cleanly (ellipsis), never mid-word like "intimate s".
        if len(long_note) > 600:
            assert note.endswith("…")
        assert "intimate s" not in note or "intimate setting" in note

    def test_normalize_humanizes_leaked_vibe_tags_in_note(self):
        """Raw snake_case vibe/love-language tags echoed into prose are humanized."""
        rec = {
            "title": "Vinyl Record",
            "description": "A record honoring their quiet_luxury and street_urban aesthetic.",
            "recommendation_type": "gift",
            "personalization_note": (
                "Ronnie loves music while honoring their quiet_luxury and "
                "street_urban aesthetic and quality_time love language."
            ),
        }
        vault = _sample_vault_data(
            vibes=["quiet_luxury", "street_urban"],
            primary_love_language="quality_time",
        )
        candidate = _normalize_recommendation(rec, vault)
        for field in (candidate.personalization_note, candidate.description):
            assert "quiet_luxury" not in field
            assert "street_urban" not in field
            assert "quality_time" not in field
            assert "quiet luxury" in field

    def test_normalize_preserves_rich_personalization_note(self):
        """A ~400-char note (2-3 sentences) survives intact — would have been
        truncated under the old 300-char cap."""
        rich_note = (
            "Alex's love of pottery and quiet weekends makes this a perfect fit. "
            "You mentioned she's been wanting to slow down lately, and this gives her "
            "exactly that kind of unhurried, hands-on afternoon away from the noise. "
            "It speaks straight to her quality-time love language and the calm, "
            "quiet-luxury vibe she always gravitates toward on a lazy Sunday together."
        )
        # Longer than the old 300-char cap, within the new 500-char cap.
        assert 300 < len(rich_note) <= 500
        rec = {
            "title": "Pottery Afternoon for Two",
            "description": "A class for two.",
            "recommendation_type": "date",
            "personalization_note": rich_note,
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert candidate.personalization_note == rich_note

    def test_normalize_date_keeps_long_description_and_note(self):
        """A date with a fuller 3-4 sentence description + rich note normalizes
        with both fields intact (description cap is 500)."""
        long_desc = (
            "A sunset sail around the harbor aboard a small wooden boat, just the two "
            "of you. You'll cast off at golden hour with a bottle of wine, drift past "
            "the lighthouse as the sky turns, and toast on deck as the sun dips below "
            "the water. It's a slow, romantic evening with nothing to do but be together."
        )
        rich_note = (
            "Alex's love of the ocean and your note about wanting more slow weekends "
            "make this a quiet-luxury escape she'll adore. It leans right into her "
            "quality-time love language."
        )
        rec = {
            "title": "Sunset Harbor Sail for Two",
            "description": long_desc,
            "recommendation_type": "date",
            "is_purchasable": True,
            "merchant_name": "Harbor Sails Co.",
            "price_cents": 12000,
            "search_query": "Harbor Sails Co sunset sail for two booking",
            "personalization_note": rich_note,
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert candidate.type == "date"
        assert candidate.description == long_desc
        assert candidate.personalization_note == rich_note

    def test_normalize_repairs_incomplete_note_and_description(self):
        """A short (sub-600) note/description ending mid-sentence is repaired by the
        trim_to_complete_sentence safety net (truncate_prose is a no-op here)."""
        rec = {
            "title": "Cozy Movie Night",
            "description": "An intimate evening. It's low-pressure and works perfectly for a",
            "recommendation_type": "gift",
            "personalization_note": "You'll love this. It's intimate, low-pressure, and works perfectly for a",
        }
        vault = _sample_vault_data()
        candidate = _normalize_recommendation(rec, vault)
        assert candidate.personalization_note == "You'll love this."
        assert candidate.description == "An intimate evening."

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

    async def test_discards_max_tokens_truncated_attempt(self):
        """A max_tokens stop is discarded (even with parseable text) and retried."""
        truncated = MagicMock()
        truncated.content = [MagicMock()]
        truncated.content[0].text = json.dumps(_sample_claude_response())
        truncated.stop_reason = "max_tokens"

        clean = MagicMock()
        clean.content = [MagicMock()]
        clean.content[0].text = json.dumps(_sample_claude_response())
        clean.stop_reason = "end_turn"

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(side_effect=[truncated, clean])

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

    async def test_all_attempts_truncated_returns_empty(self):
        """If every attempt stops at max_tokens, no partial recs are returned."""
        truncated = MagicMock()
        truncated.content = [MagicMock()]
        truncated.content[0].text = json.dumps(_sample_claude_response())
        truncated.stop_reason = "max_tokens"

        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=truncated)

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
            assert mock_client.messages.create.call_count == 3

    async def test_end_to_end_no_returned_note_ends_mid_sentence(self):
        """If the model emits one mid-sentence note inside valid JSON, that rec is
        dropped by validation and every surviving note ends on a complete thought."""
        recs = _sample_claude_response()
        recs[0]["personalization_note"] = (
            "She mentioned wanting to learn pottery. "
            "It's intimate, low-pressure, and works perfectly for a"
        )

        mock_response = MagicMock()
        mock_response.content = [MagicMock()]
        mock_response.content[0].text = json.dumps(recs)
        mock_response.stop_reason = "end_turn"

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
            # The mid-sentence rec is filtered out; the other two survive intact.
            assert len(results) == 2
            for rec in results:
                assert not is_incomplete_sentence(rec.personalization_note)
