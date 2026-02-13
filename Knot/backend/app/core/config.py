"""
Application Configuration

Loads environment variables and provides typed settings
for the application. Uses python-dotenv to load from .env file.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file from the backend directory
_env_path = Path(__file__).resolve().parent.parent.parent / ".env"
load_dotenv(dotenv_path=_env_path)

# --- App Settings ---
API_V1_PREFIX = "/api/v1"
PROJECT_NAME = "Knot"

# --- Supabase ---
SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_ANON_KEY: str = os.getenv("SUPABASE_ANON_KEY", "")
SUPABASE_SERVICE_ROLE_KEY: str = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")

# --- Vertex AI (future steps) ---
GOOGLE_CLOUD_PROJECT: str = os.getenv("GOOGLE_CLOUD_PROJECT", "")
GOOGLE_APPLICATION_CREDENTIALS: str = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")


# --- Upstash QStash ---
UPSTASH_QSTASH_TOKEN: str = os.getenv("UPSTASH_QSTASH_TOKEN", "")
UPSTASH_QSTASH_URL: str = os.getenv("UPSTASH_QSTASH_URL", "https://qstash.upstash.io")
QSTASH_CURRENT_SIGNING_KEY: str = os.getenv("QSTASH_CURRENT_SIGNING_KEY", "")
QSTASH_NEXT_SIGNING_KEY: str = os.getenv("QSTASH_NEXT_SIGNING_KEY", "")

# --- Webhook Configuration ---
WEBHOOK_BASE_URL: str = os.getenv("WEBHOOK_BASE_URL", "")

# --- APNs Push Notifications ---
APNS_KEY_ID: str = os.getenv("APNS_KEY_ID", "")
APNS_TEAM_ID: str = os.getenv("APNS_TEAM_ID", "")
APNS_AUTH_KEY_PATH: str = os.getenv("APNS_AUTH_KEY_PATH", "")
APNS_BUNDLE_ID: str = os.getenv("APNS_BUNDLE_ID", "")
APNS_USE_SANDBOX: bool = os.getenv("APNS_USE_SANDBOX", "true").lower() == "true"

# --- Yelp Fusion API ---
YELP_API_KEY: str = os.getenv("YELP_API_KEY", "")

# --- Ticketmaster Discovery API ---
TICKETMASTER_API_KEY: str = os.getenv("TICKETMASTER_API_KEY", "")

# --- Amazon Product Advertising API ---
AMAZON_ACCESS_KEY: str = os.getenv("AMAZON_ACCESS_KEY", "")
AMAZON_SECRET_KEY: str = os.getenv("AMAZON_SECRET_KEY", "")
AMAZON_ASSOCIATE_TAG: str = os.getenv("AMAZON_ASSOCIATE_TAG", "")

# --- Shopify Storefront API ---
SHOPIFY_STOREFRONT_TOKEN: str = os.getenv("SHOPIFY_STOREFRONT_TOKEN", "")
SHOPIFY_STORE_DOMAIN: str = os.getenv("SHOPIFY_STORE_DOMAIN", "")


def validate_yelp_config() -> bool:
    """
    Check that Yelp Fusion API credentials are configured.

    Returns True if configured, False if not (non-fatal — Yelp
    searches will be disabled but the app will still function).
    """
    return bool(YELP_API_KEY)


def is_yelp_configured() -> bool:
    """
    Check if Yelp is available without raising exceptions.

    Used by tests and services to conditionally enable Yelp search features.
    """
    return bool(YELP_API_KEY)


def validate_ticketmaster_config() -> bool:
    """
    Check that Ticketmaster Discovery API credentials are configured.

    Returns True if configured, False if not (non-fatal — Ticketmaster
    searches will be disabled but the app will still function).
    """
    return bool(TICKETMASTER_API_KEY)


def is_ticketmaster_configured() -> bool:
    """
    Check if Ticketmaster is available without raising exceptions.

    Used by tests and services to conditionally enable Ticketmaster search features.
    """
    return bool(TICKETMASTER_API_KEY)


def validate_amazon_config() -> bool:
    """
    Check that Amazon Product Advertising API credentials are configured.

    Returns True if configured, False if not (non-fatal — Amazon
    searches will be disabled but the app will still function).
    """
    return bool(AMAZON_ACCESS_KEY and AMAZON_SECRET_KEY and AMAZON_ASSOCIATE_TAG)


def is_amazon_configured() -> bool:
    """
    Check if Amazon PA-API is available without raising exceptions.

    Used by tests and services to conditionally enable Amazon search features.
    """
    return bool(AMAZON_ACCESS_KEY and AMAZON_SECRET_KEY and AMAZON_ASSOCIATE_TAG)


def validate_shopify_config() -> bool:
    """
    Check that Shopify Storefront API credentials are configured.

    Returns True if configured, False if not (non-fatal — Shopify
    searches will be disabled but the app will still function).
    """
    return bool(SHOPIFY_STOREFRONT_TOKEN and SHOPIFY_STORE_DOMAIN)


def is_shopify_configured() -> bool:
    """
    Check if Shopify Storefront API is available without raising exceptions.

    Used by tests and services to conditionally enable Shopify search features.
    """
    return bool(SHOPIFY_STOREFRONT_TOKEN and SHOPIFY_STORE_DOMAIN)


def validate_supabase_config() -> bool:
    """Check that all required Supabase credentials are present and non-empty."""
    missing = []
    if not SUPABASE_URL:
        missing.append("SUPABASE_URL")
    if not SUPABASE_ANON_KEY:
        missing.append("SUPABASE_ANON_KEY")
    if not SUPABASE_SERVICE_ROLE_KEY:
        missing.append("SUPABASE_SERVICE_ROLE_KEY")
    if missing:
        raise EnvironmentError(
            f"Missing required Supabase environment variables: {', '.join(missing)}. "
            f"Please fill in your .env file at: {_env_path}"
        )
    return True


def validate_vertex_ai_config() -> bool:
    """
    Check that Vertex AI credentials are configured.

    Only GOOGLE_CLOUD_PROJECT is required. GOOGLE_APPLICATION_CREDENTIALS
    is optional — when absent, the Vertex AI SDK falls back to Application
    Default Credentials (ADC) configured via `gcloud auth application-default login`.

    Returns True if configured, False if not (non-fatal — embedding
    generation will be disabled but the app will still function).
    """
    if not GOOGLE_CLOUD_PROJECT:
        return False
    return True


def is_vertex_ai_configured() -> bool:
    """
    Check if Vertex AI is available without raising exceptions.

    Used by tests and services to conditionally enable embedding features.
    """
    return bool(GOOGLE_CLOUD_PROJECT)


def validate_qstash_config() -> bool:
    """
    Check that QStash credentials are configured for webhook verification.

    Returns True if configured, False if not (non-fatal — notification
    scheduling will be disabled but the app will still function).
    """
    return bool(UPSTASH_QSTASH_TOKEN and QSTASH_CURRENT_SIGNING_KEY and WEBHOOK_BASE_URL)


def is_qstash_configured() -> bool:
    """
    Check if QStash is available without raising exceptions.

    Used by tests and services to conditionally enable notification features.
    """
    return bool(UPSTASH_QSTASH_TOKEN and QSTASH_CURRENT_SIGNING_KEY and WEBHOOK_BASE_URL)


def validate_apns_config() -> bool:
    """
    Check that APNs credentials are configured for push notifications.

    Returns True if configured, False if not (non-fatal — push
    notification delivery will be disabled but the app will still function).
    """
    return bool(APNS_KEY_ID and APNS_TEAM_ID and APNS_AUTH_KEY_PATH and APNS_BUNDLE_ID)


def is_apns_configured() -> bool:
    """
    Check if APNs is available without raising exceptions.

    Used by tests and services to conditionally enable push notification features.
    """
    return bool(APNS_KEY_ID and APNS_TEAM_ID and APNS_AUTH_KEY_PATH and APNS_BUNDLE_ID)
