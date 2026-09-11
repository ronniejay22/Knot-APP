"""
GET /api/v1/recommendations/latest — the stored-batch recovery read.

This endpoint exists to close a real dead end. The generation pipeline runs
server-side and stores its picks *before* responding, so when the HTTP response
never reaches the client — iOS suspends the app mid-request (it grants roughly
30s of background execution against a ~20-30s pipeline), or the client times out
while the backend runs on — the work is finished and sitting in the database
with no way to reach it. `GET /by-milestone/{id}` covered that for milestone
runs only; a "just because" batch belongs to no milestone and had no read path
at all, so tapping the "your picks are ready" push landed on an error screen and
Try Again burned a fresh ~25s run over recommendations that already existed.

Tests cover:
1. Route registration, and the ordering that keeps `/latest` from being
   swallowed by the `/{recommendation_id}` catch-all
2. Returns the newest batch of 3, newest-first
3. `milestone_id` echoes the newest row — set for a milestone batch, null for
   a just-because batch
4. Empty vault returns 200 with an empty list rather than an error
5. 404 when the user has no vault
6. Vault-lookup and recommendation-query failures surface as 500
7. Row mapping is shared with `/by-milestone` (`_stored_rows_to_items`), so
   content_sections decoding, image back-fill and search-URL nulling all apply
8. The Ideas feed — which shares this table — is excluded
9. Only the newest insert batch is returned, never a straddle into an older one
10. Vault selection matches `load_vault_data`'s oldest-first rule

Runs fully offline — every Supabase call is mocked.

Run with: pytest tests/test_latest_recommendations_endpoint.py -v
"""

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app


# ---------------------------------------------------------------------------
# Fixtures & helpers
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """FastAPI test client for the Knot API."""
    return TestClient(app)


@pytest.fixture
def auth_override():
    """Override auth with a fixed user id, cleaned up after the test."""
    from app.core.security import get_active_user_id

    app.dependency_overrides[get_active_user_id] = lambda: "test-user-123"
    yield "test-user-123"
    app.dependency_overrides.pop(get_active_user_id, None)


def _row(**overrides) -> dict:
    """A stored `recommendations` row with sane defaults."""
    row = {
        "id": str(uuid.uuid4()),
        "recommendation_type": "gift",
        "title": "Hand-thrown Mug",
        "description": "A speckled stoneware mug.",
        "external_url": "https://example.com/mug",
        "price_cents": 4200,
        "merchant_name": "Clay Co.",
        "image_url": "https://example.com/mug.jpg",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "personalization_note": "She has been taking pottery classes.",
        "milestone_id": None,
        "is_idea": False,
        "content_sections": None,
    }
    row.update(overrides)
    return row


def _rec_query(rec_table):
    """
    The recommendations query chain, in the order the endpoint builds it:
    `.select(...).eq(...).not_.is_(...).order(...)`.
    """
    return rec_table.select.return_value.eq.return_value.not_.is_.return_value.order.return_value


def _mock_supabase(*, vault_rows=None, rec_rows=None, vault_error=None, rec_error=None):
    """
    Build a mock Supabase client plus the recommendations table mock, so a test
    can assert on the query the endpoint built (ordering, limit) and not just
    on the response body.
    """
    if vault_rows is None:
        vault_rows = [{"id": str(uuid.uuid4())}]
    if rec_rows is None:
        rec_rows = []

    mock_client = MagicMock()
    vault_table = MagicMock()
    rec_table = MagicMock()

    vault_chain = vault_table.select.return_value.eq.return_value.order.return_value.limit.return_value
    if vault_error:
        vault_chain.execute.side_effect = vault_error
    else:
        vault_chain.execute.return_value = MagicMock(data=vault_rows)

    rec_chain = _rec_query(rec_table).limit.return_value
    if rec_error:
        rec_chain.execute.side_effect = rec_error
    else:
        rec_chain.execute.return_value = MagicMock(data=rec_rows)

    def table_side_effect(table_name):
        if table_name == "partner_vaults":
            return vault_table
        if table_name == "recommendations":
            return rec_table
        return MagicMock()

    mock_client.table.side_effect = table_side_effect
    return mock_client, vault_table, rec_table


# ===================================================================
# 1. Route registration and ordering
# ===================================================================

class TestRouteRegistration:
    """`/latest` is a literal path competing with a catch-all path param."""

    def test_latest_route_is_registered(self):
        routes = [getattr(r, "path", "") for r in app.routes]
        assert "/api/v1/recommendations/latest" in routes
        print("  /latest endpoint is registered")

    def test_latest_registers_before_the_catch_all_id_route(self):
        """
        `GET /{recommendation_id}` matches literally any single segment,
        including the string "latest". Starlette resolves routes in
        registration order, so if the catch-all were registered first every
        call to /latest would be handled as a lookup for a recommendation whose
        id is "latest" — a 404 (or a UUID parse error), not the batch.
        """
        paths = [getattr(r, "path", "") for r in app.routes]
        latest_index = paths.index("/api/v1/recommendations/latest")
        catch_all_index = paths.index("/api/v1/recommendations/{recommendation_id}")

        assert latest_index < catch_all_index, (
            "/latest must be registered before the /{recommendation_id} "
            "catch-all or the catch-all swallows it"
        )
        print("  /latest is registered ahead of the /{recommendation_id} catch-all")

    def test_latest_is_a_get(self):
        route = next(
            r for r in app.routes
            if getattr(r, "path", "") == "/api/v1/recommendations/latest"
        )
        assert "GET" in route.methods
        print("  /latest is a GET (read-only, never triggers the pipeline)")


# ===================================================================
# 2. Happy path — the newest batch
# ===================================================================

class TestReturnsNewestBatch:

    def test_returns_the_stored_batch(self, client, auth_override):
        rows = [_row(title="Mug"), _row(title="Picnic"), _row(title="Letter")]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 3
        assert [r["title"] for r in data["recommendations"]] == ["Mug", "Picnic", "Letter"]
        print("  Returns the stored batch")

    def test_requests_the_newest_three_newest_first(self, client, auth_override):
        """
        One generation run inserts its trio in a single call, so ordering by
        created_at desc and limiting to 3 is exactly the latest
        Choice-of-Three — the same batch semantics as /by-milestone.
        """
        mock_client, _, rec_table = _mock_supabase(rec_rows=[_row()])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        rec_table.select.return_value.eq.return_value.not_.is_.return_value.order.assert_called_with(
            "created_at", desc=True
        )
        _rec_query(rec_table).limit.assert_called_with(3)
        print("  Queries the newest 3 by created_at desc")

    def test_scopes_the_query_to_the_users_vault(self, client, auth_override):
        vault_id = str(uuid.uuid4())
        mock_client, _, rec_table = _mock_supabase(
            vault_rows=[{"id": vault_id}], rec_rows=[_row()]
        )

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        rec_table.select.return_value.eq.assert_called_with("vault_id", vault_id)
        print("  Scopes the read to the caller's vault")

    def test_empty_vault_returns_an_empty_batch_not_an_error(self, client, auth_override):
        """
        A user who has never generated anything is a normal state, not a
        failure — the client treats an empty batch as "nothing to recover".
        """
        mock_client, _, _ = _mock_supabase(rec_rows=[])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 0
        assert data["recommendations"] == []
        assert data["milestone_id"] is None
        print("  Empty batch returns 200 with an empty list")

    def test_briefing_text_is_null(self, client, auth_override):
        """
        Briefings are milestone-scoped; a just-because batch has none, and this
        endpoint does not know which milestone (if any) a batch belongs to
        until it reads the rows. It deliberately serves none rather than
        guessing.
        """
        mock_client, _, _ = _mock_supabase(rec_rows=[_row()])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.json()["briefing_text"] is None
        print("  briefing_text is null")


# ===================================================================
# 3. milestone_id echoes the newest row
# ===================================================================

class TestMilestoneIdEcho:

    def test_null_for_a_just_because_batch(self, client, auth_override):
        """
        The case that motivated the endpoint: a just-because run belongs to no
        milestone, so there is nothing for /by-milestone to look it up by.
        """
        mock_client, _, _ = _mock_supabase(rec_rows=[_row(milestone_id=None)])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        assert resp.json()["milestone_id"] is None
        print("  milestone_id is null for a just-because batch")

    def test_echoes_the_milestone_when_the_batch_has_one(self, client, auth_override):
        milestone_id = str(uuid.uuid4())
        mock_client, _, _ = _mock_supabase(
            rec_rows=[_row(milestone_id=milestone_id), _row(milestone_id=milestone_id)]
        )

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        assert resp.json()["milestone_id"] == milestone_id
        print("  milestone_id echoes a milestone batch")

    def test_tolerates_rows_without_a_milestone_id_key(self, client, auth_override):
        """Older rows predate the column being selected; `.get` must not KeyError."""
        row = _row()
        row.pop("milestone_id")
        mock_client, _, _ = _mock_supabase(rec_rows=[row])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        assert resp.json()["milestone_id"] is None
        print("  A row missing milestone_id does not raise")


# ===================================================================
# 4. Failure modes
# ===================================================================

class TestFailureModes:

    def test_404_when_the_user_has_no_vault(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(vault_rows=[])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 404
        assert "vault" in resp.json()["detail"].lower()
        print("  404 when the user has no vault")

    def test_500_when_the_vault_lookup_fails(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(vault_error=Exception("PostgREST down"))

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 500
        print("  500 when the vault lookup fails")

    def test_500_when_the_recommendations_query_fails(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(rec_error=Exception("PostgREST down"))

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 500
        print("  500 when the recommendations query fails")

    def test_requires_authentication(self, client):
        """No auth override here — the dependency must reject the call."""
        resp = client.get("/api/v1/recommendations/latest")
        assert resp.status_code in (401, 403)
        print("  Unauthenticated callers are rejected")


# ===================================================================
# 5. Row mapping is shared with /by-milestone
# ===================================================================

class TestSharedRowMapping:
    """
    Both read paths go through `_stored_rows_to_items`. These assert the
    enrichment actually reaches /latest's response, so the two endpoints cannot
    drift into returning differently-shaped items for the same stored row.
    """

    def test_uses_the_shared_mapper(self, client, auth_override):
        from app.api import recommendations as recs_module

        rows = [_row()]
        mock_client, _, _ = _mock_supabase(rec_rows=list(rows))

        with patch("app.api.recommendations.get_service_client", return_value=mock_client), \
             patch.object(
                 recs_module, "_stored_rows_to_items",
                 wraps=recs_module._stored_rows_to_items,
             ) as spy:
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        spy.assert_called_once_with(rows)
        print("  /latest maps rows through the shared helper")

    def test_decodes_content_sections_from_its_stored_json_string(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(rec_rows=[
            _row(
                recommendation_type="idea",
                is_idea=True,
                external_url=None,
                content_sections='[{"type": "overview", "heading": "Overview", "body": "A cozy night."}]',
            )
        ])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        item = resp.json()["recommendations"][0]
        assert item["is_idea"] is True
        assert item["content_sections"][0]["type"] == "overview"
        print("  content_sections is decoded for the client")

    def test_malformed_content_sections_becomes_null(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(rec_rows=[_row(content_sections="{not json")])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        assert resp.json()["recommendations"][0]["content_sections"] is None
        print("  Malformed content_sections degrades to null")

    def test_back_fills_an_image_for_rows_stored_without_one(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(rec_rows=[_row(image_url=None)])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        image_url = resp.json()["recommendations"][0]["image_url"]
        assert image_url, "image_url must never be null — older rows have none stored"
        print("  Missing image_url is back-filled with the per-type default")

    def test_nulls_a_legacy_search_url(self, client, auth_override):
        """
        A recommendation stored before the URL fix can carry a shopping-search
        link. Serving it would open a dead search; nulling it degrades the
        client to the Save action.
        """
        mock_client, _, _ = _mock_supabase(rec_rows=[
            _row(external_url="https://www.google.com/search?tbm=shop&q=mug")
        ])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.json()["recommendations"][0]["external_url"] is None
        print("  A legacy search URL is nulled")


# ===================================================================
# 6. The Ideas feed shares this table and must not be recovered
# ===================================================================

class TestExcludesTheIdeasFeed:
    """
    `ideas.py` inserts into `recommendations` for the same vault, and the
    hint-then-refresh flow schedules a background idea generation ~30s out —
    squarely inside the window a recovering client is looking at. Without a
    filter, a failed refresh recovers three Knot Ideas instead of the lost
    picks.
    """

    def test_query_excludes_rows_with_no_image(self, client, auth_override):
        mock_client, _, rec_table = _mock_supabase(rec_rows=[_row()])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.status_code == 200
        rec_table.select.return_value.eq.return_value.not_.is_.assert_called_with(
            "image_url", "null"
        )
        print("  /latest filters out NULL-image rows (the Ideas feed)")

    def test_ideas_rows_are_written_without_an_image(self):
        """
        Half of the contract the filter relies on: `ideas.py` explicitly stores
        `image_url: None`. If it ever started resolving images, the filter would
        stop separating the two and only this test would notice.
        """
        import inspect

        from app.api import ideas

        source = inspect.getsource(ideas)
        assert '"image_url": None' in source, (
            "ideas.py no longer stores a NULL image_url — /latest can no longer "
            "tell Ideas-feed rows from pipeline rows"
        )
        print("  ideas.py still stores a NULL image_url")

    def test_pipeline_rows_always_carry_an_image(self):
        """
        The other half: `build_recommendation_row` resolves an image before
        persisting, so no genuine pipeline row is caught by the filter.
        """
        from app.agents.state import CandidateRecommendation
        from app.api.recommendations import build_recommendation_row

        candidate = CandidateRecommendation(
            id=str(uuid.uuid4()),
            source="knot",
            type="idea",
            title="Cozy Night In",
            description="A test idea.",
            is_idea=True,
        )
        row = build_recommendation_row(candidate, vault_id=str(uuid.uuid4()))

        assert row["image_url"], (
            "a pipeline row must always carry an image, or /latest's filter "
            "would drop genuine picks"
        )
        # And it is an idea — proving the filter does not simply mean "not an idea".
        assert row["is_idea"] is True
        print("  Pipeline rows always carry an image, Knot Originals included")


# ===================================================================
# 7. Only the newest insert batch is returned
# ===================================================================

class TestNewestInsertBatchOnly:
    """
    The limit of 3 is a full Choice-of-Three. A run that stored fewer would
    otherwise have the remainder filled from the *previous* run, handing a
    recovering client two fresh picks and one stale one, counted as three.
    """

    def test_drops_rows_from_an_older_batch(self, client, auth_override):
        now = datetime.now(timezone.utc)
        rows = [
            _row(title="Fresh A", created_at=now.isoformat()),
            _row(title="Fresh B", created_at=(now - timedelta(milliseconds=40)).isoformat()),
            _row(title="Stale", created_at=(now - timedelta(minutes=9)).isoformat()),
        ]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        data = resp.json()
        assert [r["title"] for r in data["recommendations"]] == ["Fresh A", "Fresh B"]
        assert data["count"] == 2, "count must describe what was actually returned"
        print("  A row from an older batch is dropped, and count follows")

    def test_keeps_a_whole_batch_inserted_together(self, client, auth_override):
        now = datetime.now(timezone.utc)
        rows = [
            _row(title="A", created_at=now.isoformat()),
            _row(title="B", created_at=(now - timedelta(milliseconds=30)).isoformat()),
            _row(title="C", created_at=(now - timedelta(milliseconds=60)).isoformat()),
        ]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.json()["count"] == 3
        print("  A trio inserted together survives intact")

    def test_unparseable_timestamps_do_not_shrink_the_result(self, client, auth_override):
        """Failing open here: an odd timestamp is not evidence of an older batch."""
        mock_client, _, _ = _mock_supabase(rec_rows=[
            _row(title="A", created_at="not a timestamp"),
            _row(title="B", created_at="also not a timestamp"),
        ])

        with patch("app.api.recommendations.get_service_client", return_value=mock_client):
            resp = client.get("/api/v1/recommendations/latest")

        assert resp.json()["count"] == 2
        print("  Unparseable timestamps keep the rows rather than dropping them")


# ===================================================================
# 8. Vault selection matches the write path
# ===================================================================

def test_vault_selection_is_oldest_first_like_load_vault_data(client, auth_override):
    """
    `load_vault_data` — which the generation endpoints use to pick the vault
    they write against — orders `partner_vaults` by created_at ascending. If
    /latest picked a different row for a user with more than one vault (dev
    testing leaves them behind), it would read a vault the just-completed run
    never wrote to and the recovery would silently find nothing.
    """
    mock_client, vault_table, _ = _mock_supabase(rec_rows=[_row()])

    with patch("app.api.recommendations.get_service_client", return_value=mock_client):
        resp = client.get("/api/v1/recommendations/latest")

    assert resp.status_code == 200
    vault_table.select.return_value.eq.return_value.order.assert_called_with(
        "created_at", desc=False
    )
    print("  Vault selection matches load_vault_data's oldest-first rule")


def test_load_vault_data_still_orders_oldest_first():
    """
    Pins the other half of the contract above: if `load_vault_data` ever
    changed its ordering, /latest would start reading a different vault than
    the one the pipeline wrote to, and only this test would notice.
    """
    import inspect

    from app.services import vault_loader

    source = inspect.getsource(vault_loader.load_vault_data)
    vault_section = source.split('table("partner_vaults")')[1][:300]
    assert 'order("created_at", desc=False)' in vault_section, (
        "load_vault_data's vault ordering changed — /latest must match it"
    )
    print("  load_vault_data still selects the oldest vault")
