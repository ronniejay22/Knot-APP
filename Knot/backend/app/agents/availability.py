"""
Availability Verification & Price Enrichment Node — LangGraph node for
verifying recommendation URLs and confirming prices from product pages.

1. Verifies that the 3 selected recommendations have valid, reachable external URLs.
2. If a URL is unavailable, replaces it with the next-best candidate from the pool.
3. Fetches page content for verified candidates and extracts real prices via Claude.
4. Updates price_cents and price_confidence based on verification results.

Verification strategy:
- Fetches each URL via GET (also serves as availability check).
- Extracts visible text and JSON-LD structured data from the HTML response.
- Sends all page excerpts to Claude in a single batched call for price extraction.
- Falls back gracefully if page fetch or Claude extraction fails.

Step 5.7: Create Availability Verification Node
Step 14.1: Add Price Verification via Page Scraping
"""

import json
import logging
import re
from typing import Any

import httpx

from app.agents.state import CandidateRecommendation, RecommendationState

logger = logging.getLogger(__name__)

# --- Constants ---
REQUEST_TIMEOUT = 10.0  # seconds per page fetch (increased from 5s for full GET)
MAX_REPLACEMENT_ATTEMPTS = 3  # max times to try replacing a single slot
VALID_STATUS_RANGE = range(200, 400)  # 2xx and 3xx are considered available
MAX_PAGE_CONTENT_CHARS = 8000  # limit page text sent to Claude per candidate

# Claude model for price extraction
CLAUDE_PRICE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_PRICE_MAX_TOKENS = 1024

# User-Agent to avoid bot detection on merchant sites
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


# ======================================================================
# HTML text extraction
# ======================================================================

def _extract_text_from_html(html: str) -> str:
    """
    Extract price-relevant text from HTML content.

    Prioritizes structured data (JSON-LD) which is the most reliable
    source of machine-readable prices, then falls back to visible text.

    Args:
        html: Raw HTML content from a product page.

    Returns:
        A text string containing title, meta description, JSON-LD data,
        and visible body text, capped at MAX_PAGE_CONTENT_CHARS.
    """
    # Remove script and style blocks (except JSON-LD scripts)
    cleaned = re.sub(
        r"<script(?![^>]*type=[\"']application/ld\+json[\"'])[^>]*>.*?</script>",
        "", html, flags=re.DOTALL | re.IGNORECASE,
    )
    cleaned = re.sub(
        r"<style[^>]*>.*?</style>",
        "", cleaned, flags=re.DOTALL | re.IGNORECASE,
    )

    # Extract title
    title_match = re.search(
        r"<title[^>]*>(.*?)</title>", html, re.IGNORECASE | re.DOTALL,
    )
    title = title_match.group(1).strip() if title_match else ""

    # Extract meta description
    meta_match = re.search(
        r'<meta[^>]*name=["\']description["\'][^>]*content=["\']([^"\']*)["\']',
        html, re.IGNORECASE,
    )
    if not meta_match:
        # Try reversed attribute order
        meta_match = re.search(
            r'<meta[^>]*content=["\']([^"\']*)["\'][^>]*name=["\']description["\']',
            html, re.IGNORECASE,
        )
    meta_desc = meta_match.group(1).strip() if meta_match else ""

    # Extract JSON-LD structured data (often contains exact prices)
    jsonld_matches = re.findall(
        r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html, re.DOTALL | re.IGNORECASE,
    )
    jsonld_text = "\n".join(jsonld_matches[:3])

    # Strip remaining HTML tags for body text
    body_text = re.sub(r"<[^>]+>", " ", cleaned)
    body_text = re.sub(r"\s+", " ", body_text).strip()

    parts = []
    if title:
        parts.append(f"Title: {title}")
    if meta_desc:
        parts.append(f"Meta: {meta_desc}")
    if jsonld_text:
        parts.append(f"Structured Data: {jsonld_text}")
    if body_text:
        parts.append(f"Page Text: {body_text[:4000]}")

    return "\n".join(parts)[:MAX_PAGE_CONTENT_CHARS]


# ======================================================================
# Page fetching (replaces _check_url for final candidates)
# ======================================================================

async def _fetch_page(
    url: str,
    client: httpx.AsyncClient,
) -> tuple[bool, str]:
    """
    Fetch a URL via GET and return availability status plus page text.

    Combines URL availability checking with page content extraction
    for price verification. Falls back to HEAD if GET times out on
    a second attempt (to still confirm availability without content).

    Args:
        url: The external URL to fetch.
        client: An httpx.AsyncClient instance.

    Returns:
        A tuple of (is_available, page_text). page_text is empty if
        the page couldn't be fetched or parsed.
    """
    try:
        response = await client.get(
            url,
            follow_redirects=True,
            headers={"User-Agent": USER_AGENT},
        )
        if response.status_code in VALID_STATUS_RANGE:
            content_type = response.headers.get("content-type", "")
            if "text/html" in content_type or "text/plain" in content_type:
                page_text = _extract_text_from_html(response.text)
                return True, page_text
            # Non-HTML response (PDF, image, etc.) — available but no text
            return True, ""
        return False, ""
    except (httpx.TimeoutException, httpx.ConnectError, httpx.HTTPError) as exc:
        logger.warning("Page fetch failed for %s: %s", url, exc)
        return False, ""


async def _check_url(url: str, client: httpx.AsyncClient) -> bool:
    """
    Check if a URL is reachable (lightweight HEAD check for replacements).

    Used for backup candidate URL checks where we don't need page content.

    Args:
        url: The external URL to check.
        client: An httpx.AsyncClient instance.

    Returns:
        True if the URL is reachable with a valid status, False otherwise.
    """
    try:
        response = await client.head(url, follow_redirects=True)
        if response.status_code == 405:
            response = await client.get(url, follow_redirects=True)
        return response.status_code in VALID_STATUS_RANGE
    except (httpx.TimeoutException, httpx.ConnectError, httpx.HTTPError) as exc:
        logger.warning("URL check failed for %s: %s", url, exc)
        return False


# ======================================================================
# Claude price verification
# ======================================================================

PRICE_EXTRACTION_SYSTEM_PROMPT = """\
You are a price extraction specialist. Given product or experience page content, \
extract the actual price.

Return ONLY a JSON array of objects with:
- "id": the item ID provided
- "price_cents": price in US cents (e.g., $49.99 = 4999). Use null if no price found.
- "verified": true if you found a clear, unambiguous price on the page, false if uncertain

Rules:
- If a page shows a price range (e.g., "$50-$100"), use the lower end.
- If the price is per-person (e.g., "$50/person"), use the per-person price.
- Convert any currency to US cents (e.g., $49.99 = 4999, $100 = 10000).
- If the page has no price information at all, set price_cents to null and verified to false.
- No markdown fencing, no explanation — only valid JSON."""


async def _verify_prices_with_claude(
    candidates_with_content: list[tuple[CandidateRecommendation, str]],
) -> dict[str, dict[str, Any]]:
    """
    Send page content to Claude for price extraction in a single batched call.

    Args:
        candidates_with_content: List of (candidate, page_text) tuples.

    Returns:
        A dict mapping candidate ID to {"price_cents": int|None, "verified": bool}.
        Returns empty dict on any error.
    """
    if not candidates_with_content:
        return {}

    from anthropic import AsyncAnthropic
    from app.core.config import ANTHROPIC_API_KEY, is_claude_search_configured

    if not is_claude_search_configured():
        logger.info("Claude not configured — skipping price verification")
        return {}

    client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)

    prompt_parts = []
    for candidate, content in candidates_with_content:
        prompt_parts.append(
            f"--- Item: {candidate.title} (ID: {candidate.id}) ---\n"
            f"Current estimated price: "
            f"{'$' + f'{candidate.price_cents / 100:.2f}' if candidate.price_cents else 'unknown'}\n"
            f"URL: {candidate.external_url}\n"
            f"Page content:\n{content}\n"
        )

    user_prompt = (
        "Extract the actual price from each of these product/experience pages:\n\n"
        + "\n".join(prompt_parts)
    )

    try:
        response = await client.messages.create(
            model=CLAUDE_PRICE_MODEL,
            max_tokens=CLAUDE_PRICE_MAX_TOKENS,
            system=PRICE_EXTRACTION_SYSTEM_PROMPT,
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

        results = json.loads(text)

        if not isinstance(results, list):
            logger.warning("Price verification: Claude returned non-list response")
            return {}

        return {
            item["id"]: item
            for item in results
            if isinstance(item, dict) and "id" in item
        }

    except json.JSONDecodeError as exc:
        logger.error("Price verification: Claude returned invalid JSON: %s", exc)
        return {}
    except Exception as exc:
        logger.error("Price verification Claude call failed: %s", exc)
        return {}


# ======================================================================
# Replacement logic
# ======================================================================

def _get_backup_candidates(
    filtered: list[CandidateRecommendation],
    excluded_ids: set[str],
) -> list[CandidateRecommendation]:
    """
    Get backup candidates from the filtered pool, excluding already-used IDs.

    Returns candidates sorted by final_score descending (best first).

    Args:
        filtered: The full filtered_recommendations pool.
        excluded_ids: IDs of candidates already selected or already tried.

    Returns:
        List of backup candidates, sorted by final_score descending.
    """
    backups = [c for c in filtered if c.id not in excluded_ids]
    backups.sort(key=lambda c: c.final_score, reverse=True)
    return backups


# ======================================================================
# LangGraph node
# ======================================================================

async def verify_availability(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Verify URLs and enrich prices for the 3 selected recommendations.

    Processing:
    1. Takes final_three from the state (3 selected recommendations)
    2. Fetches each candidate's page via GET (checks availability + captures content)
    3. If a URL is unreachable, replaces with next-best from filtered_recommendations
    4. Sends page content for all verified candidates to Claude in a single call
       for price extraction and verification
    5. Updates price_cents and price_confidence based on verification results
    6. Returns the verified and price-enriched list

    Args:
        state: The current RecommendationState with final_three and
               filtered_recommendations (backup pool).

    Returns:
        A dict with "final_three" key containing the verified recommendations.
    """
    selected = list(state.final_three)
    filtered_pool = list(state.filtered_recommendations)

    logger.info(
        "Verifying availability and prices for %d recommendations (backup pool: %d)",
        len(selected), len(filtered_pool),
    )

    if not selected:
        logger.warning("No recommendations to verify")
        return {"final_three": []}

    # Track all IDs we've used or tried (to avoid re-checking the same candidate)
    used_ids: set[str] = {c.id for c in selected}

    verified: list[CandidateRecommendation] = []
    candidates_with_content: list[tuple[CandidateRecommendation, str]] = []

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        for i, candidate in enumerate(selected):
            # Skip URL verification for ideas — they have no external URL (Step 14.5)
            if candidate.is_idea or candidate.external_url is None:
                logger.debug(
                    "Slot %d: '%s' is an idea — skipping URL verification",
                    i + 1, candidate.title,
                )
                verified.append(candidate)
                continue

            # Fetch the page (availability check + content extraction)
            is_available, page_content = await _fetch_page(
                candidate.external_url, client,
            )

            if is_available:
                logger.debug(
                    "Slot %d: '%s' verified (URL: %s)",
                    i + 1, candidate.title, candidate.external_url,
                )
                verified.append(candidate)
                if page_content:
                    candidates_with_content.append((candidate, page_content))
                continue

            # URL unavailable — try to find a replacement
            logger.info(
                "Slot %d: '%s' unavailable (URL: %s) — seeking replacement",
                i + 1, candidate.title, candidate.external_url,
            )
            used_ids.add(candidate.id)

            replaced = False
            for attempt in range(MAX_REPLACEMENT_ATTEMPTS):
                backups = _get_backup_candidates(filtered_pool, used_ids)
                if not backups:
                    logger.warning(
                        "Slot %d: No more backup candidates available "
                        "(attempt %d/%d)",
                        i + 1, attempt + 1, MAX_REPLACEMENT_ATTEMPTS,
                    )
                    break

                replacement = backups[0]
                used_ids.add(replacement.id)

                # Use lightweight HEAD check for replacements
                replacement_available = await _check_url(
                    replacement.external_url, client,
                )
                if replacement_available:
                    logger.info(
                        "Slot %d: Replaced with '%s' (URL: %s, attempt %d)",
                        i + 1, replacement.title, replacement.external_url,
                        attempt + 1,
                    )
                    verified.append(replacement)
                    replaced = True
                    break
                else:
                    logger.debug(
                        "Slot %d: Replacement '%s' also unavailable (attempt %d/%d)",
                        i + 1, replacement.title, attempt + 1,
                        MAX_REPLACEMENT_ATTEMPTS,
                    )

            if not replaced:
                logger.warning(
                    "Slot %d: Could not find a valid replacement after %d attempts",
                    i + 1, MAX_REPLACEMENT_ATTEMPTS,
                )

    # --- Price verification pass ---
    if candidates_with_content:
        logger.info(
            "Verifying prices for %d candidates via Claude",
            len(candidates_with_content),
        )
        price_results = await _verify_prices_with_claude(candidates_with_content)

        if price_results:
            updated_verified: list[CandidateRecommendation] = []
            for candidate in verified:
                if candidate.id in price_results:
                    price_data = price_results[candidate.id]
                    new_price = price_data.get("price_cents")
                    is_verified = price_data.get("verified", False)

                    if is_verified and new_price is not None:
                        candidate = candidate.model_copy(update={
                            "price_cents": new_price,
                            "price_confidence": "verified",
                        })
                        logger.info(
                            "Price verified for '%s': %d cents",
                            candidate.title, new_price,
                        )
                    elif new_price is not None:
                        # Claude found a price but wasn't confident
                        candidate = candidate.model_copy(update={
                            "price_cents": new_price,
                            "price_confidence": "estimated",
                        })
                        logger.debug(
                            "Price estimated (unverified) for '%s': %d cents",
                            candidate.title, new_price,
                        )
                    # else: keep existing price and confidence
                updated_verified.append(candidate)
            verified = updated_verified

    logger.info(
        "Verification complete: %d/%d recommendations verified — %s",
        len(verified), len(selected),
        [f"{c.title} ({c.price_confidence})" for c in verified],
    )

    if len(verified) < len(selected):
        logger.warning(
            "Partial results: only %d of %d recommendations have valid URLs",
            len(verified), len(selected),
        )

    return {"final_three": verified}
