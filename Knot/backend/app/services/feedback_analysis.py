"""
Feedback Analysis Service — Analyzes user feedback patterns to compute
preference weights for personalized recommendation scoring.

The weekly analysis job:
1. Fetches all users who have recommendation feedback
2. For each user, analyzes feedback patterns across vibes, interests,
   recommendation types, and love languages
3. Computes weight multipliers (centered at 1.0, clamped to [0.5, 2.0])
4. Upserts results into the user_preferences_weights table

Weight computation uses a damped averaging formula to prevent wild swings
from small sample sizes. Minimum 3 feedback entries are required before
weights deviate from the default 1.0.

Step 10.2: Create Feedback Analysis Job (Backend)
"""

import logging
import math
from datetime import datetime, timezone

from app.db.supabase_client import get_service_client
from app.models.feedback_analysis import UserPreferencesWeights

logger = logging.getLogger(__name__)

# Weight bounds — prevents extreme swings from limited data
MIN_WEIGHT = 0.5
MAX_WEIGHT = 2.0
DEFAULT_WEIGHT = 1.0

# Minimum feedback count before we start adjusting weights
MIN_FEEDBACK_FOR_ADJUSTMENT = 3

# ======================================================================
# Vibe keywords — replicated from matching.py for feedback analysis.
# These are used to determine which vibes a recommendation aligned with
# based on its title/description text.
# ======================================================================

VIBE_KEYWORDS: dict[str, list[str]] = {
    "quiet_luxury": [
        "luxury", "fine dining", "exclusive", "upscale",
        "boutique", "sommelier", "omakase", "artisan", "spa",
    ],
    "street_urban": [
        "street art", "urban", "underground", "food truck", "graffiti", "mural",
    ],
    "outdoorsy": [
        "outdoor", "kayak", "hiking", "climbing", "balloon",
        "nature", "trail",
    ],
    "vintage": [
        "vintage", "antique", "classic", "retro", "prohibition", "speakeasy",
    ],
    "minimalist": [
        "minimalist", "zen", "meditation", "tea ceremony", "mindfulness",
        "architecture",
    ],
    "bohemian": [
        "pottery", "indie", "tie-dye", "handmade", "craft", "workshop",
    ],
    "romantic": [
        "romantic", "candlelit", "sunset", "stargazing", "cruise", "couples",
    ],
    "adventurous": [
        "adventure", "skydiving", "rafting", "escape room", "extreme",
        "thrill", "white water",
    ],
}

# Love language keywords — replicated from matching.py for feedback analysis.
LOVE_LANGUAGE_KEYWORDS: dict[str, list[str]] = {
    "acts_of_service": [
        "tool", "kit", "repair", "practical", "organizer", "useful",
        "home", "cleaning", "service",
    ],
    "words_of_affirmation": [
        "personalized", "custom", "portrait", "engraved", "sentimental",
        "monogram", "letter", "journal", "poem", "song",
    ],
    "physical_touch": [
        "couples", "massage", "spa", "dance class",
        "together", "two people", "for two",
    ],
}


# ======================================================================
# Scoring helpers
# ======================================================================

def _clamp(value: float) -> float:
    """Clamp a weight value to [MIN_WEIGHT, MAX_WEIGHT]."""
    return max(MIN_WEIGHT, min(MAX_WEIGHT, value))


def _score_from_feedback(action: str, rating: int | None) -> float:
    """
    Convert a feedback action + rating into a numeric score.

    Returns a value in [-1.0, 1.0]:
      - rated 5:    +1.0
      - rated 4:    +0.5
      - rated 3:     0.0 (neutral)
      - rated 2:    -0.5
      - rated 1:    -1.0
      - purchased:  +0.5 (strong positive — user bought it)
      - selected:   +0.3 (mild positive — user chose it)
      - shared:     +0.3 (mild positive — user shared with partner)
      - saved:      +0.2 (mild positive — user bookmarked)
      - handoff:    +0.1 (weak positive — user visited merchant)
      - refreshed:  -0.5 (negative — user rejected the set)
    """
    if action == "rated" and rating is not None:
        # Maps 1 → -1.0, 2 → -0.5, 3 → 0.0, 4 → +0.5, 5 → +1.0
        return (rating - 3) / 2.0

    action_scores = {
        "purchased": 0.5,
        "selected": 0.3,
        "shared": 0.3,
        "saved": 0.2,
        "handoff": 0.1,
        "refreshed": -0.5,
    }
    return action_scores.get(action, 0.0)


def _compute_weight_from_scores(scores: list[float]) -> float:
    """
    Convert a list of feedback scores into a weight multiplier.

    The weight is centered at 1.0. Positive average scores push it above 1.0,
    negative averages push it below. The magnitude is dampened to prevent
    wild swings from small sample sizes.

    Formula: weight = 1.0 + (avg_score * damping_factor)
    Damping factor increases with sample size (more data = more confidence).
      n=1:   damping = 0.33
      n=4:   damping = 0.50
      n=9:   damping = 0.60
      n=25:  damping = 0.71
      n=100: damping = 0.83
    """
    if not scores:
        return DEFAULT_WEIGHT

    avg = sum(scores) / len(scores)
    n = len(scores)
    damping = math.sqrt(n) / (math.sqrt(n) + 2)

    weight = 1.0 + (avg * damping)
    return _clamp(weight)


# ======================================================================
# Vibe and content matching helpers
# ======================================================================

def _match_recommendation_vibes(
    title: str,
    description: str | None,
    vault_vibes: list[str],
) -> list[str]:
    """
    Determine which vault vibes a recommendation matches based on text.

    Uses keyword matching against the recommendation's title and description,
    scoped to the vault's active vibes. Only returns vibes that the vault
    has selected AND that match the recommendation's content.

    Args:
        title: The recommendation title.
        description: The recommendation description (may be None).
        vault_vibes: The partner's selected vibe tags.

    Returns:
        List of matched vibe tags (subset of vault_vibes).
    """
    text = title.lower().strip()
    if description:
        text += " " + description.lower().strip()

    matched = []
    for vibe in vault_vibes:
        vibe_lower = vibe.strip().lower()
        keywords = VIBE_KEYWORDS.get(vibe_lower, [])
        for keyword in keywords:
            if keyword in text:
                matched.append(vibe_lower)
                break

    return matched


def _match_recommendation_love_languages(
    title: str,
    description: str | None,
    recommendation_type: str,
) -> list[str]:
    """
    Determine which love languages a recommendation aligns with.

    Uses type-based mapping and keyword matching:
      - gift type → receiving_gifts
      - experience/date type → quality_time
      - Keyword matches for acts_of_service, words_of_affirmation, physical_touch

    Args:
        title: The recommendation title.
        description: The recommendation description (may be None).
        recommendation_type: One of "gift", "experience", "date".

    Returns:
        List of matched love language keys.
    """
    matched = []

    # Type-based mapping
    if recommendation_type == "gift":
        matched.append("receiving_gifts")
    elif recommendation_type in ("experience", "date"):
        matched.append("quality_time")

    # Keyword-based matching
    text = title.lower().strip()
    if description:
        text += " " + description.lower().strip()

    for ll, keywords in LOVE_LANGUAGE_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            matched.append(ll)

    return list(set(matched))


# ======================================================================
# Per-user analysis
# ======================================================================

async def analyze_user_feedback(user_id: str) -> UserPreferencesWeights | None:
    """
    Analyze feedback for a single user and compute preference weights.

    Steps:
    1. Load feedback joined with recommendations (to get recommendation_type)
    2. Load the vault's vibes and interests
    3. For each dimension (vibes, interests, types, love languages),
       group feedback scores and compute weight multipliers
    4. Return the computed weights (does NOT write to DB)

    Returns:
        UserPreferencesWeights if the user has sufficient feedback, None otherwise.
    """
    client = get_service_client()

    # 1. Load all feedback for this user
    feedback_result = (
        client.table("recommendation_feedback")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=False)
        .execute()
    )

    feedback_rows = feedback_result.data or []
    if not feedback_rows:
        logger.debug("No feedback found for user %s", user_id[:8])
        return None

    total_feedback = len(feedback_rows)
    if total_feedback < MIN_FEEDBACK_FOR_ADJUSTMENT:
        logger.info(
            "User %s has %d feedback entries (below minimum %d) — skipping",
            user_id[:8], total_feedback, MIN_FEEDBACK_FOR_ADJUSTMENT,
        )
        return None

    # 2. Load vault data (vibes and interests)
    vault_result = (
        client.table("partner_vaults")
        .select("id")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if not vault_result.data:
        logger.warning("No vault found for user %s — skipping analysis", user_id[:8])
        return None

    vault_id = vault_result.data[0]["id"]

    vibes_result = (
        client.table("partner_vibes")
        .select("vibe_tag")
        .eq("vault_id", vault_id)
        .execute()
    )
    vault_vibes = [v["vibe_tag"] for v in (vibes_result.data or [])]

    interests_result = (
        client.table("partner_interests")
        .select("interest_category, interest_type")
        .eq("vault_id", vault_id)
        .execute()
    )
    vault_likes = [
        i["interest_category"]
        for i in (interests_result.data or [])
        if i["interest_type"] == "like"
    ]

    # 3. Load recommendation details for each feedback entry
    rec_ids = list({fb["recommendation_id"] for fb in feedback_rows})
    recommendations_result = (
        client.table("recommendations")
        .select("id, recommendation_type, title, description")
        .in_("id", rec_ids)
        .execute()
    )
    rec_lookup: dict[str, dict] = {
        r["id"]: r for r in (recommendations_result.data or [])
    }

    # 4. Compute scores per dimension
    vibe_scores: dict[str, list[float]] = {}
    type_scores: dict[str, list[float]] = {}
    interest_scores: dict[str, list[float]] = {}
    love_language_scores: dict[str, list[float]] = {}

    for fb in feedback_rows:
        score = _score_from_feedback(fb["action"], fb.get("rating"))
        rec = rec_lookup.get(fb["recommendation_id"])
        if rec is None:
            continue

        rec_title = rec.get("title", "")
        rec_desc = rec.get("description")
        rec_type = rec.get("recommendation_type", "")

        # --- Vibe weights ---
        matched_vibes = _match_recommendation_vibes(
            rec_title, rec_desc, vault_vibes,
        )
        for vibe in matched_vibes:
            vibe_scores.setdefault(vibe, []).append(score)

        # If recommendation matched no vibes but user has vibes,
        # distribute a mild neutral signal to all vault vibes
        # (absence of match is informative too)
        if not matched_vibes and vault_vibes:
            for vibe in vault_vibes:
                vibe_lower = vibe.strip().lower()
                vibe_scores.setdefault(vibe_lower, []).append(score * 0.1)

        # --- Type weights ---
        if rec_type:
            type_scores.setdefault(rec_type, []).append(score)

        # --- Interest weights ---
        # Match recommendation content against the vault's liked interests
        text = rec_title.lower()
        if rec_desc:
            text += " " + rec_desc.lower()

        for interest in vault_likes:
            interest_lower = interest.lower()
            if interest_lower in text:
                interest_scores.setdefault(interest, []).append(score)

        # --- Love language weights ---
        matched_lls = _match_recommendation_love_languages(
            rec_title, rec_desc, rec_type,
        )
        for ll in matched_lls:
            love_language_scores.setdefault(ll, []).append(score)

    # 5. Compute weights from scores
    vibe_weights = {
        vibe: _compute_weight_from_scores(scores)
        for vibe, scores in vibe_scores.items()
    }

    type_weights = {
        rtype: _compute_weight_from_scores(scores)
        for rtype, scores in type_scores.items()
    }

    interest_weights = {
        interest: _compute_weight_from_scores(scores)
        for interest, scores in interest_scores.items()
    }

    love_language_weights_computed = {
        ll: _compute_weight_from_scores(scores)
        for ll, scores in love_language_scores.items()
    }

    logger.info(
        "Analyzed %d feedback entries for user %s: "
        "vibes=%s, types=%s, interests=%d categories, love_languages=%s",
        total_feedback, user_id[:8],
        {k: round(v, 3) for k, v in vibe_weights.items()},
        {k: round(v, 3) for k, v in type_weights.items()},
        len(interest_weights),
        {k: round(v, 3) for k, v in love_language_weights_computed.items()},
    )

    return UserPreferencesWeights(
        user_id=user_id,
        vibe_weights=vibe_weights,
        interest_weights=interest_weights,
        type_weights=type_weights,
        love_language_weights=love_language_weights_computed,
        feedback_count=total_feedback,
    )


# ======================================================================
# Database operations
# ======================================================================

async def upsert_user_weights(weights: UserPreferencesWeights) -> None:
    """
    Insert or update the user's preference weights in the database.

    Uses the Supabase service client (bypasses RLS). The user_id UNIQUE
    constraint enables conflict-based upsert — existing rows are updated,
    new rows are inserted.
    """
    client = get_service_client()

    row = {
        "user_id": weights.user_id,
        "vibe_weights": weights.vibe_weights,
        "interest_weights": weights.interest_weights,
        "type_weights": weights.type_weights,
        "love_language_weights": weights.love_language_weights,
        "feedback_count": weights.feedback_count,
        "last_analyzed_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        client.table("user_preferences_weights").upsert(
            row, on_conflict="user_id",
        ).execute()
        logger.info(
            "Upserted weights for user %s (feedback_count=%d)",
            weights.user_id[:8], weights.feedback_count,
        )
    except Exception as exc:
        logger.error(
            "Failed to upsert weights for user %s: %s",
            weights.user_id[:8], exc,
        )
        raise


# ======================================================================
# Main entry point
# ======================================================================

async def run_feedback_analysis(
    target_user_id: str | None = None,
) -> dict:
    """
    Run feedback analysis for all users (or a single user if specified).

    This is the main entry point called by the API endpoint.

    Args:
        target_user_id: If provided, only analyze this user (for testing).
                        If None, analyze all users with feedback.

    Returns:
        dict with 'users_analyzed' count, 'status', and 'message' strings.
    """
    client = get_service_client()

    # Determine which users to analyze
    if target_user_id:
        user_ids = [target_user_id]
    else:
        # Get distinct user_ids from recommendation_feedback
        feedback_result = (
            client.table("recommendation_feedback")
            .select("user_id")
            .execute()
        )
        if not feedback_result.data:
            return {
                "status": "no_feedback",
                "users_analyzed": 0,
                "message": "No feedback data found.",
            }

        user_ids = list({row["user_id"] for row in feedback_result.data})

    logger.info(
        "Starting feedback analysis for %d user(s)%s",
        len(user_ids),
        f" (target: {target_user_id[:8]}...)" if target_user_id else "",
    )

    users_analyzed = 0
    errors = 0

    for uid in user_ids:
        try:
            weights = await analyze_user_feedback(uid)
            if weights is not None:
                await upsert_user_weights(weights)
                users_analyzed += 1
        except Exception as exc:
            logger.error(
                "Error analyzing user %s: %s", uid[:8], exc, exc_info=True,
            )
            errors += 1

    status = "completed" if errors == 0 else "completed_with_errors"
    message = (
        f"Analyzed {users_analyzed} user(s) out of {len(user_ids)} with feedback."
    )
    if errors > 0:
        message += f" {errors} error(s) encountered."

    logger.info(
        "Feedback analysis complete: %s — %s", status, message,
    )

    return {
        "status": status,
        "users_analyzed": users_analyzed,
        "message": message,
    }
