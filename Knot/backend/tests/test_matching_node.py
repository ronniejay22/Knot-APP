"""
Step 5.5 Verification: Vibe and Love Language Matching Node

Tests that the match_vibes_and_love_languages LangGraph node:
1. Computes vibe_boost from matching vault vibes to candidate vibes
2. Computes love_language_boost from primary/secondary love language alignment
3. Calculates final_score = max(interest_score, 1.0) × (1 + vibe_boost) × (1 + love_language_boost)
4. Re-ranks candidates by final_score (descending)
5. Handles edge cases (empty input, zero interest scores, no matches)
6. Returns result compatible with RecommendationState update

Test categories:
- Vibe matching: Verify _candidate_matches_vibe detects metadata and keywords
- Vibe boost: Verify _compute_vibe_boost stacks +30% per matching vibe
- Love language matching: Verify _candidate_matches_love_language by type/keywords
- Love language boost: Verify _compute_love_language_boost applies primary/secondary boosts
- Final scoring: Verify combined formula produces correct scores
- Full node: Verify match_vibes_and_love_languages end-to-end behavior
- Spec tests: The 3 specific tests from the implementation plan
- Edge cases: Empty candidates, zero interest scores, unknown love languages
- State compatibility: Verify returned dict updates RecommendationState correctly

Prerequisites:
- Complete Steps 5.1-5.4 (state schema, hint retrieval, aggregation, filtering)

Run with: pytest tests/test_matching_node.py -v
"""

import uuid

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    MilestoneContext,
    RecommendationState,
    VaultData,
)
from app.agents.matching import (
    VIBE_MATCH_BOOST,
    _candidate_matches_love_language,
    _candidate_matches_vibe,
    _compute_love_language_boost,
    _compute_vibe_boost,
    _normalize,
    match_vibes_and_love_languages,
)


# ======================================================================
# Sample data factories
# ======================================================================

def _sample_vault_data(**overrides) -> dict:
    """Returns a complete VaultData dict. Override any field via kwargs."""
    data = {
        "vault_id": "vault-match-test",
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
        "id": "milestone-match-001",
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
    filtered=None,
    **overrides,
) -> RecommendationState:
    """Build a RecommendationState with sensible defaults."""
    defaults = {
        "vault_data": VaultData(**_sample_vault_data()),
        "occasion_type": "major_milestone",
        "milestone_context": MilestoneContext(**_sample_milestone()),
        "budget_range": BudgetRange(min_amount=2000, max_amount=30000),
    }
    defaults.update(overrides)
    state = RecommendationState(**defaults)
    if filtered is not None:
        state = state.model_copy(update={"filtered_recommendations": filtered})
    return state


def _make_candidate(
    title: str = "Test Gift",
    description: str = "A test gift description",
    rec_type: str = "gift",
    source: str = "amazon",
    price_cents: int = 5000,
    interest_score: float = 0.0,
    matched_interest: str | None = None,
    matched_vibe: str | None = None,
    **overrides,
) -> CandidateRecommendation:
    """Build a CandidateRecommendation with sensible defaults."""
    metadata = {}
    if matched_interest:
        metadata["matched_interest"] = matched_interest
    if matched_vibe:
        metadata["matched_vibe"] = matched_vibe
    metadata["catalog"] = "stub"

    data = {
        "id": str(uuid.uuid4()),
        "source": source,
        "type": rec_type,
        "title": title,
        "description": description,
        "price_cents": price_cents,
        "external_url": f"https://{source}.com/products/test",
        "image_url": "https://images.example.com/test.jpg",
        "merchant_name": "Test Merchant",
        "metadata": metadata,
        "interest_score": interest_score,
    }
    data.update(overrides)
    return CandidateRecommendation(**data)


# ======================================================================
# 1. Normalize helper
# ======================================================================

class TestNormalize:
    """Verify the _normalize helper."""

    def test_lowercase(self):
        assert _normalize("Quiet_Luxury") == "quiet_luxury"

    def test_strip_whitespace(self):
        assert _normalize("  romantic  ") == "romantic"

    def test_already_lowercase(self):
        assert _normalize("minimalist") == "minimalist"


# ======================================================================
# 2. Vibe matching
# ======================================================================

class TestCandidateMatchesVibe:
    """Verify _candidate_matches_vibe detects metadata and keywords."""

    def test_matches_via_metadata_vibe(self):
        """Metadata matched_vibe is the strongest signal."""
        candidate = _make_candidate(
            title="Spa Day for Two",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        assert _candidate_matches_vibe(candidate, "quiet_luxury") is True

    def test_matches_via_metadata_case_insensitive(self):
        """Metadata matching is case-insensitive."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="Quiet_Luxury",
        )
        assert _candidate_matches_vibe(candidate, "quiet_luxury") is True

    def test_matches_via_title_keyword(self):
        """Title keyword matching catches vibe-related words."""
        candidate = _make_candidate(
            title="Luxury Spa Experience",
            rec_type="experience",
        )
        assert _candidate_matches_vibe(candidate, "quiet_luxury") is True

    def test_matches_via_description_keyword(self):
        """Description keyword matching catches vibe-related words."""
        candidate = _make_candidate(
            title="Evening Out",
            description="Exclusive fine dining experience at an upscale restaurant",
            rec_type="date",
        )
        assert _candidate_matches_vibe(candidate, "quiet_luxury") is True

    def test_no_match_when_unrelated(self):
        """Candidate with no relation to vibe returns False."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            description="Premium audio quality",
            rec_type="gift",
            matched_interest="Music",
        )
        assert _candidate_matches_vibe(candidate, "bohemian") is False

    def test_no_match_with_different_vibe_metadata(self):
        """Candidate tagged with a different vibe doesn't match."""
        candidate = _make_candidate(
            title="Street Art Walking Tour",
            rec_type="experience",
            matched_vibe="street_urban",
        )
        assert _candidate_matches_vibe(candidate, "quiet_luxury") is False

    def test_adventurous_keyword_match(self):
        """Adventurous vibe matches via keyword."""
        candidate = _make_candidate(
            title="White Water Rafting Adventure",
            rec_type="experience",
        )
        assert _candidate_matches_vibe(candidate, "adventurous") is True

    def test_romantic_keyword_match(self):
        """Romantic vibe matches via keyword."""
        candidate = _make_candidate(
            title="Candlelit Dinner for Two",
            description="Romantic sunset dining experience",
            rec_type="date",
        )
        assert _candidate_matches_vibe(candidate, "romantic") is True

    def test_none_description_no_crash(self):
        """Handles None description gracefully."""
        candidate = _make_candidate(
            title="Simple Gift",
            description=None,
            rec_type="gift",
        )
        assert _candidate_matches_vibe(candidate, "minimalist") is False

    def test_gift_with_vibe_keyword_matches(self):
        """Even gift candidates can match vibes via keywords."""
        candidate = _make_candidate(
            title="Vintage Leather Journal",
            description="Classic retro design",
            rec_type="gift",
        )
        assert _candidate_matches_vibe(candidate, "vintage") is True


# ======================================================================
# 3. Vibe boost computation
# ======================================================================

class TestComputeVibeBoost:
    """Verify _compute_vibe_boost stacks +30% per matching vibe."""

    def test_single_vibe_match(self):
        """One matching vibe gives +0.30."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        boost, matched = _compute_vibe_boost(candidate, ["quiet_luxury"])
        assert boost == VIBE_MATCH_BOOST  # 0.30
        assert matched == ["quiet_luxury"]

    def test_two_vibe_matches(self):
        """Two matching vibes stack to +0.60."""
        candidate = _make_candidate(
            title="Candlelit Dinner Cruise",
            description="Exclusive luxury sunset cruise for couples",
            rec_type="date",
            matched_vibe="romantic",
        )
        # Matches "romantic" via metadata, and "quiet_luxury" via keywords
        boost, matched = _compute_vibe_boost(candidate, ["romantic", "quiet_luxury"])
        assert boost == VIBE_MATCH_BOOST * 2  # 0.60
        assert "romantic" in matched
        assert "quiet_luxury" in matched

    def test_no_vibe_match(self):
        """No matching vibes gives 0.0."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            rec_type="gift",
            matched_interest="Music",
        )
        boost, matched = _compute_vibe_boost(candidate, ["outdoorsy", "bohemian"])
        assert boost == 0.0
        assert matched == []

    def test_empty_vibes_list(self):
        """Empty vault vibes gives 0.0."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            matched_vibe="quiet_luxury",
        )
        boost, matched = _compute_vibe_boost(candidate, [])
        assert boost == 0.0
        assert matched == []

    def test_partial_match_from_multiple(self):
        """Only matching vibes contribute, unmatched ones don't."""
        candidate = _make_candidate(
            title="Pottery Workshop",
            rec_type="experience",
            matched_vibe="bohemian",
        )
        # Only "bohemian" matches, not "quiet_luxury"
        boost, matched = _compute_vibe_boost(candidate, ["quiet_luxury", "bohemian"])
        assert boost == VIBE_MATCH_BOOST  # 0.30
        assert matched == ["bohemian"]


# ======================================================================
# 4. Love language matching
# ======================================================================

class TestCandidateMatchesLoveLanguage:
    """Verify _candidate_matches_love_language by type and keywords."""

    def test_receiving_gifts_matches_gift_type(self):
        """Gift-type candidates match receiving_gifts."""
        candidate = _make_candidate(rec_type="gift")
        assert _candidate_matches_love_language(candidate, "receiving_gifts") is True

    def test_receiving_gifts_does_not_match_experience(self):
        """Experience candidates don't match receiving_gifts."""
        candidate = _make_candidate(rec_type="experience")
        assert _candidate_matches_love_language(candidate, "receiving_gifts") is False

    def test_quality_time_matches_experience(self):
        """Experience-type candidates match quality_time."""
        candidate = _make_candidate(rec_type="experience")
        assert _candidate_matches_love_language(candidate, "quality_time") is True

    def test_quality_time_matches_date(self):
        """Date-type candidates match quality_time."""
        candidate = _make_candidate(rec_type="date")
        assert _candidate_matches_love_language(candidate, "quality_time") is True

    def test_quality_time_does_not_match_gift(self):
        """Gift candidates don't match quality_time."""
        candidate = _make_candidate(rec_type="gift")
        assert _candidate_matches_love_language(candidate, "quality_time") is False

    def test_acts_of_service_matches_practical_keywords(self):
        """Practical/useful items match acts_of_service via keywords."""
        candidate = _make_candidate(
            title="Complete Home Tool Kit",
            description="112-piece home repair tool kit",
            rec_type="gift",
        )
        assert _candidate_matches_love_language(candidate, "acts_of_service") is True

    def test_acts_of_service_no_match_without_keywords(self):
        """Non-practical items don't match acts_of_service."""
        candidate = _make_candidate(
            title="Vinyl Record Player",
            description="Bluetooth turntable with speakers",
            rec_type="gift",
        )
        assert _candidate_matches_love_language(candidate, "acts_of_service") is False

    def test_words_of_affirmation_matches_personalized(self):
        """Personalized/sentimental items match words_of_affirmation."""
        candidate = _make_candidate(
            title="Custom Song Portrait Print",
            description="Personalized sound wave art of your song",
            rec_type="gift",
        )
        assert _candidate_matches_love_language(candidate, "words_of_affirmation") is True

    def test_words_of_affirmation_no_match_generic(self):
        """Generic items don't match words_of_affirmation."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            description="Premium audio quality",
            rec_type="gift",
        )
        assert _candidate_matches_love_language(candidate, "words_of_affirmation") is False

    def test_physical_touch_matches_couples_experience(self):
        """Couples experiences match physical_touch."""
        candidate = _make_candidate(
            title="Couples Massage and Spa Day",
            description="Full spa treatment for two",
            rec_type="experience",
        )
        assert _candidate_matches_love_language(candidate, "physical_touch") is True

    def test_physical_touch_matches_dance_class(self):
        """Dance class matches physical_touch."""
        candidate = _make_candidate(
            title="Salsa Dance Class",
            description="Beginner dance class for couples",
            rec_type="experience",
        )
        assert _candidate_matches_love_language(candidate, "physical_touch") is True

    def test_physical_touch_no_match_solo_experience(self):
        """Solo experiences don't match physical_touch."""
        candidate = _make_candidate(
            title="Skydiving Jump",
            description="Tandem skydiving experience",
            rec_type="experience",
        )
        assert _candidate_matches_love_language(candidate, "physical_touch") is False

    def test_unknown_love_language_returns_false(self):
        """Unknown love language returns False."""
        candidate = _make_candidate(rec_type="gift")
        assert _candidate_matches_love_language(candidate, "unknown_language") is False


# ======================================================================
# 5. Love language boost computation
# ======================================================================

class TestComputeLoveLanguageBoost:
    """Verify _compute_love_language_boost applies primary/secondary boosts."""

    def test_primary_receiving_gifts_boosts_gift(self):
        """Primary receiving_gifts gives +40% to gifts."""
        candidate = _make_candidate(rec_type="gift")
        boost, matched = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
        )
        assert boost == 0.40
        assert matched == ["receiving_gifts"]

    def test_secondary_receiving_gifts_boosts_gift(self):
        """Secondary receiving_gifts gives +20% to gifts."""
        candidate = _make_candidate(rec_type="gift")
        boost, matched = _compute_love_language_boost(
            candidate, "quality_time", "receiving_gifts",
        )
        assert boost == 0.20
        assert matched == ["receiving_gifts"]

    def test_primary_quality_time_boosts_experience(self):
        """Primary quality_time gives +40% to experiences."""
        candidate = _make_candidate(rec_type="experience")
        boost, matched = _compute_love_language_boost(
            candidate, "quality_time", "receiving_gifts",
        )
        assert boost == 0.40
        assert matched == ["quality_time"]

    def test_secondary_quality_time_boosts_date(self):
        """Secondary quality_time gives +20% to dates."""
        candidate = _make_candidate(rec_type="date")
        boost, matched = _compute_love_language_boost(
            candidate, "receiving_gifts", "quality_time",
        )
        assert boost == 0.20
        assert matched == ["quality_time"]

    def test_both_match_stacks_boosts(self):
        """When both primary and secondary match, boosts stack."""
        # A couples spa experience: type=experience (quality_time) + "spa" keyword (physical_touch)
        candidate = _make_candidate(
            title="Couples Spa Day",
            description="Couples massage and spa treatment",
            rec_type="experience",
        )
        boost, matched = _compute_love_language_boost(
            candidate, "quality_time", "physical_touch",
        )
        # quality_time primary: +0.40, physical_touch secondary: +0.10
        assert boost == 0.50
        assert "quality_time" in matched
        assert "physical_touch" in matched

    def test_no_match_returns_zero(self):
        """No matching love language gives 0.0."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            rec_type="gift",
        )
        boost, matched = _compute_love_language_boost(
            candidate, "quality_time", "physical_touch",
        )
        # Gift doesn't match quality_time; headphones don't match physical_touch
        assert boost == 0.0
        assert matched == []

    def test_acts_of_service_primary_boost(self):
        """Primary acts_of_service gives +20% to practical items."""
        candidate = _make_candidate(
            title="Complete Home Tool Kit",
            description="Repair tool kit for home",
            rec_type="gift",
        )
        boost, matched = _compute_love_language_boost(
            candidate, "acts_of_service", "quality_time",
        )
        assert boost == 0.20
        assert matched == ["acts_of_service"]

    def test_words_of_affirmation_secondary_boost(self):
        """Secondary words_of_affirmation gives +10% to personalized items."""
        candidate = _make_candidate(
            title="Custom Portrait Commission",
            description="Personalized portrait from your photo",
            rec_type="gift",
        )
        boost, matched = _compute_love_language_boost(
            candidate, "receiving_gifts", "words_of_affirmation",
        )
        # receiving_gifts primary: +0.40 (it's a gift)
        # words_of_affirmation secondary: +0.10 ("personalized", "custom", "portrait")
        assert boost == 0.50
        assert "receiving_gifts" in matched
        assert "words_of_affirmation" in matched


# ======================================================================
# 6. Final scoring formula
# ======================================================================

class TestFinalScoring:
    """Verify the combined scoring formula."""

    def test_zero_interest_score_with_vibe_match(self):
        """Experience with 0 interest_score still gets a meaningful score via vibes."""
        candidate = _make_candidate(
            title="Spa Day",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )
        vibe_boost, _ = _compute_vibe_boost(candidate, ["quiet_luxury"])
        ll_boost, _ = _compute_love_language_boost(candidate, "quality_time", "receiving_gifts")
        base = max(candidate.interest_score, 1.0)
        final = base * (1 + vibe_boost) * (1 + ll_boost)
        # base=1.0 (floor), vibe=+0.30, ll=+0.40 → 1.0 × 1.30 × 1.40 = 1.82
        assert final == 1.0 * 1.30 * 1.40

    def test_positive_interest_score_amplifies_boosts(self):
        """Higher interest_score amplifies the vibe/ll multipliers."""
        candidate = _make_candidate(
            title="Japanese Chef Knife",
            rec_type="gift",
            interest_score=1.5,
            matched_interest="Cooking",
        )
        vibe_boost, _ = _compute_vibe_boost(candidate, ["quiet_luxury"])
        ll_boost, _ = _compute_love_language_boost(candidate, "receiving_gifts", "quality_time")
        base = max(candidate.interest_score, 1.0)
        final = base * (1 + vibe_boost) * (1 + ll_boost)
        # base=1.5 (interest_score > 1.0), vibe=0.0, ll=+0.40 → 1.5 × 1.0 × 1.40 = 2.10
        assert final == 1.5 * 1.0 * 1.40

    def test_no_boosts_just_base(self):
        """Without vibe or love language matches, final_score = base."""
        candidate = _make_candidate(
            title="Wireless Headphones",
            rec_type="gift",
            interest_score=1.0,
        )
        vibe_boost, _ = _compute_vibe_boost(candidate, ["outdoorsy"])
        ll_boost, _ = _compute_love_language_boost(candidate, "quality_time", "physical_touch")
        base = max(candidate.interest_score, 1.0)
        final = base * (1 + vibe_boost) * (1 + ll_boost)
        # base=1.0, no vibe match, no ll match → 1.0 × 1.0 × 1.0 = 1.0
        assert final == 1.0


# ======================================================================
# 7. Full node (end-to-end)
# ======================================================================

class TestMatchVibesAndLoveLanguages:
    """Verify match_vibes_and_love_languages end-to-end behavior."""

    async def test_returns_re_ranked_candidates(self):
        """Node returns filtered_recommendations re-ranked by final_score."""
        candidates = [
            _make_candidate(
                title="Generic Headphones",
                rec_type="gift",
                interest_score=1.0,
            ),
            _make_candidate(
                title="Spa Day for Two",
                rec_type="experience",
                interest_score=0.0,
                matched_vibe="quiet_luxury",
            ),
        ]
        state = _make_state(
            filtered=candidates,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)

        assert "filtered_recommendations" in result
        ranked = result["filtered_recommendations"]
        assert len(ranked) == 2
        # Spa Day should rank first: vibe match + quality_time match
        assert ranked[0].title == "Spa Day for Two"
        assert ranked[0].final_score > ranked[1].final_score

    async def test_scores_are_populated(self):
        """Node populates vibe_score, love_language_score, and final_score."""
        candidates = [
            _make_candidate(
                title="Fine Dining Omakase",
                rec_type="date",
                interest_score=0.0,
                matched_vibe="quiet_luxury",
            ),
        ]
        state = _make_state(
            filtered=candidates,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        assert c.vibe_score == 0.30  # quiet_luxury match
        assert c.love_language_score == 0.40  # quality_time primary (date type)
        assert c.final_score > 0

    async def test_empty_candidates_returns_empty(self):
        """Node handles empty candidate list gracefully."""
        state = _make_state(filtered=[])
        result = await match_vibes_and_love_languages(state)
        assert result["filtered_recommendations"] == []

    async def test_does_not_remove_candidates(self):
        """The matching node never removes candidates — only re-scores and re-ranks."""
        candidates = [
            _make_candidate(title="Gift A", rec_type="gift", interest_score=1.0),
            _make_candidate(title="Gift B", rec_type="gift", interest_score=0.5),
            _make_candidate(title="Experience C", rec_type="experience", interest_score=0.0),
        ]
        state = _make_state(filtered=candidates)
        result = await match_vibes_and_love_languages(state)
        assert len(result["filtered_recommendations"]) == 3

    async def test_deterministic_ordering(self):
        """Same input always produces same output order (title tiebreaker)."""
        candidates = [
            _make_candidate(title="B Gift", rec_type="gift", interest_score=1.0),
            _make_candidate(title="A Gift", rec_type="gift", interest_score=1.0),
        ]
        state = _make_state(
            filtered=candidates,
            vault_data=VaultData(**_sample_vault_data(
                primary_love_language="receiving_gifts",
                secondary_love_language="quality_time",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]
        # Same final_score → alphabetical by title
        assert ranked[0].title == "A Gift"
        assert ranked[1].title == "B Gift"

    async def test_matched_factors_populated(self):
        """Node populates matched_vibes and matched_love_languages lists."""
        candidates = [
            _make_candidate(
                title="Fine Dining Omakase",
                rec_type="date",
                interest_score=0.0,
                matched_vibe="quiet_luxury",
            ),
        ]
        state = _make_state(
            filtered=candidates,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury", "romantic"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        # Should have quiet_luxury in matched_vibes (matches via metadata)
        assert "quiet_luxury" in c.matched_vibes
        # Should have quality_time in matched_love_languages (date type matches quality_time)
        assert "quality_time" in c.matched_love_languages

    async def test_does_not_mutate_original_candidates(self):
        """Node uses model_copy instead of mutating original candidates."""
        original = _make_candidate(
            title="Original Gift",
            rec_type="gift",
            interest_score=1.0,
        )
        state = _make_state(filtered=[original])
        result = await match_vibes_and_love_languages(state)

        # Original should be unchanged
        assert original.final_score == 0.0
        assert original.vibe_score == 0.0
        assert original.love_language_score == 0.0

        # Result should have new scores
        scored = result["filtered_recommendations"][0]
        assert scored.final_score > 0

    async def test_state_compatibility(self):
        """Returned dict correctly updates RecommendationState."""
        candidates = [
            _make_candidate(title="Test", rec_type="gift", interest_score=1.0),
        ]
        state = _make_state(filtered=candidates)
        result = await match_vibes_and_love_languages(state)

        updated = state.model_copy(update=result)
        assert len(updated.filtered_recommendations) == 1
        assert updated.filtered_recommendations[0].final_score > 0


# ======================================================================
# 8. Spec tests (from implementation plan)
# ======================================================================

class TestSpecRequirements:
    """The 3 specific tests required by the Step 5.5 implementation plan."""

    async def test_quiet_luxury_minimalist_ranks_flashy_lower(self):
        """
        Spec Test 1: Set vibes to "quiet_luxury" and "minimalist."
        Confirm loud/flashy candidates are ranked lower.
        """
        quiet_spa = _make_candidate(
            title="Japanese Tea Ceremony",
            description="Authentic zen matcha tea ceremony experience",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="minimalist",
        )
        luxury_dinner = _make_candidate(
            title="Fine Dining Omakase",
            description="Exclusive 12-course chef's tasting menu",
            rec_type="date",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )
        flashy_festival = _make_candidate(
            title="Food Truck Festival Tickets",
            description="Weekend pass to the annual food truck festival",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="street_urban",
        )
        loud_skydiving = _make_candidate(
            title="Skydiving Tandem Jump",
            description="First-time tandem skydiving experience",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="adventurous",
        )

        state = _make_state(
            filtered=[flashy_festival, loud_skydiving, quiet_spa, luxury_dinner],
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury", "minimalist"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        # Quiet luxury and minimalist candidates should be in top 2
        top_titles = {ranked[0].title, ranked[1].title}
        assert "Japanese Tea Ceremony" in top_titles
        assert "Fine Dining Omakase" in top_titles

        # Flashy/loud candidates should be at the bottom
        bottom_titles = {ranked[2].title, ranked[3].title}
        assert "Food Truck Festival Tickets" in bottom_titles
        assert "Skydiving Tandem Jump" in bottom_titles

        # Verify vibe scores: matching vibes get +0.30, non-matching get 0.0
        for c in ranked:
            if c.title in ("Japanese Tea Ceremony", "Fine Dining Omakase"):
                assert c.vibe_score > 0, f"{c.title} should have positive vibe_score"
            else:
                assert c.vibe_score == 0.0, f"{c.title} should have zero vibe_score"

    async def test_primary_receiving_gifts_ranks_gifts_higher(self):
        """
        Spec Test 2: Set primary love language to "receiving_gifts."
        Confirm gift-type recommendations rank higher than experiences.
        """
        gift_a = _make_candidate(
            title="Japanese Chef Knife",
            rec_type="gift",
            interest_score=1.0,
            matched_interest="Cooking",
        )
        gift_b = _make_candidate(
            title="Premium Wireless Headphones",
            rec_type="gift",
            interest_score=1.0,
            matched_interest="Music",
        )
        experience_a = _make_candidate(
            title="Sunset Kayak Tour",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="outdoorsy",
        )
        experience_b = _make_candidate(
            title="Rock Climbing Class",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="adventurous",
        )

        state = _make_state(
            filtered=[experience_a, gift_a, experience_b, gift_b],
            vault_data=VaultData(**_sample_vault_data(
                vibes=["outdoorsy"],
                primary_love_language="receiving_gifts",
                secondary_love_language="acts_of_service",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        # Both gifts should rank above both experiences
        assert ranked[0].type == "gift"
        assert ranked[1].type == "gift"
        # Gifts get +40% from primary receiving_gifts
        for c in ranked:
            if c.type == "gift":
                assert c.love_language_score >= 0.40

    async def test_primary_quality_time_secondary_receiving_gifts(self):
        """
        Spec Test 3: Set primary to "quality_time," secondary to "receiving_gifts."
        Confirm experiences rank highest, gifts rank second.
        """
        experience = _make_candidate(
            title="Spa Day for Two",
            rec_type="experience",
            interest_score=0.0,
            matched_vibe="quiet_luxury",
        )
        date = _make_candidate(
            title="Candlelit Cooking Class",
            rec_type="date",
            interest_score=0.0,
            matched_vibe="romantic",
        )
        gift = _make_candidate(
            title="Japanese Chef Knife",
            rec_type="gift",
            interest_score=1.5,
            matched_interest="Cooking",
        )
        neutral = _make_candidate(
            title="Wireless Headphones",
            description="Premium audio quality",
            rec_type="gift",
            interest_score=1.0,
        )

        state = _make_state(
            filtered=[neutral, gift, experience, date],
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury", "romantic"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        # Experiences/dates should rank highest (quality_time primary +40%)
        # Both get vibe match too
        assert ranked[0].type in ("experience", "date")
        assert ranked[1].type in ("experience", "date")

        # Experiences get +0.40 from primary quality_time
        for c in ranked:
            if c.type in ("experience", "date"):
                assert c.love_language_score >= 0.40

        # Gifts get +0.20 from secondary receiving_gifts
        for c in ranked:
            if c.type == "gift":
                assert c.love_language_score == 0.20 or c.love_language_score == 0.0


# ======================================================================
# 9. Edge cases
# ======================================================================

class TestEdgeCases:
    """Edge cases and boundary conditions."""

    async def test_all_candidates_same_interest_score(self):
        """When all candidates have the same interest_score, vibes differentiate."""
        candidates = [
            _make_candidate(
                title="Street Art Tour",
                rec_type="experience",
                interest_score=0.0,
                matched_vibe="street_urban",
            ),
            _make_candidate(
                title="Spa Day",
                rec_type="experience",
                interest_score=0.0,
                matched_vibe="quiet_luxury",
            ),
            _make_candidate(
                title="Pottery Class",
                rec_type="experience",
                interest_score=0.0,
                matched_vibe="bohemian",
            ),
        ]
        state = _make_state(
            filtered=candidates,
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]

        # Spa Day should rank first (matches quiet_luxury vibe)
        assert ranked[0].title == "Spa Day"
        assert ranked[0].vibe_score > 0
        # Others have no vibe match
        assert ranked[1].vibe_score == 0.0
        assert ranked[2].vibe_score == 0.0

    async def test_single_candidate(self):
        """Node handles a single candidate correctly."""
        candidates = [
            _make_candidate(
                title="Solo Gift",
                rec_type="gift",
                interest_score=1.0,
            ),
        ]
        state = _make_state(filtered=candidates)
        result = await match_vibes_and_love_languages(state)
        ranked = result["filtered_recommendations"]
        assert len(ranked) == 1
        assert ranked[0].final_score > 0

    async def test_many_vibes_all_matching(self):
        """All vault vibes matching a single candidate stack correctly."""
        candidate = _make_candidate(
            title="Luxury Candlelit Sunset Pottery Craft Adventure",
            description="Exclusive vintage zen outdoor indie thrill experience",
            rec_type="experience",
            interest_score=0.0,
        )
        # This candidate has keywords matching many vibes
        state = _make_state(
            filtered=[candidate],
            vault_data=VaultData(**_sample_vault_data(
                vibes=["quiet_luxury", "romantic", "vintage", "bohemian", "adventurous"],
                primary_love_language="quality_time",
                secondary_love_language="receiving_gifts",
            )),
        )
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        # Multiple vibes should stack
        assert c.vibe_score >= VIBE_MATCH_BOOST * 2  # at least 2 matches

    async def test_candidate_without_metadata(self):
        """Candidates without matched_vibe or matched_interest still get scored."""
        candidate = _make_candidate(
            title="Random Product",
            rec_type="gift",
            interest_score=0.5,
        )
        state = _make_state(filtered=[candidate])
        result = await match_vibes_and_love_languages(state)
        c = result["filtered_recommendations"][0]

        # Should still have a valid final_score (base only, no boosts)
        assert c.final_score > 0
        assert c.vibe_score == 0.0

    async def test_final_scores_are_all_positive(self):
        """All final scores should be positive (base is always >= 1.0)."""
        candidates = [
            _make_candidate(title=f"Item {i}", rec_type="gift", interest_score=0.0)
            for i in range(5)
        ]
        state = _make_state(filtered=candidates)
        result = await match_vibes_and_love_languages(state)
        for c in result["filtered_recommendations"]:
            assert c.final_score > 0, f"{c.title} should have positive final_score"
