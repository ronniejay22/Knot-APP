"""
Availability Verification & Price Enrichment Node — LangGraph node for
verifying recommendation URLs and confirming prices from product pages.

1. Verifies that the 3 selected recommendations have valid, reachable external URLs.
2. If a purchasable has no resolved URL (resolution found no real page) or its URL is
   dead, SWAPS it for a bookable spare from the pool (resolving + live-checking the
   spare's URL). Bookable purchasable backups are tried first (the goal is a card the
   user can actually buy); an in-app idea is used only as a last resort — the best
   spare idea, or, failing that, the original converted to a linkless idea card. We
   never show a web-search link, and the count never falls below 3 (PRD F2).
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

import asyncio
import json
import logging
import re
from typing import Any

import httpx
from bs4 import BeautifulSoup

from app.agents.state import CandidateRecommendation, RecommendationState
from app.agents.url_resolution import _localize_search_query, _search_for_purchase_url
from app.services.llm_tuning import fast_generation_params

logger = logging.getLogger(__name__)

# --- Constants ---
REQUEST_TIMEOUT = 10.0  # seconds per page fetch (increased from 5s for full GET)
MAX_REPLACEMENT_ATTEMPTS = 3  # max times to try replacing a single slot
VALID_STATUS_RANGE = range(200, 400)  # 2xx and 3xx are considered available
MAX_PAGE_CONTENT_CHARS = 8000  # limit page text sent to Claude per candidate

# Claude model for price extraction
CLAUDE_PRICE_MODEL = "claude-sonnet-4-6"
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
    # Parse with a real HTML parser rather than regex — regex-based tag
    # filtering is unreliable against malformed markup (e.g. </script foo="bar">)
    # and lets script bodies leak into the extracted text (CodeQL py/bad-tag-filter).
    soup = BeautifulSoup(html, "html.parser")

    def _is_jsonld(tag: Any) -> bool:
        return (tag.get("type") or "").strip().lower() == "application/ld+json"

    # Extract JSON-LD structured data (often contains exact prices) before
    # decomposing any scripts, so it survives the script/style stripping below.
    jsonld_matches = [
        s.get_text() for s in soup.find_all("script") if _is_jsonld(s)
    ]
    jsonld_text = "\n".join(jsonld_matches[:3]).strip()

    # Extract title and meta description before stripping body content.
    title = soup.title.get_text().strip() if soup.title else ""

    meta_tag = soup.find("meta", attrs={"name": re.compile(r"^description$", re.IGNORECASE)})
    meta_desc = (meta_tag.get("content") or "").strip() if meta_tag else ""

    # Remove script and style blocks (except JSON-LD scripts) for body text.
    for tag in soup.find_all(["script", "style"]):
        if tag.name == "script" and _is_jsonld(tag):
            continue
        tag.decompose()

    body_text = re.sub(r"\s+", " ", soup.get_text(" ")).strip()

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
# Page fetching (GET — checks availability and captures content)
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
            # Keep extraction fast — see app/services/llm_tuning.py.
            **fast_generation_params(CLAUDE_PRICE_MODEL),
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


def _best_unused_idea(
    filtered: list[CandidateRecommendation],
    excluded_ids: set[str],
) -> CandidateRecommendation | None:
    """Highest-scoring unused in-app idea/plan (needs no URL) — last-resort filler."""
    ideas = [c for c in filtered if c.is_idea and c.id not in excluded_ids]
    if not ideas:
        return None
    return max(ideas, key=lambda c: c.final_score)


async def _resolve_and_verify(
    candidate: CandidateRecommendation,
    client: httpx.AsyncClient,
) -> tuple[CandidateRecommendation, str] | None:
    """
    Resolve a purchasable backup's real purchase page and confirm it is live.

    Backups from the pool were never URL-resolved (only the shown 3 are), so a
    swap must resolve the query AND live-check the result before trusting it.

    Returns (candidate with a live external_url, page_content) or None if no
    real, reachable page could be found.
    """
    if not candidate.search_query:
        return None
    query = _localize_search_query(candidate.search_query, candidate.location)
    url = await _search_for_purchase_url(query, candidate.merchant_name)
    if not url:
        return None
    is_available, content = await _fetch_page(url, client)
    if not is_available:
        return None
    return candidate.model_copy(update={"external_url": url}), content


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
    3. If a purchasable has no resolved URL or an unreachable one, swaps in a bookable
       spare from filtered_recommendations — resolving+live-checking spare purchasables
       first, then falling back to a spare idea, then to the original converted to a
       linkless idea card. Never a web-search link; never drops below the input count
       (PRD F2)
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

        # ----------------------------------------------------------------
        # Phase 1: Fetch all pages in parallel (happy path)
        # Ideas are no-ops (no URL). A purchasable with no resolved URL is NOT a
        # no-op — it counts as unavailable so Phase 2 swaps it for a bookable spare.
        # ----------------------------------------------------------------
        async def _fetch_indexed(
            idx: int,
            candidate: CandidateRecommendation,
        ) -> tuple[int, bool, str]:
            if candidate.is_idea:
                return idx, True, ""
            if candidate.external_url is None:
                return idx, False, ""
            is_avail, content = await _fetch_page(candidate.external_url, client)
            return idx, is_avail, content

        fetch_results = await asyncio.gather(
            *[_fetch_indexed(i, c) for i, c in enumerate(selected)],
        )

        # ----------------------------------------------------------------
        # Phase 2: Process results; handle failures with replacement logic
        # ----------------------------------------------------------------
        for idx, is_available, page_content in fetch_results:
            candidate = selected[idx]
            i = idx  # keep variable name consistent with original logging

            # Skip URL verification for ideas — they have no external URL (Step 14.5)
            if candidate.is_idea:
                logger.debug(
                    "Slot %d: '%s' is an idea — skipping URL verification",
                    i + 1, candidate.title,
                )
                verified.append(candidate)
                continue

            if is_available:
                logger.debug(
                    "Slot %d: '%s' verified (URL: %s)",
                    i + 1, candidate.title, candidate.external_url,
                )
                verified.append(candidate)
                if page_content:
                    candidates_with_content.append((candidate, page_content))
                continue

            # Not bookable (no resolved URL, or a dead one) — swap for a spare that IS.
            logger.info(
                "Slot %d: '%s' not bookable (URL: %s) — seeking replacement",
                i + 1, candidate.title, candidate.external_url or "unresolved",
            )
            used_ids.add(candidate.id)

            # Prefer a real bookable replacement (the user's stated priority), so try
            # PURCHASABLE backups first — resolving + live-checking each. Ideas are
            # held back for the last-resort step below. Each attempt is a serial
            # Brave call + page GET, so the loop is bounded by MAX_REPLACEMENT_ATTEMPTS
            # to cap worst-case tail latency.
            replaced = False
            for attempt in range(MAX_REPLACEMENT_ATTEMPTS):
                purchasable_backups = [
                    b for b in _get_backup_candidates(filtered_pool, used_ids)
                    if not b.is_idea
                ]
                if not purchasable_backups:
                    logger.warning(
                        "Slot %d: No more purchasable backups (attempt %d/%d)",
                        i + 1, attempt + 1, MAX_REPLACEMENT_ATTEMPTS,
                    )
                    break

                replacement = purchasable_backups[0]
                used_ids.add(replacement.id)

                # Backups arrive URL-less — resolve to a real page and live-check it.
                result = await _resolve_and_verify(replacement, client)
                if result is not None:
                    live_replacement, content = result
                    logger.info(
                        "Slot %d: Replaced with '%s' (URL: %s, attempt %d)",
                        i + 1, live_replacement.title, live_replacement.external_url,
                        attempt + 1,
                    )
                    verified.append(live_replacement)
                    if content:
                        candidates_with_content.append((live_replacement, content))
                    replaced = True
                    break
                else:
                    logger.debug(
                        "Slot %d: Replacement '%s' not bookable (attempt %d/%d)",
                        i + 1, replacement.title, attempt + 1,
                        MAX_REPLACEMENT_ATTEMPTS,
                    )

            if not replaced:
                # Never drop a card (PRD F2) and never show a web-search link. Last
                # resort: use the best remaining idea (needs no URL); if none exists,
                # keep the original as a linkless idea-style card so it still renders
                # with a Save action instead of a dead buy button.
                idea = _best_unused_idea(filtered_pool, used_ids)
                if idea is not None:
                    used_ids.add(idea.id)
                    logger.warning(
                        "Slot %d: no bookable replacement — using idea '%s'",
                        i + 1, idea.title,
                    )
                    verified.append(idea)
                else:
                    logger.warning(
                        "Slot %d: no bookable replacement and no spare idea — keeping "
                        "'%s' as a linkless idea card",
                        i + 1, candidate.title,
                    )
                    # Convert fully to an idea so BOTH the detail view and the
                    # card/deck (which branch on `type`) render it as a linkless,
                    # saveable idea — not a purchasable with a dead price/merchant.
                    verified.append(candidate.model_copy(
                        update={
                            "external_url": None,
                            "is_idea": True,
                            "type": "idea",
                            "price_cents": None,
                            "merchant_name": None,
                        },
                    ))

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

    # Count is always preserved — an unbookable slot is swapped for a bookable spare
    # or an idea (never dropped, never a web-search link) — so there is no
    # partial-results path to warn about.
    return {"final_three": verified}
