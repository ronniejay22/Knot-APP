"""
Recommendation Judge — an LLM that scores a generated recommendation against the
quality rubric (`app/services/rec_quality.py`).

This is the automated half of "judge the recommendations, not the user": given a
recommendation and the partner profile it was generated for, Claude scores each
applicable rubric dimension 0.0–1.0 and returns a short rationale. The overall
score and good/bad verdict are computed in code (via `rec_quality.overall_from_scores`)
so the critical-dimension logic stays centralized and the judge can't hand-wave a
dislike-violating rec into "good".

Used by both the QA cockpit endpoint (scores shown beside each card) and the
offline eval harness (`eval/run_eval.py`).

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Literal, Optional

from anthropic import AsyncAnthropic
from pydantic import BaseModel, Field

from app.agents.state import BudgetRange, CandidateRecommendation, VaultData
from app.core.config import ANTHROPIC_API_KEY, is_anthropic_configured
from app.services import rec_quality
from app.services.llm_tuning import fast_generation_params

logger = logging.getLogger(__name__)

# Sonnet is the right tier for a small, high-value scoring call — richer judgment
# than Haiku, and latency is not user-facing here (QA / offline eval).
JUDGE_MODEL = "claude-sonnet-4-6"
JUDGE_MAX_TOKENS = 1500

# Overall score at/above which a recommendation is labelled "good".
GOOD_THRESHOLD = 0.7

# Score used when a NON-critical dimension the judge should have scored is
# missing/invalid — neutral, so it neither helps nor hurts.
_MISSING_DIMENSION_SCORE = 0.5
# Score used when a CRITICAL dimension (grounded/dislike_safe) is missing/invalid.
# Below FAIL_THRESHOLD so an omitted critical dimension trips the critical cap in
# overall_from_scores — the judge must AFFIRM safety/grounding, silence is not "good".
_MISSING_CRITICAL_SCORE = 0.0


class RecommendationJudgment(BaseModel):
    """The judge's verdict on a single recommendation."""

    dimension_scores: dict[str, float] = Field(default_factory=dict)
    overall: float = 0.0
    verdict: Literal["good", "bad"] = "bad"
    rationale: str = ""
    model: str = JUDGE_MODEL


JUDGE_SYSTEM_PROMPT = """\
You are a strict quality reviewer for Knot, a relationship app that recommends \
gifts, dates, experiences, and personalized ideas for someone's partner. You are \
grading ONE recommendation against a fixed rubric. Be honest and critical — your \
job is to catch weak, generic, or off-target recommendations, not to be kind.

{rubric}

Return ONLY a JSON object (no markdown, no code fences, no prose) of the form:
{{"scores": {{"<dimension_id>": 0.0-1.0, ...}}, "rationale": "one or two sentences \
naming the biggest strength and the biggest weakness"}}
Only include dimension ids that apply to this recommendation's type."""


def _build_judge_user_prompt(
    rec: CandidateRecommendation,
    vault_data: VaultData,
    budget_range: Optional[BudgetRange],
) -> str:
    """Render the partner profile + the recommendation under review."""
    parts: list[str] = ["=== PARTNER PROFILE ==="]
    parts.append(f"Name: {vault_data.partner_name}")
    if vault_data.location_city:
        loc = ", ".join(p for p in (vault_data.location_city, vault_data.location_state) if p)
        parts.append(f"Location: {loc}")
    parts.append(f"Interests (LOVES): {', '.join(vault_data.interests)}")
    parts.append(f"Dislikes (HARD AVOID): {', '.join(vault_data.dislikes)}")
    parts.append(f"Aesthetic vibes: {', '.join(vault_data.vibes)}")
    parts.append(
        f"Love languages: {vault_data.primary_love_language} (primary), "
        f"{vault_data.secondary_love_language} (secondary)"
    )
    if budget_range is not None:
        parts.append(
            f"Budget: ${budget_range.min_amount / 100:.0f}–${budget_range.max_amount / 100:.0f} "
            f"{budget_range.currency}"
        )

    parts.append("\n=== RECOMMENDATION UNDER REVIEW ===")
    parts.append(f"Type: {rec.type}")
    parts.append(f"Title: {rec.title}")
    if rec.description:
        parts.append(f"Description: {rec.description}")
    if rec.personalization_note:
        parts.append(f"Personalization note: {rec.personalization_note}")
    if rec.merchant_name:
        parts.append(f"Merchant: {rec.merchant_name}")
    if rec.price_cents is not None:
        parts.append(f"Price: ${rec.price_cents / 100:.2f}")
    if rec.search_query:
        parts.append(f"Search query: {rec.search_query}")
    if rec.matched_interests:
        parts.append(f"Claims to match interests: {', '.join(rec.matched_interests)}")
    if rec.matched_vibes:
        parts.append(f"Claims to match vibes: {', '.join(rec.matched_vibes)}")
    if rec.content_sections:
        headings = [s.get("heading", s.get("type", "")) for s in rec.content_sections if isinstance(s, dict)]
        parts.append(f"Content sections: {', '.join(h for h in headings if h)}")

    applicable = [d.id for d in rec_quality.dimensions_for_type(rec.type)]
    parts.append(f"\nScore these dimensions for this {rec.type}: {', '.join(applicable)}")
    return "\n".join(parts)


def _parse_json_object(text: str) -> dict[str, Any]:
    """Parse a JSON object from a model response, tolerating code fences."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else text[3:]
    if text.endswith("```"):
        text = text[:-3].strip()
    if text.startswith("json"):
        text = text[4:].strip()
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("Judge response was not a JSON object")
    return parsed


def _coerce_scores(raw_scores: Any, rec_type: str) -> dict[str, float]:
    """Keep only applicable dimensions, clamp to [0,1], fill missing/invalid.

    A missing or unparseable dimension falls to a neutral 0.5, EXCEPT a critical
    dimension (grounded/dislike_safe), which falls to a failing score so the judge
    omitting it can't let a dislike-violating rec pass as "good". JSON booleans are
    treated as a formatting slip (not a real 0.0/1.0), so they take the same default.
    """
    raw = raw_scores if isinstance(raw_scores, dict) else {}
    scores: dict[str, float] = {}
    for dim in rec_quality.dimensions_for_type(rec_type):
        default = _MISSING_CRITICAL_SCORE if dim.critical else _MISSING_DIMENSION_SCORE
        value = raw.get(dim.id)
        if isinstance(value, bool):
            score = default
        else:
            try:
                score = float(value)
            except (TypeError, ValueError):
                score = default
        scores[dim.id] = max(0.0, min(1.0, score))
    return scores


async def judge_recommendation(
    rec: CandidateRecommendation,
    vault_data: VaultData,
    budget_range: Optional[BudgetRange] = None,
    model: str = JUDGE_MODEL,
) -> RecommendationJudgment:
    """Score one recommendation against the rubric.

    Raises RuntimeError if Anthropic is not configured (the judge is required
    for the eval harness; the QA endpoint guards on `is_anthropic_configured()`
    before calling).
    """
    if not is_anthropic_configured():
        raise RuntimeError("Anthropic API key not configured — cannot judge recommendations")

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
    system = JUDGE_SYSTEM_PROMPT.format(rubric=rec_quality.rubric_for_judge())
    user = _build_judge_user_prompt(rec, vault_data, budget_range)

    response = await client.messages.create(
        model=model,
        max_tokens=JUDGE_MAX_TOKENS,
        system=system,
        messages=[{"role": "user", "content": user}],
        **fast_generation_params(model),
    )

    # Scan for the first non-empty text block rather than assuming content[0] is
    # text — a leading thinking/tool block or empty content would otherwise raise.
    text = next(
        (
            block.text
            for block in response.content
            if getattr(block, "type", None) == "text" and getattr(block, "text", None)
        ),
        None,
    )
    if text is None:
        raise RuntimeError("Judge response contained no text block")
    parsed = _parse_json_object(text)
    scores = _coerce_scores(parsed.get("scores"), rec.type)
    overall = rec_quality.overall_from_scores(scores)

    return RecommendationJudgment(
        dimension_scores=scores,
        overall=round(overall, 3),
        verdict="good" if overall >= GOOD_THRESHOLD else "bad",
        rationale=str(parsed.get("rationale", "")).strip(),
        model=model,
    )
