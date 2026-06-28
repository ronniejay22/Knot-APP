"""
Tests for prose cleanup helpers used on AI-generated recommendation copy.

Run with: pytest tests/test_text_cleanup.py -v
"""

from app.services.text_cleanup import (
    humanize_tags,
    is_incomplete_sentence,
    normalize_whitespace,
    trim_to_complete_sentence,
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


class TestIsIncompleteSentence:
    # The exact string the user saw cut off in the recommendation detail view.
    REPORTED = "It's intimate, low-pressure, and works perfectly for a"

    def test_detects_reported_dangling_article(self):
        assert is_incomplete_sentence(self.REPORTED) is True

    def test_detects_dangling_connectives(self):
        for tail in [
            "We can plan slow weekends and",
            "Curl up for a quiet night with",
            "It honors how they gravitate toward the",
            "A keepsake made just for",
            "It becomes a keepsake of",
            "Lean the evening into",
        ]:
            assert is_incomplete_sentence(tail) is True, tail

    def test_no_terminal_punctuation_is_incomplete(self):
        assert is_incomplete_sentence("She loves pottery and quiet evenings") is True

    def test_complete_sentence_is_false(self):
        assert is_incomplete_sentence("She loves pottery and quiet evenings.") is False

    def test_complete_with_trailing_quote_is_false(self):
        assert is_incomplete_sentence('He said "let\'s go."') is False

    def test_complete_multi_sentence_is_false(self):
        text = "It's intimate and low-pressure. It works perfectly for a quiet night in."
        assert is_incomplete_sentence(text) is False

    def test_question_and_exclamation_terminal_are_false(self):
        assert is_incomplete_sentence("Ready for this?") is False
        assert is_incomplete_sentence("What a night!") is False

    def test_ellipsis_terminal_but_dangling_word_is_incomplete(self):
        # truncate_prose can leave "...for…" — terminal char is fine but the
        # final word is dangling, so this is still mid-thought.
        assert is_incomplete_sentence("works perfectly for…") is True

    def test_empty_is_false(self):
        assert is_incomplete_sentence("") is False
        assert is_incomplete_sentence("   ") is False


class TestTrimToCompleteSentence:
    def test_trims_reported_dangling_tail(self):
        bad = (
            "This is pure acts of service and a great fit. "
            "It's intimate, low-pressure, and works perfectly for a"
        )
        out = trim_to_complete_sentence(bad)
        assert out == "This is pure acts of service and a great fit."
        assert not is_incomplete_sentence(out)

    def test_complete_text_unchanged(self):
        assert trim_to_complete_sentence("All done here.") == "All done here."

    def test_single_incomplete_fragment_strips_dangling_word(self):
        out = trim_to_complete_sentence("works perfectly for a")
        assert out != ""
        assert "for a" not in out
        assert not out.endswith("for")

    def test_never_returns_empty_for_nonempty_input(self):
        assert trim_to_complete_sentence("a") != ""

    def test_keeps_fragment_ending_in_legit_final_word(self):
        # "in" can validly end a phrase, so an unpunctuated fragment ending in it
        # must not be clipped (guards the narrowed dangling-word set).
        assert trim_to_complete_sentence("A romantic night in") == "A romantic night in"
        assert trim_to_complete_sentence("I love you") == "I love you"

    def test_empty_unchanged(self):
        assert trim_to_complete_sentence("") == ""

    def test_trims_truncate_style_dangling_ellipsis(self):
        # Mimics truncate_prose output that cut on a dangling word: trim repairs
        # back to the prior complete sentence.
        out = trim_to_complete_sentence("First sentence is complete. It works perfectly for…")
        assert out == "First sentence is complete."

    def test_composes_with_truncate_prose_never_incomplete(self):
        # truncate_prose enforces length; trim_to_complete_sentence guarantees the
        # composed result never ends mid-sentence, whatever the cut landed on.
        long = "First sentence is complete. " + "the evening drifts gently into a " * 40
        assert len(long) > 600
        out = trim_to_complete_sentence(truncate_prose(long, 600))
        assert not is_incomplete_sentence(out)
        assert out  # never empty


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
