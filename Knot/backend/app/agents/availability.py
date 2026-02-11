"""
Availability Verification Node — LangGraph node for verifying recommendation URLs.

Checks that the 3 selected recommendations have valid, reachable external URLs.
If a URL is unavailable (non-200 response, timeout, connection error), the
recommendation is replaced with the next-best candidate from the filtered pool.

Verification strategy:
- Sends an async HEAD request to each external URL (lighter than GET).
- Falls back to GET if HEAD returns 405 Method Not Allowed.
- Uses a short timeout (5s) to avoid blocking the pipeline.
- Retries replacement up to 3 times from the backup pool before accepting
  a partial result set.

Step 5.7: Create Availability Verification Node
"""

import logging
from typing import Any

import httpx

from app.agents.state import CandidateRecommendation, RecommendationState

logger = logging.getLogger(__name__)

# --- Constants ---
REQUEST_TIMEOUT = 5.0  # seconds per URL check
MAX_REPLACEMENT_ATTEMPTS = 3  # max times to try replacing a single slot
VALID_STATUS_RANGE = range(200, 400)  # 2xx and 3xx are considered available


# ======================================================================
# URL verification
# ======================================================================

async def _check_url(url: str, client: httpx.AsyncClient) -> bool:
    """
    Check if a URL is reachable and returns a valid HTTP status.

    Tries HEAD first (lightweight). If HEAD returns 405 (Method Not Allowed),
    falls back to GET. Any 2xx or 3xx status is considered valid.

    Args:
        url: The external URL to check.
        client: An httpx.AsyncClient instance for making requests.

    Returns:
        True if the URL is reachable with a valid status, False otherwise.
    """
    try:
        response = await client.head(url, follow_redirects=True)
        if response.status_code == 405:
            # HEAD not allowed — try GET
            response = await client.get(url, follow_redirects=True)
        return response.status_code in VALID_STATUS_RANGE
    except (httpx.TimeoutException, httpx.ConnectError, httpx.HTTPError) as exc:
        logger.warning("URL check failed for %s: %s", url, exc)
        return False


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
    LangGraph node: Verify that the 3 selected recommendations have valid URLs.

    Processing:
    1. Takes final_three from the state (3 selected recommendations)
    2. For each, sends a HEAD/GET request to the external URL
    3. If a URL is unreachable or returns an error status, replaces the
       recommendation with the next-best candidate from filtered_recommendations
    4. Verifies replacement URLs as well (up to MAX_REPLACEMENT_ATTEMPTS per slot)
    5. Returns the verified list (may be fewer than 3 if no valid replacements found)

    Args:
        state: The current RecommendationState with final_three and
               filtered_recommendations (backup pool).

    Returns:
        A dict with "final_three" key containing the verified recommendations.
    """
    selected = list(state.final_three)
    filtered_pool = list(state.filtered_recommendations)

    logger.info(
        "Verifying availability for %d recommendations (backup pool: %d)",
        len(selected), len(filtered_pool),
    )

    if not selected:
        logger.warning("No recommendations to verify")
        return {"final_three": []}

    # Track all IDs we've used or tried (to avoid re-checking the same candidate)
    used_ids: set[str] = {c.id for c in selected}

    verified: list[CandidateRecommendation] = []

    async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
        for i, candidate in enumerate(selected):
            # Check the current candidate's URL
            is_available = await _check_url(candidate.external_url, client)

            if is_available:
                logger.debug(
                    "Slot %d: '%s' verified (URL: %s)",
                    i + 1, candidate.title, candidate.external_url,
                )
                verified.append(candidate)
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

    logger.info(
        "Verification complete: %d/%d recommendations verified — %s",
        len(verified), len(selected),
        [c.title for c in verified],
    )

    if len(verified) < len(selected):
        logger.warning(
            "Partial results: only %d of %d recommendations have valid URLs",
            len(verified), len(selected),
        )

    return {"final_three": verified}
