"""
Milestone Briefing Generation Service — Claude-powered contextual narratives.

Generates a conversational 2-4 sentence briefing that synthesizes the partner's
hints, interests, vibes, and love languages into a personalized "friend-like"
suggestion for an upcoming milestone.

The briefing accompanies the 3 recommendation cards, providing narrative context
that explains why these recommendations were chosen and how they connect to what
the user has observed about their partner.

Also produces a condensed snippet (<100 chars) for push notification bodies.
"""

import json
import logging
from typing import Optional

from pydantic import BaseModel

from anthropic import AsyncAnthropic

from app.agents.state import MilestoneContext, RelevantHint, VaultData
from app.core.config import ANTHROPIC_API_KEY, is_anthropic_configured

logger = logging.getLogger(__name__)

CLAUDE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_MAX_TOKENS = 512
MAX_RETRIES = 1


# ======================================================================
# Result model
# ======================================================================

class BriefingResult(BaseModel):
    """Output from the briefing generation service."""

    briefing_text: str
    briefing_snippet: str
    hint_ids_referenced: list[str]


# ======================================================================
# System prompt
# ======================================================================

BRIEFING_SYSTEM_PROMPT = """\
You are Knot, a warm and perceptive relationship advisor. You write like \
a thoughtful friend who knows the couple well — conversational, specific, \
and genuinely helpful.

You will receive information about a partner (their interests, vibes, love \
languages) along with personal hints their partner has captured about them, \
and details about an upcoming milestone.

Your job is to write a SHORT contextual briefing (2-4 sentences) that:
1. Acknowledges the upcoming milestone naturally (don't just state "X's birthday is in Y days")
2. References 1-2 specific hints by paraphrasing them naturally into the narrative
3. Suggests a thematic direction that weaves together hints + interests + vibes
4. Feels like advice from a friend, not a product listing or AI assistant
5. Uses second person ("you", "your partner")

Also produce a condensed version (under 100 characters) suitable for a push \
notification body. This snippet should be intriguing and personal enough to \
make the user want to open the app.

Return ONLY a JSON object with these keys:
- "briefing_text": string (2-4 sentences, the full briefing)
- "briefing_snippet": string (under 100 characters, for push notification)
- "hint_ids_referenced": array of hint ID strings that you referenced

Do NOT include markdown, code fences, or explanation."""


# ======================================================================
# Prompt construction
# ======================================================================

def _build_briefing_prompt(
    vault_data: VaultData,
    hints: list[RelevantHint],
    milestone_context: MilestoneContext,
) -> str:
    """Build the user prompt for briefing generation."""
    parts: list[str] = []

    parts.append(f"=== UPCOMING MILESTONE ===")
    parts.append(f"Milestone: {milestone_context.milestone_name} ({milestone_context.milestone_type})")
    if milestone_context.days_until is not None:
        parts.append(f"Days until: {milestone_context.days_until}")

    parts.append(f"\n=== PARTNER PROFILE ===")
    parts.append(f"Partner name: {vault_data.partner_name}")
    parts.append(f"Interests: {', '.join(vault_data.interests)}")
    parts.append(f"Vibes: {', '.join(vault_data.vibes)}")
    parts.append(f"Primary love language: {vault_data.primary_love_language}")
    parts.append(f"Secondary love language: {vault_data.secondary_love_language}")

    if vault_data.relationship_tenure_months:
        years = vault_data.relationship_tenure_months // 12
        months = vault_data.relationship_tenure_months % 12
        tenure_str = f"{years} year(s), {months} month(s)" if years else f"{months} month(s)"
        parts.append(f"Together for: {tenure_str}")

    if hints:
        parts.append(f"\n=== CAPTURED HINTS (things noticed about the partner) ===")
        for hint in hints[:10]:
            parts.append(f'- [id: {hint.id}] "{hint.hint_text}"')

    parts.append(
        "\nWrite a warm, specific briefing that references at least one hint "
        "and connects it to the milestone. Be conversational, not formulaic."
    )

    return "\n".join(parts)


# ======================================================================
# Main generation function
# ======================================================================

async def generate_milestone_briefing(
    vault_data: VaultData,
    hints: list[RelevantHint],
    milestone_context: MilestoneContext,
) -> Optional[BriefingResult]:
    """
    Generate a contextual milestone briefing using Claude.

    Returns a BriefingResult with the full briefing text, a condensed snippet
    for push notifications, and the IDs of hints that were referenced.

    Returns None if generation fails or Claude is not configured.
    """
    if not is_anthropic_configured():
        logger.warning("Anthropic API key not configured — skipping briefing generation")
        return None

    if not milestone_context:
        logger.debug("No milestone context — skipping briefing generation")
        return None

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
    user_prompt = _build_briefing_prompt(vault_data, hints, milestone_context)

    logger.info(
        "Generating milestone briefing for vault %s (milestone: %s, %d hints)",
        vault_data.vault_id,
        milestone_context.milestone_name,
        len(hints),
    )

    for attempt in range(MAX_RETRIES + 1):
        try:
            response = await client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=CLAUDE_MAX_TOKENS,
                system=BRIEFING_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user_prompt}],
            )

            text = response.content[0].text.strip()

            # Strip markdown code fences if added
            if text.startswith("```"):
                text = text.split("\n", 1)[1] if "\n" in text else text[3:]
            if text.endswith("```"):
                text = text[:-3].strip()
            if text.startswith("json"):
                text = text[4:].strip()

            result = json.loads(text)

            if not isinstance(result, dict):
                logger.warning(
                    "Briefing generation returned non-dict (attempt %d/%d)",
                    attempt + 1, MAX_RETRIES + 1,
                )
                continue

            briefing_text = result.get("briefing_text", "").strip()
            briefing_snippet = result.get("briefing_snippet", "").strip()
            hint_ids = result.get("hint_ids_referenced", [])

            if not briefing_text:
                logger.warning("Empty briefing_text (attempt %d/%d)", attempt + 1, MAX_RETRIES + 1)
                continue

            # Truncate snippet if needed
            if len(briefing_snippet) > 100:
                briefing_snippet = briefing_snippet[:97] + "..."

            # Fall back to truncated briefing_text if snippet missing
            if not briefing_snippet:
                briefing_snippet = briefing_text[:97] + "..." if len(briefing_text) > 100 else briefing_text

            # Validate hint IDs — only keep ones that match provided hints
            valid_hint_ids = {h.id for h in hints}
            hint_ids = [hid for hid in hint_ids if hid in valid_hint_ids]

            logger.info(
                "Generated briefing for vault %s: snippet=%r, hints_referenced=%d",
                vault_data.vault_id,
                briefing_snippet[:50],
                len(hint_ids),
            )

            return BriefingResult(
                briefing_text=briefing_text,
                briefing_snippet=briefing_snippet,
                hint_ids_referenced=hint_ids,
            )

        except json.JSONDecodeError as exc:
            logger.error(
                "Briefing generation returned invalid JSON (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )
        except Exception as exc:
            logger.error(
                "Briefing generation failed (attempt %d/%d): %s",
                attempt + 1, MAX_RETRIES + 1, exc,
            )

    logger.error("Briefing generation exhausted all retries for vault %s", vault_data.vault_id)
    return None
