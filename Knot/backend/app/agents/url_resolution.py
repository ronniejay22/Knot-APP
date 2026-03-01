"""
URL Resolution Node — Resolves purchase URLs for purchasable recommendations.

For each purchasable item (gift, experience, date) in the final_three,
performs a targeted Brave Search using the search_query provided by Claude,
then picks the best matching result URL.

Ideas (is_idea=True) skip URL resolution entirely.

Step 15.1: Unified AI Recommendation System
"""

import asyncio
import logging
from typing import Any

import httpx

from app.agents.state import CandidateRecommendation, RecommendationState
from app.core.config import BRAVE_SEARCH_API_KEY, is_brave_search_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/web/search"
BRAVE_TIMEOUT = 10.0
RESULTS_PER_QUERY = 5

# Domains to exclude — articles, listicles, review sites (not actual purchase pages)
EXCLUDED_DOMAINS = {
    "reddit.com", "quora.com", "medium.com", "buzzfeed.com",
    "pinterest.com", "wikihow.com", "wikipedia.org",
}


# ======================================================================
# Brave Search for a single item
# ======================================================================

async def _search_for_purchase_url(
    search_query: str,
    merchant_name: str | None = None,
) -> str | None:
    """
    Search Brave for a real purchase/booking URL matching the search query.

    Filters out article/listicle domains and prioritizes results that look
    like actual product or booking pages.

    Returns the best matching URL, or None if nothing suitable found.
    """
    if not is_brave_search_configured():
        return None

    headers = {
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": BRAVE_SEARCH_API_KEY,
    }
    params = {
        "q": search_query,
        "count": RESULTS_PER_QUERY,
        "text_decorations": False,
        "search_lang": "en",
    }

    try:
        async with httpx.AsyncClient(timeout=BRAVE_TIMEOUT) as client:
            response = await client.get(
                BRAVE_SEARCH_URL,
                headers=headers,
                params=params,
            )

            if response.status_code == 429:
                logger.warning("Brave Search rate limited for query: %s", search_query[:60])
                return None

            response.raise_for_status()
            data = response.json()

            web_results = data.get("web", {}).get("results", [])

            for result in web_results:
                url = result.get("url", "")
                if not url:
                    continue

                # Skip excluded domains
                from urllib.parse import urlparse
                domain = urlparse(url).netloc.lower()
                if any(excluded in domain for excluded in EXCLUDED_DOMAINS):
                    continue

                # Prefer the first non-excluded result — Brave ranks by relevance
                return url

            logger.debug("No suitable purchase URL found for: %s", search_query[:60])
            return None

    except (httpx.TimeoutException, httpx.HTTPError) as exc:
        logger.warning("Brave Search failed for '%s': %s", search_query[:60], exc)
        return None


def _build_merchant_search_url(candidate: CandidateRecommendation) -> str:
    """Build a Google Shopping search fallback URL for a candidate."""
    query_parts = []
    if candidate.merchant_name:
        query_parts.append(candidate.merchant_name)
    query_parts.append(candidate.title)
    query = "+".join(query_parts[0].split()[:5]) if query_parts else candidate.title
    return f"https://www.google.com/search?tbm=shop&q={query}"


# ======================================================================
# LangGraph node
# ======================================================================

async def resolve_purchase_urls(
    state: RecommendationState,
) -> dict[str, Any]:
    """
    LangGraph node: Resolve real purchase/booking URLs for purchasable items.

    For each item in final_three that has a search_query (purchasable items),
    performs a targeted Brave Search to find the actual purchase URL.
    Ideas (is_idea=True) are skipped.

    If URL resolution fails for an item, assigns a Google Shopping fallback.

    Args:
        state: The current RecommendationState with final_three populated
               by the generate_unified node.

    Returns:
        A dict with "final_three" containing updated candidates with URLs.
    """
    selected = list(state.final_three)

    if not selected:
        logger.warning("No recommendations to resolve URLs for")
        return {"final_three": []}

    logger.info(
        "Resolving purchase URLs for %d recommendations",
        len(selected),
    )

    # Run all URL searches in parallel
    async def _resolve_single(candidate: CandidateRecommendation) -> CandidateRecommendation:
        # Skip ideas — no URL needed
        if candidate.is_idea or not candidate.search_query:
            return candidate

        url = await _search_for_purchase_url(
            search_query=candidate.search_query,
            merchant_name=candidate.merchant_name,
        )

        if url:
            logger.info(
                "Resolved URL for '%s': %s",
                candidate.title, url,
            )
            return candidate.model_copy(update={"external_url": url})
        else:
            # Fallback to Google Shopping search
            fallback_url = _build_merchant_search_url(candidate)
            logger.info(
                "Using fallback search URL for '%s': %s",
                candidate.title, fallback_url,
            )
            return candidate.model_copy(update={"external_url": fallback_url})

    resolved = await asyncio.gather(
        *[_resolve_single(c) for c in selected],
    )

    logger.info(
        "URL resolution complete: %s",
        [
            f"{c.title} ({'idea' if c.is_idea else c.external_url or 'no-url'})"
            for c in resolved
        ],
    )

    return {"final_three": list(resolved)}
