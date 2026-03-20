"""
Tests: Milestone CRUD API

Tests for the milestone management endpoints:
- POST /api/v1/milestones — Create milestone with notification scheduling
- GET /api/v1/milestones — List milestones with computed days_until
- PUT /api/v1/milestones/{id} — Update milestone with notification rescheduling
- DELETE /api/v1/milestones/{id} — Delete milestone

Run with: pytest tests/test_milestone_crud.py -v
"""

from datetime import date

import pytest

from app.models.milestones import (
    MilestoneCreateRequest,
    MilestoneItemResponse,
    MilestoneListResponse,
    MilestoneUpdateRequest,
)
from app.services.notification_scheduler import compute_next_occurrence


# ======================================================================
# Model validation tests
# ======================================================================

class TestMilestoneModels:
    """Tests for Pydantic model validation."""

    def test_create_request_valid(self):
        req = MilestoneCreateRequest(
            milestone_type="birthday",
            milestone_name="Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
        )
        assert req.milestone_type == "birthday"
        assert req.milestone_name == "Birthday"
        assert req.recurrence == "yearly"

    def test_create_request_defaults(self):
        req = MilestoneCreateRequest(
            milestone_type="custom",
            milestone_name="Game Night",
            milestone_date="2000-03-20",
        )
        assert req.recurrence == "yearly"
        assert req.budget_tier is None

    def test_create_request_invalid_type(self):
        with pytest.raises(Exception):
            MilestoneCreateRequest(
                milestone_type="invalid",
                milestone_name="Test",
                milestone_date="2000-01-01",
            )

    def test_update_request_partial(self):
        req = MilestoneUpdateRequest(
            milestone_name="Updated Name",
        )
        assert req.milestone_name == "Updated Name"
        assert req.milestone_date is None
        assert req.recurrence is None

    def test_item_response(self):
        resp = MilestoneItemResponse(
            id="ms-123",
            milestone_type="birthday",
            milestone_name="Birthday",
            milestone_date="2000-06-15",
            recurrence="yearly",
            budget_tier="major_milestone",
            days_until=45,
            created_at="2026-01-01T00:00:00Z",
        )
        assert resp.days_until == 45

    def test_list_response(self):
        resp = MilestoneListResponse(
            milestones=[
                MilestoneItemResponse(
                    id="ms-123",
                    milestone_type="birthday",
                    milestone_name="Birthday",
                    milestone_date="2000-06-15",
                    recurrence="yearly",
                    days_until=45,
                    created_at="2026-01-01T00:00:00Z",
                ),
            ],
            count=1,
        )
        assert resp.count == 1
        assert len(resp.milestones) == 1


# ======================================================================
# Next occurrence computation (from notification_scheduler)
# ======================================================================

class TestComputeNextOccurrence:
    """Tests for computing the next occurrence of milestones used in the CRUD API."""

    def test_yearly_milestone_future_this_year(self):
        # A date later this year
        future_date = date(2000, 12, 25)
        result = compute_next_occurrence(future_date, "Christmas", "yearly")
        assert result is not None
        assert result.month == 12
        assert result.day == 25

    def test_one_time_past(self):
        past_date = date(2020, 1, 1)
        result = compute_next_occurrence(past_date, "Past Event", "one_time")
        assert result is None

    def test_one_time_future(self):
        future_date = date(2099, 6, 15)
        result = compute_next_occurrence(future_date, "Future Event", "one_time")
        assert result is not None
        assert result == future_date

    def test_mothers_day_floating(self):
        result = compute_next_occurrence(
            date(2000, 5, 1), "Mother's Day", "yearly",
        )
        assert result is not None
        assert result.month == 5
        # Mother's Day is always a Sunday
        assert result.weekday() == 6


# ======================================================================
# Plan type validation tests
# ======================================================================

class TestPlanRecommendationType:
    """Tests for the new 'plan' recommendation type."""

    def test_plan_type_in_state_literal(self):
        from app.agents.state import CandidateRecommendation
        rec = CandidateRecommendation(
            id="test-plan",
            source="unified",
            type="plan",
            title="Bake & Movie Night",
            is_idea=True,
            content_sections=[
                {"type": "overview", "heading": "Overview", "body": "A cozy evening plan."},
                {"type": "steps", "heading": "Timeline", "items": ["6 PM: Bake", "8 PM: Watch Scream"]},
            ],
        )
        assert rec.type == "plan"
        assert rec.is_idea is True

    def test_plan_type_in_response_model(self):
        from app.models.recommendations import RecommendationItemResponse
        resp = RecommendationItemResponse(
            id="test-plan",
            recommendation_type="plan",
            title="Bake & Movie Night",
            source="unified",
            is_idea=True,
        )
        assert resp.recommendation_type == "plan"

    def test_plan_validation_in_unified_generation(self):
        from app.services.unified_generation import _validate_recommendation
        rec = {
            "title": "Bake & Movie Night",
            "description": "A cozy evening combining baking and a horror movie.",
            "recommendation_type": "plan",
            "personalization_note": "Based on her love of lemon bars and scary movies.",
            "content_sections": [
                {"type": "overview", "heading": "Overview", "body": "A cozy evening."},
                {"type": "steps", "heading": "Timeline", "items": ["6 PM: Bake", "8 PM: Watch"]},
            ],
        }
        assert _validate_recommendation(rec) is True

    def test_plan_without_sections_fails(self):
        from app.services.unified_generation import _validate_recommendation
        rec = {
            "title": "Bake & Movie Night",
            "description": "A cozy evening.",
            "recommendation_type": "plan",
            "personalization_note": "Test.",
        }
        assert _validate_recommendation(rec) is False


# ======================================================================
# APNs briefing snippet tests
# ======================================================================

class TestApnsBriefingSnippet:
    """Tests for enhanced push notifications with briefing snippets."""

    def test_payload_uses_snippet_when_provided(self):
        from app.services.apns import build_notification_payload
        payload = build_notification_payload(
            partner_name="Alex",
            milestone_name="Birthday",
            days_before=7,
            vibes=["quiet_luxury"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-123",
            briefing_snippet="She's been craving lemon bars — bake together!",
        )
        assert payload["aps"]["alert"]["body"] == "She's been craving lemon bars — bake together!"

    def test_payload_falls_back_without_snippet(self):
        from app.services.apns import build_notification_payload
        payload = build_notification_payload(
            partner_name="Alex",
            milestone_name="Birthday",
            days_before=7,
            vibes=["quiet_luxury"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-123",
        )
        assert "Quiet luxury" in payload["aps"]["alert"]["body"]
        assert "3" in payload["aps"]["alert"]["body"]

    def test_payload_falls_back_with_none_snippet(self):
        from app.services.apns import build_notification_payload
        payload = build_notification_payload(
            partner_name="Alex",
            milestone_name="Birthday",
            days_before=7,
            vibes=["quiet_luxury"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-123",
            briefing_snippet=None,
        )
        assert "Quiet luxury" in payload["aps"]["alert"]["body"]
