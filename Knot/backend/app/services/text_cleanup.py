"""
Prose cleanup helpers for AI-generated recommendation copy.

Two problems these fix, both visible to the user on the recommendation detail page:

1. Raw snake_case tag tokens (e.g. "quiet_luxury", "quality_time") leaking into
   prose because the model echoes the vibe/love-language tags it was given.
   `humanize_tags` deterministically rewrites those exact tokens to readable text.

2. Hard `[:N]` slicing cutting copy mid-word (e.g. "Pair wit"). `truncate_prose`
   trims at a sentence or word boundary and adds an ellipsis instead.
"""

import re

__all__ = ["humanize_tags", "truncate_prose", "normalize_whitespace"]


def humanize_tags(text: str, tags: list[str]) -> str:
    """
    Replace raw snake_case tag tokens that leaked into prose with readable text.

    Only the provided tags (the partner's vibes + love languages) are rewritten,
    so legitimate prose is never altered. Matching is case-insensitive and
    word-bounded, e.g. "quiet_luxury" -> "quiet luxury", "street_urban" ->
    "street urban".
    """
    if not text:
        return text
    for tag in tags:
        if not tag or "_" not in tag:
            continue
        readable = tag.replace("_", " ")
        text = re.sub(rf"\b{re.escape(tag)}\b", readable, text, flags=re.IGNORECASE)
    return text


def truncate_prose(text: str, limit: int) -> str:
    """
    Truncate to roughly `limit` characters without cutting mid-word.

    Prefers ending on a sentence boundary when one falls reasonably late in the
    window; otherwise trims at the last word boundary and appends an ellipsis.
    The trimmed result is at most `limit` characters, plus the one-character
    ellipsis when a trim occurs — so it is not intended for a hard byte cap.
    """
    if not text:
        return text
    text = text.strip()
    if len(text) <= limit:
        return text

    window = text[:limit]
    # Prefer a clean sentence end if it's not too early in the window.
    sentence_end = max(window.rfind(". "), window.rfind("! "), window.rfind("? "))
    if sentence_end >= int(limit * 0.6):
        return window[: sentence_end + 1].strip()

    # Otherwise cut at the last whole word and signal the trim with an ellipsis.
    last_space = window.rfind(" ")
    if last_space > 0:
        window = window[:last_space]
    return window.rstrip(" ,;:.—-") + "…"


def normalize_whitespace(text: str) -> str:
    """
    Collapse runs of whitespace into single spaces and trim the ends.

    Useful for tidying AI-generated copy before display, e.g.
    "  too   many\n spaces " -> "too many spaces".
    """
    if not text:
        return text
    return re.sub(r"\s+", " ", text).strip()
