"""
Pytest configuration for the Knot backend test suite.

Adds an **offline mode** — enabled with ``pytest --offline`` or by exporting
``KNOT_OFFLINE_TESTS=1`` — that blanks every external-service credential before
the test modules are collected. The suite already gates its integration tests
behind ``requires_*`` / ``is_*_configured()`` checks that look at the
credentials in ``app.core.config``; when a checkout carries a populated ``.env``
(as git worktrees do — ``.worktreeinclude`` copies ``backend/.env``) those
checks all report "configured", so the integration tests run against the live
Supabase / Claude / Firecrawl / QStash / Yelp / etc. services. That makes a
plain ``pytest`` run slow and prone to hanging on network calls.

In offline mode we set those credential constants to empty strings, so every
``is_*_configured()`` returns ``False`` and the ``requires_*`` skip-guards fire,
leaving only the pure unit tests to run — fast and with no network.

Usage:
    pytest --offline                 # one-off
    KNOT_OFFLINE_TESTS=1 pytest      # e.g. in CI or a worktree
"""

import os

# Credential constants in app.core.config that gate the integration tests.
# Blanking them makes every is_*_configured() / requires_* guard report
# "not configured", so the credential-gated tests skip instead of calling out.
_CREDENTIAL_CONSTANTS = (
    "SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY",
    "GOOGLE_CLOUD_PROJECT", "GOOGLE_APPLICATION_CREDENTIALS",
    "UPSTASH_QSTASH_TOKEN", "UPSTASH_QSTASH_URL",
    "QSTASH_CURRENT_SIGNING_KEY", "QSTASH_NEXT_SIGNING_KEY", "WEBHOOK_BASE_URL",
    "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_AUTH_KEY_PATH", "APNS_BUNDLE_ID",
    "YELP_API_KEY", "TICKETMASTER_API_KEY",
    "AMAZON_ACCESS_KEY", "AMAZON_SECRET_KEY", "AMAZON_ASSOCIATE_TAG",
    "SHOPIFY_STOREFRONT_TOKEN", "SHOPIFY_STORE_DOMAIN", "OPENTABLE_AFFILIATE_ID",
    "FIRECRAWL_API_KEY", "ANTHROPIC_API_KEY", "BRAVE_SEARCH_API_KEY",
)


def pytest_addoption(parser):
    parser.addoption(
        "--offline",
        action="store_true",
        default=False,
        help="Skip integration tests that require live external-service "
             "credentials (also enabled via KNOT_OFFLINE_TESTS=1). Runs only "
             "the pure unit tests — fast and network-free.",
    )


def _offline_requested(config) -> bool:
    return bool(config.getoption("--offline")) or os.getenv("KNOT_OFFLINE_TESTS") == "1"


def pytest_configure(config):
    """Blank external credentials when offline mode is requested.

    Runs after option parsing but before collection imports the test modules,
    so both live ``is_*_configured()`` reads and the ``from app.core.config
    import SUPABASE_URL`` copies taken at a test module's import time observe
    the empty values and skip.
    """
    if not _offline_requested(config):
        return

    import app.core.config as cfg

    for name in _CREDENTIAL_CONSTANTS:
        os.environ.pop(name, None)
        if hasattr(cfg, name):
            setattr(cfg, name, "")


def pytest_report_header(config):
    if _offline_requested(config):
        return (
            "knot: OFFLINE mode — external credentials blanked; integration "
            "tests requiring live services are skipped"
        )
