"""
Tests for the offline eval harness (Step 20.1).

`summarize()` is a pure aggregation function tested directly; `run_eval` is
tested with generation + judging mocked so no network is touched.
"""

from unittest.mock import AsyncMock, patch

import pytest

from app.agents.state import CandidateRecommendation
from app.services.rec_judge import RecommendationJudgment
from eval import run_eval


def _rec(title, rec_type="gift"):
    return CandidateRecommendation(id=title, source="unified", type=rec_type, title=title)


def _judgment(overall, verdict, dims):
    return RecommendationJudgment(dimension_scores=dims, overall=overall, verdict=verdict, rationale="r")


class TestSummarize:
    def test_empty(self):
        s = run_eval.summarize([])
        assert s == {"count": 0, "mean_overall": 0.0, "good_rate": 0.0,
                     "per_dimension_mean": {}, "type_distribution": {}}

    def test_aggregates_scores_and_types(self):
        judged = [
            (_rec("A", "gift"), _judgment(0.9, "good", {"grounded": 1.0, "specific": 0.8})),
            (_rec("B", "idea"), _judgment(0.4, "bad", {"grounded": 0.4, "specific": 0.4})),
        ]
        s = run_eval.summarize(judged)
        assert s["count"] == 2
        assert s["mean_overall"] == 0.65
        assert s["good_rate"] == 0.5
        assert s["per_dimension_mean"]["grounded"] == 0.7
        assert s["type_distribution"] == {"gift": 1, "idea": 1}


class TestRunEval:
    async def test_runs_over_profile_with_mocks(self):
        recs = [_rec("A", "gift"), _rec("B", "idea")]
        judgments = [
            _judgment(0.9, "good", {"grounded": 1.0}),
            _judgment(0.8, "good", {"grounded": 0.8}),
        ]
        with patch("eval.run_eval.generate_unified_recommendations",
                   new=AsyncMock(return_value=recs)), \
             patch("eval.run_eval.judge_recommendation",
                   new=AsyncMock(side_effect=judgments)):
            report = await run_eval.run_eval(
                profile_ids=["quiet-luxury-foodie"],
                occasion_type="minor_occasion",
                models=[None],
            )

        assert "default" in report["by_model"]
        model_data = report["by_model"]["default"]
        assert model_data["mean_overall"] > 0.0
        assert len(model_data["profiles"]) == 1
        assert model_data["profiles"][0]["profile_id"] == "quiet-luxury-foodie"
        assert model_data["profiles"][0]["count"] == 2

        text = run_eval.format_report(report)
        assert "MODEL: default" in text
        assert "quiet-luxury-foodie" in text

    async def test_unknown_profile_id_raises(self):
        with pytest.raises(ValueError):
            await run_eval.run_eval(
                profile_ids=["quiet-luxury-foddie"],  # typo
                occasion_type="minor_occasion",
                models=[None],
            )

    async def test_judge_failure_is_skipped_not_fatal(self):
        # One judge raises; the run still completes with the surviving rec judged.
        recs = [_rec("A", "gift"), _rec("B", "idea")]
        with patch("eval.run_eval.generate_unified_recommendations",
                   new=AsyncMock(return_value=recs)), \
             patch("eval.run_eval.judge_recommendation",
                   new=AsyncMock(side_effect=[RuntimeError("bad json"),
                                              _judgment(0.8, "good", {"grounded": 0.8})])):
            report = await run_eval.run_eval(
                profile_ids=["quiet-luxury-foodie"],
                occasion_type="minor_occasion",
                models=[None],
            )
        # Only the successfully-judged rec is counted; the run did not crash.
        assert report["by_model"]["default"]["profiles"][0]["count"] == 1
