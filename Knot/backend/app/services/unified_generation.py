"""
Unified Recommendation Generation Service — Claude-powered personalized recommendations.

Makes a single Claude call to generate all 3 recommendations as a mix of
purchasable items (gifts, bookable experiences, restaurant reservations) and
personalized ideas/gestures. Claude decides the optimal mix based on the
partner's profile, occasion, and what would genuinely delight them.

Every recommendation includes a personalization_note explaining WHY it fits
this specific partner, referencing their interests, hints, vibes, and love
languages.

Step 15.1: Unified AI Recommendation System
"""

import json
import logging
import uuid
from typing import Any, Optional

from anthropic import AsyncAnthropic

from app.agents.state import (
    BudgetRange,
    CandidateRecommendation,
    LocationData,
    MilestoneContext,
    RelevantHint,
    VaultData,
)
from app.core.config import ANTHROPIC_API_KEY, is_anthropic_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

CLAUDE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_MAX_TOKENS = 4096
MAX_RETRIES = 2

# Valid content section types (same as idea_generation.py)
VALID_SECTION_TYPES = {
    "overview", "setup", "steps", "tips", "conversation",
    "budget_tips", "variations", "music", "food_pairing",
}

REQUIRED_IDEA_SECTIONS = {"overview", "steps"}

# Occasion-aware generation guidance
OCCASION_GUIDANCE: dict[str, str] = {
    "just_because": (
        "Mix creative, low-cost personalized ideas with affordable but thoughtful "
        "purchasable items ($20-$50). Prioritize gestures that show you were paying attention."
    ),
    "minor_occasion": (
        "Balance between meaningful experiences and curated gifts ($50-$150). "
        "Ideas should feel special but not over-the-top."
    ),
    "major_milestone": (
        "Go big. Premium gifts, memorable experiences, or elaborate gestures. "
        "This is the time for wow-factor items and once-in-a-lifetime ideas."
    ),
}


# ======================================================================
# System prompt
# ======================================================================

UNIFIED_SYSTEM_PROMPT = """\
You are Knot, an AI relationship advisor that generates deeply personalized \
recommendations for someone's partner. You create a curated mix of real \
purchasable items AND creative personalized ideas.

You will receive detailed information about a partner including their \
interests, dislikes, aesthetic vibes, love languages, budget, location, \
and personal hints their partner has captured about them.

Generate exactly 3 recommendations. You decide the ideal MIX:
- PURCHASABLE items: Real products you can buy, restaurants you can book, \
experiences with tickets (concerts, spa, classes). These MUST be specific \
real things (name the actual product, restaurant, or venue).
- IDEAS: Creative personalized gestures, at-home activities, or date concepts \
that don't require purchasing a specific product. These live entirely in-app.

Rules:
1. Every recommendation MUST feel specifically crafted for THIS partner. \
Reference their actual interests, hints, and preferences.
2. NEVER recommend anything related to their dislikes.
3. NEVER repeat anything from the excluded list.
4. Ensure DIVERSITY across the 3 cards — vary the type (gift/experience/date/idea), \
price range, and nature of the recommendation.
5. For purchasable items: Name a SPECIFIC real product, restaurant, or experience. \
Include the actual merchant/brand name and a realistic price estimate. \
Provide a search_query that would find this exact item online for purchase/booking.
6. For ideas: Include rich structured content with steps, tips, and personalization.
7. Only link to things people can actually BUY or BOOK. No articles, blog posts, \
listicles, or review roundups.

For each recommendation, return a JSON object with these keys:
- "title": string (under 60 characters)
- "description": string (1-2 sentences)
- "recommendation_type": "gift" | "experience" | "date" | "idea"
- "is_purchasable": boolean (true for gifts/experiences/dates, false for ideas)
- "merchant_name": string or null (for purchasable items)
- "price_cents": integer or null (in US cents, e.g. $50 = 5000; null for ideas)
- "search_query": string or null (for purchasable items: a specific search query \
to find this product/experience for purchase online. Include brand, product name, etc.)
- "personalization_note": string (1-2 sentences explaining WHY this is perfect \
for this specific partner, referencing their actual interests/hints/vibes)
- "matched_interests": array of interest names this connects to
- "matched_vibes": array of vibe tags this aligns with
- "matched_love_languages": array of love language names this supports
- "content_sections": array of section objects (REQUIRED for ideas, optional for purchasable)

Content section format (for ideas):
Each section is a JSON object with:
- "type": "overview" | "steps" | "setup" | "tips" | "conversation" | \
"budget_tips" | "variations" | "music" | "food_pairing"
- "heading": short descriptive heading (2-5 words)
- "body": paragraph text (for overview, tips, budget_tips, music, food_pairing)
- "items": array of strings (for setup, steps, conversation, variations)
Use either "body" or "items" per section, not both.
Ideas MUST include "overview" and "steps" sections at minimum.

Return ONLY a JSON array of 3 objects. No markdown, no code fences, no explanation."""


# ======================================================================
# User prompt construction
# ======================================================================

def _build_user_prompt(
    vault_data: VaultData,
    hints: list[RelevantHint],
    occasion_type: str,
    budget_range: BudgetRange,
    milestone_context: Optional[MilestoneContext] = None,
    excluded_titles: list[str] | None = None,
    excluded_descriptions: list[str] | None = None,
    vibe_override: list[str] | None = None,
    rejection_reason: Optional[str] = None,
) -> str:
    """Build the user prompt with all personalization data and exclusion context."""
    parts: list[str] = []

    parts.append("Generate exactly 3 unique, personalized recommendations.\n")

    # Partner profile
    parts.append("=== PARTNER PROFILE ===")
    parts.append(f"Partner name: {vault_data.partner_name}")

    if vault_data.location_city:
        location_parts = [p for p in (vault_data.location_city, vault_data.location_state) if p]
        parts.append(f"Location: {', '.join(location_parts)}")

    parts.append(f"Interests (LOVES): {', '.join(vault_data.interests)}")
    parts.append(f"Dislikes (HARD AVOID): {', '.join(vault_data.dislikes)}")

    # Use vibe override if provided, otherwise vault vibes
    active_vibes = vibe_override if vibe_override else vault_data.vibes
    parts.append(f"Aesthetic vibes: {', '.join(active_vibes)}")

    parts.append(f"Primary love language: {vault_data.primary_love_language}")
    parts.append(f"Secondary love language: {vault_data.secondary_love_language}")

    if vault_data.cohabitation_status:
        parts.append(f"Living situation: {vault_data.cohabitation_status}")
    if vault_data.relationship_tenure_months:
        years = vault_data.relationship_tenure_months // 12
        months = vault_data.relationship_tenure_months % 12
        tenure_str = f"{years} year(s), {months} month(s)" if years else f"{months} month(s)"
        parts.append(f"Together for: {tenure_str}")

    # Budget
    budget_min = budget_range.min_amount / 100
    budget_max = budget_range.max_amount / 100
    parts.append(f"\n=== BUDGET ===")
    parts.append(f"Range: ${budget_min:.0f} - ${budget_max:.0f} {budget_range.currency}")
    parts.append("Purchasable items should fall within this budget range.")
    parts.append("Ideas can be free or low-cost — no budget constraint for ideas.")

    # Hints
    if hints:
        parts.append("\n=== RECENT HINTS (things the user noticed about their partner) ===")
        for hint in hints[:10]:
            parts.append(f'- "{hint.hint_text}"')

    # Occasion + milestone context
    parts.append(f"\n=== OCCASION ===")
    parts.append(f"Type: {occasion_type}")
    guidance = OCCASION_GUIDANCE.get(occasion_type, "")
    if guidance:
        parts.append(f"Guidance: {guidance}")

    if milestone_context:
        parts.append(f"Milestone: {milestone_context.milestone_name} ({milestone_context.milestone_type})")
        if milestone_context.days_until is not None:
            parts.append(f"Days until: {milestone_context.days_until}")

    # Rejection reason context (for refresh)
    if rejection_reason:
        reason_guidance = {
            "too_expensive": "Previous recommendations were too expensive. Favor LOWER price options this time.",
            "too_cheap": "Previous recommendations were too cheap. Favor HIGHER-END options this time.",
            "not_their_style": "Previous recommendations didn't match their style. Try a DIFFERENT aesthetic approach.",
            "already_have_similar": "They already have something similar. Recommend COMPLETELY DIFFERENT categories.",
            "show_different": "Just show different options. Vary the type and approach from what was shown before.",
        }
        parts.append(f"\n=== REFRESH CONTEXT ===")
        parts.append(reason_guidance.get(rejection_reason, "Show different options."))

    # Exclusion list — critical for preventing repeats
    excluded_titles = excluded_titles or []
    excluded_descriptions = excluded_descriptions or []
    if excluded_titles:
        parts.append(f"\n=== DO NOT RECOMMEND (previously shown — user wants fresh ideas) ===")
        for i, title in enumerate(excluded_titles[:50]):
            desc = excluded_descriptions[i] if i < len(excluded_descriptions) else ""
            if desc:
                parts.append(f"- {title}: {desc}")
            else:
                parts.append(f"- {title}")

    # Final instructions
    parts.append(
        "\nIMPORTANT: Every recommendation must feel specifically crafted for this couple. "
        "Reference their interests, vibes, hints, and love languages directly. "
        "Avoid generic suggestions that could apply to anyone. "
        "NEVER suggest anything related to their dislikes. "
        "NEVER repeat anything from the exclusion list above."
    )

    return "\n".join(parts)


# ======================================================================
# Response validation
# ======================================================================

def _validate_recommendation(rec: dict[str, Any]) -> bool:
    """Validate a single recommendation dict has required fields."""
    if not isinstance(rec, dict):
        return False

    required_keys = {"title", "description", "recommendation_type", "personalization_note"}
    if not required_keys.issubset(rec.keys()):
        return False

    rec_type = rec.get("recommendation_type")
    if rec_type not in ("gift", "experience", "date", "idea"):
        return False

    # Ideas must have content_sections with overview + steps
    if rec_type == "idea":
        sections = rec.get("content_sections")
        if not isinstance(sections, list):
            return False
        section_types = {s.get("type") for s in sections if isinstance(s, dict)}
        if not REQUIRED_IDEA_SECTIONS.issubset(section_types):
            return False

    return True


def _normalize_recommendation(
    rec: dict[str, Any],
    vault_data: VaultData,
) -> CandidateRecommendation:
    """Convert a validated recommendation dict into a CandidateRecommendation."""
    rec_type = rec["recommendation_type"]
    is_idea = rec_type == "idea"
    is_purchasable = rec.get("is_purchasable", not is_idea)

    # Clean content sections for ideas
    content_sections = None
    if rec.get("content_sections"):
        clean_sections = []
        for section in rec["content_sections"]:
            if not isinstance(section, dict):
                continue
            section_type = section.get("type", "")
            if section_type not in VALID_SECTION_TYPES:
                continue
            clean_section: dict[str, Any] = {
                "type": section_type,
                "heading": section.get("heading", section_type.replace("_", " ").title()),
            }
            if section.get("body"):
                clean_section["body"] = str(section["body"])[:2000]
            if section.get("items") and isinstance(section["items"], list):
                clean_section["items"] = [str(item)[:500] for item in section["items"][:20]]
            clean_sections.append(clean_section)
        content_sections = clean_sections if clean_sections else None

    # Build location data for experiences/dates
    location = None
    if rec_type in ("experience", "date") and vault_data.location_city:
        location = LocationData(
            city=vault_data.location_city,
            state=vault_data.location_state,
            country=vault_data.location_country,
        )

    return CandidateRecommendation(
        id=str(uuid.uuid4()),
        source="unified",
        type=rec_type,
        title=str(rec["title"])[:100],
        description=str(rec.get("description", ""))[:500],
        price_cents=rec.get("price_cents") if is_purchasable else None,
        currency=vault_data.budgets[0].currency if vault_data.budgets else "USD",
        price_confidence="estimated" if rec.get("price_cents") and is_purchasable else "unknown",
        external_url=None,  # Resolved later by resolve_purchase_urls
        image_url=None,
        merchant_name=rec.get("merchant_name") if is_purchasable else None,
        location=location,
        metadata={"generation_model": CLAUDE_MODEL},
        is_idea=is_idea,
        content_sections=content_sections,
        personalization_note=str(rec.get("personalization_note", ""))[:300],
        search_query=rec.get("search_query") if is_purchasable else None,
        matched_interests=rec.get("matched_interests", []),
        matched_vibes=rec.get("matched_vibes", []),
        matched_love_languages=rec.get("matched_love_languages", []),
    )


# ======================================================================
# Main generation function
# ======================================================================

async def generate_unified_recommendations(
    vault_data: VaultData,
    hints: list[RelevantHint],
    occasion_type: str,
    budget_range: BudgetRange,
    milestone_context: Optional[MilestoneContext] = None,
    excluded_titles: list[str] | None = None,
    excluded_descriptions: list[str] | None = None,
    vibe_override: list[str] | None = None,
    rejection_reason: Optional[str] = None,
) -> list[CandidateRecommendation]:
    """
    Generate 3 personalized recommendations using Claude.

    Claude generates a mix of purchasable items and ideas, each with a
    personalization_note explaining why it fits the partner. Purchasable
    items include a search_query for URL resolution in a later pipeline step.

    Args:
        vault_data: The partner's full vault profile data.
        hints: Relevant hints from pgvector semantic search.
        occasion_type: Budget tier context.
        budget_range: Min/max budget in cents.
        milestone_context: Optional milestone being planned for.
        excluded_titles: Previously shown recommendation titles to avoid.
        excluded_descriptions: Previously shown description snippets.
        vibe_override: Optional session-scoped vibe override.
        rejection_reason: Optional reason from refresh (adjusts generation).

    Returns:
        A list of 3 CandidateRecommendation objects (or fewer on error).
        Returns empty list if Claude is not configured or generation fails.
    """
    if not is_anthropic_configured():
        logger.warning("Anthropic API key not configured — skipping unified generation")
        return []

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
    user_prompt = _build_user_prompt(
        vault_data=vault_data,
        hints=hints,
        occasion_type=occasion_type,
        budget_range=budget_range,
        milestone_context=milestone_context,
        excluded_titles=excluded_titles,
        excluded_descriptions=excluded_descriptions,
        vibe_override=vibe_override,
        rejection_reason=rejection_reason,
    )

    logger.info(
        "Generating unified recommendations for vault %s (occasion: %s, excluded: %d)",
        vault_data.vault_id, occasion_type, len(excluded_titles or []),
    )

    for attempt in range(MAX_RETRIES + 1):
        try:
            response = await client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=CLAUDE_MAX_TOKENS,
                system=UNIFIED_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_prompt}],
            )

            text = response.content[0].text.strip()

            # Strip markdown code fences if Claude added them
            if text.startswith("```"):
                text = text.split("\n", 1)[1] if "\n" in text else text[3:]
            if text.endswith("```"):
                text = text[:-3].strip()
            if text.startswith("json"):
                text = text[4:].strip()

            recommendations = json.loads(text)

            if not isinstance(recommendations, list):
                logger.warning(
                    "Claude returned non-list response (attempt %d/%d)",
                    attempt + 1, MAX_RETRIES + 1,
                )
                continue

            # Validate and normalize each recommendation
            valid_recs: list[CandidateRecommendation] = []
            for raw_rec in recommendations:
                if _validate_recommendation(raw_rec):
                    candidate = _normalize_recommendation(raw_rec, vault_data)
                    valid_recs.append(candidate)
                else:
                    logger.debug(
                        "Skipping invalid recommendation: %s",
                        raw_rec.get("title", "?"),
                    )

            if valid_recs:
                logger.info(
                    "Generated %d valid recommendations for vault %s: %s",
                    len(valid_recs), vault_data.vault_id,
                    [r.title for r in valid_recs],
                )
                return valid_recs[:3]

            logger.warning(
                "No valid recommendations in Claude response (attempt %d/%d)",
                attempt + 1, MAX_RETRIES + 1,
            )

        except json.JSONDecodeError as exc:
            logger.error(
                "Claude returned invalid JSON (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )
        except Exception as exc:
            logger.error(
                "Unified generation failed (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )

    logger.error(
        "Unified generation exhausted all retries for vault %s",
        vault_data.vault_id,
    )
    return []
