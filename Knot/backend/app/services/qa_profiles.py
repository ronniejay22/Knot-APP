"""
Sample partner profiles for the Recommendation Quality cockpit and eval harness.

These are fixed, representative `VaultData` personas (varied vibes, love
languages, budgets, and cities) so recommendation quality can be QA'd and
eval'd reproducibly without touching real user data. The QA endpoint can also
load a real vault by user id via `load_vault_data`, but the sample set is the
default so runs are deterministic and comparable across model/config changes.

Step 20.1: Recommendation Quality Cockpit.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.agents.state import RelevantHint, VaultBudget, VaultData


def _standard_budgets() -> list[VaultBudget]:
    """The three budget tiers, using the app's default ranges (in cents)."""
    return [
        VaultBudget(occasion_type="just_because", min_amount=2000, max_amount=5000),
        VaultBudget(occasion_type="minor_occasion", min_amount=5000, max_amount=15000),
        VaultBudget(occasion_type="major_milestone", min_amount=10000, max_amount=50000),
    ]


@dataclass(frozen=True)
class QAProfile:
    """A sample profile: the vault data plus a few captured hints."""

    id: str
    headline: str  # short human description for the cockpit dropdown
    vault: VaultData
    hints: list[RelevantHint]


def _profile(
    id: str,
    headline: str,
    partner_name: str,
    city: str,
    state: str,
    interests: list[str],
    dislikes: list[str],
    vibes: list[str],
    primary_ll: str,
    secondary_ll: str,
    hints: list[str],
    cohabitation: str = "living_together",
    tenure_months: int = 30,
) -> QAProfile:
    return QAProfile(
        id=id,
        headline=headline,
        vault=VaultData(
            vault_id=f"qa-{id}",
            partner_name=partner_name,
            relationship_tenure_months=tenure_months,
            cohabitation_status=cohabitation,  # type: ignore[arg-type]
            location_city=city,
            location_state=state,
            interests=interests,
            dislikes=dislikes,
            vibes=vibes,
            primary_love_language=primary_ll,
            secondary_love_language=secondary_ll,
            budgets=_standard_budgets(),
        ),
        hints=[
            RelevantHint(id=f"qa-{id}-hint-{i}", hint_text=text, similarity_score=0.8)
            for i, text in enumerate(hints)
        ],
    )


_PROFILE_LIST: list[QAProfile] = [
    _profile(
        id="quiet-luxury-foodie",
        headline="Quiet-luxury foodie in NYC — quality time",
        partner_name="Alex",
        city="New York",
        state="NY",
        interests=["fine dining", "natural wine", "art galleries", "jazz", "travel"],
        dislikes=["crowds", "fast food", "camping", "horror movies", "loud bars"],
        vibes=["quiet_luxury", "minimalist"],
        primary_ll="quality_time",
        secondary_ll="receiving_gifts",
        hints=[
            "She keeps mentioning the natural wine bar that opened in the West Village.",
            "She loved the tasting menu on our anniversary and still talks about it.",
        ],
    ),
    _profile(
        id="outdoorsy-adventurer",
        headline="Outdoorsy adventurer in Denver — physical touch",
        partner_name="Sam",
        city="Denver",
        state="CO",
        interests=["hiking", "rock climbing", "craft beer", "cycling", "national parks"],
        dislikes=["shopping malls", "formal events", "seafood", "opera", "crowds"],
        vibes=["outdoorsy", "adventurous"],
        primary_ll="physical_touch",
        secondary_ll="quality_time",
        hints=[
            "He's been eyeing a new bouldering gym membership.",
            "He wants to do a fourteener this summer.",
        ],
    ),
    _profile(
        id="bohemian-creative",
        headline="Bohemian creative in Austin — words of affirmation",
        partner_name="Riley",
        city="Austin",
        state="TX",
        interests=["pottery", "live music", "vintage shopping", "vegan cooking", "indie films"],
        dislikes=["chain restaurants", "sports bars", "hunting", "EDM festivals", "fast fashion"],
        vibes=["bohemian", "vintage"],
        primary_ll="words_of_affirmation",
        secondary_ll="quality_time",
        hints=[
            "She's been wanting to take a wheel-throwing pottery class.",
            "She mentioned loving the vinyl selection at the record store on South Congress.",
        ],
    ),
    _profile(
        id="homebody-gamer",
        headline="Homebody gamer & reader in Seattle — acts of service",
        partner_name="Jordan",
        city="Seattle",
        state="WA",
        interests=["video games", "sci-fi novels", "specialty coffee", "board games", "anime"],
        dislikes=["nightclubs", "hiking", "very spicy food", "public speaking", "cold plunges"],
        vibes=["minimalist", "romantic"],
        primary_ll="acts_of_service",
        secondary_ll="quality_time",
        hints=[
            "He keeps saying he wants a better pour-over setup.",
            "He's been waiting for the next book in his favorite sci-fi series.",
        ],
    ),
    _profile(
        id="street-style-urbanite",
        headline="Street-style romantic in Miami — physical touch",
        partner_name="Devin",
        city="Miami",
        state="FL",
        interests=["dancing", "rooftop bars", "street art", "fashion", "the beach"],
        dislikes=["hiking", "museums", "country music", "board games", "cooking at home"],
        vibes=["street_urban", "romantic"],
        primary_ll="physical_touch",
        secondary_ll="receiving_gifts",
        hints=[
            "She's been talking about the new rooftop lounge in Wynwood.",
            "She loves salsa dancing but we haven't been in months.",
        ],
    ),
    _profile(
        id="long-distance-minimalist",
        headline="Long-distance minimalist in Chicago — words of affirmation",
        partner_name="Casey",
        city="Chicago",
        state="IL",
        interests=["photography", "specialty coffee", "architecture", "running", "podcasts"],
        dislikes=["clubbing", "gambling", "reality TV", "fast food", "big crowds"],
        vibes=["minimalist", "quiet_luxury"],
        primary_ll="words_of_affirmation",
        secondary_ll="acts_of_service",
        hints=[
            "She mentioned wanting a print of the skyline photo she took.",
            "She's been running along the lakefront most mornings.",
        ],
        cohabitation="long_distance",
        tenure_months=18,
    ),
]

SAMPLE_PROFILES: dict[str, QAProfile] = {p.id: p for p in _PROFILE_LIST}


def list_sample_profiles() -> list[dict[str, str]]:
    """Return lightweight summaries for the QA cockpit dropdown."""
    return [
        {
            "id": p.id,
            "headline": p.headline,
            "partner_name": p.vault.partner_name,
            "city": p.vault.location_city or "",
        }
        for p in _PROFILE_LIST
    ]


def get_sample_profile(profile_id: str) -> QAProfile | None:
    """Look up a sample profile by id, or None if unknown."""
    return SAMPLE_PROFILES.get(profile_id)
