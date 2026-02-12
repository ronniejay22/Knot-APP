"""
Step 7.5 Verification: APNs Push Notification Service

Tests that:
1. build_notification_payload produces correct title, body, category, sound, and custom data
2. _generate_apns_token creates ES256-signed JWTs with correct headers and claims
3. _generate_apns_token caches tokens and refreshes after expiry
4. send_push_notification uses HTTP/2, correct headers, and handles success/failure
5. deliver_push_notification looks up device tokens and handles missing tokens gracefully
6. The notification webhook integrates push delivery after recommendation generation
7. Push failures do not block the notification from being marked as 'sent'

Prerequisites:
- Complete Steps 0.4-0.5 (backend setup + dependencies)
- Complete Steps 7.1-7.4 (QStash webhook, scheduling, processing, device token)
- httpx[http2], cryptography, PyJWT installed

Run with: pytest tests/test_apns_push_service.py -v
"""

import hashlib
import json
import time
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from fastapi.testclient import TestClient

from app.agents.state import (
    CandidateRecommendation,
    MilestoneContext,
    VaultBudget,
    VaultData,
)
from app.core.config import (
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
)
from app.main import app
from app.services.apns import (
    APNS_PRODUCTION_URL,
    APNS_SANDBOX_URL,
    TOKEN_REFRESH_INTERVAL,
    build_notification_payload,
)


# ---------------------------------------------------------------------------
# Helper: check if credentials are configured
# ---------------------------------------------------------------------------

def _supabase_configured() -> bool:
    """Return True if all Supabase credentials are present."""
    return bool(SUPABASE_URL and SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY)


requires_supabase = pytest.mark.skipif(
    not _supabase_configured(),
    reason="Supabase credentials not configured in .env",
)


# ---------------------------------------------------------------------------
# Test signing key for QStash webhook tests
# ---------------------------------------------------------------------------

TEST_SIGNING_KEY = "test_signing_key_for_unit_tests_only"


# ---------------------------------------------------------------------------
# Mock data factories
# ---------------------------------------------------------------------------

def _mock_vault_data(vault_id: str = "vault-123") -> VaultData:
    """Create a mock VaultData for testing."""
    return VaultData(
        vault_id=vault_id,
        partner_name="Test Partner",
        relationship_tenure_months=24,
        cohabitation_status="living_together",
        location_city="Austin",
        location_state="TX",
        location_country="US",
        interests=["cooking", "hiking", "music", "photography", "travel"],
        dislikes=["sports", "gaming", "fishing", "hunting", "cars"],
        vibes=["quiet_luxury", "adventurous"],
        primary_love_language="quality_time",
        secondary_love_language="acts_of_service",
        budgets=[
            VaultBudget(occasion_type="just_because", min_amount=2000, max_amount=5000),
            VaultBudget(occasion_type="minor_occasion", min_amount=5000, max_amount=15000),
            VaultBudget(occasion_type="major_milestone", min_amount=10000, max_amount=50000),
        ],
    )


def _mock_candidates() -> list[CandidateRecommendation]:
    """Create 3 mock recommendation candidates."""
    return [
        CandidateRecommendation(
            id="rec-001",
            source="amazon",
            type="gift",
            title="Ceramic Mug Set",
            description="Handmade ceramic mugs",
            price_cents=4500,
            currency="USD",
            external_url="https://example.com/mugs",
            image_url="https://example.com/mugs.jpg",
            merchant_name="Artisan Co.",
            interest_score=0.85,
            vibe_score=0.78,
            love_language_score=0.72,
            final_score=0.80,
        ),
        CandidateRecommendation(
            id="rec-002",
            source="yelp",
            type="experience",
            title="Sunset Sailing",
            description="Private sailing trip",
            price_cents=24900,
            currency="USD",
            external_url="https://example.com/sailing",
            image_url="https://example.com/sailing.jpg",
            merchant_name="Bay Sailing Co.",
            interest_score=0.90,
            vibe_score=0.85,
            love_language_score=0.70,
            final_score=0.83,
        ),
        CandidateRecommendation(
            id="rec-003",
            source="yelp",
            type="date",
            title="Italian Dinner",
            description="Intimate 5-course dinner",
            price_cents=18000,
            currency="USD",
            external_url="https://example.com/dinner",
            image_url="https://example.com/dinner.jpg",
            merchant_name="Trattoria Luna",
            interest_score=0.75,
            vibe_score=0.92,
            love_language_score=0.88,
            final_score=0.84,
        ),
    ]


# ---------------------------------------------------------------------------
# Helpers: QStash signature generation (for webhook integration tests)
# ---------------------------------------------------------------------------

def _create_qstash_signature(
    body: bytes,
    url: str,
    signing_key: str = TEST_SIGNING_KEY,
) -> str:
    """Create a QStash-compatible JWT signature for testing."""
    now = int(time.time())
    body_hash = hashlib.sha256(body).hexdigest()

    claims = {
        "iss": "Upstash",
        "sub": url,
        "exp": now + 3600,
        "nbf": now - 60,
        "iat": now,
        "jti": f"msg_{uuid.uuid4().hex[:16]}",
        "body": body_hash,
    }

    return jwt.encode(claims, signing_key, algorithm="HS256")


# ---------------------------------------------------------------------------
# Fake ES256 key for APNs JWT tests
# ---------------------------------------------------------------------------

FAKE_ES256_PRIVATE_KEY = """-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIK22VSh7W4ha3V0GY29a3cmEV8MiPb8wA/ayJnxDuLl5oAoGCCqGSM49
AwEHoUQDQgAE4AxO/Iz5bRDDrT6QVgPeoMjQuqZmcvJJdQhQzvXFgnPajQxVrelJ
8QLD8MFQlvh9Zj7QZKfvd5R5nWxH05nfJg==
-----END EC PRIVATE KEY-----"""


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    """FastAPI test client for the Knot API."""
    return TestClient(app)


# ===================================================================
# Test Class: build_notification_payload (pure unit tests)
# ===================================================================

class TestBuildNotificationPayload:
    """Tests for the notification payload builder function."""

    def test_payload_has_correct_title_format(self):
        """Title should be '[Partner]'s [Milestone] is in [X] days'."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=14,
            vibes=["cozy"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        assert payload["aps"]["alert"]["title"] == "Alice's Birthday is in 14 days"

    def test_payload_has_correct_body_format(self):
        """Body should reference vibe and recommendation count."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["romantic"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        expected = (
            "I've found 3 Romantic options based on their interests. "
            "Tap to see them."
        )
        assert payload["aps"]["alert"]["body"] == expected

    def test_payload_uses_first_vibe_capitalized(self):
        """When multiple vibes exist, use the first one capitalized."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=3,
            vibes=["quiet_luxury", "adventurous"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        body = payload["aps"]["alert"]["body"]
        assert "Quiet luxury" in body

    def test_payload_uses_curated_when_no_vibes(self):
        """When vibes list is empty, fall back to 'curated'."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Anniversary",
            days_before=14,
            vibes=[],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        body = payload["aps"]["alert"]["body"]
        assert "curated" in body.lower()

    def test_payload_has_milestone_reminder_category(self):
        """Category should be MILESTONE_REMINDER for View/Snooze actions."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["cozy"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        assert payload["aps"]["category"] == "MILESTONE_REMINDER"

    def test_payload_has_default_sound(self):
        """Sound should be 'default'."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["cozy"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        assert payload["aps"]["sound"] == "default"

    def test_payload_includes_custom_data(self):
        """notification_id and milestone_id should be at top level."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["cozy"],
            recommendations_count=3,
            notification_id="notif-abc-123",
            milestone_id="ms-def-456",
        )
        assert payload["notification_id"] == "notif-abc-123"
        assert payload["milestone_id"] == "ms-def-456"

    def test_payload_alert_structure(self):
        """aps.alert should contain both title and body keys."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["cozy"],
            recommendations_count=3,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        alert = payload["aps"]["alert"]
        assert "title" in alert
        assert "body" in alert
        assert isinstance(alert["title"], str)
        assert isinstance(alert["body"], str)

    def test_payload_with_different_days_before_values(self):
        """Title should correctly reflect 14, 7, and 3 day values."""
        for days in [14, 7, 3]:
            payload = build_notification_payload(
                partner_name="Bob",
                milestone_name="Valentine's Day",
                days_before=days,
                vibes=["romantic"],
                recommendations_count=3,
                notification_id="notif-123",
                milestone_id="ms-456",
            )
            assert f"in {days} days" in payload["aps"]["alert"]["title"]

    def test_payload_body_reflects_recommendation_count(self):
        """Body should show the actual number of recommendations."""
        payload = build_notification_payload(
            partner_name="Alice",
            milestone_name="Birthday",
            days_before=7,
            vibes=["cozy"],
            recommendations_count=2,
            notification_id="notif-123",
            milestone_id="ms-456",
        )
        assert "I've found 2" in payload["aps"]["alert"]["body"]


# ===================================================================
# Test Class: _generate_apns_token (JWT generation)
# ===================================================================

class TestGenerateApnsToken:
    """Tests for APNs JWT token generation."""

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/fake/path/key.p8")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123456")
    @patch("app.services.apns.APNS_KEY_ID", "KEY123456")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_token_generation_uses_es256(self):
        """JWT should be signed with ES256 algorithm."""
        from app.services.apns import _generate_apns_token

        with patch("app.services.apns._load_auth_key", return_value=FAKE_ES256_PRIVATE_KEY):
            token = _generate_apns_token()

        # Decode header without verification to check algorithm
        header = jwt.get_unverified_header(token)
        assert header["alg"] == "ES256"

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/fake/path/key.p8")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123456")
    @patch("app.services.apns.APNS_KEY_ID", "KEY_ABC_789")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_token_includes_kid_header(self):
        """JWT headers should include kid matching APNS_KEY_ID."""
        from app.services.apns import _generate_apns_token

        with patch("app.services.apns._load_auth_key", return_value=FAKE_ES256_PRIVATE_KEY):
            token = _generate_apns_token()

        header = jwt.get_unverified_header(token)
        assert header["kid"] == "KEY_ABC_789"

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/fake/path/key.p8")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM_XYZ_99")
    @patch("app.services.apns.APNS_KEY_ID", "KEY123456")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_token_includes_team_id_as_issuer(self):
        """JWT 'iss' claim should equal APNS_TEAM_ID."""
        from app.services.apns import _generate_apns_token

        with patch("app.services.apns._load_auth_key", return_value=FAKE_ES256_PRIVATE_KEY):
            token = _generate_apns_token()

        # Decode without verification to inspect claims
        claims = jwt.decode(token, options={"verify_signature": False})
        assert claims["iss"] == "TEAM_XYZ_99"

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/fake/path/key.p8")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123456")
    @patch("app.services.apns.APNS_KEY_ID", "KEY123456")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_token_caching(self):
        """Second call should return cached token without re-reading key."""
        from app.services.apns import _generate_apns_token

        mock_load = MagicMock(return_value=FAKE_ES256_PRIVATE_KEY)
        with patch("app.services.apns._load_auth_key", mock_load):
            token1 = _generate_apns_token()
            token2 = _generate_apns_token()

        assert token1 == token2
        mock_load.assert_called_once()

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/fake/path/key.p8")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123456")
    @patch("app.services.apns.APNS_KEY_ID", "KEY123456")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_token_refresh_after_expiry(self):
        """After TOKEN_REFRESH_INTERVAL, a new token should be generated."""
        from app.services.apns import _generate_apns_token
        import app.services.apns as apns_module

        mock_load = MagicMock(return_value=FAKE_ES256_PRIVATE_KEY)
        with patch("app.services.apns._load_auth_key", mock_load):
            token1 = _generate_apns_token()

            # Simulate time passing beyond refresh interval
            apns_module._token_generated_at = time.time() - (TOKEN_REFRESH_INTERVAL + 60)
            token2 = _generate_apns_token()

        # Both calls should have loaded the key
        assert mock_load.call_count == 2
        # Tokens may differ due to different iat values
        assert isinstance(token2, str)

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_missing_key_path_raises_runtime_error(self):
        """RuntimeError when APNS_AUTH_KEY_PATH is empty."""
        from app.services.apns import _generate_apns_token

        with pytest.raises(RuntimeError, match="APNS_AUTH_KEY_PATH not configured"):
            _generate_apns_token()

    @patch("app.services.apns.APNS_AUTH_KEY_PATH", "/nonexistent/path/key.p8")
    @patch("app.services.apns._cached_token", None)
    @patch("app.services.apns._token_generated_at", 0)
    def test_missing_key_file_raises_file_not_found(self):
        """FileNotFoundError when the .p8 file does not exist on disk."""
        from app.services.apns import _generate_apns_token

        with pytest.raises(FileNotFoundError, match="APNs auth key file not found"):
            _generate_apns_token()


# ===================================================================
# Test Class: send_push_notification (HTTP delivery)
# ===================================================================

class TestSendPushNotification:
    """Tests for APNs HTTP/2 push delivery."""

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_successful_delivery_returns_success(self, mock_token):
        """200 response from APNs should return success=True."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "apns-uuid-123"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            result = await send_push_notification(
                "abc123device", {"aps": {"alert": "test"}}
            )

        assert result["success"] is True
        assert result["status_code"] == 200

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_successful_delivery_includes_apns_id(self, mock_token):
        """apns_id should be captured from response headers."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "unique-apns-id-abc"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            result = await send_push_notification(
                "abc123device", {"aps": {"alert": "test"}}
            )

        assert result["apns_id"] == "unique-apns-id-abc"

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_uses_sandbox_url_when_configured(self, mock_token):
        """When APNS_USE_SANDBOX=True, URL should use sandbox endpoint."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "test"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            await send_push_notification("abc123", {"aps": {}})

        call_args = mock_client.post.call_args
        url = call_args[0][0] if call_args[0] else call_args[1].get("url", "")
        assert APNS_SANDBOX_URL in url

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", False)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_uses_production_url_when_configured(self, mock_token):
        """When APNS_USE_SANDBOX=False, URL should use production endpoint."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "test"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            await send_push_notification("abc123", {"aps": {}})

        call_args = mock_client.post.call_args
        url = call_args[0][0] if call_args[0] else call_args[1].get("url", "")
        assert APNS_PRODUCTION_URL in url

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_failed_delivery_returns_reason(self, mock_token):
        """Non-200 response should return success=False with reason."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 400
        mock_response.headers = {"apns-id": "fail-id"}
        mock_response.json.return_value = {"reason": "BadDeviceToken"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            result = await send_push_notification("bad-token", {"aps": {}})

        assert result["success"] is False
        assert result["status_code"] == 400
        assert result["reason"] == "BadDeviceToken"

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_expired_token_returns_reason(self, mock_token):
        """403 with ExpiredProviderToken should be captured."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 403
        mock_response.headers = {"apns-id": "exp-id"}
        mock_response.json.return_value = {"reason": "ExpiredProviderToken"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            result = await send_push_notification("device123", {"aps": {}})

        assert result["success"] is False
        assert result["status_code"] == 403
        assert result["reason"] == "ExpiredProviderToken"

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_unregistered_device_returns_reason(self, mock_token):
        """410 with Unregistered should be captured."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 410
        mock_response.headers = {"apns-id": "unreg-id"}
        mock_response.json.return_value = {"reason": "Unregistered"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            result = await send_push_notification("old-token", {"aps": {}})

        assert result["success"] is False
        assert result["status_code"] == 410
        assert result["reason"] == "Unregistered"

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_http2_is_enabled(self, mock_token):
        """httpx.AsyncClient should be constructed with http2=True."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "test"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        mock_constructor = MagicMock(return_value=mock_client)
        with patch("app.services.apns.httpx.AsyncClient", mock_constructor):
            await send_push_notification("abc123", {"aps": {}})

        mock_constructor.assert_called_once_with(http2=True)

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.test.bundle")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_request_headers_include_topic(self, mock_token):
        """apns-topic header should be set to APNS_BUNDLE_ID."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "test"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            await send_push_notification("abc123", {"aps": {}})

        call_kwargs = mock_client.post.call_args[1]
        headers = call_kwargs.get("headers", {})
        assert headers["apns-topic"] == "com.test.bundle"

    @pytest.mark.asyncio
    @patch("app.services.apns.APNS_KEY_ID", "KEY123")
    @patch("app.services.apns.APNS_TEAM_ID", "TEAM123")
    @patch("app.services.apns.APNS_BUNDLE_ID", "com.example.app")
    @patch("app.services.apns.APNS_USE_SANDBOX", True)
    @patch("app.services.apns._generate_apns_token", return_value="fake-jwt-token")
    async def test_request_headers_include_push_type(self, mock_token):
        """apns-push-type header should be 'alert'."""
        from app.services.apns import send_push_notification

        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.headers = {"apns-id": "test"}

        mock_client = AsyncMock()
        mock_client.post.return_value = mock_response
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with patch("app.services.apns.httpx.AsyncClient", return_value=mock_client):
            await send_push_notification("abc123", {"aps": {}})

        call_kwargs = mock_client.post.call_args[1]
        headers = call_kwargs.get("headers", {})
        assert headers["apns-push-type"] == "alert"
        assert headers["apns-priority"] == "10"

    @pytest.mark.asyncio
    async def test_unconfigured_apns_raises_runtime_error(self):
        """send_push_notification should raise when APNs creds are missing."""
        from app.services.apns import send_push_notification

        with patch("app.services.apns.APNS_KEY_ID", ""):
            with patch("app.services.apns.APNS_TEAM_ID", ""):
                with pytest.raises(RuntimeError, match="APNs credentials not configured"):
                    await send_push_notification("abc123", {"aps": {}})


# ===================================================================
# Test Class: deliver_push_notification (DB lookup + send)
# ===================================================================

class TestDeliverPushNotification:
    """Tests for the high-level deliver_push_notification function."""

    @pytest.mark.asyncio
    async def test_delivers_to_registered_device(self):
        """Should look up device token and send push when registered."""
        from app.services.apns import deliver_push_notification

        mock_execute = MagicMock()
        mock_execute.data = [{"device_token": "abc123hex", "device_platform": "ios"}]

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_execute

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.db.supabase_client.get_service_client", return_value=mock_client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value={"success": True, "apns_id": "apns-123", "status_code": 200, "reason": None},
            ) as mock_send:
                result = await deliver_push_notification(
                    user_id="user-uuid-123",
                    notification_id="notif-uuid-456",
                    milestone_id="ms-uuid-789",
                    partner_name="Alice",
                    milestone_name="Birthday",
                    days_before=7,
                    vibes=["romantic"],
                    recommendations_count=3,
                )

        assert result["success"] is True
        mock_send.assert_called_once()

    @pytest.mark.asyncio
    async def test_returns_no_device_token_when_missing(self):
        """When device_token is None, should return graceful failure."""
        from app.services.apns import deliver_push_notification

        mock_execute = MagicMock()
        mock_execute.data = [{"device_token": None, "device_platform": None}]

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_execute

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.db.supabase_client.get_service_client", return_value=mock_client):
            result = await deliver_push_notification(
                user_id="user-uuid-123",
                notification_id="notif-uuid-456",
                milestone_id="ms-uuid-789",
                partner_name="Alice",
                milestone_name="Birthday",
                days_before=7,
                vibes=["romantic"],
                recommendations_count=3,
            )

        assert result["success"] is False
        assert result["reason"] == "no_device_token"

    @pytest.mark.asyncio
    async def test_returns_no_device_token_when_user_not_found(self):
        """When user has no rows in DB, should return graceful failure."""
        from app.services.apns import deliver_push_notification

        mock_execute = MagicMock()
        mock_execute.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_execute

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.db.supabase_client.get_service_client", return_value=mock_client):
            result = await deliver_push_notification(
                user_id="nonexistent-user",
                notification_id="notif-uuid-456",
                milestone_id="ms-uuid-789",
                partner_name="Alice",
                milestone_name="Birthday",
                days_before=7,
                vibes=["romantic"],
                recommendations_count=3,
            )

        assert result["success"] is False
        assert result["reason"] == "no_device_token"

    @pytest.mark.asyncio
    async def test_handles_db_lookup_failure(self):
        """Database exception should return graceful failure."""
        from app.services.apns import deliver_push_notification

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.side_effect = Exception("Connection refused")

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.db.supabase_client.get_service_client", return_value=mock_client):
            result = await deliver_push_notification(
                user_id="user-uuid-123",
                notification_id="notif-uuid-456",
                milestone_id="ms-uuid-789",
                partner_name="Alice",
                milestone_name="Birthday",
                days_before=7,
                vibes=["romantic"],
                recommendations_count=3,
            )

        assert result["success"] is False
        assert "device_token_lookup_failed" in result["reason"]

    @pytest.mark.asyncio
    async def test_builds_correct_payload(self):
        """The payload passed to send_push_notification should match expected format."""
        from app.services.apns import deliver_push_notification

        mock_execute = MagicMock()
        mock_execute.data = [{"device_token": "abc123hex", "device_platform": "ios"}]

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.execute.return_value = mock_execute

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.db.supabase_client.get_service_client", return_value=mock_client):
            with patch(
                "app.services.apns.send_push_notification",
                new_callable=AsyncMock,
                return_value={"success": True, "apns_id": "test", "status_code": 200, "reason": None},
            ) as mock_send:
                await deliver_push_notification(
                    user_id="user-uuid-123",
                    notification_id="notif-uuid-456",
                    milestone_id="ms-uuid-789",
                    partner_name="Alice",
                    milestone_name="Birthday",
                    days_before=14,
                    vibes=["quiet_luxury"],
                    recommendations_count=3,
                )

        # Verify the payload structure
        call_args = mock_send.call_args
        device_token = call_args[0][0]
        payload = call_args[0][1]

        assert device_token == "abc123hex"
        assert payload["aps"]["alert"]["title"] == "Alice's Birthday is in 14 days"
        assert "Quiet luxury" in payload["aps"]["alert"]["body"]
        assert payload["aps"]["category"] == "MILESTONE_REMINDER"
        assert payload["notification_id"] == "notif-uuid-456"
        assert payload["milestone_id"] == "ms-uuid-789"


# ===================================================================
# Test Class: Webhook Push Integration
# ===================================================================

class TestNotificationWebhookPushIntegration:
    """Tests for push notification integration in the webhook endpoint."""

    def _make_webhook_request(
        self,
        client,
        notification_id: str,
        user_id: str,
        milestone_id: str,
        days_before: int = 7,
    ) -> dict:
        """Build and send a webhook request with valid QStash signature."""
        payload = {
            "notification_id": notification_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "days_before": days_before,
        }
        body = json.dumps(payload).encode()
        url = "http://testserver/api/v1/notifications/process"
        signature = _create_qstash_signature(body, url)

        response = client.post(
            "/api/v1/notifications/process",
            content=body,
            headers={
                "Content-Type": "application/json",
                "Upstash-Signature": signature,
            },
        )
        return response

    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_webhook_attempts_push_after_recommendations(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        client,
    ):
        """Push should be attempted after successful recommendation generation."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}
        mock_push.return_value = {
            "success": True, "apns_id": "apns-123", "status_code": 200, "reason": None,
        }

        # Mock the notification lookup and update
        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id,
            "user_id": user_id,
            "milestone_id": milestone_id,
            "status": "pending",
            "days_before": 7,
        }]

        mock_execute_insert = MagicMock()
        mock_execute_insert.data = []

        mock_execute_update = MagicMock()
        mock_execute_update.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}
        original_execute = mock_table.execute

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            elif call_count["n"] == 2:
                return mock_execute_insert
            else:
                return mock_execute_update

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            response = self._make_webhook_request(
                client, notif_id, user_id, milestone_id,
            )

        assert response.status_code == 200
        mock_push.assert_called_once()

        # Verify push was called with correct vault data
        push_kwargs = mock_push.call_args[1]
        assert push_kwargs["partner_name"] == "Test Partner"
        assert push_kwargs["milestone_name"] == "Birthday"
        assert push_kwargs["days_before"] == 7
        assert push_kwargs["recommendations_count"] == 3

    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_webhook_push_failure_does_not_block_status_update(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        client,
    ):
        """Push failure should not prevent notification from being marked 'sent'."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}
        mock_push.side_effect = Exception("APNs connection refused")

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id, "user_id": user_id,
            "milestone_id": milestone_id, "status": "pending", "days_before": 7,
        }]

        mock_execute_other = MagicMock()
        mock_execute_other.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            return mock_execute_other

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            response = self._make_webhook_request(
                client, notif_id, user_id, milestone_id,
            )

        # Should still succeed (200) despite push failure
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "processed"
        assert data["push_delivered"] is False

    @patch("app.api.notifications.is_apns_configured", return_value=False)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_webhook_skips_push_when_apns_not_configured(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_apns_config,
        client,
    ):
        """When APNs is not configured, push should be skipped."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id, "user_id": user_id,
            "milestone_id": milestone_id, "status": "pending", "days_before": 7,
        }]

        mock_execute_other = MagicMock()
        mock_execute_other.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            return mock_execute_other

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            with patch("app.api.notifications.deliver_push_notification") as mock_deliver:
                response = self._make_webhook_request(
                    client, notif_id, user_id, milestone_id,
                )

        assert response.status_code == 200
        mock_deliver.assert_not_called()
        data = response.json()
        assert data["push_delivered"] is False

    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_webhook_skips_push_when_zero_recommendations(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_apns_config,
        client,
    ):
        """When pipeline returns no recommendations, push should be skipped."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": []}

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id, "user_id": user_id,
            "milestone_id": milestone_id, "status": "pending", "days_before": 7,
        }]

        mock_execute_other = MagicMock()
        mock_execute_other.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            return mock_execute_other

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            with patch("app.api.notifications.deliver_push_notification") as mock_deliver:
                response = self._make_webhook_request(
                    client, notif_id, user_id, milestone_id,
                )

        assert response.status_code == 200
        mock_deliver.assert_not_called()
        data = response.json()
        assert data["recommendations_generated"] == 0
        assert data["push_delivered"] is False

    @patch("app.api.notifications.is_apns_configured", return_value=True)
    @patch("app.api.notifications.deliver_push_notification", new_callable=AsyncMock)
    @patch("app.api.notifications.run_recommendation_pipeline", new_callable=AsyncMock)
    @patch("app.api.notifications.load_vault_data", new_callable=AsyncMock)
    @patch("app.api.notifications.load_milestone_context", new_callable=AsyncMock)
    @patch("app.services.qstash.QSTASH_CURRENT_SIGNING_KEY", TEST_SIGNING_KEY)
    def test_response_includes_push_delivered_field(
        self,
        mock_milestone,
        mock_vault,
        mock_pipeline,
        mock_push,
        mock_apns_config,
        client,
    ):
        """Response JSON should include push_delivered boolean."""
        vault_data = _mock_vault_data()
        mock_vault.return_value = (vault_data, "vault-123")
        mock_milestone.return_value = MilestoneContext(
            id="ms-123", milestone_type="birthday", milestone_name="Birthday",
            milestone_date="2000-06-15", recurrence="yearly", budget_tier="minor_occasion",
        )
        mock_pipeline.return_value = {"final_three": _mock_candidates()}
        mock_push.return_value = {
            "success": True, "apns_id": "apns-123", "status_code": 200, "reason": None,
        }

        notif_id = str(uuid.uuid4())
        user_id = str(uuid.uuid4())
        milestone_id = str(uuid.uuid4())

        mock_execute_select = MagicMock()
        mock_execute_select.data = [{
            "id": notif_id, "user_id": user_id,
            "milestone_id": milestone_id, "status": "pending", "days_before": 7,
        }]

        mock_execute_other = MagicMock()
        mock_execute_other.data = []

        mock_table = MagicMock()
        mock_table.select.return_value = mock_table
        mock_table.eq.return_value = mock_table
        mock_table.insert.return_value = mock_table
        mock_table.update.return_value = mock_table

        call_count = {"n": 0}

        def execute_side_effect():
            call_count["n"] += 1
            if call_count["n"] == 1:
                return mock_execute_select
            return mock_execute_other

        mock_table.execute.side_effect = execute_side_effect

        mock_client = MagicMock()
        mock_client.table.return_value = mock_table

        with patch("app.api.notifications.get_service_client", return_value=mock_client):
            response = self._make_webhook_request(
                client, notif_id, user_id, milestone_id,
            )

        assert response.status_code == 200
        data = response.json()
        assert "push_delivered" in data
        assert data["push_delivered"] is True


# ===================================================================
# Test Class: Module Imports
# ===================================================================

class TestModuleImports:
    """Verify that all APNs-related modules import successfully."""

    def test_apns_service_imports(self):
        """The APNs service module should import without errors."""
        from app.services.apns import (
            build_notification_payload,
            deliver_push_notification,
            send_push_notification,
            APNS_PRODUCTION_URL,
            APNS_SANDBOX_URL,
            TOKEN_REFRESH_INTERVAL,
        )
        assert callable(build_notification_payload)
        assert callable(deliver_push_notification)
        assert callable(send_push_notification)

    def test_config_has_apns_vars(self):
        """Config module should export all APNs configuration variables."""
        from app.core.config import (
            APNS_KEY_ID,
            APNS_TEAM_ID,
            APNS_AUTH_KEY_PATH,
            APNS_BUNDLE_ID,
            APNS_USE_SANDBOX,
            is_apns_configured,
            validate_apns_config,
        )
        assert isinstance(APNS_KEY_ID, str)
        assert isinstance(APNS_TEAM_ID, str)
        assert isinstance(APNS_AUTH_KEY_PATH, str)
        assert isinstance(APNS_BUNDLE_ID, str)
        assert isinstance(APNS_USE_SANDBOX, bool)
        assert callable(is_apns_configured)
        assert callable(validate_apns_config)

    def test_notification_model_has_push_delivered(self):
        """NotificationProcessResponse should have push_delivered field."""
        from app.models.notifications import NotificationProcessResponse
        response = NotificationProcessResponse(
            status="processed",
            notification_id="test-123",
        )
        assert hasattr(response, "push_delivered")
        assert response.push_delivered is False

    def test_notification_model_push_delivered_defaults_false(self):
        """push_delivered should default to False."""
        from app.models.notifications import NotificationProcessResponse
        response = NotificationProcessResponse(
            status="processed",
            notification_id="test-123",
            recommendations_generated=3,
        )
        assert response.push_delivered is False

    def test_notification_model_push_delivered_can_be_true(self):
        """push_delivered should accept True."""
        from app.models.notifications import NotificationProcessResponse
        response = NotificationProcessResponse(
            status="processed",
            notification_id="test-123",
            push_delivered=True,
        )
        assert response.push_delivered is True
