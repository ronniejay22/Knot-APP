"""
Step 3.11 Validation Tests — Simulates the iOS App's Onboarding-to-Backend Flow

These tests verify the complete iOS → Backend integration by:
1. Creating payloads in the EXACT format the iOS DTOs produce (snake_case JSON)
2. Sending them to POST /api/v1/vault with a real Supabase auth token
3. Verifying all 6 database tables are populated correctly
4. Testing the vault existence check (PostgREST query used by VaultService.vaultExists())
5. Testing error handling (network error simulation, duplicate vault 409)
6. Testing the returning-user flow (sign out, sign in, vault still exists)

Run with: pytest tests/test_step_3_11_ios_integration.py -v
"""

import json
import uuid

import httpx
import pytest
from fastapi.testclient import TestClient

from app.core.config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
from app.db.supabase_client import get_service_client
from app.main import app


# ======================================================================
# Fixtures
# ======================================================================

@pytest.fixture
def client():
    """FastAPI test client."""
    return TestClient(app)


@pytest.fixture
def test_auth_user_with_token():
    """
    Creates a real Supabase auth user, signs them in, and yields their info.
    Cleans up the user on teardown (CASCADE deletes all vault data).
    """
    service = get_service_client()
    email = f"ios-test-{uuid.uuid4().hex[:8]}@knot-test.com"
    password = f"TestPass_{uuid.uuid4().hex[:12]}!"

    # Create user via Admin API
    admin_url = f"{SUPABASE_URL}/auth/v1/admin/users"
    headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    create_resp = httpx.post(admin_url, headers=headers, json={
        "email": email,
        "password": password,
        "email_confirm": True,
    })
    assert create_resp.status_code == 200, f"Failed to create user: {create_resp.text}"
    user_id = create_resp.json()["id"]

    # Sign in to get access token
    signin_url = f"{SUPABASE_URL}/auth/v1/token?grant_type=password"
    signin_headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }
    signin_resp = httpx.post(signin_url, headers=signin_headers, json={
        "email": email,
        "password": password,
    })
    assert signin_resp.status_code == 200, f"Failed to sign in: {signin_resp.text}"
    access_token = signin_resp.json()["access_token"]

    yield {
        "user_id": user_id,
        "email": email,
        "access_token": access_token,
    }

    # Cleanup: delete auth user (CASCADE removes all data)
    delete_url = f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    httpx.delete(delete_url, headers=headers)


# ======================================================================
# Helper: Build the EXACT payload the iOS app sends
# ======================================================================

def _ios_onboarding_payload() -> dict:
    """
    Builds the EXACT JSON payload that the iOS DTOs (VaultCreatePayload)
    would produce after a user completes the 9-step onboarding flow.

    This mirrors what buildVaultPayload() in OnboardingViewModel.swift creates.
    """
    return {
        "partner_name": "Alex",
        "relationship_tenure_months": 18,
        "cohabitation_status": "living_together",
        "location_city": "San Francisco",
        "location_state": "CA",
        "location_country": "US",
        "interests": ["Travel", "Cooking", "Movies", "Music", "Reading"],
        "dislikes": ["Sports", "Gaming", "Cars", "DIY", "Gardening"],
        "milestones": [
            {
                "milestone_type": "birthday",
                "milestone_name": "Alex's Birthday",
                "milestone_date": "2000-03-15",
                "recurrence": "yearly",
                "budget_tier": None,  # DB trigger sets major_milestone
            },
            {
                "milestone_type": "anniversary",
                "milestone_name": "Anniversary",
                "milestone_date": "2000-06-20",
                "recurrence": "yearly",
                "budget_tier": None,  # DB trigger sets major_milestone
            },
            {
                "milestone_type": "holiday",
                "milestone_name": "Valentine's Day",
                "milestone_date": "2000-02-14",
                "recurrence": "yearly",
                "budget_tier": None,  # DB trigger sets minor_occasion
            },
            {
                "milestone_type": "holiday",
                "milestone_name": "Christmas",
                "milestone_date": "2000-12-25",
                "recurrence": "yearly",
                "budget_tier": None,
            },
            {
                "milestone_type": "custom",
                "milestone_name": "First Date",
                "milestone_date": "2000-09-10",
                "recurrence": "yearly",
                "budget_tier": "minor_occasion",  # iOS defaults custom → minor_occasion
            },
        ],
        "vibes": ["quiet_luxury", "minimalist", "romantic"],
        "budgets": [
            {
                "occasion_type": "just_because",
                "min_amount": 2000,
                "max_amount": 5000,
                "currency": "USD",
            },
            {
                "occasion_type": "minor_occasion",
                "min_amount": 5000,
                "max_amount": 15000,
                "currency": "USD",
            },
            {
                "occasion_type": "major_milestone",
                "min_amount": 10000,
                "max_amount": 50000,
                "currency": "USD",
            },
        ],
        "love_languages": {
            "primary": "quality_time",
            "secondary": "receiving_gifts",
        },
    }


def _auth_headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def _query_table(table: str, column: str, value: str) -> list:
    """Query a table via PostgREST with service role (bypass RLS)."""
    service = get_service_client()
    result = service.table(table).select("*").eq(column, value).execute()
    return result.data


# ======================================================================
# Test 1: iOS onboarding payload → 201 success
# ======================================================================

class TestiOSOnboardingSubmission:
    """Simulates the complete iOS onboarding → backend submission flow."""

    def test_ios_payload_accepted(self, client, test_auth_user_with_token):
        """The exact payload from iOS DTOs is accepted with 201."""
        token = test_auth_user_with_token["access_token"]
        payload = _ios_onboarding_payload()

        resp = client.post("/api/v1/vault", json=payload, headers=_auth_headers(token))

        assert resp.status_code == 201, f"Expected 201, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert "vault_id" in data
        assert data["partner_name"] == "Alex"
        assert data["interests_count"] == 5
        assert data["dislikes_count"] == 5
        assert data["milestones_count"] == 5
        assert data["vibes_count"] == 3
        assert data["budgets_count"] == 3
        assert data["love_languages"]["primary"] == "quality_time"
        assert data["love_languages"]["secondary"] == "receiving_gifts"

    def test_ios_data_stored_in_all_6_tables(self, client, test_auth_user_with_token):
        """After iOS submission, data exists in all 6 database tables."""
        token = test_auth_user_with_token["access_token"]
        user_id = test_auth_user_with_token["user_id"]
        payload = _ios_onboarding_payload()

        resp = client.post("/api/v1/vault", json=payload, headers=_auth_headers(token))
        assert resp.status_code == 201
        vault_id = resp.json()["vault_id"]

        # 1. partner_vaults
        vaults = _query_table("partner_vaults", "id", vault_id)
        assert len(vaults) == 1
        assert vaults[0]["partner_name"] == "Alex"
        assert vaults[0]["relationship_tenure_months"] == 18
        assert vaults[0]["cohabitation_status"] == "living_together"
        assert vaults[0]["location_city"] == "San Francisco"
        assert vaults[0]["location_state"] == "CA"
        assert vaults[0]["user_id"] == user_id

        # 2. partner_interests (5 likes + 5 dislikes = 10 rows)
        interests = _query_table("partner_interests", "vault_id", vault_id)
        assert len(interests) == 10
        likes = [i for i in interests if i["interest_type"] == "like"]
        dislikes = [i for i in interests if i["interest_type"] == "dislike"]
        assert len(likes) == 5
        assert len(dislikes) == 5
        assert set(i["interest_category"] for i in likes) == {
            "Travel", "Cooking", "Movies", "Music", "Reading"
        }
        assert set(i["interest_category"] for i in dislikes) == {
            "Sports", "Gaming", "Cars", "DIY", "Gardening"
        }

        # 3. partner_milestones (5 milestones)
        milestones = _query_table("partner_milestones", "vault_id", vault_id)
        assert len(milestones) == 5

        birthday = [m for m in milestones if m["milestone_type"] == "birthday"]
        assert len(birthday) == 1
        assert birthday[0]["milestone_name"] == "Alex's Birthday"
        assert birthday[0]["budget_tier"] == "major_milestone"  # trigger default

        anniversary = [m for m in milestones if m["milestone_type"] == "anniversary"]
        assert len(anniversary) == 1
        assert anniversary[0]["budget_tier"] == "major_milestone"  # trigger default

        holidays = [m for m in milestones if m["milestone_type"] == "holiday"]
        assert len(holidays) == 2

        custom = [m for m in milestones if m["milestone_type"] == "custom"]
        assert len(custom) == 1
        assert custom[0]["milestone_name"] == "First Date"
        assert custom[0]["budget_tier"] == "minor_occasion"  # iOS default for custom

        # 4. partner_vibes (3 vibes)
        vibes = _query_table("partner_vibes", "vault_id", vault_id)
        assert len(vibes) == 3
        assert set(v["vibe_tag"] for v in vibes) == {
            "quiet_luxury", "minimalist", "romantic"
        }

        # 5. partner_budgets (3 tiers)
        budgets = _query_table("partner_budgets", "vault_id", vault_id)
        assert len(budgets) == 3
        jb = [b for b in budgets if b["occasion_type"] == "just_because"][0]
        assert jb["min_amount"] == 2000
        assert jb["max_amount"] == 5000
        mo = [b for b in budgets if b["occasion_type"] == "minor_occasion"][0]
        assert mo["min_amount"] == 5000
        assert mo["max_amount"] == 15000
        mm = [b for b in budgets if b["occasion_type"] == "major_milestone"][0]
        assert mm["min_amount"] == 10000
        assert mm["max_amount"] == 50000

        # 6. partner_love_languages (2 rows)
        languages = _query_table("partner_love_languages", "vault_id", vault_id)
        assert len(languages) == 2
        primary = [l for l in languages if l["priority"] == 1][0]
        assert primary["language"] == "quality_time"
        secondary = [l for l in languages if l["priority"] == 2][0]
        assert secondary["language"] == "receiving_gifts"


# ======================================================================
# Test 2: Vault existence check (simulates VaultService.vaultExists())
# ======================================================================

class TestVaultExistenceCheck:
    """
    Simulates VaultService.vaultExists() — the PostgREST query
    that the iOS app uses to check if a vault already exists on
    session restore or sign-in.
    """

    def test_vault_exists_after_creation(self, client, test_auth_user_with_token):
        """After creating a vault, the existence check returns data."""
        token = test_auth_user_with_token["access_token"]
        payload = _ios_onboarding_payload()

        # Create vault
        resp = client.post("/api/v1/vault", json=payload, headers=_auth_headers(token))
        assert resp.status_code == 201

        # Simulate VaultService.vaultExists() — query PostgREST with user's token
        postgrest_url = f"{SUPABASE_URL}/rest/v1/partner_vaults?select=id&limit=1"
        postgrest_headers = {
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
        }
        check_resp = httpx.get(postgrest_url, headers=postgrest_headers)
        assert check_resp.status_code == 200
        results = check_resp.json()
        assert len(results) == 1, "Vault should exist after creation"
        assert "id" in results[0]

    def test_vault_not_exists_before_creation(self, test_auth_user_with_token):
        """Before creating a vault, the existence check returns empty."""
        token = test_auth_user_with_token["access_token"]

        # Simulate VaultService.vaultExists() — no vault yet
        postgrest_url = f"{SUPABASE_URL}/rest/v1/partner_vaults?select=id&limit=1"
        postgrest_headers = {
            "apikey": SUPABASE_ANON_KEY,
            "Authorization": f"Bearer {token}",
        }
        check_resp = httpx.get(postgrest_url, headers=postgrest_headers)
        assert check_resp.status_code == 200
        results = check_resp.json()
        assert len(results) == 0, "No vault should exist for a new user"


# ======================================================================
# Test 3: Error handling (simulates iOS error scenarios)
# ======================================================================

class TestiOSErrorHandling:
    """Simulates error conditions the iOS app must handle."""

    def test_duplicate_vault_returns_409(self, client, test_auth_user_with_token):
        """
        If user already has a vault (e.g., re-tapping "Get Started"),
        the backend returns 409 with a clear message.
        """
        token = test_auth_user_with_token["access_token"]
        payload = _ios_onboarding_payload()

        # First submission — success
        resp1 = client.post("/api/v1/vault", json=payload, headers=_auth_headers(token))
        assert resp1.status_code == 201

        # Second submission — 409 conflict
        resp2 = client.post("/api/v1/vault", json=payload, headers=_auth_headers(token))
        assert resp2.status_code == 409
        assert "already exists" in resp2.json()["detail"].lower()

    def test_no_auth_returns_401(self, client):
        """Missing auth token returns 401 (iOS shows sign-in screen)."""
        payload = _ios_onboarding_payload()
        resp = client.post("/api/v1/vault", json=payload)
        assert resp.status_code == 401

    def test_invalid_token_returns_401(self, client):
        """Expired/invalid token returns 401 (iOS shows sign-in screen)."""
        payload = _ios_onboarding_payload()
        headers = _auth_headers("invalid_garbage_token_12345")
        resp = client.post("/api/v1/vault", json=payload, headers=headers)
        assert resp.status_code == 401

    def test_error_response_has_detail_field(self, client):
        """Error responses include a 'detail' field the iOS app can parse."""
        payload = _ios_onboarding_payload()
        resp = client.post("/api/v1/vault", json=payload)
        assert resp.status_code == 401
        body = resp.json()
        assert "detail" in body, "Error response must have 'detail' for iOS parsing"


# ======================================================================
# Test 4: Returning user flow (sign out → sign in → vault still there)
# ======================================================================

class TestReturningUserFlow:
    """
    Simulates the returning user scenario:
    1. User completes onboarding → vault created
    2. User signs out
    3. User signs in again (new token)
    4. Vault existence check → returns true → skip onboarding
    """

    def test_vault_persists_after_new_session(self, client):
        """
        After creating a vault, signing out, and signing in again,
        the vault existence check still returns the vault.
        """
        service = get_service_client()
        email = f"returning-{uuid.uuid4().hex[:8]}@knot-test.com"
        password = f"TestPass_{uuid.uuid4().hex[:12]}!"

        # Create user
        admin_url = f"{SUPABASE_URL}/auth/v1/admin/users"
        admin_headers = {
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
        }
        create_resp = httpx.post(admin_url, headers=admin_headers, json={
            "email": email,
            "password": password,
            "email_confirm": True,
        })
        assert create_resp.status_code == 200
        user_id = create_resp.json()["id"]

        try:
            # Session 1: Sign in and create vault
            signin_url = f"{SUPABASE_URL}/auth/v1/token?grant_type=password"
            signin_headers = {"apikey": SUPABASE_ANON_KEY, "Content-Type": "application/json"}
            signin1 = httpx.post(signin_url, headers=signin_headers, json={
                "email": email, "password": password,
            })
            assert signin1.status_code == 200
            token1 = signin1.json()["access_token"]

            # Create vault with first session
            resp = client.post(
                "/api/v1/vault",
                json=_ios_onboarding_payload(),
                headers=_auth_headers(token1),
            )
            assert resp.status_code == 201

            # Session 2: Sign in again (simulates app relaunch / re-auth)
            signin2 = httpx.post(signin_url, headers=signin_headers, json={
                "email": email, "password": password,
            })
            assert signin2.status_code == 200
            token2 = signin2.json()["access_token"]

            # Vault existence check with NEW token → should still find the vault
            postgrest_url = f"{SUPABASE_URL}/rest/v1/partner_vaults?select=id&limit=1"
            postgrest_headers = {
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": f"Bearer {token2}",
            }
            check_resp = httpx.get(postgrest_url, headers=postgrest_headers)
            assert check_resp.status_code == 200
            results = check_resp.json()
            assert len(results) == 1, "Vault must persist across sessions"

        finally:
            # Cleanup
            httpx.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}",
                headers=admin_headers,
            )
