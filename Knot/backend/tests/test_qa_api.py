"""
Tests for the dev-gated QA cockpit API and its generation hooks (Step 20.1).

Covers: the KNOT_QA_ENABLED gate (403 when off), profile listing, generate with
mocked generation + judge + steering, verdict storage (with dimension
sanitizing), the steering fetch/split, and the generation-layer wiring the
cockpit depends on (QA-steering prompt injection + model override).
"""

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.agents.state import CandidateRecommendation
from app.main import app
from app.services.rec_judge import RecommendationJudgment

client = TestClient(app)


def _rec(title="A gift", rec_type="gift", **kw) -> CandidateRecommendation:
    base = dict(id="r1", source="unified", type=rec_type, title=title,
                description="d", personalization_note="p", metadata={"generation_model": "claude-haiku-4-5"})
    base.update(kw)
    return CandidateRecommendation(**base)


@pytest.fixture
def qa_on(monkeypatch):
    monkeypatch.setattr("app.api.qa.QA_ENABLED", True)


@pytest.fixture
def qa_off(monkeypatch):
    monkeypatch.setattr("app.api.qa.QA_ENABLED", False)


# ---------------------------------------------------------------------------
# Gating
# ---------------------------------------------------------------------------

class TestGating:
    def test_all_routes_403_when_disabled(self, qa_off):
        assert client.get("/qa").status_code == 403
        assert client.get("/api/v1/qa/profiles").status_code == 403
        assert client.post("/api/v1/qa/generate", json={"profile_id": "x"}).status_code == 403
        assert client.post("/api/v1/qa/verdict",
                           json={"verdict": "like"}).status_code == 403

    def test_page_and_profiles_when_enabled(self, qa_on):
        page = client.get("/qa")
        assert page.status_code == 200
        assert "Recommendation QA" in page.text

        resp = client.get("/api/v1/qa/profiles")
        assert resp.status_code == 200
        body = resp.json()
        assert len(body["profiles"]) == 6
        assert any(c["id"] == "grounded" for c in body["reason_chips"])


# ---------------------------------------------------------------------------
# Generate
# ---------------------------------------------------------------------------

class TestGenerate:
    def test_unknown_profile_404(self, qa_on):
        with patch("app.api.qa._fetch_steering", return_value=([], [])):
            resp = client.post("/api/v1/qa/generate", json={"profile_id": "does-not-exist"})
        assert resp.status_code == 404

    def test_happy_path_without_judge(self, qa_on):
        recs = [_rec("Gift A"), _rec("Idea B", rec_type="idea")]
        with patch("app.api.qa.generate_unified_recommendations",
                   new=AsyncMock(return_value=recs)), \
             patch("app.api.qa._fetch_steering", return_value=([], [])):
            resp = client.post("/api/v1/qa/generate",
                               json={"profile_id": "quiet-luxury-foodie", "use_judge": False})
        assert resp.status_code == 200
        body = resp.json()
        assert body["count"] == 2
        assert body["recommendations"][0]["title"] == "Gift A"
        assert body["recommendations"][0]["judgment"] is None
        assert body["model"] == "claude-haiku-4-5"

    def test_with_judge_attaches_scores(self, qa_on):
        recs = [_rec("Gift A")]
        judgment = RecommendationJudgment(
            dimension_scores={"grounded": 0.9}, overall=0.82, verdict="good", rationale="nice"
        )
        with patch("app.api.qa.generate_unified_recommendations",
                   new=AsyncMock(return_value=recs)), \
             patch("app.api.qa._fetch_steering", return_value=([], [])), \
             patch("app.api.qa.is_anthropic_configured", return_value=True), \
             patch("app.api.qa.judge_recommendation",
                   new=AsyncMock(return_value=judgment)):
            resp = client.post("/api/v1/qa/generate",
                               json={"profile_id": "quiet-luxury-foodie", "use_judge": True})
        body = resp.json()
        assert body["recommendations"][0]["judgment"]["verdict"] == "good"
        assert body["recommendations"][0]["judgment"]["overall"] == 0.82


# ---------------------------------------------------------------------------
# Verdict storage
# ---------------------------------------------------------------------------

class _FakeExec:
    def __init__(self, data):
        self._data = data

    def execute(self):
        return MagicMock(data=self._data)


class _FakeTable:
    def __init__(self, store):
        self.store = store

    def insert(self, row):
        self.store["inserted"] = row
        return _FakeExec([{"id": "verdict-1"}])

    def select(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def order(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def execute(self):
        return MagicMock(data=self.store.get("rows", []))


class _FakeClient:
    def __init__(self, store):
        self.store = store

    def table(self, _name):
        return _FakeTable(self.store)


class TestVerdict:
    def test_stores_and_sanitizes_dimensions(self, qa_on):
        store: dict = {}
        with patch("app.api.qa.get_service_client", return_value=_FakeClient(store)):
            resp = client.post("/api/v1/qa/verdict", json={
                "profile_id": "quiet-luxury-foodie",
                "rec_snapshot": {"title": "Gift A"},
                "verdict": "dislike",
                "reason_dimensions": ["grounded", "bogus_dim", "budget_fit"],
                "reason_text": "too generic",
            })
        assert resp.status_code == 201
        assert resp.json()["ok"] is True
        # Unknown dimensions are dropped; valid ones kept.
        assert store["inserted"]["reason_dimensions"] == ["grounded", "budget_fit"]
        assert store["inserted"]["verdict"] == "dislike"


class TestSteeringFetch:
    def test_splits_like_and_dislike(self, qa_on):
        rows = [
            {"rec_snapshot": {"title": "Liked one"}, "verdict": "like",
             "reason_dimensions": ["grounded"], "reason_text": "great"},
            {"rec_snapshot": {"title": "Bad one"}, "verdict": "dislike",
             "reason_dimensions": ["specific"], "reason_text": "vague"},
        ]
        from app.api import qa as qa_module
        with patch("app.api.qa.get_service_client", return_value=_FakeClient({"rows": rows})):
            liked, disliked = qa_module._fetch_steering("quiet-luxury-foodie")
        assert len(liked) == 1 and liked[0]["title"] == "Liked one"
        assert "Grounded in their profile" in liked[0]["reasons"]
        assert len(disliked) == 1 and disliked[0]["title"] == "Bad one"

    def test_no_profile_returns_empty(self, qa_on):
        from app.api import qa as qa_module
        assert qa_module._fetch_steering(None) == ([], [])


# ---------------------------------------------------------------------------
# Generation-layer wiring the cockpit depends on
# ---------------------------------------------------------------------------

class TestGenerationWiring:
    def test_build_user_prompt_injects_steering(self):
        from app.services.qa_profiles import SAMPLE_PROFILES
        from app.services.unified_generation import _build_user_prompt
        from app.services.vault_loader import find_budget_range

        profile = SAMPLE_PROFILES["quiet-luxury-foodie"]
        budget = find_budget_range(profile.vault.budgets, "minor_occasion")
        prompt = _build_user_prompt(
            vault_data=profile.vault,
            hints=profile.hints,
            occasion_type="minor_occasion",
            budget_range=budget,
            liked_exemplars=[{"title": "Wine tasting flight", "reasons": ["Grounded"], "note": "loved it"}],
            disliked_exemplars=[{"title": "Generic gift card", "reasons": ["Specific and real"], "note": "too generic"}],
        )
        assert "QA STEERING" in prompt
        assert "LIKED" in prompt and "DISLIKED" in prompt
        assert "Wine tasting flight" in prompt
        assert "Generic gift card" in prompt
        assert "strong on Grounded" in prompt
        assert "weak on Specific and real" in prompt

    async def test_generate_honors_model_override(self):
        from app.services import unified_generation

        payload = json.dumps([
            {"title": f"Rec {i}", "description": "d", "recommendation_type": "gift",
             "is_purchasable": True, "personalization_note": "You will love this because it is thoughtful.",
             "price_cents": 5000, "merchant_name": "Brand", "search_query": "brand thing"}
            for i in range(3)
        ])
        response = MagicMock()
        response.content = [MagicMock()]
        response.content[0].text = payload
        response.stop_reason = "end_turn"
        mock_client = AsyncMock()
        mock_client.messages.create = AsyncMock(return_value=response)

        from app.services.qa_profiles import SAMPLE_PROFILES
        from app.services.vault_loader import find_budget_range
        vault = SAMPLE_PROFILES["quiet-luxury-foodie"].vault
        budget = find_budget_range(vault.budgets, "minor_occasion")

        with patch("app.services.unified_generation.AsyncAnthropic", MagicMock(return_value=mock_client)), \
             patch("app.services.unified_generation.is_anthropic_configured", return_value=True):
            recs = await unified_generation.generate_unified_recommendations(
                vault_data=vault, hints=[], occasion_type="minor_occasion",
                budget_range=budget, model="claude-sonnet-4-6",
            )

        assert recs, "expected recommendations"
        # The create() call used the override model...
        _, kwargs = mock_client.messages.create.call_args
        assert kwargs["model"] == "claude-sonnet-4-6"
        # ...and Sonnet is effort-capable, so effort:low is present.
        assert kwargs["output_config"] == {"effort": "low"}
        # ...and the model is recorded on the recommendation metadata.
        assert recs[0].metadata["generation_model"] == "claude-sonnet-4-6"
