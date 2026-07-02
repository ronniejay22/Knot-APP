"""
Offline recommendation-quality eval harness.

For each sample profile it generates recommendations and scores every one with
the LLM judge against the rubric, then aggregates per-dimension and overall
quality. Point it at two models to quantify the quality/latency tradeoff
(e.g. Haiku 4.5 vs Sonnet 4.6) instead of guessing.

Run from the backend directory:

    python -m eval.run_eval                       # default model, all profiles
    python -m eval.run_eval --models claude-haiku-4-5,claude-sonnet-4-6
    python -m eval.run_eval --profiles quiet-luxury-foodie --occasion major_milestone
    python -m eval.run_eval --json eval_report.json

Requires ANTHROPIC_API_KEY (the judge is an LLM call).

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import time
from collections import defaultdict
from typing import Any, Optional

from app.agents.state import CandidateRecommendation
from app.core.config import is_anthropic_configured
from app.services import qa_profiles, rec_quality
from app.services.rec_judge import RecommendationJudgment, judge_recommendation
from app.services.unified_generation import generate_unified_recommendations
from app.services.vault_loader import find_budget_range


def summarize(judged: list[tuple[CandidateRecommendation, RecommendationJudgment]]) -> dict[str, Any]:
    """Aggregate judged recommendations into a quality summary.

    Pure function (no I/O) so it is unit-testable. Reports:
      - mean overall score and good-rate
      - per-dimension mean scores
      - type distribution (a proxy for set diversity)
    """
    if not judged:
        return {"count": 0, "mean_overall": 0.0, "good_rate": 0.0,
                "per_dimension_mean": {}, "type_distribution": {}}

    overalls = [j.overall for _, j in judged]
    good = sum(1 for _, j in judged if j.verdict == "good")

    dim_totals: dict[str, float] = defaultdict(float)
    dim_counts: dict[str, int] = defaultdict(int)
    for _, j in judged:
        for dim, score in j.dimension_scores.items():
            dim_totals[dim] += score
            dim_counts[dim] += 1

    per_dimension_mean = {
        dim: round(dim_totals[dim] / dim_counts[dim], 3) for dim in dim_totals
    }

    type_distribution: dict[str, int] = defaultdict(int)
    for rec, _ in judged:
        type_distribution[rec.type] += 1

    return {
        "count": len(judged),
        "mean_overall": round(sum(overalls) / len(overalls), 3),
        "good_rate": round(good / len(judged), 3),
        "per_dimension_mean": per_dimension_mean,
        "type_distribution": dict(type_distribution),
    }


async def eval_profile(
    profile: qa_profiles.QAProfile,
    occasion_type: str,
    model: Optional[str],
) -> dict[str, Any]:
    """Generate + judge recommendations for one profile."""
    budget_range = find_budget_range(profile.vault.budgets, occasion_type)
    started = time.monotonic()
    recs = await generate_unified_recommendations(
        vault_data=profile.vault,
        hints=profile.hints,
        occasion_type=occasion_type,
        budget_range=budget_range,
        model=model,
    )
    gen_seconds = round(time.monotonic() - started, 1)

    # return_exceptions so one malformed judge reply degrades to skipping that
    # rec rather than aborting a whole multi-profile / multi-model comparison run.
    results = await asyncio.gather(
        *(judge_recommendation(rec, profile.vault, budget_range) for rec in recs),
        return_exceptions=True,
    )
    judged = [
        (rec, j) for rec, j in zip(recs, results) if isinstance(j, RecommendationJudgment)
    ]

    summary = summarize(judged)
    summary["profile_id"] = profile.id
    summary["gen_seconds"] = gen_seconds
    summary["recommendations"] = [
        {"title": rec.title, "type": rec.type, "overall": j.overall,
         "verdict": j.verdict, "rationale": j.rationale}
        for rec, j in judged
    ]
    return summary


async def run_eval(
    profile_ids: Optional[list[str]],
    occasion_type: str,
    models: list[Optional[str]],
) -> dict[str, Any]:
    """Run the eval across profiles for each model, returning a report dict.

    Raises ValueError if any requested profile id is unknown, so a typo surfaces
    as an error rather than a misleading all-zero report.
    """
    if profile_ids:
        unknown = [p for p in profile_ids if p not in qa_profiles.SAMPLE_PROFILES]
        if unknown:
            raise ValueError(
                f"Unknown profile id(s): {', '.join(unknown)}. "
                f"Known: {', '.join(qa_profiles.SAMPLE_PROFILES)}"
            )
        profiles = [qa_profiles.SAMPLE_PROFILES[p] for p in profile_ids]
    else:
        profiles = list(qa_profiles.SAMPLE_PROFILES.values())

    report: dict[str, Any] = {"occasion_type": occasion_type, "by_model": {}}
    for model in models:
        model_key = model or "default"
        per_profile = []
        for profile in profiles:
            per_profile.append(await eval_profile(profile, occasion_type, model))

        overalls = [p["mean_overall"] for p in per_profile if p["count"]]
        good_rates = [p["good_rate"] for p in per_profile if p["count"]]
        report["by_model"][model_key] = {
            "profiles": per_profile,
            "mean_overall": round(sum(overalls) / len(overalls), 3) if overalls else 0.0,
            "mean_good_rate": round(sum(good_rates) / len(good_rates), 3) if good_rates else 0.0,
        }
    return report


def format_report(report: dict[str, Any]) -> str:
    """Render a human-readable report."""
    lines = [f"Recommendation quality eval — occasion: {report['occasion_type']}", "=" * 60]
    for model_key, data in report["by_model"].items():
        lines.append(f"\nMODEL: {model_key}")
        lines.append(f"  mean overall: {data['mean_overall']:.3f} | good-rate: {data['mean_good_rate']:.3f}")
        for p in data["profiles"]:
            lines.append(
                f"  · {p['profile_id']:<26} overall {p['mean_overall']:.2f} "
                f"good {p['good_rate']:.2f} ({p['count']} recs, {p.get('gen_seconds', '?')}s)"
            )
    if len(report["by_model"]) > 1:
        lines.append("\nDimension means (per model):")
        for model_key, data in report["by_model"].items():
            agg: dict[str, list[float]] = defaultdict(list)
            for p in data["profiles"]:
                for dim, v in p["per_dimension_mean"].items():
                    agg[dim].append(v)
            dims = ", ".join(
                f"{d}={sum(vs) / len(vs):.2f}" for d, vs in sorted(agg.items())
            )
            lines.append(f"  {model_key}: {dims}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Recommendation quality eval harness")
    parser.add_argument("--profiles", help="Comma-separated sample profile ids (default: all)")
    parser.add_argument("--occasion", default="minor_occasion",
                        choices=["just_because", "minor_occasion", "major_milestone"])
    parser.add_argument("--models", default="",
                        help="Comma-separated model ids to compare (default: the generator default)")
    parser.add_argument("--json", help="Write the full report to this JSON path")
    args = parser.parse_args()

    if not is_anthropic_configured():
        raise SystemExit("ANTHROPIC_API_KEY is not configured — the eval harness needs it to judge.")

    profile_ids = [p.strip() for p in args.profiles.split(",")] if args.profiles else None
    models: list[Optional[str]] = (
        [m.strip() for m in args.models.split(",") if m.strip()] if args.models else [None]
    )

    try:
        report = asyncio.run(run_eval(profile_ids, args.occasion, models))
    except ValueError as exc:
        raise SystemExit(str(exc))
    print(format_report(report))
    print("\nRubric dimensions:", ", ".join(sorted(rec_quality.RUBRIC_DIMENSION_IDS)))

    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
        print(f"\nWrote full report to {args.json}")


if __name__ == "__main__":
    main()
