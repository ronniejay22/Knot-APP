"""Root pytest configuration for the Knot backend.

Test tiering: offline-by-default, live integration opt-in.

The backend's ``.env`` carries real credentials for every external service
(Supabase, Anthropic, Brave, Firecrawl, Yelp, Amazon, Ticketmaster, Shopify,
Vertex AI, …). Many tests are guarded by a ``skipif`` that fires only when the
relevant creds are *absent* — e.g.::

    requires_supabase = pytest.mark.skipif(
        not _supabase_configured(),
        reason="Supabase credentials not configured in .env",
    )

Because the creds ARE present, those guards do NOT fire, so a bare ``pytest``
run makes real HTTP calls (creating/deleting live Supabase auth users, waiting
on DB triggers, live Yelp/Amazon/Ticketmaster/Claude calls). With no per-call
timeout, a single slow/blocked request can hang the whole run.

To keep the default suite fast, deterministic, and offline, this module gates
those live tests at the **item** level: any test carrying a ``skipif`` guard
whose reason says "... not configured ..." (the established convention shared by
every service guard) is tagged ``integration`` and skipped — unless the run
opts in via ``--integration`` or ``KNOT_RUN_INTEGRATION=1`` (the env var is used
by the agent /ship-pr workflow).

Item-level gating matters: the live modules also contain pure offline/mocked
unit tests (Pydantic models, helpers) that carry no such guard — those keep
running on the default suite. New live tests following the same guard convention
are covered automatically with no further wiring.

Run the offline suite:          pytest
Run the live integration suite:  pytest --integration   (or KNOT_RUN_INTEGRATION=1 pytest)
"""

import os

import pytest

# Every live-service guard's reason follows the convention "<service> ... not
# configured in .env". Matching this substring identifies a cred-gated live test
# without coupling to any individual service.
_LIVE_GUARD_HINT = "not configured"


def pytest_addoption(parser):
    parser.addoption(
        "--integration",
        action="store_true",
        default=False,
        help="Run live integration tests that hit external services "
        "(Supabase/Yelp/Amazon/Claude/etc.). Off by default.",
    )


def _integration_enabled(config) -> bool:
    if config.getoption("--integration"):
        return True
    return os.getenv("KNOT_RUN_INTEGRATION", "").strip().lower() in {"1", "true", "yes"}


def _is_live_item(item) -> bool:
    """True if the item is gated by a live-service cred guard (skipif "... not configured ...").

    Walks the item's own, class-, and module-level markers, so a guard applied to
    a test class or via module-level ``pytestmark`` is detected for each test in it.
    """
    for marker in item.iter_markers(name="skipif"):
        reason = marker.kwargs.get("reason") or ""
        if _LIVE_GUARD_HINT in reason.lower():
            return True
    return False


def pytest_collection_modifyitems(config, items):
    enabled = _integration_enabled(config)
    skip_integration = pytest.mark.skip(
        reason="live integration test; run with --integration or KNOT_RUN_INTEGRATION=1"
    )
    for item in items:
        if _is_live_item(item):
            item.add_marker(pytest.mark.integration)
            if not enabled:
                item.add_marker(skip_integration)
