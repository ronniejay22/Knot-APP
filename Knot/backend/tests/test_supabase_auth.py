"""
Step 0.7 Verification: Supabase Auth with Apple Sign-In

Tests that:
1. Supabase GoTrue auth service is reachable
2. Apple Sign-In provider is enabled in the Supabase project
3. Auth settings are correctly configured for the Knot app

Prerequisites:
- Complete Step 0.6 (Supabase project + credentials in .env)
- Enable Apple Sign-In in Supabase dashboard:
    1. Go to Authentication > Providers > Apple
    2. Toggle "Enable Apple provider" ON
    3. Fill in Apple Developer credentials:
       - Services ID (from Apple Developer > Certificates, Identifiers & Profiles > Services IDs)
       - Team ID (from Apple Developer > Membership > Team ID)
       - Key ID (from Apple Developer > Keys > Sign in with Apple key)
       - Private Key (.p8 file contents from the key download)
    4. Copy the "Callback URL" shown in Supabase and add it to your
       Apple Developer Services ID as a "Return URL"

Run with: pytest tests/test_supabase_auth.py -v
"""

import pytest
import httpx
from app.core.config import SUPABASE_URL, SUPABASE_ANON_KEY


def _supabase_configured() -> bool:
    """Return True if Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


def _get_auth_settings() -> dict:
    """Fetch the GoTrue auth settings from Supabase."""
    resp = httpx.get(
        f"{SUPABASE_URL}/auth/v1/settings",
        headers={"apikey": SUPABASE_ANON_KEY},
    )
    resp.raise_for_status()
    return resp.json()


# ---------------------------------------------------------------------------
# 1. Auth service reachability
# ---------------------------------------------------------------------------

@requires_supabase
class TestAuthServiceReachable:
    """Verify the Supabase GoTrue auth service is accessible."""

    def test_auth_settings_endpoint_returns_200(self):
        """The /auth/v1/settings endpoint should return 200 with provider list."""
        resp = httpx.get(
            f"{SUPABASE_URL}/auth/v1/settings",
            headers={"apikey": SUPABASE_ANON_KEY},
        )
        assert resp.status_code == 200, (
            f"Auth settings endpoint returned {resp.status_code}. "
            "Verify SUPABASE_URL and SUPABASE_ANON_KEY in .env."
        )
        data = resp.json()
        assert "external" in data, (
            "Auth settings response missing 'external' key. "
            "Unexpected response format from GoTrue."
        )
        print(f"  Auth settings endpoint reachable (HTTP 200)")

    def test_auth_health_endpoint(self):
        """The /auth/v1/health endpoint should return healthy status."""
        resp = httpx.get(
            f"{SUPABASE_URL}/auth/v1/health",
            headers={"apikey": SUPABASE_ANON_KEY},
        )
        # GoTrue health returns 200 if healthy
        assert resp.status_code == 200, (
            f"Auth health endpoint returned {resp.status_code}."
        )
        print(f"  Auth health endpoint OK")

    def test_email_provider_enabled_by_default(self):
        """Email provider should be enabled by default in new Supabase projects."""
        settings = _get_auth_settings()
        assert settings["external"]["email"] is True, (
            "Email provider is disabled. This should be enabled by default."
        )
        print(f"  Email provider: enabled (default)")


# ---------------------------------------------------------------------------
# 2. Apple Sign-In provider configuration
# ---------------------------------------------------------------------------

@requires_supabase
class TestAppleSignInProvider:
    """Verify Apple Sign-In is enabled and configured in Supabase Auth."""

    def test_apple_provider_is_enabled(self):
        """
        Apple provider must be enabled in Supabase Auth settings.

        If this test fails, go to:
            Supabase Dashboard → Authentication → Providers → Apple
        Toggle "Enable Apple provider" ON and fill in your Apple Developer credentials:
            - Services ID
            - Team ID
            - Key ID
            - Private Key (.p8 contents)
        """
        settings = _get_auth_settings()
        assert settings["external"]["apple"] is True, (
            "Apple Sign-In provider is NOT enabled in Supabase. "
            "Go to Supabase Dashboard → Authentication → Providers → Apple "
            "and toggle it ON with your Apple Developer credentials."
        )
        print(f"  Apple provider: enabled")

    def test_signup_is_not_disabled(self):
        """New user signup must be allowed for onboarding."""
        settings = _get_auth_settings()
        assert settings["disable_signup"] is False, (
            "Signup is disabled in Supabase Auth. "
            "Go to Authentication → Settings and ensure 'Allow new users to sign up' is ON."
        )
        print(f"  Signup: enabled")

    def test_apple_native_auth_endpoint_accessible(self):
        """
        Verify the token-based auth endpoint accepts Apple as a provider.

        Knot uses NATIVE iOS Sign in with Apple (not the web OAuth redirect flow).
        The native flow uses signInWithIdToken, which hits /auth/v1/token?grant_type=id_token.
        We verify this endpoint exists and recognizes Apple as a valid provider.

        Note: The web OAuth flow (/auth/v1/authorize?provider=apple) requires an
        OAuth Secret Key, which is intentionally not configured since Knot only
        uses native iOS auth. This test validates the native path instead.
        """
        # The native auth endpoint accepts id_token grants.
        # We send an invalid token — we just want to confirm the endpoint
        # recognizes Apple and doesn't say "unsupported provider".
        resp = httpx.post(
            f"{SUPABASE_URL}/auth/v1/token?grant_type=id_token",
            headers={
                "apikey": SUPABASE_ANON_KEY,
                "Content-Type": "application/json",
            },
            json={
                "provider": "apple",
                "id_token": "invalid_test_token",
            },
        )
        # We expect a 400 because the token is invalid,
        # but the error should be about the TOKEN, not about the PROVIDER.
        # If Apple weren't enabled, we'd get "unsupported provider".
        assert resp.status_code == 400 or resp.status_code == 401, (
            f"Unexpected status code: {resp.status_code}"
        )
        error_text = resp.text.lower()
        assert "unsupported provider" not in error_text, (
            "Apple is not recognized as a provider for native auth. "
            "Verify Apple is enabled in Supabase Dashboard → Authentication → Providers."
        )
        print(f"  Native Apple auth endpoint: accessible (provider recognized)")
