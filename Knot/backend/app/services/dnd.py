"""
DND (Do Not Disturb) Service — Quiet hours enforcement for notifications.

Checks whether the current time falls within a user's configured quiet hours
and computes the next valid delivery time if rescheduling is needed.

The quiet hours check runs in the notification webhook before push delivery.
If the current time is within quiet hours, the notification is rescheduled
via QStash to deliver at the end of quiet hours (default 8am local time).

Step 7.6: Implement DND Respect Logic.
"""

import logging
from datetime import datetime, timedelta, timezone as tz
from zoneinfo import ZoneInfo

from app.db.supabase_client import get_service_client

logger = logging.getLogger(__name__)

# Default quiet hours (used when no user preference exists)
DEFAULT_QUIET_HOURS_START = 22  # 10pm
DEFAULT_QUIET_HOURS_END = 8  # 8am

# Fallback timezone when we cannot infer from location
DEFAULT_TIMEZONE = "America/New_York"


# ===================================================================
# US State → IANA Timezone Mapping
# ===================================================================

_US_STATE_TIMEZONES: dict[str, str] = {
    # Hawaii
    "HI": "Pacific/Honolulu",
    # Alaska
    "AK": "America/Anchorage",
    # Pacific
    "WA": "America/Los_Angeles",
    "OR": "America/Los_Angeles",
    "CA": "America/Los_Angeles",
    "NV": "America/Los_Angeles",
    # Mountain
    "ID": "America/Boise",
    "MT": "America/Denver",
    "WY": "America/Denver",
    "UT": "America/Denver",
    "CO": "America/Denver",
    "AZ": "America/Phoenix",
    "NM": "America/Denver",
    # Central
    "ND": "America/Chicago",
    "SD": "America/Chicago",
    "NE": "America/Chicago",
    "KS": "America/Chicago",
    "MN": "America/Chicago",
    "IA": "America/Chicago",
    "MO": "America/Chicago",
    "WI": "America/Chicago",
    "IL": "America/Chicago",
    "OK": "America/Chicago",
    "TX": "America/Chicago",
    "AR": "America/Chicago",
    "LA": "America/Chicago",
    "MS": "America/Chicago",
    "AL": "America/Chicago",
    "TN": "America/Chicago",
    # Eastern
    "MI": "America/Detroit",
    "IN": "America/Indiana/Indianapolis",
    "OH": "America/New_York",
    "KY": "America/New_York",
    "GA": "America/New_York",
    "FL": "America/New_York",
    "SC": "America/New_York",
    "NC": "America/New_York",
    "VA": "America/New_York",
    "WV": "America/New_York",
    "MD": "America/New_York",
    "DE": "America/New_York",
    "NJ": "America/New_York",
    "PA": "America/New_York",
    "NY": "America/New_York",
    "CT": "America/New_York",
    "RI": "America/New_York",
    "MA": "America/New_York",
    "VT": "America/New_York",
    "NH": "America/New_York",
    "ME": "America/New_York",
    "DC": "America/New_York",
}


# ===================================================================
# Timezone Inference
# ===================================================================


def infer_timezone_from_location(
    state: str | None,
    country: str | None,
) -> str:
    """
    Infer an IANA timezone string from location data.

    For US users, maps the state abbreviation to the predominant timezone.
    For non-US users or when state is unknown, falls back to DEFAULT_TIMEZONE.

    Args:
        state: State/province abbreviation (e.g., "TX", "CA").
        country: Country code (e.g., "US", "UK").

    Returns:
        IANA timezone string (e.g., "America/Chicago").
    """
    if country and country.upper() == "US" and state:
        tz_name = _US_STATE_TIMEZONES.get(state.upper())
        if tz_name:
            return tz_name

    return DEFAULT_TIMEZONE


def get_user_timezone(
    user_timezone: str | None,
    vault_state: str | None = None,
    vault_country: str | None = None,
) -> ZoneInfo:
    """
    Resolve the user's timezone as a ZoneInfo object.

    Priority:
    1. User's explicitly set timezone (users.timezone column)
    2. Inferred from vault location (partner_vaults.location_state/country)
    3. Fallback to DEFAULT_TIMEZONE

    Args:
        user_timezone: IANA timezone from users table (may be None).
        vault_state: State/province from partner_vaults (may be None).
        vault_country: Country from partner_vaults (may be None).

    Returns:
        ZoneInfo timezone object.
    """
    if user_timezone:
        try:
            return ZoneInfo(user_timezone)
        except Exception:
            logger.warning(
                "Invalid timezone '%s' in user record, falling back to inference",
                user_timezone,
            )

    tz_name = infer_timezone_from_location(vault_state, vault_country)
    return ZoneInfo(tz_name)


# ===================================================================
# Quiet Hours Check (Pure Function)
# ===================================================================


def is_in_quiet_hours(
    quiet_hours_start: int,
    quiet_hours_end: int,
    user_tz: ZoneInfo,
    now_utc: datetime | None = None,
) -> tuple[bool, datetime | None]:
    """
    Check whether the current time is within the user's quiet hours.

    Handles the common case where quiet hours span midnight (e.g., 22:00-08:00)
    as well as the edge case where they do not (e.g., 01:00-06:00).
    When start == end, quiet hours are disabled.

    Args:
        quiet_hours_start: Hour when quiet hours begin (0-23).
        quiet_hours_end: Hour when quiet hours end (0-23).
        user_tz: The user's timezone as a ZoneInfo object.
        now_utc: Current UTC time (injectable for testing). Defaults to now().

    Returns:
        Tuple of:
        - is_quiet (bool): True if current time is within quiet hours.
        - next_delivery_time (datetime | None): UTC datetime when the notification
          should be delivered instead. None if not in quiet hours.
    """
    if now_utc is None:
        now_utc = datetime.now(tz.utc)

    # Convert current UTC time to user's local time
    now_local = now_utc.astimezone(user_tz)
    current_hour = now_local.hour

    # Determine if we're in quiet hours
    if quiet_hours_start > quiet_hours_end:
        # Spans midnight: e.g., 22:00-08:00
        # Quiet if hour >= start OR hour < end
        is_quiet = current_hour >= quiet_hours_start or current_hour < quiet_hours_end
    elif quiet_hours_start < quiet_hours_end:
        # Same day: e.g., 01:00-06:00
        is_quiet = quiet_hours_start <= current_hour < quiet_hours_end
    else:
        # start == end means quiet hours are disabled
        is_quiet = False

    if not is_quiet:
        return (False, None)

    # Calculate next delivery time: quiet_hours_end on the appropriate day
    next_delivery_time = _compute_next_delivery_time(
        quiet_hours_end, now_local, user_tz,
    )

    return (True, next_delivery_time)


def _compute_next_delivery_time(
    quiet_hours_end: int,
    now_local: datetime,
    user_tz: ZoneInfo,
) -> datetime:
    """
    Compute the next valid delivery time in UTC.

    If the end hour is later today (in user's local time), use today.
    Otherwise, use tomorrow. Constructs the target time using the
    timezone-aware constructor to handle DST gaps correctly (e.g.,
    if quiet_hours_end=2 and 2am is skipped during spring-forward,
    the result lands on the correct wall-clock time post-transition).

    Args:
        quiet_hours_end: Hour when quiet hours end (0-23).
        now_local: Current time in the user's local timezone.
        user_tz: The user's timezone.

    Returns:
        datetime in UTC when the notification should be delivered.
    """
    # Build candidate as a timezone-aware datetime from scratch to
    # avoid DST gap issues that can occur with replace().
    target_date = now_local.date()
    candidate = datetime(
        target_date.year, target_date.month, target_date.day,
        quiet_hours_end, 0, 0,
        tzinfo=user_tz,
    )

    if candidate <= now_local:
        # End hour has already passed today; use tomorrow
        candidate += timedelta(days=1)

    # Convert back to UTC for QStash scheduling
    return candidate.astimezone(tz.utc)


# ===================================================================
# High-Level Check (DB Lookup + DND Check)
# ===================================================================


async def check_quiet_hours(user_id: str) -> tuple[bool, datetime | None]:
    """
    Check if a notification for this user should be deferred due to quiet hours.

    Loads the user's quiet hours preferences and timezone from the database,
    then checks against the current time.

    Args:
        user_id: UUID of the user.

    Returns:
        Tuple of:
        - is_quiet (bool): True if the notification should be rescheduled.
        - next_delivery_time (datetime | None): UTC time to reschedule to.
          None if not in quiet hours.
    """
    client = get_service_client()

    # Load user quiet hours settings
    user_result = (
        client.table("users")
        .select("quiet_hours_start, quiet_hours_end, timezone")
        .eq("id", user_id)
        .execute()
    )

    if not user_result.data:
        logger.warning(
            "User %s not found for DND check — allowing delivery",
            user_id[:8],
        )
        return (False, None)

    user = user_result.data[0]
    quiet_start = user.get("quiet_hours_start", DEFAULT_QUIET_HOURS_START)
    quiet_end = user.get("quiet_hours_end", DEFAULT_QUIET_HOURS_END)
    user_timezone = user.get("timezone")

    # If user has no explicit timezone, try to infer from vault location
    vault_state = None
    vault_country = None
    if not user_timezone:
        vault_result = (
            client.table("partner_vaults")
            .select("location_state, location_country")
            .eq("user_id", user_id)
            .execute()
        )
        if vault_result.data:
            vault_state = vault_result.data[0].get("location_state")
            vault_country = vault_result.data[0].get("location_country")

    user_tz = get_user_timezone(user_timezone, vault_state, vault_country)

    return is_in_quiet_hours(quiet_start, quiet_end, user_tz)
