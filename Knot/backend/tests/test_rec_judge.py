"""
Tests for the LLM recommendation judge (Step 20.1).

The judge's Anthropic call is mocked — these tests lock the parsing, score
coercion, and the fact that the overall score / verdict are computed in code
(via the rubric) rather than trusted from the model.
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.agents.state import CandidateRecommendation
from app.services import qa_profiles
from app.services.rec_judge import judge_recommendation


def _rec(rec_type: str = "gift", **overrides) -> CandidateRecommendation:
    base = dict(
        id="r1", source="unified", type=rec_type, title="Test rec",
        description="A thing.", personalization_note="Because you love it.",
    )
    base.update(overrides)
    return CandidateRecommendation(**base)


def _mock_anthropic(text: str):
    """Return a patch target for AsyncAnthropic that yields `text` as the reply."""
    block = MagicMock()
    block.type = "text"  # real Anthropic text blocks carry type="text"
    block.text = text
    response = MagicMock()
    response.content = [block]
    client = AsyncMock()
    client.messages.create = AsyncMock(return_value=response)
    return MagicMock(return_value=client), client


VAULT = qa_profiles.SAMPLE_PROFILES["quiet-luxury-foodie"].vault


async def test_judge_parses_scores_and_computes_overall():
    payload = json.dumps({
        "scores": {"grounded": 1.0, "dislike_safe": 1.0, "specific": 0.9, "budget_fit": 0.8,
                   "vibe_fit": 0.9, "love_language_fit": 0.9, "actionable": 0.9, "well_written": 0.9},
        "rationale": "Strong and specific.",
    })
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)

    assert result.verdict == "good"
    assert 0.85 <= result.overall <= 1.0
    assert result.rationale == "Strong and specific."
    # gift excludes location_fit — the judge output must not carry it.
    assert "location_fit" not in result.dimension_scores


async def test_judge_strips_code_fences():
    payload = "```json\n" + json.dumps({"scores": {"grounded": 1.0, "dislike_safe": 1.0}, "rationale": "ok"}) + "\n```"
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("idea"), VAULT)
    assert result.dimension_scores["grounded"] == 1.0


async def test_missing_dimension_gets_neutral_fill():
    # Judge only returns two dims; the rest are filled with the neutral 0.5.
    payload = json.dumps({"scores": {"grounded": 1.0, "dislike_safe": 1.0}, "rationale": ""})
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)
    assert result.dimension_scores["specific"] == 0.5
    assert result.dimension_scores["grounded"] == 1.0


async def test_critical_failure_forces_bad_verdict():
    payload = json.dumps({
        "scores": {"grounded": 1.0, "dislike_safe": 0.0, "specific": 1.0, "vibe_fit": 1.0,
                   "love_language_fit": 1.0, "budget_fit": 1.0, "actionable": 1.0, "well_written": 1.0},
        "rationale": "References a hard-avoid.",
    })
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)
    assert result.verdict == "bad"
    assert result.overall == 0.0


async def test_scores_clamped_to_unit_interval():
    payload = json.dumps({"scores": {"grounded": 5.0, "dislike_safe": -3.0, "specific": "bad"}, "rationale": ""})
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)
    assert result.dimension_scores["grounded"] == 1.0
    assert result.dimension_scores["dislike_safe"] == 0.0
    assert result.dimension_scores["specific"] == 0.5  # unparseable → neutral


async def test_boolean_scores_treated_as_invalid():
    # JSON booleans are a formatting slip, not real 0.0/1.0 scores: non-critical
    # bool → neutral 0.5, critical bool → failing default (not a hard 1.0/0.0).
    payload = json.dumps({"scores": {"grounded": True, "specific": False, "dislike_safe": True},
                          "rationale": ""})
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)
    assert result.dimension_scores["specific"] == 0.5   # non-critical bool → neutral
    assert result.dimension_scores["grounded"] == 0.0   # critical bool → failing
    assert result.verdict == "bad"


async def test_omitted_critical_dimension_forces_bad():
    # Every non-critical dim is perfect, but dislike_safe is omitted entirely.
    # It must NOT be able to pass as "good" — an unaffirmed critical dim fails.
    payload = json.dumps({
        "scores": {"grounded": 1.0, "specific": 1.0, "budget_fit": 1.0, "vibe_fit": 1.0,
                   "love_language_fit": 1.0, "actionable": 1.0, "well_written": 1.0},
        "rationale": "omitted dislike_safe",
    })
    mock_cls, _ = _mock_anthropic(payload)
    with patch("app.services.rec_judge.AsyncAnthropic", mock_cls), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        result = await judge_recommendation(_rec("gift"), VAULT)
    assert result.dimension_scores["dislike_safe"] == 0.0
    assert result.verdict == "bad"


async def test_no_text_block_raises():
    # An empty content list (or a leading non-text block) must raise clearly,
    # not IndexError/AttributeError.
    response = MagicMock()
    response.content = []
    client = AsyncMock()
    client.messages.create = AsyncMock(return_value=response)
    with patch("app.services.rec_judge.AsyncAnthropic", MagicMock(return_value=client)), \
         patch("app.services.rec_judge.is_anthropic_configured", return_value=True):
        with pytest.raises(RuntimeError):
            await judge_recommendation(_rec("gift"), VAULT)


async def test_raises_when_not_configured():
    with patch("app.services.rec_judge.is_anthropic_configured", return_value=False):
        with pytest.raises(RuntimeError):
            await judge_recommendation(_rec("gift"), VAULT)
