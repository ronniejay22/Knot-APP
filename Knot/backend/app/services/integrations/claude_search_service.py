"""
Claude Search Service — AI-powered web search for recommendation candidates.

Uses Brave Search API to find real products, restaurants, and experiences,
then uses Claude to extract and normalize results into the
CandidateRecommendation schema.

Replaces the 6 individual API integrations (Yelp, Ticketmaster, Amazon,
Shopify, OpenTable, Firecrawl) with a single intelligent search pipeline.

Step 13.1: Replace External APIs with Claude Search Agent
"""

import asyncio
import json
import logging
import uuid
from typing import Any, Optional

import httpx
from anthropic import AsyncAnthropic

from app.core.config import (
    ANTHROPIC_API_KEY,
    BRAVE_SEARCH_API_KEY,
    is_claude_search_configured,
)

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/web/search"
BRAVE_TIMEOUT = 10.0  # seconds
MAX_RETRIES = 2
MAX_SEARCH_QUERIES = 5  # limit parallel searches to control cost
RESULTS_PER_QUERY = 5  # Brave results per query
TARGET_CANDIDATES = 20  # match TARGET_CANDIDATE_COUNT in aggregation.py

# Claude model for structured extraction
CLAUDE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_MAX_TOKENS = 4096

# Map occasion types to search intent modifiers
OCCASION_MODIFIERS: dict[str, str] = {
    "just_because": "casual thoughtful",
    "minor_occasion": "special",
    "major_milestone": "premium memorable",
}

# Map vibes to descriptive search terms
VIBE_SEARCH_TERMS: dict[str, str] = {
    "quiet_luxury": "upscale luxury boutique",
    "street_urban": "trendy urban hip",
    "outdoorsy": "outdoor nature adventure",
    "vintage": "vintage classic retro",
    "minimalist": "minimalist modern zen",
    "bohemian": "artisan handmade creative",
    "romantic": "romantic couples intimate",
    "adventurous": "adventure extreme thrilling",
}


# ======================================================================
# Search query construction
# ======================================================================

def _build_search_queries(
    interests: list[str],
    vibes: list[str],
    location: tuple[str, str, str],
    budget_range: tuple[int, int],
    occasion_type: str,
    hints: list[str],
    milestone_context: Optional[dict[str, str]] = None,
) -> list[dict[str, str]]:
    """
    Build targeted search queries from vault data.

    Returns a list of dicts with "query" (the search string) and
    "search_type" ("gift", "experience", or "date") keys.

    Strategy:
    1. Gift queries from interests + budget
    2. Experience/date queries from vibes + location
    3. Hint-derived queries from the top hints
    4. Occasion-specific queries if milestone context exists
    """
    city, state, country = location
    location_str = ", ".join(p for p in (city, state) if p) or "United States"
    budget_max_dollars = budget_range[1] / 100
    occasion_mod = OCCASION_MODIFIERS.get(occasion_type, "")
    vibe_terms = " ".join(
        VIBE_SEARCH_TERMS.get(v, "") for v in vibes[:2]
    ).strip()

    queries: list[dict[str, str]] = []

    # 1. Gift queries from top interests (2-3 queries)
    for interest in interests[:3]:
        q = f"best {occasion_mod} {interest.lower()} gifts under ${budget_max_dollars:.0f}"
        if vibe_terms:
            q += f" {vibe_terms} style"
        queries.append({"query": q, "search_type": "gift"})

    # 2. Experience/date queries from vibes + location (1-2 queries)
    if city:
        vibe_desc = vibe_terms or "fun unique"
        queries.append({
            "query": f"best {vibe_desc} date ideas in {location_str} under ${budget_max_dollars:.0f}",
            "search_type": "date",
        })
        queries.append({
            "query": f"unique {occasion_mod} experiences in {location_str} for couples",
            "search_type": "experience",
        })

    # 3. Hint-derived queries (up to 2 from top hints)
    for hint_text in hints[:2]:
        hint_short = hint_text[:80].strip()
        q = f"{hint_short} gift or experience near {location_str}"
        queries.append({"query": q, "search_type": "gift"})

    # 4. Milestone-specific query
    if milestone_context:
        milestone_type = milestone_context.get("milestone_type", "")
        if milestone_type:
            q = f"best {milestone_type} {occasion_mod} gift ideas {vibe_terms}"
            queries.append({"query": q, "search_type": "gift"})

    # Cap total queries to control API costs
    return queries[:MAX_SEARCH_QUERIES]


# ======================================================================
# Brave Search API
# ======================================================================

async def _brave_search(
    query: str,
    count: int = RESULTS_PER_QUERY,
) -> list[dict[str, Any]]:
    """
    Call Brave Search API and return web results.

    Returns a list of result dicts with "title", "url", "description" keys.
    Returns [] on any error.
    """
    headers = {
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": BRAVE_SEARCH_API_KEY,
    }
    params = {
        "q": query,
        "count": count,
        "text_decorations": False,
        "search_lang": "en",
    }

    async with httpx.AsyncClient(timeout=BRAVE_TIMEOUT) as client:
        for retry in range(MAX_RETRIES):
            try:
                response = await client.get(
                    BRAVE_SEARCH_URL,
                    headers=headers,
                    params=params,
                )

                if response.status_code == 429:
                    delay = 2 ** retry
                    logger.warning(
                        "Brave Search rate limited (429), retrying in %ds",
                        delay,
                    )
                    await asyncio.sleep(delay)
                    continue

                response.raise_for_status()
                data = response.json()

                web_results = data.get("web", {}).get("results", [])
                return [
                    {
                        "title": r.get("title", ""),
                        "url": r.get("url", ""),
                        "description": r.get("description", ""),
                        "extra_snippets": r.get("extra_snippets", []),
                    }
                    for r in web_results
                ]

            except httpx.TimeoutException:
                logger.warning(
                    "Brave Search timeout (attempt %d/%d)",
                    retry + 1, MAX_RETRIES,
                )
                if retry < MAX_RETRIES - 1:
                    await asyncio.sleep(1)
                continue

            except httpx.HTTPError as exc:
                logger.error("Brave Search error: %s", exc)
                return []

    logger.warning(
        "Brave Search exhausted retries for query: %s", query[:80],
    )
    return []


# ======================================================================
# Claude extraction
# ======================================================================

EXTRACTION_SYSTEM_PROMPT = """\
You are an expert gift and experience recommender.
You analyze web search results and extract structured product/experience recommendations.

For each relevant result, extract:
- title: A clear, appealing product or experience name
- description: 1-2 sentence description highlighting why it's a good recommendation
- type: "gift" for purchasable items, "experience" for activities/events, "date" for restaurants/dining
- price_cents: Estimated price in US cents (e.g., $50 = 5000). Use null if unknown.
- external_url: The URL from the search result
- merchant_name: The business or seller name
- image_url: Product/venue image URL if visible in the result, else null

Only include results that are:
1. Actually purchasable or bookable (not articles, listicles, or review roundups)
2. Within the specified budget range
3. Relevant to the described interests and occasion

Return ONLY a JSON array of objects. No markdown, no explanation."""


def _build_extraction_prompt(
    search_results: list[dict[str, Any]],
    search_type: str,
    interests: list[str],
    vibes: list[str],
    budget_range: tuple[int, int],
    location_str: str,
    occasion_type: str,
    hints: list[str],
) -> str:
    """Build the user prompt for Claude to extract candidates from search results."""
    budget_min_dollars = budget_range[0] / 100
    budget_max_dollars = budget_range[1] / 100

    results_text = ""
    for i, r in enumerate(search_results, 1):
        results_text += f"\n--- Result {i} ---\n"
        results_text += f"Title: {r['title']}\n"
        results_text += f"URL: {r['url']}\n"
        results_text += f"Description: {r['description']}\n"
        if r.get("extra_snippets"):
            results_text += f"Details: {' '.join(r['extra_snippets'][:2])}\n"

    prompt = f"""Extract recommendation candidates from these search results.

Context:
- Searching for: {search_type} recommendations
- Partner interests: {', '.join(interests)}
- Aesthetic vibes: {', '.join(vibes)}
- Location: {location_str}
- Occasion: {occasion_type}
- Budget: ${budget_min_dollars:.0f} - ${budget_max_dollars:.0f}
"""

    if hints:
        prompt += f"- Partner hints: {'; '.join(hints[:3])}\n"

    prompt += f"""
Search Results:
{results_text}

Extract up to 4 high-quality {search_type} recommendations from these results.
Return a JSON array. Each object must have: title, description, type, price_cents, external_url, merchant_name, image_url.
Only valid JSON, no markdown fencing."""

    return prompt


async def _extract_candidates_with_claude(
    search_results: list[dict[str, Any]],
    search_type: str,
    interests: list[str],
    vibes: list[str],
    budget_range: tuple[int, int],
    location_str: str,
    occasion_type: str,
    hints: list[str],
) -> list[dict[str, Any]]:
    """
    Use Claude to extract structured recommendation candidates from search results.

    Returns a list of dicts with candidate fields.
    Returns [] on any error.
    """
    if not search_results:
        return []

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)

    prompt = _build_extraction_prompt(
        search_results, search_type, interests, vibes,
        budget_range, location_str, occasion_type, hints,
    )

    try:
        response = await client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=CLAUDE_MAX_TOKENS,
            system=EXTRACTION_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )

        text = response.content[0].text.strip()

        # Strip markdown code fences if Claude added them despite instruction
        if text.startswith("```"):
            text = text.split("\n", 1)[1] if "\n" in text else text[3:]
        if text.endswith("```"):
            text = text[:-3].strip()
        if text.startswith("json"):
            text = text[4:].strip()

        candidates = json.loads(text)

        if not isinstance(candidates, list):
            logger.warning("Claude returned non-list response for extraction")
            return []

        return candidates

    except json.JSONDecodeError as exc:
        logger.error("Claude returned invalid JSON: %s", exc)
        return []
    except Exception as exc:
        logger.error("Claude extraction failed: %s", exc)
        return []


# ======================================================================
# Normalization
# ======================================================================

def _normalize_claude_result(
    raw: dict[str, Any],
    city: str,
    state: str,
    country: str,
) -> dict[str, Any]:
    """Convert a Claude-extracted result into CandidateRecommendation-compatible dict."""
    from app.services.integrations.yelp import COUNTRY_CURRENCY_MAP

    currency = COUNTRY_CURRENCY_MAP.get(country.upper(), "USD") if country else "USD"
    rec_type = raw.get("type", "gift")
    if rec_type not in ("gift", "experience", "date"):
        rec_type = "gift"

    location_data = None
    if rec_type in ("experience", "date") and city:
        location_data = {
            "city": city,
            "state": state,
            "country": country,
            "address": None,
        }

    return {
        "id": str(uuid.uuid4()),
        "source": "claude_search",
        "type": rec_type,
        "title": raw.get("title", "Unknown"),
        "description": raw.get("description"),
        "price_cents": raw.get("price_cents"),
        "currency": currency,
        "external_url": raw.get("external_url", ""),
        "image_url": raw.get("image_url"),
        "merchant_name": raw.get("merchant_name"),
        "location": location_data,
        "metadata": {
            "search_source": "claude_search",
            "extraction_model": CLAUDE_MODEL,
        },
    }


# ======================================================================
# ClaudeSearchService
# ======================================================================

class ClaudeSearchService:
    """
    AI-powered search service that combines Brave Search + Claude
    to find and extract recommendation candidates.
    """

    async def search(
        self,
        interests: list[str],
        vibes: list[str],
        location: tuple[str, str, str],
        budget_range: tuple[int, int],
        occasion_type: str = "just_because",
        hints: list[str] | None = None,
        milestone_context: dict[str, str] | None = None,
    ) -> list[dict[str, Any]]:
        """
        Search for recommendation candidates using Claude + Brave Search.

        Args:
            interests: Partner interest categories.
            vibes: Partner aesthetic vibes.
            location: Tuple of (city, state, country_code).
            budget_range: Budget in cents as (min_cents, max_cents).
            occasion_type: "just_because", "minor_occasion", or "major_milestone".
            hints: Optional list of hint text strings.
            milestone_context: Optional dict with milestone_type, milestone_name.

        Returns:
            List of normalized dicts matching CandidateRecommendation schema.
            Returns [] if not configured or on error.
        """
        if not is_claude_search_configured():
            logger.warning(
                "Claude Search not configured (missing ANTHROPIC_API_KEY or "
                "BRAVE_SEARCH_API_KEY) — skipping"
            )
            return []

        hints = hints or []
        city, state, country = location
        location_str = ", ".join(p for p in (city, state) if p) or "United States"

        # Step 1: Build search queries
        queries = _build_search_queries(
            interests, vibes, location, budget_range,
            occasion_type, hints, milestone_context,
        )

        logger.info(
            "Claude Search: executing %d queries for interests=%s, vibes=%s, "
            "location=%s",
            len(queries), interests[:3], vibes[:2], location_str,
        )

        # Step 2: Execute all Brave searches in parallel
        search_tasks = [_brave_search(q["query"]) for q in queries]
        search_results_list = await asyncio.gather(
            *search_tasks, return_exceptions=True,
        )

        # Step 3: Extract candidates from each batch with Claude
        extraction_tasks = []

        for i, (query_info, results) in enumerate(
            zip(queries, search_results_list),
        ):
            if isinstance(results, Exception):
                logger.error("Search query %d failed: %s", i, results)
                continue
            if not results:
                continue

            extraction_tasks.append(
                _extract_candidates_with_claude(
                    search_results=results,
                    search_type=query_info["search_type"],
                    interests=interests,
                    vibes=vibes,
                    budget_range=budget_range,
                    location_str=location_str,
                    occasion_type=occasion_type,
                    hints=hints,
                )
            )

        if not extraction_tasks:
            logger.warning("No search results to extract from")
            return []

        # Execute all Claude extractions in parallel
        extraction_results = await asyncio.gather(
            *extraction_tasks, return_exceptions=True,
        )

        all_candidates: list[dict[str, Any]] = []
        for result in extraction_results:
            if isinstance(result, Exception):
                logger.error("Claude extraction failed: %s", result)
                continue
            if isinstance(result, list):
                all_candidates.extend(result)

        # Step 4: Normalize to CandidateRecommendation schema
        normalized = []
        for raw in all_candidates:
            try:
                normalized.append(
                    _normalize_claude_result(raw, city, state, country)
                )
            except (KeyError, ValueError, TypeError) as exc:
                logger.warning(
                    "Skipping malformed Claude result: %s — %s",
                    exc, raw.get("title", "unknown"),
                )

        # Deduplicate by URL
        seen_urls: set[str] = set()
        deduped: list[dict[str, Any]] = []
        for candidate in normalized:
            url = candidate.get("external_url", "")
            if url and url not in seen_urls:
                seen_urls.add(url)
                deduped.append(candidate)
            elif not url:
                deduped.append(candidate)

        logger.info(
            "Claude Search: %d candidates extracted (%d after dedup)",
            len(normalized), len(deduped),
        )

        return deduped[:TARGET_CANDIDATES]
