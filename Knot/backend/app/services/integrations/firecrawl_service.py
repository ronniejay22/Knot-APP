"""
Firecrawl Curated Content Service — Crawl city guides for experience/date recommendations.

Uses the Firecrawl API to scrape predefined city guide URLs and extract
"best of" lists (best new restaurants, trending experiences). Normalizes
results into the CandidateRecommendation schema used by the LangGraph pipeline.

Caches results in-memory with a 24-hour TTL to avoid excessive crawling.
Uses httpx directly (not the firecrawl-py SDK) for consistency with all
other integration services.

Step 8.6: Implement Firecrawl for Curated Content
"""

import asyncio
import logging
import re
import time
import uuid
from typing import Any, Optional

import httpx

from app.core.config import FIRECRAWL_API_KEY, is_firecrawl_configured

logger = logging.getLogger(__name__)

# ======================================================================
# Constants
# ======================================================================

FIRECRAWL_API_URL = "https://api.firecrawl.dev/v1/scrape"
DEFAULT_TIMEOUT = 15.0  # seconds (slightly longer — scraping takes more time)
MAX_RETRIES = 3
CACHE_TTL_SECONDS = 86400  # 24 hours

# Predefined city guide URLs — configurable list of curated content sources.
# Maps lowercase city name → list of guide URLs to scrape.
# In production, these would point to real city guide / "best of" pages.
CITY_GUIDE_URLS: dict[str, list[str]] = {
    "new york": [
        "https://www.theinfatuation.com/new-york/guides/best-new-restaurants-nyc",
        "https://ny.eater.com/maps/best-new-restaurants-nyc",
    ],
    "los angeles": [
        "https://www.theinfatuation.com/los-angeles/guides/best-new-restaurants-la",
        "https://la.eater.com/maps/best-new-restaurants-los-angeles",
    ],
    "san francisco": [
        "https://www.theinfatuation.com/san-francisco/guides/best-new-restaurants-sf",
        "https://sf.eater.com/maps/best-new-restaurants-san-francisco",
    ],
    "chicago": [
        "https://www.theinfatuation.com/chicago/guides/best-new-restaurants-chicago",
        "https://chicago.eater.com/maps/best-new-restaurants-chicago",
    ],
    "miami": [
        "https://www.theinfatuation.com/miami/guides/best-new-restaurants-miami",
        "https://miami.eater.com/maps/best-new-restaurants-miami",
    ],
    "london": [
        "https://www.theinfatuation.com/london/guides/best-new-restaurants-london",
    ],
    "paris": [
        "https://www.theinfatuation.com/paris/guides/best-new-restaurants-paris",
    ],
}

# Interest categories that map well to curated dining/experience content
RELEVANT_INTERESTS: set[str] = {
    "Food", "Cooking", "Wine", "Coffee", "Baking",
    "Travel", "Art", "Music", "Theater", "Dancing",
    "Shopping", "Fashion", "Nature", "Photography",
}

# Category keywords → recommendation type mapping
EXPERIENCE_KEYWORDS: set[str] = {
    "museum", "gallery", "tour", "class", "workshop", "show",
    "concert", "festival", "market", "exhibit", "performance",
    "adventure", "activity", "hike", "walk", "bike",
}

DATE_KEYWORDS: set[str] = {
    "restaurant", "bar", "cafe", "bistro", "dinner", "brunch",
    "cocktail", "wine", "rooftop", "lounge", "dining", "eatery",
    "supper", "tasting", "omakase", "speakeasy",
}


# ======================================================================
# Cache
# ======================================================================

class _CacheEntry:
    """In-memory cache entry with TTL tracking."""

    __slots__ = ("results", "timestamp")

    def __init__(self, results: list[dict[str, Any]], timestamp: float) -> None:
        self.results = results
        self.timestamp = timestamp


# Module-level cache — shared across all CuratedContentService instances
_cache: dict[str, _CacheEntry] = {}


def _is_cache_valid(url: str) -> bool:
    """Check if cached entry exists and is within the 24-hour TTL."""
    entry = _cache.get(url)
    if entry is None:
        return False
    return (time.time() - entry.timestamp) < CACHE_TTL_SECONDS


def _get_cached(url: str) -> list[dict[str, Any]] | None:
    """Get cached results if the entry is valid, else None."""
    if _is_cache_valid(url):
        return _cache[url].results
    return None


def _set_cache(url: str, results: list[dict[str, Any]]) -> None:
    """Store results in cache with current timestamp."""
    _cache[url] = _CacheEntry(results=results, timestamp=time.time())


def clear_cache() -> None:
    """Clear all cached entries. Useful for testing."""
    _cache.clear()


def clear_expired_cache() -> None:
    """Remove cache entries older than CACHE_TTL_SECONDS."""
    now = time.time()
    expired = [
        url for url, entry in _cache.items()
        if (now - entry.timestamp) >= CACHE_TTL_SECONDS
    ]
    for url in expired:
        del _cache[url]


# ======================================================================
# Venue extraction from markdown
# ======================================================================

def _extract_venues_from_markdown(
    markdown: str,
    interests: Optional[list[str]] = None,
) -> list[dict[str, Any]]:
    """
    Parse markdown content from a city guide page to extract venue entries.

    Looks for common patterns in "best of" lists:
    - Markdown headers (## Venue Name or ### Venue Name)
    - Bold venue names (**Venue Name**)
    - Numbered lists (1. Venue Name)
    - Links with venue names ([Venue Name](url))

    Returns a list of raw venue dicts with name, description, and url fields.
    """
    if not markdown or not markdown.strip():
        return []

    venues: list[dict[str, Any]] = []
    seen_names: set[str] = set()

    # Pattern 1: Markdown headers followed by description text
    # Matches: ## Venue Name\nDescription text...
    header_pattern = re.compile(
        r"^#{2,4}\s+(.+?)(?:\s*\n)+(.+?)(?=\n#{2,4}\s|\n\n\n|\Z)",
        re.MULTILINE | re.DOTALL,
    )

    for match in header_pattern.finditer(markdown):
        name = match.group(1).strip()
        # Clean markdown formatting from name
        name = re.sub(r"[*_`\[\]]", "", name).strip()
        if not name or len(name) < 3 or len(name) > 100:
            continue

        desc_block = match.group(2).strip()
        # Take first 2 sentences as description
        description = _extract_description(desc_block)

        # Extract URL from the block if present
        url = _extract_url_from_block(desc_block) or _extract_url_from_block(
            match.group(0)
        )

        name_key = name.lower()
        if name_key not in seen_names:
            seen_names.add(name_key)
            venues.append({
                "name": name,
                "description": description,
                "url": url,
            })

    # Pattern 2: Bold venue names with surrounding text
    # Matches: **Venue Name** — description or **Venue Name**: description
    bold_pattern = re.compile(
        r"\*\*([^*]{3,80})\*\*\s*[—:\-–]\s*(.+?)(?:\n|$)",
    )

    for match in bold_pattern.finditer(markdown):
        name = match.group(1).strip()
        name = re.sub(r"[\[\]]", "", name).strip()
        if not name or len(name) < 3:
            continue

        description = _extract_description(match.group(2).strip())
        url = _extract_url_from_block(match.group(0))

        name_key = name.lower()
        if name_key not in seen_names:
            seen_names.add(name_key)
            venues.append({
                "name": name,
                "description": description,
                "url": url,
            })

    # Pattern 3: Numbered list entries with links
    # Matches: 1. [Venue Name](url) — description
    numbered_link_pattern = re.compile(
        r"^\d+\.\s+\[([^\]]{3,80})\]\(([^)]+)\)\s*[—:\-–]?\s*(.*?)(?:\n|$)",
        re.MULTILINE,
    )

    for match in numbered_link_pattern.finditer(markdown):
        name = match.group(1).strip()
        url = match.group(2).strip()
        description = _extract_description(match.group(3).strip())

        name_key = name.lower()
        if name_key not in seen_names:
            seen_names.add(name_key)
            venues.append({
                "name": name,
                "description": description,
                "url": url if url.startswith("http") else None,
            })

    # Filter by interest relevance if interests are provided
    if interests:
        venues = _filter_by_interests(venues, interests)

    return venues


def _extract_description(text: str) -> str | None:
    """Extract first 1-2 sentences as a clean description."""
    if not text:
        return None

    # Remove markdown formatting
    clean = re.sub(r"[*_`]", "", text)
    clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", clean)  # [text](url) → text
    clean = re.sub(r"\s+", " ", clean).strip()

    if not clean:
        return None

    # Take first 2 sentences (up to 300 chars)
    sentences = re.split(r"(?<=[.!?])\s+", clean)
    desc = ". ".join(sentences[:2])
    if len(desc) > 300:
        desc = desc[:297] + "..."

    return desc if desc else None


def _extract_url_from_block(text: str) -> str | None:
    """Extract the first HTTP(S) URL from a text block."""
    if not text:
        return None
    match = re.search(r"https?://[^\s)\]>\"']+", text)
    return match.group(0) if match else None


def _filter_by_interests(
    venues: list[dict[str, Any]],
    interests: list[str],
) -> list[dict[str, Any]]:
    """
    Filter venues to those relevant to provided interest categories.

    Uses keyword matching between venue name/description and interest names.
    If no venues match any interest, returns all venues (avoid empty results).
    """
    if not interests:
        return venues

    interest_lower = {i.lower() for i in interests}

    scored: list[tuple[dict[str, Any], int]] = []
    for venue in venues:
        score = 0
        text = (
            (venue.get("name") or "") + " " + (venue.get("description") or "")
        ).lower()

        for interest in interest_lower:
            if interest in text:
                score += 1

        scored.append((venue, score))

    # If at least some venues match, return only those with score > 0
    matched = [v for v, s in scored if s > 0]
    if matched:
        return matched

    # No interest matches — return all (better than empty)
    return venues


def _classify_venue_type(venue: dict[str, Any]) -> str:
    """
    Classify a venue as 'date' or 'experience' based on keywords.

    Defaults to 'experience' when no strong signal is found.
    """
    text = (
        (venue.get("name") or "") + " " + (venue.get("description") or "")
    ).lower()

    date_score = sum(1 for kw in DATE_KEYWORDS if kw in text)
    exp_score = sum(1 for kw in EXPERIENCE_KEYWORDS if kw in text)

    if date_score > exp_score:
        return "date"
    if exp_score > date_score:
        return "experience"
    # Default to "experience" for curated content (most city guides
    # feature unique experiences rather than standard restaurants)
    return "experience"


# ======================================================================
# CuratedContentService
# ======================================================================

class CuratedContentService:
    """Async service for crawling curated city guide content via Firecrawl."""

    async def search_curated_content(
        self,
        location: tuple[str, str, str],
        interests: Optional[list[str]] = None,
        limit: int = 10,
    ) -> list[dict[str, Any]]:
        """
        Search curated city guide content for a given location.

        Args:
            location: Tuple of (city, state, country_code).
            interests: Partner interest categories to filter by.
            limit: Max results to return.

        Returns:
            List of normalized dicts matching CandidateRecommendation schema.
            Returns [] on any error (missing API key, timeout, no guides, etc.).
        """
        if not is_firecrawl_configured():
            logger.warning(
                "Firecrawl API key not configured — skipping curated content"
            )
            return []

        city, state, country = location
        if not city:
            logger.warning("Empty city provided — skipping curated content")
            return []

        # Find guide URLs for this city
        guide_urls = _get_guide_urls(city)
        if not guide_urls:
            logger.info(
                "No city guide URLs configured for '%s' — skipping curated content",
                city,
            )
            return []

        # Scrape each URL (with caching)
        all_venues: list[dict[str, Any]] = []
        for url in guide_urls:
            # Check cache first
            cached = _get_cached(url)
            if cached is not None:
                logger.debug("Cache hit for %s (%d venues)", url, len(cached))
                all_venues.extend(cached)
                continue

            # Scrape via Firecrawl
            markdown = await self._scrape_url(url)
            if not markdown:
                continue

            # Extract venues
            venues = _extract_venues_from_markdown(markdown, interests)
            logger.info(
                "Extracted %d venues from %s", len(venues), url,
            )

            # Cache the raw extracted venues
            _set_cache(url, venues)
            all_venues.extend(venues)

        if not all_venues:
            return []

        # Normalize to CandidateRecommendation schema
        country_code = country or "US"
        normalized = [
            _normalize_venue(venue, city, state, country_code)
            for venue in all_venues
        ]

        return normalized[:limit]

    async def _scrape_url(self, url: str) -> str | None:
        """
        Scrape a URL via Firecrawl API and return markdown content.

        Uses POST https://api.firecrawl.dev/v1/scrape with exponential
        backoff on rate limits. Returns None on any error.
        """
        headers = {
            "Authorization": f"Bearer {FIRECRAWL_API_KEY}",
            "Content-Type": "application/json",
        }
        payload = {
            "url": url,
            "formats": ["markdown"],
        }

        async with httpx.AsyncClient(timeout=DEFAULT_TIMEOUT) as client:
            for retry in range(MAX_RETRIES):
                try:
                    response = await client.post(
                        FIRECRAWL_API_URL,
                        headers=headers,
                        json=payload,
                    )

                    if response.status_code == 429:
                        delay = 2**retry
                        logger.warning(
                            "Firecrawl API rate limited (429) for %s, retrying "
                            "in %ds (attempt %d/%d)",
                            url, delay, retry + 1, MAX_RETRIES,
                        )
                        await asyncio.sleep(delay)
                        continue

                    response.raise_for_status()
                    data = response.json()

                    # Firecrawl v1 response: {"success": true, "data": {"markdown": "..."}}
                    if data.get("success"):
                        return data.get("data", {}).get("markdown")

                    logger.warning(
                        "Firecrawl returned success=false for %s: %s",
                        url, data.get("error", "unknown"),
                    )
                    return None

                except httpx.TimeoutException:
                    logger.warning(
                        "Firecrawl API timeout for %s (attempt %d/%d)",
                        url, retry + 1, MAX_RETRIES,
                    )
                    if retry < MAX_RETRIES - 1:
                        await asyncio.sleep(1)
                    continue

                except httpx.HTTPStatusError as exc:
                    logger.error(
                        "Firecrawl API HTTP error %d for %s: %s",
                        exc.response.status_code, url, exc.response.text,
                    )
                    return None

                except httpx.HTTPError as exc:
                    logger.error(
                        "Firecrawl API request error for %s: %s", url, exc,
                    )
                    return None

        logger.warning(
            "Firecrawl API exhausted all %d retries for %s", MAX_RETRIES, url,
        )
        return None


# ======================================================================
# Helpers
# ======================================================================

def _get_guide_urls(city: str) -> list[str]:
    """
    Find guide URLs for a city. Case-insensitive with partial matching.

    Tries exact match first, then substring match on configured cities.
    """
    city_lower = city.lower().strip()
    if not city_lower:
        return []

    # Exact match
    if city_lower in CITY_GUIDE_URLS:
        return CITY_GUIDE_URLS[city_lower]

    # Partial match — city name is substring of a configured key
    for key, urls in CITY_GUIDE_URLS.items():
        if city_lower in key or key in city_lower:
            return urls

    return []


def _normalize_venue(
    venue: dict[str, Any],
    city: str,
    state: str,
    country_code: str,
) -> dict[str, Any]:
    """
    Convert extracted venue data to CandidateRecommendation-compatible dict.

    Reuses COUNTRY_CURRENCY_MAP from yelp.py for international currency
    detection to keep currency mapping consistent across integrations.
    """
    from app.services.integrations.yelp import COUNTRY_CURRENCY_MAP

    currency = COUNTRY_CURRENCY_MAP.get(country_code.upper(), "USD")
    rec_type = _classify_venue_type(venue)

    return {
        "id": str(uuid.uuid4()),
        "source": "firecrawl",
        "type": rec_type,
        "title": venue.get("name", "Unknown Venue"),
        "description": venue.get("description"),
        "price_cents": None,  # City guides rarely include prices
        "currency": currency,
        "external_url": venue.get("url") or "",
        "image_url": None,  # Firecrawl markdown doesn't reliably provide images
        "merchant_name": venue.get("name"),
        "location": {
            "city": city,
            "state": state,
            "country": country_code,
            "address": None,
        },
        "metadata": {
            "source_type": "curated_guide",
            "crawled_from": venue.get("url") or "",
            "venue_type": rec_type,
        },
    }
