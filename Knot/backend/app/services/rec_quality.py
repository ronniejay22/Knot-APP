"""
Recommendation Quality Rubric — the single source of truth for what makes a
recommendation "good" vs. "bad".

One rubric definition, reused in three places so they can never drift apart:
  1. Generation — `rubric_prompt_guidance()` is appended to the generation
     system prompt so Claude generates against the same bar it will be judged by.
  2. Human QA — `rubric_reason_chips()` supplies the "why did you like/dislike
     this?" options in the QA cockpit, tagged to rubric dimensions.
  3. LLM judge / eval — `rubric_for_judge()` tells the judge model how to score
     each dimension, and `RUBRIC_DIMENSION_IDS` validates judge output.

The dimensions are derived from the PRD (F1 strict-interest grounding, the
"Recommendation Hit Rate" KPI) and the existing generation prompt's rules
(location grounding, natural prose, dislike avoidance, real/bookable items).

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

from dataclasses import dataclass

# Recommendation types the pipeline can emit (mirror of state.CandidateRecommendation.type).
_PURCHASABLE_TYPES = {"gift", "experience", "date"}
_LOCATION_BOUND_TYPES = {"experience", "date", "plan"}


@dataclass(frozen=True)
class RubricDimension:
    """A single scored quality dimension.

    Attributes:
        id: Stable machine key (used in judge output, QA verdict storage, chips).
        label: Short human label for the QA cockpit.
        like_reason: How this dimension reads when the evaluator LIKED a rec.
        dislike_reason: How it reads when the evaluator DISLIKED a rec.
        judge_guidance: What the judge should look for when scoring 0.0–1.0.
        applies_to: Recommendation types this dimension is scored for. None = all.
        critical: If True, a failing score here makes the whole rec "bad"
            regardless of the other dimensions (e.g. it references a hard-avoid).
    """

    id: str
    label: str
    like_reason: str
    dislike_reason: str
    judge_guidance: str
    applies_to: frozenset[str] | None = None
    critical: bool = False

    def applies_to_type(self, rec_type: str) -> bool:
        """Whether this dimension is scored for a recommendation of ``rec_type``."""
        return self.applies_to is None or rec_type in self.applies_to


# ======================================================================
# The rubric — ordered from most to least load-bearing.
# ======================================================================

RUBRIC: tuple[RubricDimension, ...] = (
    RubricDimension(
        id="grounded",
        label="Grounded in their profile",
        like_reason="Clearly built from their interests, hints, or vibes",
        dislike_reason="Generic — could be for anyone, not this partner",
        judge_guidance=(
            "Does the recommendation (and its personalization_note) draw on the "
            "partner's SPECIFIC interests, captured hints, vibes, or love languages? "
            "Score high only when the connection is concrete and personal; score low "
            "for anything that reads as one-size-fits-all."
        ),
        critical=True,
    ),
    RubricDimension(
        id="dislike_safe",
        label="Avoids their dislikes",
        like_reason="Steers clear of everything they dislike",
        dislike_reason="Touches one of their hard-avoids",
        judge_guidance=(
            "Does the recommendation avoid EVERY item in the partner's dislikes / "
            "hard-avoids? Any overlap — even tangential — is an automatic fail (0.0)."
        ),
        critical=True,
    ),
    RubricDimension(
        id="specific",
        label="Specific and real",
        like_reason="Names a concrete, real thing — not a vague placeholder",
        dislike_reason="Vague or generic (\"a nice restaurant\", \"a fun class\")",
        judge_guidance=(
            "For purchasables: does it name an actual product / brand / venue you "
            "could really buy or book? For ideas/plans: are the steps concrete enough "
            "to actually follow? Penalize placeholders like \"a local park\" or "
            "\"a cozy spot\"."
        ),
    ),
    RubricDimension(
        id="budget_fit",
        label="Fits the budget",
        like_reason="Priced right for the occasion and budget",
        dislike_reason="Too expensive or too cheap for the budget",
        judge_guidance=(
            "For purchasable items, is the price within the stated budget range and "
            "appropriate to the occasion tier? Ideas/plans are exempt (score 1.0)."
        ),
        applies_to=frozenset(_PURCHASABLE_TYPES),
    ),
    RubricDimension(
        id="vibe_fit",
        label="Matches their vibe",
        like_reason="Nails their aesthetic / vibe",
        dislike_reason="Wrong aesthetic — off-vibe",
        judge_guidance=(
            "Does the recommendation align with the partner's aesthetic vibes? "
            "Score low when it clashes with their stated vibe."
        ),
    ),
    RubricDimension(
        id="love_language_fit",
        label="Speaks their love language",
        like_reason="Lands on their primary/secondary love language",
        dislike_reason="Ignores how they actually receive love",
        judge_guidance=(
            "Does the recommendation support the partner's primary or secondary love "
            "language (e.g. quality_time → shared experience, receiving_gifts → a "
            "thoughtful object)?"
        ),
    ),
    RubricDimension(
        id="location_fit",
        label="Locally grounded",
        like_reason="Anchored in their city with real, local places",
        dislike_reason="City-agnostic filler or a generic \"local store\"",
        judge_guidance=(
            "When a city is known, are dates/experiences/plans (and supply runs for "
            "at-home ideas) anchored in that city with real neighborhoods and venues, "
            "rather than generic filler? If no city is known, score 1.0."
        ),
        applies_to=frozenset(_LOCATION_BOUND_TYPES),
    ),
    RubricDimension(
        id="actionable",
        label="Actionable",
        like_reason="Something you could actually do or buy right now",
        dislike_reason="No real way to act on it",
        judge_guidance=(
            "Purchasables: is there a plausible real buy/book path (a real merchant / "
            "search_query, not an article or listicle)? Ideas/plans: do they include a "
            "complete overview + steps someone could follow end-to-end?"
        ),
    ),
    RubricDimension(
        id="well_written",
        label="Well written",
        like_reason="Warm, clear, complete copy",
        dislike_reason="Awkward, cut off, or full of raw tags/underscores",
        judge_guidance=(
            "Is the title/description/personalization_note natural, warm, and "
            "complete? Penalize raw tag identifiers or underscores in prose "
            "(e.g. \"quiet_luxury\"), mid-sentence cutoffs, and repetition between the "
            "description and the personalization_note."
        ),
    ),
)

# Set-level dimension — scored across the trio, not per recommendation. Kept
# separate so the per-rec judge never tries to score it in isolation.
DIVERSITY_DIMENSION = RubricDimension(
    id="diversity",
    label="Diverse set",
    like_reason="The set varies type, price, and feel",
    dislike_reason="The set is repetitive / samey",
    judge_guidance=(
        "Across the shown set, do the recommendations vary in type "
        "(gift/experience/date/idea/plan), price range, and overall nature — with at "
        "least one linkless idea/plan? Penalize near-duplicates."
    ),
)

RUBRIC_DIMENSION_IDS: frozenset[str] = frozenset(d.id for d in RUBRIC)
ALL_DIMENSION_IDS: frozenset[str] = RUBRIC_DIMENSION_IDS | {DIVERSITY_DIMENSION.id}
CRITICAL_DIMENSION_IDS: frozenset[str] = frozenset(d.id for d in RUBRIC if d.critical)

# A rec scoring at or below this on any dimension is treated as failing it.
FAIL_THRESHOLD = 0.5


def dimensions_for_type(rec_type: str) -> list[RubricDimension]:
    """Return the per-rec rubric dimensions that apply to ``rec_type``."""
    return [d for d in RUBRIC if d.applies_to_type(rec_type)]


def rubric_prompt_guidance() -> str:
    """Render the rubric as generation guidance appended to the system prompt.

    Keeps generation honest against the same bar the judge and human QA use.
    """
    lines = [
        "QUALITY BAR — every recommendation you produce is scored against this "
        "rubric, so build to it:",
    ]
    for i, d in enumerate(RUBRIC, start=1):
        marker = " (CRITICAL — a violation makes the whole recommendation bad)" if d.critical else ""
        lines.append(f"{i}. {d.label}{marker}: {d.judge_guidance}")
    lines.append(
        f"{len(RUBRIC) + 1}. {DIVERSITY_DIMENSION.label}: {DIVERSITY_DIMENSION.judge_guidance}"
    )
    return "\n".join(lines)


def rubric_for_judge() -> str:
    """Render per-dimension scoring instructions for the LLM judge."""
    lines = [
        "Score each dimension from 0.0 (fails completely) to 1.0 (nails it). "
        "Only score dimensions that apply to the recommendation's type.",
    ]
    for d in RUBRIC:
        scope = "all types" if d.applies_to is None else ", ".join(sorted(d.applies_to))
        crit = " [CRITICAL: 0.0 here = the recommendation is BAD overall]" if d.critical else ""
        lines.append(f'- "{d.id}" ({d.label}; applies to: {scope}){crit}: {d.judge_guidance}')
    return "\n".join(lines)


def rubric_reason_chips() -> list[dict[str, str]]:
    """Reason options for the QA "why did you like/dislike this?" modal.

    Each chip carries both polarities so the frontend can show the wording that
    matches the evaluator's verdict while storing the stable dimension ``id``.
    Includes the set-level diversity dimension since the evaluator may cite it.
    """
    chips = [
        {
            "id": d.id,
            "label": d.label,
            "like_reason": d.like_reason,
            "dislike_reason": d.dislike_reason,
        }
        for d in RUBRIC
    ]
    chips.append(
        {
            "id": DIVERSITY_DIMENSION.id,
            "label": DIVERSITY_DIMENSION.label,
            "like_reason": DIVERSITY_DIMENSION.like_reason,
            "dislike_reason": DIVERSITY_DIMENSION.dislike_reason,
        }
    )
    return chips


def overall_from_scores(scores: dict[str, float]) -> float:
    """Combine per-dimension scores (0.0–1.0) into a single overall quality score.

    The mean of the applicable dimensions, except that a failing CRITICAL
    dimension (grounded / dislike_safe) hard-caps the overall at its own value —
    a rec that references a hard-avoid cannot be "good" no matter how polished.
    """
    applicable = {k: v for k, v in scores.items() if k in RUBRIC_DIMENSION_IDS}
    if not applicable:
        return 0.0

    mean = sum(applicable.values()) / len(applicable)

    critical_fail = min(
        (v for k, v in applicable.items() if k in CRITICAL_DIMENSION_IDS and v < FAIL_THRESHOLD),
        default=None,
    )
    if critical_fail is not None:
        return min(mean, critical_fail)
    return mean
