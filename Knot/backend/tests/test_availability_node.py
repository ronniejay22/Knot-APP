"""
Step 5.7 Verification: Availability Verification Node

Tests that the verify_availability LangGraph node:
1. Verifies URLs of the 3 selected recommendations via HTTP HEAD/GET
2. Replaces unavailable recommendations with next-best candidates from the pool
3. Handles edge cases (all unavailable, empty input, HEAD 405 fallback)
4. Returns result compatible with RecommendationState update

Test categories:
- URL checking: Verify _check_url handles various HTTP responses
- Replacement logic: Verify _get_backup_candidates excludes used IDs
- Full node: Verify verify_availability end-to-end behavior
- Spec tests: The 2 specific tests from the implementation plan
- Edge cases: Empty input, all unavailable, no backup pool
- State compatibility: Verify returned dict updates RecommendationState correctly

Prerequisites:
- Complete Steps 5.1-5.6 (state schema through diversity selection node)

Run with: pytest tests/test_availability_node.py -v
"""

import uuid
from unittest.mock import AsyncMock, patch

import httpx

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.availability import (
    MAX_REPLACEMENT_ATTEMPTS,
    REQUEST_TIMEOUT,
    VALID_STATUS_RANGE,
    _check_url,
    _get_backup_candidates,
    verify_availability,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-avail-test",
        "partner_name": "Alex",
        "relationship_tenure_months": 24,
        "cohabitation_status": "living_together",
        "location_city": "Austin",
        "location_state": "TX",
        "location_country": "US",
        "interests": ["Cooking", "Travel", "Music", "Art", "Hiking"],
        "dislikes": ["Gaming", "Cars", "Skiing", "Karaoke", "Surfing"],
        "vibes": ["quiet_luxury", "romantic"],
        "primary_love_language": "quality_time",
        "secondary_love_language": "receiving_gifts",
        "budgets": [
            {"occasion_type": "just_because", "min_amount": 2000, "max_amount": 5000, "currency": "USD"},
            {"occasion_type": "minor_occasion", "min_amount": 5000, "max_amount": 10000, "currency": "USD"},
            {"occasion_type": "major_milestone", "min_amount": 10000, "max_amount": 25000, "currency": "USD"},
        ],
    }
    data.update(overrides)
    return data


def _sample_milestone(**overrides) -> dict:
    data = {
        "id": "milestone-avail-001",
        "milestone_type": "birthday",
        "milestone_name": "Alex's Birthday",
        "milestone_date": "2000-03-15",
        "recurrence": "yearly",
        "budget_tier": "major_milestone",
        "days_until": 10,
    }
    data.update(overrides)
    return data


def _make_state(
    final_three=None,
    filtered=None,
    budget_min=3000,
    budget_max=30000,
    **overrides,
) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=budget_min, max_amount=budget_max),
    }
    defaults.update(overrides)
    state = RecommendationState(**defaults)
    updates = {}
    if final_three is not None:
        updates["final_three"] = final_three
    if filtered is not None:
        updates["filtered_recommendations"] = filtered
    if updates:
        state = state.model_copy(update=updates)
    return state


def _make_candidate(
    title: str = "Test Gift",
    rec_type: str = "gift",
    source: str = "amazon",
    price_cents: int = 5000,
    merchant_name: str = "Test Merchant",
    final_score: float = 1.0,
    external_url: str | None = None,
    candidate_id: str | None = None,
    **overrides,
) -> CandidateRecommendation:
    """Build a CandidateRecommendation with sensible defaults."""
    cid = candidate_id or str(uuid.uuid4())
    data = {
        "id": cid,
        "source": source,
        "type": rec_type,
        "title": title,
        "description": f"A {rec_type} recommendation",
        "price_cents": price_cents,
        "external_url": external_url or f"https://{source}.com/products/{cid}",
        "image_url": "https://images.example.com/test.jpg",
        "merchant_name": merchant_name,
        "metadata": {"catalog": "stub"},
        "interest_score": 1.0,
        "vibe_score": 0.0,
        "love_language_score": 0.0,
        "final_score": final_score,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


def _mock_response(status_code: int = 200):
    """Create a mock httpx.Response with the given status code."""
    response = AsyncMock(spec=httpx.Response)
    response.status_code = status_code
    return response


# ======================================================================
# 1. URL checking (_check_url)
# ======================================================================

class TestCheckUrl:
    """Verify _check_url handles various HTTP responses."""

    async def test_200_returns_true(self):
        """A 200 OK response means the URL is available."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(200))

        result = await _check_url("https://example.com/product", client)
        assert result is True
        client.head.assert_called_once()

    async def test_301_redirect_returns_true(self):
        """A 301 redirect (within valid range) is considered available."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(301))

        result = await _check_url("https://example.com/old-url", client)
        assert result is True

    async def test_404_returns_false(self):
        """A 404 Not Found means the URL is unavailable."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(404))

        result = await _check_url("https://example.com/gone", client)
        assert result is False

    async def test_500_returns_false(self):
        """A 500 Internal Server Error means the URL is unavailable."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(500))

        result = await _check_url("https://example.com/error", client)
        assert result is False

    async def test_405_falls_back_to_get(self):
        """If HEAD returns 405, falls back to GET."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(405))
        client.get = AsyncMock(return_value=_mock_response(200))

        result = await _check_url("https://example.com/no-head", client)
        assert result is True
        client.head.assert_called_once()
        client.get.assert_called_once()

    async def test_405_get_also_fails(self):
        """If HEAD returns 405 and GET also fails, returns False."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(return_value=_mock_response(405))
        client.get = AsyncMock(return_value=_mock_response(500))

        result = await _check_url("https://example.com/broken", client)
        assert result is False

    async def test_timeout_returns_false(self):
        """A timeout exception means the URL is unavailable."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(side_effect=httpx.TimeoutException("timed out"))

        result = await _check_url("https://example.com/slow", client)
        assert result is False

    async def test_connect_error_returns_false(self):
        """A connection error means the URL is unavailable."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(side_effect=httpx.ConnectError("connection refused"))

        result = await _check_url("https://example.com/unreachable", client)
        assert result is False

    async def test_generic_http_error_returns_false(self):
        """A generic HTTP error means the URL is unavailable."""
        client = AsyncMock(spec=httpx.AsyncClient)
        client.head = AsyncMock(side_effect=httpx.HTTPError("generic error"))

        result = await _check_url("https://example.com/error", client)
        assert result is False


# ======================================================================
# 2. Backup candidate logic
# ======================================================================

class TestGetBackupCandidates:
    """Verify _get_backup_candidates excludes used IDs and sorts by score."""

    def test_excludes_used_ids(self):
        """Candidates with IDs in the excluded set are filtered out."""
        c1 = _make_candidate(title="A", final_score=5.0, candidate_id="id-1")
        c2 = _make_candidate(title="B", final_score=4.0, candidate_id="id-2")
        c3 = _make_candidate(title="C", final_score=3.0, candidate_id="id-3")

        result = _get_backup_candidates([c1, c2, c3], {"id-1", "id-2"})
        assert len(result) == 1
        assert result[0].id == "id-3"

    def test_sorted_by_final_score_descending(self):
        """Backup candidates are sorted by final_score (best first)."""
        c1 = _make_candidate(title="Low", final_score=1.0, candidate_id="id-1")
        c2 = _make_candidate(title="High", final_score=5.0, candidate_id="id-2")
        c3 = _make_candidate(title="Mid", final_score=3.0, candidate_id="id-3")

        result = _get_backup_candidates([c1, c2, c3], set())
        assert [c.title for c in result] == ["High", "Mid", "Low"]

    def test_empty_when_all_excluded(self):
        """Returns empty list when all candidates are excluded."""
        c1 = _make_candidate(candidate_id="id-1")
        c2 = _make_candidate(candidate_id="id-2")

        result = _get_backup_candidates([c1, c2], {"id-1", "id-2"})
        assert result == []

    def test_empty_pool_returns_empty(self):
        """Returns empty list when the pool is empty."""
        result = _get_backup_candidates([], set())
        assert result == []


# ======================================================================
# 3. Full node (end-to-end with mocked HTTP)
# ======================================================================

class TestVerifyAvailability:
    """Verify verify_availability end-to-end behavior with mocked HTTP."""

    async def test_all_available_passes_through(self):
        """When all 3 URLs are valid, they pass through unchanged."""
        candidates = [
            _make_candidate(title="Gift A", candidate_id="a", final_score=5.0),
            _make_candidate(title="Experience B", candidate_id="b", rec_type="experience", final_score=4.0),
            _make_candidate(title="Date C", candidate_id="c", rec_type="date", final_score=3.0),
        ]
        state = _make_state(final_three=candidates, filtered=candidates)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            result = await verify_availability(state)

        assert len(result["final_three"]) == 3
        assert [c.title for c in result["final_three"]] == [
            "Gift A", "Experience B", "Date C",
        ]

    async def test_unavailable_replaced_from_pool(self):
        """An unavailable recommendation is replaced with the next-best backup."""
        selected = [
            _make_candidate(title="Good A", candidate_id="a", final_score=5.0),
            _make_candidate(title="Bad B", candidate_id="b", final_score=4.0),
            _make_candidate(title="Good C", candidate_id="c", final_score=3.0),
        ]
        backup = _make_candidate(
            title="Backup D", candidate_id="d", final_score=2.5,
            rec_type="experience",
        )
        filtered = selected + [backup]

        state = _make_state(final_three=selected, filtered=filtered)

        async def mock_check(url, client):
            # "Bad B" has an unavailable URL
            if "b" in url:
                return False
            return True

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        titles = [c.title for c in result["final_three"]]
        assert len(result["final_three"]) == 3
        assert "Bad B" not in titles
        assert "Backup D" in titles

    async def test_replacement_also_checked(self):
        """Replacement candidates are also URL-checked before being accepted."""
        selected = [
            _make_candidate(
                title="Bad A", candidate_id="orig-bad", final_score=5.0,
                external_url="https://shop.com/orig-bad",
            ),
        ]
        bad_backup = _make_candidate(
            title="Bad Backup", candidate_id="backup-bad", final_score=4.0,
            external_url="https://shop.com/backup-bad",
        )
        good_backup = _make_candidate(
            title="Good Backup", candidate_id="backup-good", final_score=3.0,
            external_url="https://shop.com/backup-good",
        )
        filtered = selected + [bad_backup, good_backup]

        state = _make_state(final_three=selected, filtered=filtered)

        async def mock_check(url, client):
            # Only the "good" backup URL is available
            return "backup-good" in url

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        assert len(result["final_three"]) == 1
        assert result["final_three"][0].title == "Good Backup"

    async def test_does_not_reuse_already_selected_ids(self):
        """Backup selection excludes candidates already in final_three."""
        selected = [
            _make_candidate(title="Good A", candidate_id="a", final_score=5.0),
            _make_candidate(title="Bad B", candidate_id="b", final_score=4.0),
            _make_candidate(title="Good C", candidate_id="c", final_score=3.0),
        ]
        # Pool includes selected + one backup; "a" and "c" should NOT be re-picked
        backup = _make_candidate(
            title="Backup D", candidate_id="d", final_score=2.0,
        )
        filtered = selected + [backup]

        state = _make_state(final_three=selected, filtered=filtered)

        async def mock_check(url, client):
            if "b" in url:
                return False
            return True

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        ids = [c.id for c in result["final_three"]]
        assert ids.count("a") == 1  # not duplicated
        assert ids.count("c") == 1  # not duplicated
        assert "d" in ids  # backup used

    async def test_max_replacement_attempts_respected(self):
        """Stops trying replacements after MAX_REPLACEMENT_ATTEMPTS failures."""
        selected = [
            _make_candidate(title="Bad A", candidate_id="a", final_score=5.0),
        ]
        # Create more backups than MAX_REPLACEMENT_ATTEMPTS
        backups = [
            _make_candidate(
                title=f"Bad Backup {i}",
                candidate_id=f"backup-{i}",
                final_score=4.0 - i * 0.5,
            )
            for i in range(MAX_REPLACEMENT_ATTEMPTS + 2)
        ]
        filtered = selected + backups

        state = _make_state(final_three=selected, filtered=filtered)

        # All URLs fail
        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = False
            result = await verify_availability(state)

        # Should stop after MAX_REPLACEMENT_ATTEMPTS and return empty
        assert len(result["final_three"]) == 0
        # Original (1) + MAX_REPLACEMENT_ATTEMPTS backups checked
        assert mock_check.call_count == 1 + MAX_REPLACEMENT_ATTEMPTS

    async def test_returns_final_three_key(self):
        """Node returns dict with 'final_three' key."""
        candidates = [
            _make_candidate(title="A", candidate_id="a"),
        ]
        state = _make_state(final_three=candidates, filtered=candidates)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            result = await verify_availability(state)

        assert "final_three" in result
        assert "filtered_recommendations" not in result


# ======================================================================
# 4. Spec tests (from implementation plan)
# ======================================================================

class TestSpecRequirements:
    """The 2 specific tests required by the Step 5.7 implementation plan."""

    async def test_invalid_url_replaced(self):
        """
        Spec Test 1: Provide 3 recommendations, one with an invalid URL.
        Confirm the invalid one is replaced.
        """
        valid_a = _make_candidate(
            title="Artisan Cookbook",
            candidate_id="valid-a",
            rec_type="gift",
            price_cents=5000,
            merchant_name="Amazon",
            final_score=5.0,
            external_url="https://amazon.com/products/cookbook",
        )
        invalid_b = _make_candidate(
            title="Dead Link Experience",
            candidate_id="invalid-b",
            rec_type="experience",
            price_cents=15000,
            merchant_name="Yelp",
            final_score=4.0,
            external_url="https://yelp.com/biz/closed-restaurant",
        )
        valid_c = _make_candidate(
            title="Concert Tickets",
            candidate_id="valid-c",
            rec_type="experience",
            price_cents=12000,
            merchant_name="Ticketmaster",
            final_score=3.0,
            external_url="https://ticketmaster.com/event/123",
        )
        backup = _make_candidate(
            title="Spa Day Package",
            candidate_id="backup-d",
            rec_type="date",
            price_cents=18000,
            merchant_name="SpaFinder",
            final_score=2.5,
            external_url="https://spafinder.com/spa/day-package",
        )

        selected = [valid_a, invalid_b, valid_c]
        filtered = selected + [backup]
        state = _make_state(final_three=selected, filtered=filtered)

        async def mock_check(url, client):
            # Only the Yelp URL is "dead"
            return "closed-restaurant" not in url

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        titles = [c.title for c in result["final_three"]]
        assert len(result["final_three"]) == 3
        assert "Dead Link Experience" not in titles, (
            "Invalid recommendation should have been replaced"
        )
        assert "Spa Day Package" in titles, (
            "Backup candidate should replace the invalid one"
        )

    async def test_all_final_urls_verified(self):
        """
        Spec Test 2: Confirm all 3 final recommendations have verified URLs.
        """
        candidates = [
            _make_candidate(
                title=f"Item {i}",
                candidate_id=f"item-{i}",
                final_score=float(5 - i),
                external_url=f"https://shop.com/item-{i}",
            )
            for i in range(5)
        ]

        state = _make_state(
            final_three=candidates[:3],
            filtered=candidates,
        )

        # Track which URLs were checked
        checked_urls = []

        async def mock_check(url, client):
            checked_urls.append(url)
            return True

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        # All 3 final recommendations should have been checked
        assert len(result["final_three"]) == 3
        final_urls = {c.external_url for c in result["final_three"]}
        # Every final URL was verified
        for url in final_urls:
            assert url in checked_urls, (
                f"URL {url} was in final results but never verified"
            )


# ======================================================================
# 5. Edge cases
# ======================================================================

class TestEdgeCases:
    """Edge cases and boundary conditions."""

    async def test_empty_final_three_returns_empty(self):
        """Node handles empty final_three gracefully."""
        state = _make_state(final_three=[], filtered=[])
        result = await verify_availability(state)
        assert result["final_three"] == []

    async def test_all_unavailable_no_backups(self):
        """When all URLs fail and no backups exist, returns empty."""
        candidates = [
            _make_candidate(title="Bad A", candidate_id="a"),
            _make_candidate(title="Bad B", candidate_id="b"),
        ]
        state = _make_state(final_three=candidates, filtered=candidates)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = False
            result = await verify_availability(state)

        assert result["final_three"] == []

    async def test_single_candidate_verified(self):
        """Node works with just 1 recommendation."""
        candidate = _make_candidate(title="Solo", candidate_id="solo")
        state = _make_state(final_three=[candidate], filtered=[candidate])

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            result = await verify_availability(state)

        assert len(result["final_three"]) == 1
        assert result["final_three"][0].title == "Solo"

    async def test_partial_results_when_some_fail(self):
        """Returns partial results when some slots cannot be filled."""
        candidates = [
            _make_candidate(title="Good", candidate_id="good", final_score=5.0),
            _make_candidate(title="Bad", candidate_id="bad", final_score=4.0),
        ]
        # No backup pool beyond the selected ones
        state = _make_state(final_three=candidates, filtered=candidates)

        async def mock_check(url, client):
            return "good" in url

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        assert len(result["final_three"]) == 1
        assert result["final_three"][0].title == "Good"

    async def test_empty_backup_pool(self):
        """When filtered pool is empty, unavailable items are just dropped."""
        candidates = [
            _make_candidate(title="Bad", candidate_id="bad"),
        ]
        state = _make_state(final_three=candidates, filtered=[])

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = False
            result = await verify_availability(state)

        assert result["final_three"] == []

    async def test_does_not_mutate_input_state(self):
        """Node does not mutate the input state."""
        candidates = [
            _make_candidate(title="A", candidate_id="a", final_score=5.0),
            _make_candidate(title="B", candidate_id="b", final_score=4.0),
            _make_candidate(title="C", candidate_id="c", final_score=3.0),
        ]
        state = _make_state(final_three=candidates, filtered=candidates)
        original_len = len(state.final_three)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            await verify_availability(state)

        assert len(state.final_three) == original_len


# ======================================================================
# 6. State compatibility
# ======================================================================

class TestStateCompatibility:
    """Verify returned dict correctly updates RecommendationState."""

    async def test_result_updates_state(self):
        """Returned dict correctly updates RecommendationState.final_three."""
        candidates = [
            _make_candidate(title="A", candidate_id="a", final_score=5.0),
            _make_candidate(title="B", candidate_id="b", final_score=4.0),
            _make_candidate(title="C", candidate_id="c", final_score=3.0),
        ]
        state = _make_state(final_three=candidates, filtered=candidates)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            result = await verify_availability(state)

        updated = state.model_copy(update=result)
        assert len(updated.final_three) == 3

    async def test_preserves_filtered_recommendations(self):
        """After update, original filtered_recommendations are still accessible."""
        candidates = [
            _make_candidate(title=f"Item {i}", candidate_id=f"item-{i}", final_score=float(5 - i))
            for i in range(5)
        ]
        state = _make_state(final_three=candidates[:3], filtered=candidates)

        with patch("app.agents.availability._check_url", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            result = await verify_availability(state)

        updated = state.model_copy(update=result)
        assert len(updated.filtered_recommendations) == 5
        assert len(updated.final_three) == 3

    async def test_replacement_preserves_candidate_fields(self):
        """Replaced candidates retain all their original fields."""
        original = _make_candidate(
            title="Bad One", candidate_id="bad", final_score=5.0,
        )
        backup = _make_candidate(
            title="Backup",
            candidate_id="backup",
            rec_type="experience",
            price_cents=15000,
            merchant_name="Great Merchant",
            final_score=4.0,
            external_url="https://great.com/experience",
        )
        state = _make_state(
            final_three=[original],
            filtered=[original, backup],
        )

        async def mock_check(url, client):
            return "great.com" in url

        with patch("app.agents.availability._check_url", side_effect=mock_check):
            result = await verify_availability(state)

        replaced = result["final_three"][0]
        assert replaced.title == "Backup"
        assert replaced.type == "experience"
        assert replaced.price_cents == 15000
        assert replaced.merchant_name == "Great Merchant"
        assert replaced.external_url == "https://great.com/experience"
        assert replaced.final_score == 4.0


# ======================================================================
# 7. Constants verification
# ======================================================================

class TestConstants:
    """Verify module constants are reasonable."""

    def test_timeout_is_reasonable(self):
        """Request timeout should be between 1-30 seconds."""
        assert 1.0 <= REQUEST_TIMEOUT <= 30.0

    def test_max_replacement_attempts_positive(self):
        """Max replacement attempts should be a positive integer."""
        assert MAX_REPLACEMENT_ATTEMPTS > 0

    def test_valid_status_range_includes_200(self):
        """Valid status range should include 200."""
        assert 200 in VALID_STATUS_RANGE

    def test_valid_status_range_excludes_400(self):
        """Valid status range should exclude 400."""
        assert 400 not in VALID_STATUS_RANGE

    def test_valid_status_range_excludes_500(self):
        """Valid status range should exclude 500."""
        assert 500 not in VALID_STATUS_RANGE
