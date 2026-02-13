"""
Tests for Universal Links — AASA Endpoint and Web Fallback (Step 9.1)

Validates that the Apple App Site Association file is served correctly
at both /.well-known/apple-app-site-association and /apple-app-site-association,
and that the web fallback page renders for recommendation deep links.

Prerequisites:
- No external credentials required (all endpoints are public)
- Uses FastAPI TestClient (no running server needed)
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# --- Constants ---

EXPECTED_APP_ID = "VN5G3R8J23.com.ronniejay.knot"
WELL_KNOWN_PATH = "/.well-known/apple-app-site-association"
ROOT_PATH = "/apple-app-site-association"


# ---------------------------------------------------------------------------
# AASA Endpoint Tests
# ---------------------------------------------------------------------------


class TestAASAWellKnownEndpoint:
    """Tests for GET /.well-known/apple-app-site-association."""

    def test_returns_200(self):
        """AASA endpoint at /.well-known/ path returns 200 OK."""
        resp = client.get(WELL_KNOWN_PATH)
        assert resp.status_code == 200

    def test_content_type_is_json(self):
        """AASA response Content-Type must be application/json."""
        resp = client.get(WELL_KNOWN_PATH)
        assert "application/json" in resp.headers["content-type"]

    def test_contains_applinks_key(self):
        """AASA JSON body must contain the 'applinks' top-level key."""
        resp = client.get(WELL_KNOWN_PATH)
        data = resp.json()
        assert "applinks" in data

    def test_contains_correct_app_id(self):
        """AASA appIDs must include the Knot app's Team ID + Bundle ID."""
        resp = client.get(WELL_KNOWN_PATH)
        data = resp.json()
        app_ids = data["applinks"]["details"][0]["appIDs"]
        assert EXPECTED_APP_ID in app_ids

    def test_contains_recommendation_pattern(self):
        """AASA components must include a /recommendation/* URL pattern."""
        resp = client.get(WELL_KNOWN_PATH)
        data = resp.json()
        components = data["applinks"]["details"][0]["components"]
        patterns = [c["/"] for c in components if "/" in c]
        assert "/recommendation/*" in patterns

    def test_contains_webcredentials(self):
        """AASA must include webcredentials section with the app ID."""
        resp = client.get(WELL_KNOWN_PATH)
        data = resp.json()
        assert "webcredentials" in data
        assert EXPECTED_APP_ID in data["webcredentials"]["apps"]

    def test_no_auth_required(self):
        """AASA endpoint must be accessible without Authorization header."""
        resp = client.get(WELL_KNOWN_PATH)
        assert resp.status_code == 200


class TestAASARootEndpoint:
    """Tests for GET /apple-app-site-association (legacy root path)."""

    def test_root_returns_200(self):
        """AASA at root path returns 200 OK."""
        resp = client.get(ROOT_PATH)
        assert resp.status_code == 200

    def test_root_content_type_is_json(self):
        """AASA at root path has application/json Content-Type."""
        resp = client.get(ROOT_PATH)
        assert "application/json" in resp.headers["content-type"]

    def test_root_matches_well_known(self):
        """Both AASA endpoints must return identical content."""
        resp_wk = client.get(WELL_KNOWN_PATH)
        resp_root = client.get(ROOT_PATH)
        assert resp_wk.json() == resp_root.json()


# ---------------------------------------------------------------------------
# Web Fallback Tests
# ---------------------------------------------------------------------------


class TestWebFallback:
    """Tests for GET /recommendation/{recommendation_id} web fallback."""

    def test_returns_200(self):
        """Web fallback returns 200 for a valid recommendation path."""
        resp = client.get("/recommendation/abc-123")
        assert resp.status_code == 200

    def test_returns_html(self):
        """Web fallback response Content-Type is text/html."""
        resp = client.get("/recommendation/test-id")
        assert "text/html" in resp.headers["content-type"]

    def test_contains_knot_branding(self):
        """Web fallback HTML must contain 'Knot' branding text."""
        resp = client.get("/recommendation/test-id")
        assert "Knot" in resp.text

    def test_contains_app_store_placeholder(self):
        """Web fallback HTML must contain the App Store placeholder text."""
        resp = client.get("/recommendation/test-id")
        assert "Coming Soon on the App Store" in resp.text

    def test_works_with_uuid_format(self):
        """Web fallback handles UUID-formatted recommendation IDs."""
        resp = client.get("/recommendation/550e8400-e29b-41d4-a716-446655440000")
        assert resp.status_code == 200
        assert "550e8400" in resp.text

    def test_works_with_arbitrary_id(self):
        """Web fallback handles non-UUID recommendation IDs gracefully."""
        resp = client.get("/recommendation/some-random-string")
        assert resp.status_code == 200

    def test_contains_recommendation_ref(self):
        """Web fallback HTML includes a truncated reference to the recommendation ID."""
        test_id = "abcdef12-3456-7890-abcd-ef1234567890"
        resp = client.get(f"/recommendation/{test_id}")
        assert "abcdef12" in resp.text


# ---------------------------------------------------------------------------
# Module Import Tests
# ---------------------------------------------------------------------------


class TestModuleImports:
    """Tests verifying the deeplinks module is properly importable and registered."""

    def test_deeplinks_router_importable(self):
        """The deeplinks router can be imported from app.api.deeplinks."""
        from app.api.deeplinks import router
        assert router is not None

    def test_aasa_content_importable(self):
        """The AASA_CONTENT dict can be imported."""
        from app.api.deeplinks import AASA_CONTENT
        assert isinstance(AASA_CONTENT, dict)
        assert "applinks" in AASA_CONTENT

    def test_deeplinks_router_registered_in_app(self):
        """The deeplinks router is registered and reachable via the main app."""
        resp = client.get(WELL_KNOWN_PATH)
        assert resp.status_code == 200

    def test_config_app_domain_importable(self):
        """The APP_DOMAIN config variable can be imported."""
        from app.core.config import APP_DOMAIN
        assert isinstance(APP_DOMAIN, str)
        assert len(APP_DOMAIN) > 0
