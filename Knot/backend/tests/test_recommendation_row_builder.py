"""
Tests for `build_recommendation_row` in app/api/recommendations.py.

Regression coverage for a bug that reached three call sites at once. Rows are
written as a single bulk insert, and PostgREST normalises a batch to the union
of every row's keys — a row missing a key that a sibling row carries is sent as
an explicit NULL. `is_idea` is `NOT NULL DEFAULT FALSE`, and a DEFAULT does not
apply to an explicit NULL, so a batch mixing a gift with an idea failed in its
entirety with a 23502 and surfaced as "Unable to generate recommendations".

Only *mixed* batches broke, which is why it went unnoticed for months. The
homogeneous-batch tests below are therefore not the interesting ones — the
mixed-batch test is.
"""

import json
from types import SimpleNamespace

import pytest

from app.agents.state import CandidateRecommendation
from app.api.recommendations import build_recommendation_row

VAULT_ID = "11111111-1111-1111-1111-111111111111"
MILESTONE_ID = "22222222-2222-2222-2222-222222222222"


def _candidate(**overrides) -> CandidateRecommendation:
    base = dict(
        id="cand-1",
        source="unified",
        title="A Thing",
        description="A description.",
        type="gift",
        external_url="https://example.com/thing",
        price_cents=2500,
        merchant_name="Example",
        image_url="https://images.example.com/thing.jpg",
    )
    base.update(overrides)
    return CandidateRecommendation(**base)


def _idea(**overrides) -> CandidateRecommendation:
    base = dict(
        type="idea",
        external_url=None,
        price_cents=None,
        merchant_name=None,
        is_idea=True,
        content_sections=[{"type": "overview", "heading": "H", "body": "B"}],
    )
    base.update(overrides)
    return _candidate(**base)


# ===================================================================
# 1. The bug
# ===================================================================

class TestUniformKeys:
    """The property the bulk insert depends on."""

    def test_mixed_batch_rows_all_share_the_same_keys(self):
        """
        The regression. A gift alongside an idea previously produced rows with
        different key sets, so PostgREST NULLed `is_idea` on the gift row and
        the whole insert failed.
        """
        batch = [
            build_recommendation_row(_candidate(), vault_id=VAULT_ID),
            build_recommendation_row(_idea(), vault_id=VAULT_ID),
            # A plan, not another gift: `plan` is the only type where is_idea
            # is True while type != "idea" (unified_generation treats plans as
            # ideas), so it is the shape most likely to regress.
            build_recommendation_row(_idea(type="plan"), vault_id=VAULT_ID),
        ]

        key_sets = {frozenset(row) for row in batch}

        assert len(key_sets) == 1, f"Rows disagree on keys: {key_sets}"

    def test_plan_is_stored_as_an_idea(self):
        """Plans carry content_sections and must not be written as is_idea=False."""
        row = build_recommendation_row(_idea(type="plan"), vault_id=VAULT_ID)

        assert row["recommendation_type"] == "plan"
        assert row["is_idea"] is True
        assert row["content_sections"] is not None

    def test_is_idea_is_never_absent(self):
        """A missing key is what becomes an explicit NULL in a mixed batch."""
        for candidate in (_candidate(), _idea(), _candidate(type="experience")):
            row = build_recommendation_row(candidate, vault_id=VAULT_ID)
            assert "is_idea" in row

    def test_is_idea_is_never_none(self):
        """The column is NOT NULL, so None fails regardless of batch shape."""
        for candidate in (_candidate(), _idea()):
            row = build_recommendation_row(candidate, vault_id=VAULT_ID)
            assert row["is_idea"] is not None

    def test_is_idea_is_a_real_bool_not_a_truthy_value(self):
        row = build_recommendation_row(_idea(), vault_id=VAULT_ID)

        assert row["is_idea"] is True

    def test_object_lacking_the_attribute_defaults_to_false(self):
        """
        The builder reads through `getattr(..., False)`. A duck-typed candidate
        with no `is_idea` must still produce a non-null column value.
        """
        stand_in = SimpleNamespace(
            type="gift",
            title="A Thing",
            description=None,
            external_url=None,
            price_cents=None,
            merchant_name=None,
            image_url="https://images.example.com/thing.jpg",
        )

        assert build_recommendation_row(stand_in, vault_id=VAULT_ID)["is_idea"] is False


# ===================================================================
# 2. Field mapping
# ===================================================================

class TestFieldMapping:

    def test_maps_the_core_columns(self):
        row = build_recommendation_row(
            _candidate(), vault_id=VAULT_ID, milestone_id=MILESTONE_ID
        )

        assert row["vault_id"] == VAULT_ID
        assert row["milestone_id"] == MILESTONE_ID
        assert row["recommendation_type"] == "gift"
        assert row["title"] == "A Thing"
        assert row["price_cents"] == 2500
        assert row["merchant_name"] == "Example"

    def test_milestone_id_defaults_to_none_for_browsing_mode(self):
        """Refresh stores picks with no milestone; the column is nullable."""
        row = build_recommendation_row(_candidate(), vault_id=VAULT_ID)

        assert row["milestone_id"] is None

    def test_content_sections_are_serialized_for_ideas(self):
        row = build_recommendation_row(_idea(), vault_id=VAULT_ID)

        assert json.loads(row["content_sections"])[0]["heading"] == "H"

    def test_content_sections_are_null_for_non_ideas(self):
        row = build_recommendation_row(_candidate(), vault_id=VAULT_ID)

        assert row["content_sections"] is None

    def test_content_sections_are_null_when_an_idea_has_none(self):
        candidate = _idea()
        candidate.content_sections = None

        assert build_recommendation_row(candidate, vault_id=VAULT_ID)["content_sections"] is None

    def test_personalization_note_passes_through(self):
        candidate = _candidate()
        candidate.personalization_note = "Because they love it."

        row = build_recommendation_row(candidate, vault_id=VAULT_ID)

        assert row["personalization_note"] == "Because they love it."

    def test_personalization_note_is_null_when_absent(self):
        row = build_recommendation_row(_candidate(), vault_id=VAULT_ID)

        assert row["personalization_note"] is None


# ===================================================================
# 3. Image guarantee
# ===================================================================

class TestImageGuarantee:

    def test_existing_image_is_preserved(self):
        row = build_recommendation_row(_candidate(), vault_id=VAULT_ID)

        assert row["image_url"] == "https://images.example.com/thing.jpg"

    def test_missing_image_is_resolved_rather_than_stored_null(self):
        """
        Every read path assumes a non-null image_url, so the builder must never
        emit one.
        """
        row = build_recommendation_row(_candidate(image_url=None), vault_id=VAULT_ID)

        assert row["image_url"]
        assert row["image_url"].startswith("http")

    def test_resolved_image_is_written_back_onto_the_candidate(self):
        """
        The response is built from the same candidate object, so it has to
        serve the image that was persisted.
        """
        candidate = _candidate(image_url=None)

        row = build_recommendation_row(candidate, vault_id=VAULT_ID)

        assert candidate.image_url == row["image_url"]


# ===================================================================
# 4. Call-site parity
# ===================================================================

class TestCallSiteParity:
    """
    All three writers (generate, refresh, notification webhook) go through this
    builder. Duplicated construction is what let one bug land in three places.
    """

    def test_row_construction_exists_in_exactly_one_place(self):
        """
        Guards against the duplication coming back. `recommendations.py` should
        contain the literal row dict exactly once — inside the builder — and
        `notifications.py` not at all.
        """
        import inspect

        from app.api import notifications, recommendations

        marker = '"recommendation_type": candidate.type'

        assert inspect.getsource(recommendations).count(marker) == 1, (
            "A recommendation row is being built outside build_recommendation_row; "
            "a batch with non-uniform keys re-introduces the NOT NULL failure."
        )
        assert marker not in inspect.getsource(notifications), (
            "notifications.py builds its own row again — import "
            "build_recommendation_row instead."
        )

    def test_no_module_conditionally_adds_is_idea_to_a_row(self):
        """
        The bug's actual signature was post-construction mutation —
        `if candidate.is_idea: row["is_idea"] = True` — which makes a row's key
        set depend on its contents.

        `ideas.py` also bulk-inserts into `recommendations`; it is safe today
        because every row it builds is an idea with `is_idea` set
        unconditionally, but it belongs in this guard so a future conditional
        there is caught too.
        """
        import inspect

        from app.api import ideas, notifications, recommendations

        for module in (recommendations, notifications, ideas):
            source = inspect.getsource(module)
            assert '["is_idea"] =' not in source, (
                f"{module.__name__} assigns is_idea after building the row. "
                "That makes the key set depend on the candidate, and a mixed "
                "bulk insert then sends an explicit NULL into a NOT NULL column."
            )

    def test_refresh_replacements_inherit_the_milestone(self):
        """
        Replacements must carry the rejected picks' milestone, or
        `GET /by-milestone` keeps serving the set the user just rejected.
        """
        import inspect

        from app.api.recommendations import refresh_recommendations

        source = inspect.getsource(refresh_recommendations)

        assert "milestone_id=source_milestone_id" in source

    @pytest.mark.parametrize("milestone_id", [None, MILESTONE_ID])
    def test_key_set_is_identical_regardless_of_milestone(self, milestone_id):
        with_ms = build_recommendation_row(
            _candidate(), vault_id=VAULT_ID, milestone_id=milestone_id
        )
        without = build_recommendation_row(_idea(), vault_id=VAULT_ID)

        assert set(with_ms) == set(without)
