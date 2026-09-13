"""
GET /api/v1/recommendations/recent — the Journal's "Recent picks" read.

A generation run's picks are stored before the response is sent, but pressing
Back after a run lost the cards from the UI: `RecommendationsView` owns its view
model as `@State`, and nothing on the client re-read what the backend had
already stored except the push tap-through (`/by-milestone/{id}`) and error
recovery (`/latest`). This endpoint is the plain "what did we generate in the
last N days" read behind the Journal section, and it is deliberately
time-boxed so saving stays the way a user keeps a pick.

Tests cover:
1. Route registration, and the ordering that keeps `/recent` from being
   swallowed by the `/{recommendation_id}` catch-all
2. The query — window cutoff, Ideas-feed exclusion, vault scoping, row cap,
   and the oldest-first vault selection that matches `load_vault_data`
3. Grouping rows back into the runs that inserted them — by insert-time gap
   AND by milestone, since two same-day milestone webhooks can land inside
   the 5-second window of each other
4. Batch shape — `batch_id` is the newest row's id, `expires_at` is
   `generated_at + window_days`, `milestone_id` echoes per batch
5. Empty window returns 200 with no batches rather than an error
6. 404 when the user has no vault; vault-lookup and query failures are 500
7. A trailing partial batch is dropped when the row cap was hit
8. Direct unit tests of `_group_into_insert_batches`

Runs fully offline — every Supabase call is mocked.

Run with: pytest tests/test_recent_recommendations_endpoint.py -v
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


def _now() -> datetime:
    return datetime.now(timezone.utc)


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
        "created_at": _now().isoformat(),
        "personalization_note": "She has been taking pottery classes.",
        "milestone_id": None,
        "is_idea": False,
        "content_sections": None,
    }
    row.update(overrides)
    return row


def _batch(count: int = 3, *, created_at: datetime, milestone_id=None, title="Pick") -> list[dict]:
    """
    Rows the way one bulk insert lands them: identical `created_at`, same
    milestone, newest-first is trivially satisfied within the batch.
    """
    return [
        _row(
            title=f"{title} {i}",
            created_at=created_at.isoformat(),
            milestone_id=milestone_id,
        )
        for i in range(count)
    ]


def _rec_query(rec_table):
    """
    The recommendations query chain, in the order the endpoint builds it:
    `.select(...).eq(...).not_.is_(...).gte(...).order(...)`.

    Positional on purpose — it is a different chain from `/latest` (which has no
    `.gte`), so reusing that file's helper would leave `.execute()` returning a
    fresh, truthy MagicMock and the handler iterating garbage.
    """
    return (
        rec_table.select.return_value
        .eq.return_value
        .not_.is_.return_value
        .gte.return_value
        .order.return_value
    )


def _mock_supabase(*, vault_rows=None, rec_rows=None, vault_error=None, rec_error=None):
    """
    Build a mock Supabase client plus the recommendations table mock, so a test
    can assert on the query the endpoint built (cutoff, limit) and not just on
    the response body.
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


def _get(client, mock_client):
    with patch("app.api.recommendations.get_service_client", return_value=mock_client):
        return client.get("/api/v1/recommendations/recent")


# ===================================================================
# 1. Route registration
# ===================================================================

class TestRouteRegistration:

    def test_route_is_registered(self):
        paths = [getattr(r, "path", "") for r in app.routes]
        assert "/api/v1/recommendations/recent" in paths
        print("  GET /api/v1/recommendations/recent is registered")

    def test_recent_registers_before_the_catch_all_id_route(self):
        """
        `/{recommendation_id}` is a catch-all path parameter. Registered first,
        it would match the literal "recent" and return a 404 for a
        recommendation with that id.
        """
        paths = [getattr(r, "path", "") for r in app.routes]
        recent_index = paths.index("/api/v1/recommendations/recent")
        catch_all_index = paths.index("/api/v1/recommendations/{recommendation_id}")

        assert recent_index < catch_all_index, (
            "/recent must be registered before the /{recommendation_id} "
            "catch-all or the catch-all swallows it"
        )
        print("  /recent is registered above the catch-all")

    def test_requires_auth(self, client):
        resp = client.get("/api/v1/recommendations/recent")
        assert resp.status_code == 401
        print("  Unauthenticated request is rejected")


# ===================================================================
# 2. The query
# ===================================================================

class TestQueryShape:

    def test_cutoff_is_seven_days_ago(self, client, auth_override):
        from app.api.recommendations import RECENT_WINDOW_DAYS

        mock_client, _, rec_table = _mock_supabase(rec_rows=[])
        before = _now()

        resp = _get(client, mock_client)

        assert resp.status_code == 200
        gte = rec_table.select.return_value.eq.return_value.not_.is_.return_value.gte
        (column, cutoff_iso), _ = gte.call_args
        assert column == "created_at"
        cutoff = datetime.fromisoformat(cutoff_iso)
        expected = before - timedelta(days=RECENT_WINDOW_DAYS)
        assert abs((cutoff - expected).total_seconds()) < 5
        assert cutoff.tzinfo is not None, "cutoff must be timezone-aware to compare with TIMESTAMPTZ"
        print(f"  Cutoff is {RECENT_WINDOW_DAYS} days ago, timezone-aware")

    def test_excludes_the_ideas_feed(self, client, auth_override):
        """
        `ideas.py` shares the table and stores an explicitly NULL image_url;
        every pipeline row has one. That is the discriminator, not `is_idea`
        (a real Choice-of-Three can contain a Knot Original).
        """
        mock_client, _, rec_table = _mock_supabase(rec_rows=[])

        _get(client, mock_client)

        rec_table.select.return_value.eq.return_value.not_.is_.assert_called_with("image_url", "null")
        print("  Ideas-feed rows are excluded via image_url IS NOT NULL")

    def test_scopes_the_query_to_the_users_vault(self, client, auth_override):
        vault_id = str(uuid.uuid4())
        mock_client, _, rec_table = _mock_supabase(vault_rows=[{"id": vault_id}], rec_rows=[])

        _get(client, mock_client)

        rec_table.select.return_value.eq.assert_called_with("vault_id", vault_id)
        print("  Scopes the read to the caller's vault")

    def test_orders_newest_first_and_reads_one_past_the_cap(self, client, auth_override):
        """The extra row is the sentinel that tells the handler the cap was hit."""
        from app.api.recommendations import RECENT_MAX_ROWS

        mock_client, _, rec_table = _mock_supabase(rec_rows=[])

        _get(client, mock_client)

        _rec_query(rec_table).limit.assert_called_with(RECENT_MAX_ROWS + 1)
        rec_table.select.return_value.eq.return_value.not_.is_.return_value.gte.return_value.order.assert_called_with(
            "created_at", desc=True
        )
        print(f"  Orders newest-first and reads {RECENT_MAX_ROWS} + 1 rows")

    def test_vault_selection_is_oldest_first(self, client, auth_override):
        """
        Matches `/latest` and `load_vault_data`: a user with more than one vault
        row must have this read the same vault the generation endpoints write to.
        """
        mock_client, vault_table, _ = _mock_supabase(rec_rows=[])

        _get(client, mock_client)

        vault_table.select.return_value.eq.return_value.order.assert_called_with("created_at", desc=False)
        print("  Vault selection is oldest-first")


# ===================================================================
# 3. Grouping rows into runs
# ===================================================================

class TestGrouping:

    def test_two_runs_thirty_seconds_apart_are_two_batches(self, client, auth_override):
        now = _now()
        newer = _batch(created_at=now, title="New")
        older = _batch(created_at=now - timedelta(seconds=30), title="Old")
        mock_client, _, _ = _mock_supabase(rec_rows=newer + older)

        resp = _get(client, mock_client)

        assert resp.status_code == 200
        data = resp.json()
        assert data["count"] == 2
        assert [b["recommendations"][0]["title"] for b in data["batches"]] == ["New 0", "Old 0"]
        assert all(len(b["recommendations"]) == 3 for b in data["batches"])
        print("  Two runs 30s apart come back as two batches, newest first")

    def test_rows_inserted_together_are_one_batch(self, client, auth_override):
        """
        One bulk insert lands its rows within milliseconds; they must not be
        split into three one-pick batches.
        """
        now = _now()
        rows = [
            _row(title="A", created_at=now.isoformat()),
            _row(title="B", created_at=(now - timedelta(milliseconds=40)).isoformat()),
            _row(title="C", created_at=(now - timedelta(milliseconds=80)).isoformat()),
        ]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        data = resp.json()
        assert data["count"] == 1
        assert [r["title"] for r in data["batches"][0]["recommendations"]] == ["A", "B", "C"]
        print("  Rows 40ms apart are one batch")

    def test_same_timestamp_different_milestones_are_two_batches(self, client, auth_override):
        """
        The case the time gap alone gets wrong: two same-day milestone webhooks
        bulk-insert inside the 5s window. Merged, six rows would be labelled
        with whichever milestone inserted last.
        """
        now = _now()
        m1, m2 = str(uuid.uuid4()), str(uuid.uuid4())
        rows = _batch(created_at=now, milestone_id=m1, title="One") + _batch(
            created_at=now, milestone_id=m2, title="Two"
        )
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        data = resp.json()
        assert data["count"] == 2
        assert [b["milestone_id"] for b in data["batches"]] == [m1, m2]
        assert all(len(b["recommendations"]) == 3 for b in data["batches"])
        print("  Same-timestamp rows for different milestones are separate batches")


# ===================================================================
# 4. Batch shape
# ===================================================================

class TestBatchShape:

    def test_batch_id_is_the_newest_rows_id(self, client, auth_override):
        rows = _batch(created_at=_now())
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        assert resp.json()["batches"][0]["batch_id"] == rows[0]["id"]
        print("  batch_id is the newest row's id")

    def test_expires_at_is_generated_at_plus_window(self, client, auth_override):
        from app.api.recommendations import RECENT_WINDOW_DAYS

        generated = _now() - timedelta(days=2)
        mock_client, _, _ = _mock_supabase(rec_rows=_batch(created_at=generated))

        resp = _get(client, mock_client)

        batch = resp.json()["batches"][0]
        assert datetime.fromisoformat(batch["generated_at"]) == generated
        assert datetime.fromisoformat(batch["expires_at"]) == generated + timedelta(days=RECENT_WINDOW_DAYS)
        assert resp.json()["window_days"] == RECENT_WINDOW_DAYS
        print("  expires_at is generated_at + window_days")

    def test_milestone_id_echoes_per_batch(self, client, auth_override):
        now = _now()
        milestone_id = str(uuid.uuid4())
        rows = _batch(created_at=now, milestone_id=milestone_id) + _batch(
            created_at=now - timedelta(minutes=10), milestone_id=None
        )
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        assert [b["milestone_id"] for b in resp.json()["batches"]] == [milestone_id, None]
        print("  milestone_id is set for a milestone batch and null for just-because")

    def test_items_use_the_shared_row_mapping(self, client, auth_override):
        """
        `_stored_rows_to_items` is shared with /by-milestone and /latest —
        JSON-string content_sections decode, image back-fill, and search-URL
        nulling all apply here too.
        """
        row = _row(
            recommendation_type="idea",
            is_idea=True,
            image_url="https://example.com/idea.jpg",
            external_url="https://www.google.com/search?q=stale",
            content_sections='[{"type": "overview", "title": "Overview", "body": "Bake together."}]',
        )
        mock_client, _, _ = _mock_supabase(rec_rows=[row])

        resp = _get(client, mock_client)

        item = resp.json()["batches"][0]["recommendations"][0]
        assert item["is_idea"] is True
        assert item["content_sections"][0]["type"] == "overview"
        assert item["external_url"] is None, "stale search URL must be nulled on read"
        print("  Items go through the shared row mapping")


# ===================================================================
# 5. Empty window
# ===================================================================

class TestEmptyWindow:

    def test_empty_window_returns_no_batches_not_an_error(self, client, auth_override):
        from app.api.recommendations import RECENT_WINDOW_DAYS

        mock_client, _, _ = _mock_supabase(rec_rows=[])

        resp = _get(client, mock_client)

        assert resp.status_code == 200
        assert resp.json() == {"batches": [], "count": 0, "window_days": RECENT_WINDOW_DAYS}
        print("  Empty window returns 200 with no batches")


# ===================================================================
# 6. Failure modes
# ===================================================================

class TestFailureModes:

    def test_404_when_the_user_has_no_vault(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(vault_rows=[])

        resp = _get(client, mock_client)

        assert resp.status_code == 404
        assert "vault" in resp.json()["detail"].lower()
        print("  404 with no vault")

    def test_500_when_the_vault_lookup_fails(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(vault_error=RuntimeError("db down"))

        resp = _get(client, mock_client)

        assert resp.status_code == 500
        print("  Vault lookup failure is a 500")

    def test_500_when_the_recommendations_query_fails(self, client, auth_override):
        mock_client, _, _ = _mock_supabase(rec_error=RuntimeError("db down"))

        resp = _get(client, mock_client)

        assert resp.status_code == 500
        print("  Query failure is a 500")

    def test_unparseable_anchor_timestamp_skips_that_batch(self, client, auth_override):
        """
        Unlike `_newest_insert_batch`, a batch with no usable timestamp is
        dropped: `expires_at` cannot be computed, and a batch that never expires
        would sit on the Journal forever. Other batches are unaffected.
        """
        # A different milestone forces the good run into its own group; with
        # the same milestone the unparseable anchor would absorb it (rows that
        # cannot be shown to differ stay together — see the grouping tests).
        rows = [_row(title="Bad", created_at="not-a-timestamp")] + _batch(
            created_at=_now() - timedelta(hours=1),
            milestone_id=str(uuid.uuid4()),
            title="Good",
        )
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        data = resp.json()
        assert data["count"] == 1
        assert data["batches"][0]["recommendations"][0]["title"] == "Good 0"
        print("  A batch with an unparseable anchor is skipped, not served")


# ===================================================================
# 7. Row cap truncation
# ===================================================================

class TestRowCapTruncation:

    def test_trailing_batch_is_dropped_when_a_row_past_the_cap_came_back(self, client, auth_override):
        """
        The handler reads one row past the cap. When that sentinel row exists,
        the oldest group is either a run the limit cut in half or a run that
        begins beyond it — incomplete either way — so it is dropped. Rows are
        newest-first and a run's rows are contiguous, so the trailing group is
        the only one the cap can ever truncate.
        """
        from app.api.recommendations import RECENT_MAX_ROWS

        now = _now()
        rows: list[dict] = []
        # Twenty complete runs fill the cap exactly; the 21st run supplies the
        # sentinel row. The query would only return one row of it.
        for i in range(RECENT_MAX_ROWS // 3 + 1):
            rows += _batch(created_at=now - timedelta(minutes=i), title=f"Run{i}")
        rows = rows[: RECENT_MAX_ROWS + 1]
        assert len(rows) == RECENT_MAX_ROWS + 1
        cut_title = rows[-1]["title"]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        data = resp.json()
        assert data["count"] == RECENT_MAX_ROWS // 3
        served_titles = {r["title"] for b in data["batches"] for r in b["recommendations"]}
        assert cut_title not in served_titles
        print("  Trailing batch is dropped when a row past the cap came back")

    def test_exactly_the_cap_serves_every_batch(self, client, auth_override):
        """
        Exactly RECENT_MAX_ROWS rows and no sentinel means nothing was cut —
        a user with twenty complete runs sees all twenty, not nineteen.
        """
        from app.api.recommendations import RECENT_MAX_ROWS

        now = _now()
        rows: list[dict] = []
        for i in range(RECENT_MAX_ROWS // 3):
            rows += _batch(created_at=now - timedelta(minutes=i), title=f"Run{i}")
        assert len(rows) == RECENT_MAX_ROWS
        oldest_title = rows[-1]["title"]
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        data = resp.json()
        assert data["count"] == RECENT_MAX_ROWS // 3
        served_titles = {r["title"] for b in data["batches"] for r in b["recommendations"]}
        assert oldest_title in served_titles
        print("  Exactly the cap with no sentinel serves every batch")

    def test_nothing_is_dropped_below_the_cap(self, client, auth_override):
        now = _now()
        rows = _batch(created_at=now) + _batch(2, created_at=now - timedelta(minutes=1), title="Two")
        mock_client, _, _ = _mock_supabase(rec_rows=rows)

        resp = _get(client, mock_client)

        assert resp.json()["count"] == 2
        print("  Below the cap every batch is served, even a two-pick one")


# ===================================================================
# 8. _group_into_insert_batches
# ===================================================================

class TestGroupIntoInsertBatches:

    def test_empty_input(self):
        from app.api.recommendations import _group_into_insert_batches

        assert _group_into_insert_batches([]) == []
        print("  Empty rows → no groups")

    def test_splits_on_time_gap(self):
        from app.api.recommendations import _group_into_insert_batches

        now = _now()
        rows = _batch(created_at=now) + _batch(created_at=now - timedelta(seconds=6))

        groups = _group_into_insert_batches(rows)

        assert [len(g) for g in groups] == [3, 3]
        print("  A 6s gap splits the group")

    def test_keeps_rows_inside_the_window_together(self):
        from app.api.recommendations import _BATCH_INSERT_WINDOW, _group_into_insert_batches

        now = _now()
        rows = [
            _row(created_at=now.isoformat()),
            _row(created_at=(now - _BATCH_INSERT_WINDOW).isoformat()),
        ]

        groups = _group_into_insert_batches(rows)

        assert [len(g) for g in groups] == [2]
        print("  A gap exactly at the window stays in one group")

    def test_splits_on_milestone_change(self):
        from app.api.recommendations import _group_into_insert_batches

        now = _now()
        rows = _batch(created_at=now, milestone_id="m1") + _batch(created_at=now, milestone_id="m2")

        groups = _group_into_insert_batches(rows)

        assert [g[0]["milestone_id"] for g in groups] == ["m1", "m2"]
        print("  A milestone change splits the group even with identical timestamps")

    def test_unparseable_row_timestamp_stays_in_current_group(self):
        from app.api.recommendations import _group_into_insert_batches

        now = _now()
        rows = [_row(created_at=now.isoformat()), _row(created_at="garbage")]

        groups = _group_into_insert_batches(rows)

        assert [len(g) for g in groups] == [2]
        print("  An unparseable row timestamp does not start a new group")

    def test_unparseable_anchor_keeps_following_rows_together(self):
        from app.api.recommendations import _group_into_insert_batches

        rows = [_row(created_at="garbage"), _row(created_at=_now().isoformat())]

        groups = _group_into_insert_batches(rows)

        assert [len(g) for g in groups] == [2]
        print("  An unparseable anchor cannot be shown to differ, so rows stay together")
