"""
Prose cleanup helpers for AI-generated recommendation copy.

Three problems these fix, all visible to the user on the recommendation detail page:

1. Raw snake_case tag tokens (e.g. "quiet_luxury", "quality_time") leaking into
   prose because the model echoes the vibe/love-language tags it was given.
   `humanize_tags` deterministically rewrites those exact tokens to readable text.

2. Hard `[:N]` slicing cutting copy mid-word (e.g. "Pair wit"). `truncate_prose`
   trims at a sentence or word boundary and adds an ellipsis instead.

3. Copy that ends mid-sentence on a dangling word (e.g. "...works perfectly for a")
   because the model either ran past the token budget or simply trailed off.
   `is_incomplete_sentence` detects this and `trim_to_complete_sentence` trims back
   to the last complete sentence so the user never sees a half-finished thought.
"""

import re

__all__ = [
    "humanize_tags",
    "truncate_prose",
    "normalize_whitespace",
    "is_incomplete_sentence",
    "trim_to_complete_sentence",
]

# Function words that always require a following word — articles, coordinating
# conjunctions, and prepositions that take an object. Copy ending on one of these
# is trailing off mid-thought. Deliberately excludes words that can legitimately
# end a phrase ("in", "on", "you", "so", "this", "that", auxiliaries) so a real
# fragment like "a quiet night in" is not mistaken for a truncation.
_DANGLING_WORDS = frozenset(
    {
        "a", "an", "the", "and", "or", "but", "nor", "to", "with", "for", "of",
        "into", "from", "than", "as", "at", "by", "your", "their", "while", "if",
    }
)

# Sentence-ending punctuation. A finished sentence ends on one of these
# (optionally followed by a closing quote/paren).
_TERMINAL_PUNCT = frozenset({".", "!", "?", "…"})

# Trailing closing quotes/parens to peel off before judging the final word.
_TRAILING_WRAPPERS = "\"'”’)]"

# Matches an internal sentence boundary: terminal punctuation, an optional
# closing quote/paren, then whitespace or end-of-string.
_SENTENCE_BOUNDARY = re.compile(r"[.!?…]['\"”’)\]]?(?=\s|$)")


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


def _final_bare_word(text: str) -> str:
    """Return the last whitespace-delimited token, stripped of surrounding punctuation."""
    tokens = text.split()
    if not tokens:
        return ""
    # Strip punctuation from both ends so "a," / "(for" reduce to "a" / "for".
    return tokens[-1].strip(".,;:!?…\"'”’()[]—-").lower()


def is_incomplete_sentence(text: str) -> bool:
    """
    Return True when `text` ends mid-sentence rather than on a finished thought.

    After peeling off a trailing closing quote/paren, a string is incomplete when:
      - it does not end in sentence-ending punctuation (the model just stopped,
        e.g. "...works perfectly for a"), or
      - it ends with an ellipsis left by `truncate_prose` on a dangling
        article/conjunction/preposition (e.g. "...works perfectly for…").

    A string the model deliberately ended with "." / "!" / "?" is treated as
    complete even if its last word would otherwise look dangling ("a quiet night
    in.", "ready for this?"). Empty/whitespace-only input is not "incomplete" —
    emptiness is handled by callers.
    """
    if not text or not text.strip():
        return False

    stripped = text.rstrip()
    # Peel one trailing closing quote/paren so the judgment is on the word itself.
    if stripped and stripped[-1] in _TRAILING_WRAPPERS:
        stripped = stripped[:-1].rstrip()
    if not stripped:
        return False

    last = stripped[-1]
    if last not in _TERMINAL_PUNCT:
        return True
    # A model-written sentence end is complete; only an ellipsis trailing a
    # dangling word signals a truncation artifact.
    if last == "…":
        return _final_bare_word(stripped) in _DANGLING_WORDS
    return False


def trim_to_complete_sentence(text: str) -> str:
    """
    Trim copy that ends mid-sentence back to its last complete sentence.

    Complementary to `truncate_prose`: that helper owns *length*, this one owns
    *grammatical completeness*. Already-complete text is returned unchanged (fast
    path). Otherwise the string is sliced back to the last internal sentence
    boundary. If no earlier complete sentence exists (a single run-on fragment),
    a trailing dangling word is dropped instead. Never returns an empty string
    for non-empty input.

    Note: a "boundary" is terminal punctuation followed by whitespace/end, so an
    abbreviation like "e.g." mid-string could be treated as a sentence end — but
    the fast path means this only ever runs on already-incomplete copy, where the
    worst case is a slightly shorter (still complete) result.
    """
    if not text:
        return text
    stripped = text.strip()
    if not is_incomplete_sentence(stripped):
        return stripped

    # Walk sentence boundaries from last to first and return the longest prefix
    # that is itself complete. (The trailing boundary may be a dangling "…" left
    # by truncate_prose, which is why we can't just take the last match.)
    for match in reversed(list(_SENTENCE_BOUNDARY.finditer(stripped))):
        candidate = stripped[: match.end()].rstrip()
        if candidate and not is_incomplete_sentence(candidate):
            return candidate

    # No earlier complete sentence — strip trailing dangling words (e.g. drop both
    # "for" and "a" from "...works perfectly for a").
    tokens = stripped.split()
    while tokens and _final_bare_word(" ".join(tokens)) in _DANGLING_WORDS:
        tokens.pop()
    result = " ".join(tokens).rstrip(" ,;:—-")
    return result or stripped
