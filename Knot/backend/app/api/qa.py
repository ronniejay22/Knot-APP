"""
Recommendation QA cockpit API — dev-only tooling to review and tune
recommendation quality.

Gated by KNOT_QA_ENABLED (config.QA_ENABLED). Every route 403s when the flag is
unset, so this surface and its dev storage are never exposed in production.

Flow:
  GET  /qa                      → the static QA web tool (app/static/qa.html)
  GET  /api/v1/qa/profiles      → sample profiles + rubric reason chips
  POST /api/v1/qa/generate      → generate recs for a profile (choose model, judge,
                                   steering); recent persisted verdicts re-steer output
  POST /api/v1/qa/verdict       → store a like/dislike + reason for a rec

The verdicts are both persisted (feeding the eval harness) and read back on the
next generate as QA-steering exemplars — the "re-steer + persist" loop.

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path
from typing import Any, Literal, Optional

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app.agents.state import BudgetRange
from app.core.config import API_V1_PREFIX, QA_ENABLED, is_anthropic_configured
from app.db.supabase_client import get_service_client
from app.models.qa_verdict import QAVerdict
from app.services import qa_profiles, rec_quality
from app.services.rec_judge import RecommendationJudgment, judge_recommendation
from app.services.unified_generation import generate_unified_recommendations
from app.services.vault_loader import find_budget_range, load_vault_data

logger = logging.getLogger(__name__)

router = APIRouter(tags=["qa"])

_STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

# Rubric dimension id → human label, for turning stored reason_dimensions into
# readable steering text.
_DIMENSION_LABELS = {chip["id"]: chip["label"] for chip in rec_quality.rubric_reason_chips()}

# How many recent verdicts to pull per profile when building steering context.
_STEERING_LOOKBACK = 40
_STEERING_PER_SIDE = 8


def _require_qa_enabled() -> None:
    """Raise 403 unless the QA cockpit is explicitly enabled for this env."""
    if not QA_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="QA cockpit is disabled in this environment (set KNOT_QA_ENABLED=true).",
        )


# ======================================================================
# Request / response models
# ======================================================================

class QAGenerateRequest(BaseModel):
    profile_id: Optional[str] = None
    vault_user_id: Optional[str] = None
    occasion_type: Literal["just_because", "minor_occasion", "major_milestone"] = "minor_occasion"
    model: Optional[str] = None  # None → generator default (Haiku)
    use_judge: bool = False
    use_steering: bool = True


class QAVerdictRequest(BaseModel):
    profile_id: Optional[str] = None
    rec_snapshot: dict[str, Any] = Field(default_factory=dict)
    verdict: Literal["like", "dislike"]
    reason_dimensions: list[str] = Field(default_factory=list)
    reason_text: Optional[str] = None
    generation_config: dict[str, Any] = Field(default_factory=dict)


# ======================================================================
# Steering helpers
# ======================================================================

def _verdict_to_exemplar(row: dict[str, Any]) -> dict[str, Any]:
    """Turn a stored verdict row into a generation steering exemplar."""
    snapshot = row.get("rec_snapshot") or {}
    reasons = [_DIMENSION_LABELS.get(d, d) for d in (row.get("reason_dimensions") or [])]
    return {
        "title": snapshot.get("title", ""),
        "reasons": reasons,
        "note": row.get("reason_text") or "",
    }


def _fetch_steering(profile_id: Optional[str]) -> tuple[list[dict], list[dict]]:
    """Fetch recent verdicts for a profile and split into liked/disliked exemplars.

    Returns ([], []) on any failure — steering is best-effort and must never
    block generation.
    """
    if not profile_id:
        return [], []
    try:
        client = get_service_client()
        query = (
            client.table("rec_qa_verdicts")
            .select("rec_snapshot, verdict, reason_dimensions, reason_text")
            .eq("profile_id", profile_id)
            .order("created_at", desc=True)
            .limit(_STEERING_LOOKBACK)
        )
        rows = query.execute().data or []
    except Exception as exc:  # pragma: no cover - network/db failure path
        logger.warning("QA steering fetch failed for profile %s: %s", profile_id, exc)
        return [], []

    liked = [_verdict_to_exemplar(r) for r in rows if r.get("verdict") == "like"]
    disliked = [_verdict_to_exemplar(r) for r in rows if r.get("verdict") == "dislike"]
    return liked[:_STEERING_PER_SIDE], disliked[:_STEERING_PER_SIDE]


# ======================================================================
# Routes
# ======================================================================

@router.get("/qa", response_class=HTMLResponse)
async def qa_cockpit_page() -> HTMLResponse:
    """Serve the static QA web tool."""
    _require_qa_enabled()
    html_path = _STATIC_DIR / "qa.html"
    if not html_path.exists():
        raise HTTPException(status_code=500, detail="QA cockpit page not found.")
    return HTMLResponse(html_path.read_text(encoding="utf-8"))


@router.get(f"{API_V1_PREFIX}/qa/profiles")
async def qa_list_profiles() -> dict[str, Any]:
    """List sample profiles and the rubric reason chips for the QA modal."""
    _require_qa_enabled()
    return {
        "profiles": qa_profiles.list_sample_profiles(),
        "reason_chips": rec_quality.rubric_reason_chips(),
    }


@router.post(f"{API_V1_PREFIX}/qa/generate")
async def qa_generate(payload: QAGenerateRequest) -> dict[str, Any]:
    """Generate recommendations for a profile, with optional judging + steering."""
    _require_qa_enabled()

    # Resolve the profile → (vault_data, budgets).
    if payload.vault_user_id:
        try:
            vault_data, _ = await load_vault_data(payload.vault_user_id)
        except Exception as exc:
            raise HTTPException(status_code=404, detail=f"Could not load vault: {exc}")
        hints: list = []
        profile_key = payload.vault_user_id
    else:
        profile = qa_profiles.get_sample_profile(payload.profile_id or "")
        if profile is None:
            raise HTTPException(status_code=404, detail="Unknown sample profile_id.")
        vault_data = profile.vault
        hints = profile.hints
        profile_key = profile.id

    budget_range: BudgetRange = find_budget_range(vault_data.budgets, payload.occasion_type)

    liked, disliked = ([], [])
    if payload.use_steering:
        liked, disliked = _fetch_steering(profile_key)

    recommendations = await generate_unified_recommendations(
        vault_data=vault_data,
        hints=hints,
        occasion_type=payload.occasion_type,
        budget_range=budget_range,
        liked_exemplars=liked,
        disliked_exemplars=disliked,
        model=payload.model,
    )

    judgments: list[Optional[dict[str, Any]]] = [None] * len(recommendations)
    if payload.use_judge and recommendations and is_anthropic_configured():
        # return_exceptions so a single judge/parse failure yields a null judgment
        # for that card rather than failing the whole request.
        results = await asyncio.gather(
            *(judge_recommendation(rec, vault_data, budget_range) for rec in recommendations),
            return_exceptions=True,
        )
        judgments = [
            (r.model_dump() if isinstance(r, RecommendationJudgment) else None) for r in results
        ]

    recs_out = []
    for rec, judgment in zip(recommendations, judgments):
        item = rec.model_dump()
        item["judgment"] = judgment
        recs_out.append(item)

    # Report the model actually used (recorded on each rec's metadata).
    model_used = payload.model
    if recommendations:
        model_used = recommendations[0].metadata.get("generation_model", payload.model)

    return {
        "profile_id": profile_key,
        "partner_name": vault_data.partner_name,
        "occasion_type": payload.occasion_type,
        "model": model_used,
        "steering_applied": {"liked": len(liked), "disliked": len(disliked)},
        "count": len(recs_out),
        "recommendations": recs_out,
    }


@router.post(f"{API_V1_PREFIX}/qa/verdict", status_code=status.HTTP_201_CREATED)
async def qa_store_verdict(payload: QAVerdictRequest) -> dict[str, Any]:
    """Persist a like/dislike verdict + reason for one recommendation."""
    _require_qa_enabled()

    # Keep only known rubric dimension ids so steering/eval stay clean.
    clean_dimensions = [d for d in payload.reason_dimensions if d in rec_quality.ALL_DIMENSION_IDS]

    verdict = QAVerdict(
        profile_id=payload.profile_id,
        rec_snapshot=payload.rec_snapshot,
        verdict=payload.verdict,
        reason_dimensions=clean_dimensions,
        reason_text=payload.reason_text,
        generation_config=payload.generation_config,
    )

    row = {
        "evaluator": verdict.evaluator,
        "profile_id": verdict.profile_id,
        "rec_snapshot": verdict.rec_snapshot,
        "verdict": verdict.verdict,
        "reason_dimensions": verdict.reason_dimensions,
        "reason_text": verdict.reason_text,
        "generation_config": verdict.generation_config,
    }

    try:
        client = get_service_client()
        result = client.table("rec_qa_verdicts").insert(row).execute()
    except Exception as exc:
        logger.error("Failed to store QA verdict: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to store verdict.")

    inserted = (result.data or [{}])[0]
    return {"ok": True, "id": inserted.get("id")}
