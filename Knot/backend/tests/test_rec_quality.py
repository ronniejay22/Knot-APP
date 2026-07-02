"""
Tests for the recommendation quality rubric and sample profiles (Step 20.1).

The rubric is the single source of truth for good-vs-bad, so these tests lock
its shape: the prompt guidance, judge instructions, and QA reason chips must all
stay derived from the same dimensions, and the overall-score math must honor the
critical-dimension cap.
"""

from app.services import qa_profiles, rec_quality


class TestRubricShape:
    def test_dimension_ids_stable(self):
        assert rec_quality.RUBRIC_DIMENSION_IDS == {
            "grounded", "dislike_safe", "specific", "budget_fit", "vibe_fit",
            "love_language_fit", "location_fit", "actionable", "well_written",
        }
        assert "grounded" in rec_quality.CRITICAL_DIMENSION_IDS
        assert "dislike_safe" in rec_quality.CRITICAL_DIMENSION_IDS
        assert "diversity" in rec_quality.ALL_DIMENSION_IDS

    def test_dimensions_for_type_scopes_correctly(self):
        gift_ids = {d.id for d in rec_quality.dimensions_for_type("gift")}
        idea_ids = {d.id for d in rec_quality.dimensions_for_type("idea")}
        date_ids = {d.id for d in rec_quality.dimensions_for_type("date")}

        # budget_fit is purchasable-only; location_fit is location-bound only.
        assert "budget_fit" in gift_ids
        assert "location_fit" not in gift_ids
        assert "budget_fit" not in idea_ids
        assert "location_fit" not in idea_ids
        assert "location_fit" in date_ids
        assert "budget_fit" in date_ids
        # grounded / dislike_safe apply everywhere.
        for ids in (gift_ids, idea_ids, date_ids):
            assert {"grounded", "dislike_safe", "specific", "well_written"} <= ids


class TestRubricRendering:
    def test_prompt_guidance_marks_critical(self):
        text = rec_quality.rubric_prompt_guidance()
        assert "QUALITY BAR" in text
        assert "CRITICAL" in text
        # Every dimension label appears.
        for d in rec_quality.RUBRIC:
            assert d.label in text

    def test_judge_instructions_list_dimension_ids(self):
        text = rec_quality.rubric_for_judge()
        for dim_id in rec_quality.RUBRIC_DIMENSION_IDS:
            assert f'"{dim_id}"' in text

    def test_reason_chips_carry_both_polarities_and_diversity(self):
        chips = rec_quality.rubric_reason_chips()
        ids = {c["id"] for c in chips}
        assert rec_quality.RUBRIC_DIMENSION_IDS <= ids
        assert "diversity" in ids  # set-level dimension is offered as a chip
        for c in chips:
            assert c["like_reason"] and c["dislike_reason"]


class TestOverallScore:
    def test_all_perfect_is_one(self):
        scores = {d: 1.0 for d in rec_quality.RUBRIC_DIMENSION_IDS}
        assert rec_quality.overall_from_scores(scores) == 1.0

    def test_empty_is_zero(self):
        assert rec_quality.overall_from_scores({}) == 0.0

    def test_critical_failure_caps_overall(self):
        # A dislike-violating rec cannot be good, however strong elsewhere.
        scores = {"grounded": 1.0, "specific": 1.0, "dislike_safe": 0.0, "well_written": 1.0}
        assert rec_quality.overall_from_scores(scores) == 0.0

    def test_noncritical_low_score_does_not_zero_out(self):
        scores = {"grounded": 1.0, "dislike_safe": 1.0, "specific": 1.0, "vibe_fit": 0.0}
        overall = rec_quality.overall_from_scores(scores)
        assert 0.0 < overall < 1.0

    def test_unknown_keys_ignored(self):
        scores = {"grounded": 1.0, "dislike_safe": 1.0, "diversity": 0.0, "bogus": 0.0}
        # diversity + bogus are not per-rec rubric dims, so they don't drag it down.
        assert rec_quality.overall_from_scores(scores) == 1.0


class TestSampleProfiles:
    def test_six_profiles_present(self):
        assert len(qa_profiles.SAMPLE_PROFILES) == 6

    def test_each_profile_is_well_formed(self):
        for profile in qa_profiles.SAMPLE_PROFILES.values():
            v = profile.vault
            assert len(v.interests) == 5
            assert len(v.dislikes) == 5
            assert len(v.vibes) >= 1
            assert {b.occasion_type for b in v.budgets} == {
                "just_because", "minor_occasion", "major_milestone"
            }
            assert profile.hints, "profiles should carry sample hints for grounding"

    def test_list_and_lookup(self):
        summaries = qa_profiles.list_sample_profiles()
        assert len(summaries) == 6
        assert all({"id", "headline", "partner_name", "city"} <= s.keys() for s in summaries)
        assert qa_profiles.get_sample_profile("quiet-luxury-foodie") is not None
        assert qa_profiles.get_sample_profile("nope") is None
