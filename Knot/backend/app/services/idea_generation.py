"""
Idea Generation Service — Claude-powered AI idea generation for Knot Originals.

Generates rich, personalized recommendation ideas using the partner's vault data
(interests, vibes, love languages) and captured hints. Each idea includes
structured content sections (overview, steps, tips, conversation starters, etc.)
that live entirely in-app with no external links.

Step 14.3: Create Idea Generation Service
"""

import json
import logging
import uuid
from typing import Any, Optional

from anthropic import AsyncAnthropic

from app.agents.state import RelevantHint, VaultData
from app.core.config import ANTHROPIC_API_KEY, is_anthropic_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

CLAUDE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_MAX_TOKENS = 4096
MAX_RETRIES = 2

# Valid content section types
VALID_SECTION_TYPES = {
    "overview", "setup", "steps", "tips", "conversation",
    "budget_tips", "variations", "music", "food_pairing",
}

# Required sections — every idea must have at least these
REQUIRED_SECTION_TYPES = {"overview", "steps"}

# Occasion-aware generation guidance
OCCASION_GUIDANCE: dict[str, str] = {
    "just_because": (
        "Ideas should be low-cost or free. Focus on creativity and thoughtfulness "
        "over spending. At-home activities, handmade gestures, and spontaneous fun."
    ),
    "minor_occasion": (
        "Ideas can involve moderate effort or a small budget ($20-$50). "
        "Think fun outings, themed evenings, or meaningful gestures."
    ),
    "major_milestone": (
        "Ideas can be elaborate and involved. Think multi-step experiences, "
        "weekend plans, or deeply personalized creations worth the effort."
    ),
}


# ======================================================================
# System prompt
# ======================================================================

IDEA_SYSTEM_PROMPT = """\
You are Knot, an AI relationship advisor that creates deeply personalized \
activity ideas, creative gestures, and date concepts for couples.

You will receive detailed information about a partner including their \
interests, aesthetic vibes, love languages, and personal hints. Use ALL \
of this data to create ideas that feel tailor-made for this specific couple.

For each idea, generate:
1. A compelling title (under 60 characters)
2. A 1-2 sentence description that captures the essence
3. Multiple content sections with structured data

REQUIRED sections for every idea:
- "overview": A paragraph describing the idea and why it's perfect for this couple. \
Reference specific interests or preferences to show personalization.
- "steps": Step-by-step guide (3-8 items) to plan and execute the idea.

INCLUDE these sections when relevant:
- "setup": List of items, ingredients, or preparation needed.
- "tips": Personalized tips that reference the partner's specific interests or preferences.
- "conversation": 3-5 fun conversation starters related to the activity.
- "budget_tips": How to do this affordably or for free.
- "variations": Alternative versions (rainy day backup, at-home version, upgraded version).
- "music": Suggested playlist genre or specific search terms.
- "food_pairing": Suggested snacks, drinks, or meals to pair with the activity.

Each section must be a JSON object with:
- "type": one of the valid section types listed above
- "heading": a short descriptive heading (2-5 words)
- "body": a paragraph of text (for overview, tips, budget_tips, music, food_pairing)
- "items": an array of strings (for setup, steps, conversation, variations)

Use either "body" or "items" per section, not both.

Return ONLY a JSON array of idea objects. No markdown, no code fences, no explanation.

Each idea object must have exactly these keys:
- "title": string
- "description": string
- "content_sections": array of section objects
- "matched_interests": array of interest names this idea connects to
- "matched_vibes": array of vibe tags this idea aligns with
- "matched_love_languages": array of love language names this idea supports"""


# ======================================================================
# User prompt construction
# ======================================================================

def _build_user_prompt(
    vault_data: VaultData,
    hints: list[RelevantHint],
    occasion_type: str,
    count: int,
    category: Optional[str] = None,
) -> str:
    """
    Build the user prompt with all personalization data.

    Incorporates partner profile, hints, and occasion context
    to guide Claude toward highly personalized ideas.
    """
    parts: list[str] = []

    parts.append(f"Generate exactly {count} unique, personalized idea(s).\n")

    # Partner profile
    parts.append("=== PARTNER PROFILE ===")
    parts.append(f"Partner name: {vault_data.partner_name}")

    if vault_data.location_city:
        location_parts = [p for p in (vault_data.location_city, vault_data.location_state) if p]
        parts.append(f"Location: {', '.join(location_parts)}")

    parts.append(f"Interests (LOVES): {', '.join(vault_data.interests)}")
    parts.append(f"Dislikes (AVOID): {', '.join(vault_data.dislikes)}")
    parts.append(f"Aesthetic vibes: {', '.join(vault_data.vibes)}")
    parts.append(f"Primary love language: {vault_data.primary_love_language}")
    parts.append(f"Secondary love language: {vault_data.secondary_love_language}")

    if vault_data.cohabitation_status:
        parts.append(f"Living situation: {vault_data.cohabitation_status}")
    if vault_data.relationship_tenure_months:
        years = vault_data.relationship_tenure_months // 12
        months = vault_data.relationship_tenure_months % 12
        tenure_str = f"{years} year(s), {months} month(s)" if years else f"{months} month(s)"
        parts.append(f"Together for: {tenure_str}")

    # Hints
    if hints:
        parts.append("\n=== RECENT HINTS (things the user noticed about their partner) ===")
        for hint in hints[:5]:
            parts.append(f"- \"{hint.hint_text}\"")

    # Occasion context
    parts.append(f"\n=== OCCASION ===")
    parts.append(f"Type: {occasion_type}")
    guidance = OCCASION_GUIDANCE.get(occasion_type, "")
    if guidance:
        parts.append(f"Guidance: {guidance}")

    # Category filter
    if category:
        parts.append(f"\nFocus on this category: {category}")

    # Final instructions
    parts.append(
        "\nIMPORTANT: Every idea must feel specifically crafted for this couple. "
        "Reference their interests, vibes, and love languages directly. "
        "Avoid generic suggestions that could apply to anyone. "
        "NEVER suggest anything related to their dislikes."
    )

    return "\n".join(parts)


# ======================================================================
# Response validation
# ======================================================================

def _validate_idea(idea: dict[str, Any]) -> bool:
    """Validate a single idea dict has required fields and sections."""
    if not isinstance(idea, dict):
        return False

    required_keys = {"title", "description", "content_sections"}
    if not required_keys.issubset(idea.keys()):
        return False

    if not isinstance(idea["content_sections"], list):
        return False

    # Check required section types are present
    section_types = {s.get("type") for s in idea["content_sections"] if isinstance(s, dict)}
    if not REQUIRED_SECTION_TYPES.issubset(section_types):
        return False

    return True


def _normalize_idea(idea: dict[str, Any]) -> dict[str, Any]:
    """Normalize and clean up a validated idea dict."""
    # Ensure matched factors are lists
    idea.setdefault("matched_interests", [])
    idea.setdefault("matched_vibes", [])
    idea.setdefault("matched_love_languages", [])

    # Filter sections to only valid types and clean up
    clean_sections = []
    for section in idea.get("content_sections", []):
        if not isinstance(section, dict):
            continue
        section_type = section.get("type", "")
        if section_type not in VALID_SECTION_TYPES:
            continue
        clean_section = {
            "type": section_type,
            "heading": section.get("heading", section_type.replace("_", " ").title()),
        }
        if section.get("body"):
            clean_section["body"] = str(section["body"])[:2000]
        if section.get("items") and isinstance(section["items"], list):
            clean_section["items"] = [str(item)[:500] for item in section["items"][:20]]
        clean_sections.append(clean_section)

    idea["content_sections"] = clean_sections

    # Truncate title and description
    idea["title"] = str(idea["title"])[:100]
    idea["description"] = str(idea.get("description", ""))[:500]

    return idea


# ======================================================================
# Main generation function
# ======================================================================

async def generate_ideas(
    vault_data: VaultData,
    hints: list[RelevantHint],
    occasion_type: str = "just_because",
    count: int = 3,
    category: Optional[str] = None,
) -> list[dict[str, Any]]:
    """
    Generate personalized Knot Original ideas using Claude.

    Args:
        vault_data: The partner's full vault profile data.
        hints: Relevant hints from pgvector semantic search.
        occasion_type: Budget tier context ("just_because", "minor_occasion", "major_milestone").
        count: Number of ideas to generate (1-10).
        category: Optional category filter (e.g., "activity", "gesture", "challenge").

    Returns:
        A list of validated idea dicts, each containing:
        - id: generated UUID
        - title: str
        - description: str
        - content_sections: list[dict]
        - matched_interests: list[str]
        - matched_vibes: list[str]
        - matched_love_languages: list[str]

        Returns empty list if Claude is not configured or generation fails.
    """
    if not is_anthropic_configured():
        logger.warning("Anthropic API key not configured — skipping idea generation")
        return []

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
    user_prompt = _build_user_prompt(vault_data, hints, occasion_type, count, category)

    logger.info(
        "Generating %d ideas for vault %s (occasion: %s, category: %s)",
        count, vault_data.vault_id, occasion_type, category,
    )

    for attempt in range(MAX_RETRIES + 1):
        try:
            response = await client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=CLAUDE_MAX_TOKENS,
                system=IDEA_SYSTEM_PROMPT,
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

            ideas = json.loads(text)

            if not isinstance(ideas, list):
                logger.warning(
                    "Claude returned non-list response (attempt %d/%d)",
                    attempt + 1, MAX_RETRIES + 1,
                )
                continue

            # Validate and normalize each idea
            valid_ideas = []
            for raw_idea in ideas:
                if _validate_idea(raw_idea):
                    idea = _normalize_idea(raw_idea)
                    idea["id"] = str(uuid.uuid4())
                    valid_ideas.append(idea)
                else:
                    logger.debug("Skipping invalid idea: %s", raw_idea.get("title", "?"))

            if valid_ideas:
                logger.info(
                    "Generated %d valid ideas (requested %d) for vault %s",
                    len(valid_ideas), count, vault_data.vault_id,
                )
                return valid_ideas[:count]

            logger.warning(
                "No valid ideas in Claude response (attempt %d/%d)",
                attempt + 1, MAX_RETRIES + 1,
            )

        except json.JSONDecodeError as exc:
            logger.error(
                "Claude returned invalid JSON (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )
        except Exception as exc:
            logger.error(
                "Idea generation failed (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )

    logger.error("Idea generation exhausted all retries for vault %s", vault_data.vault_id)
    return []
