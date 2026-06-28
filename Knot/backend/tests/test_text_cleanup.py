"""
Tests for prose cleanup helpers used on AI-generated recommendation copy.

Run with: pytest tests/test_text_cleanup.py -v
"""

from app.services.text_cleanup import (
    humanize_tags,
    normalize_whitespace,
    truncate_prose,
)


class TestHumanizeTags:
    def test_replaces_known_snake_case_tags(self):
        tags = ["quiet_luxury", "street_urban", "quality_time"]
        text = "honoring their quiet_luxury and street_urban vibe and quality_time"
        out = humanize_tags(text, tags)
        assert out == "honoring their quiet luxury and street urban vibe and quality time"

    def test_case_insensitive(self):
        out = humanize_tags("Their Quiet_Luxury aesthetic", ["quiet_luxury"])
        assert out == "Their quiet luxury aesthetic"

    def test_only_touches_provided_tags(self):
        # A snake_case token that isn't a provided tag is left alone.
        out = humanize_tags("the file_name stayed", ["quiet_luxury"])
        assert out == "the file_name stayed"

    def test_ignores_tags_without_underscore(self):
        out = humanize_tags("a romantic evening", ["romantic"])
        assert out == "a romantic evening"

    def test_word_bounded(self):
        # Should not rewrite a substring inside a larger token.
        out = humanize_tags("quiet_luxuryish", ["quiet_luxury"])
        assert out == "quiet_luxuryish"

    def test_empty_text(self):
        assert humanize_tags("", ["quiet_luxury"]) == ""


class TestTruncateProse:
    def test_short_text_unchanged(self):
        assert truncate_prose("hello world", 100) == "hello world"

    def test_prefers_sentence_boundary(self):
        # Sentence end falls late in the window (past 60%), so it's used cleanly.
        text = "A" * 40 + ". " + "B" * 40
        out = truncate_prose(text, 60)
        assert out == "A" * 40 + "."
        assert not out.endswith("…")

    def test_early_sentence_end_keeps_more_content(self):
        # A sentence ending very early is skipped in favor of a fuller word-boundary cut.
        text = "Hi there. " + "word " * 50
        out = truncate_prose(text, 60)
        assert out.endswith("…")
        assert len(out) <= 61

    def test_word_boundary_with_ellipsis(self):
        text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda"
        out = truncate_prose(text, 20)
        assert out.endswith("…")
        assert len(out) <= 21
        # never cut mid-word
        assert "kapp…" not in out and "lambd…" not in out

    def test_no_mid_word_cut(self):
        out = truncate_prose("supercalifragilistic " * 10, 30)
        assert "supercalifragilisti…" not in out
        assert out.endswith("…")

    def test_empty(self):
        assert truncate_prose("", 10) == ""


class TestNormalizeWhitespace:
    def test_collapses_internal_runs(self):
        out = normalize_whitespace("too   many\t\nspaces")
        assert out == "too many spaces"

    def test_trims_ends(self):
        assert normalize_whitespace("  hello world  ") == "hello world"

    def test_already_clean_unchanged(self):
        assert normalize_whitespace("clean text") == "clean text"

    def test_empty_text(self):
        assert normalize_whitespace("") == ""
