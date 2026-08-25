"""
Notification Scheduler — Computes milestone dates and schedules notifications.

Handles the core scheduling logic for proactive notifications:
1. Computes the next real-world occurrence of a milestone (yearly recurrence,
   floating holidays, leap year edge cases).
2. Creates notification_queue entries for 14, 7, and 3 days before the milestone.
3. Publishes corresponding QStash messages for delayed delivery.

Step 7.2: Create notification scheduling logic.
"""

import calendar
import logging
from collections.abc import Callable
from datetime import date, datetime, time, timedelta, timezone

from app.core.config import WEBHOOK_BASE_URL, is_qstash_configured
from app.db.supabase_client import get_service_client
from app.services.occasion_category import resolve_occasion_category
from app.services.qstash import publish_to_qstash

logger = logging.getLogger(__name__)

NOTIFICATION_DAYS_BEFORE = [14, 7, 3]


# ===================================================================
# Computed Holiday Dates
# ===================================================================
#
# Three kinds of holiday need real computation rather than the stored
# "2000-MM-DD" placeholder:
#
#   1. Nth-weekday-of-month  — Mother's/Father's Day, Thanksgiving.
#   2. Computus              — Easter.
#   3. Lunisolar             — Hanukkah, Diwali, Lunar New Year, Eid, which
#                              track the Hebrew / Hindu / Chinese / Islamic
#                              calendars and cannot be derived with stdlib
#                              `datetime`.
#
# (3) is a lookup table rather than a dependency: the backend ships stdlib-only
# date handling, and adding convertdate/hijri-converter to requirements.txt for
# four holidays is a poor trade. The table runs to 2035 and returns None past
# its horizon, so an unresolvable milestone is skipped rather than firing on a
# wrong date.

_SUNDAY = 6
_THURSDAY = 3


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    """
    The nth occurrence of a weekday in a month (n is 1-based).

    weekday uses date.weekday() numbering: Monday=0 … Sunday=6.
    """
    first = date(year, month, 1)
    days_until = (weekday - first.weekday()) % 7
    return first + timedelta(days=days_until + 7 * (n - 1))


def _mothers_day(year: int) -> date:
    """Mother's Day — 2nd Sunday of May (US)."""
    return _nth_weekday(year, 5, _SUNDAY, 2)


def _fathers_day(year: int) -> date:
    """Father's Day — 3rd Sunday of June (US)."""
    return _nth_weekday(year, 6, _SUNDAY, 3)


def _thanksgiving(year: int) -> date:
    """Thanksgiving — 4th Thursday of November (US)."""
    return _nth_weekday(year, 11, _THURSDAY, 4)


def _easter(year: int) -> date:
    """
    Easter Sunday (Western / Gregorian) via the anonymous Gregorian computus.

    Meeus/Jones/Butcher algorithm — exact for all Gregorian years.
    """
    a = year % 19
    b, c = divmod(year, 100)
    d, e = divmod(b, 4)
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = divmod(c, 4)
    lunar = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * lunar) // 451
    month, day = divmod(h + lunar - 7 * m + 114, 31)
    return date(year, month, day + 1)


#: Actual dates for the lunisolar holidays, sorted ascending per category.
#:
#: Stored as a flat sequence rather than {year: (month, day)} because the
#: Islamic calendar drifts ~11 days a year, so Eid al-Fitr can fall twice in one
#: Gregorian year (2033 sees both Jan 2 and Dec 22) or, in other alignments, not
#: at all. A year-keyed map cannot express that.
#:
#: Eid dates are moon-sighting dependent and vary by up to a day between
#: regions; these are the widely-published civil-calendar values.
_LUNISOLAR_DATES: dict[str, tuple[date, ...]] = {
    "hanukkah": (  # first night
        date(2026, 12, 4), date(2027, 12, 24), date(2028, 12, 12),
        date(2029, 12, 1), date(2030, 12, 20), date(2031, 12, 9),
        date(2032, 11, 27), date(2033, 12, 16), date(2034, 12, 6),
        date(2035, 12, 25),
    ),
    "diwali": (  # Lakshmi Puja, the main day
        date(2026, 11, 8), date(2027, 10, 29), date(2028, 11, 15),
        date(2029, 11, 5), date(2030, 10, 26), date(2031, 11, 14),
        date(2032, 11, 2), date(2033, 10, 22), date(2034, 11, 10),
        date(2035, 10, 30),
    ),
    "lunar_new_year": (
        date(2026, 2, 17), date(2027, 2, 6), date(2028, 1, 26),
        date(2029, 2, 13), date(2030, 2, 3), date(2031, 1, 23),
        date(2032, 2, 11), date(2033, 1, 31), date(2034, 2, 19),
        date(2035, 2, 8),
    ),
    "eid": (  # Eid al-Fitr
        date(2026, 3, 20), date(2027, 3, 9), date(2028, 2, 26),
        date(2029, 2, 14), date(2030, 2, 4), date(2031, 1, 24),
        date(2032, 1, 14), date(2033, 1, 2), date(2033, 12, 22),
        date(2034, 12, 11), date(2035, 11, 30),
    ),
}

#: Categories resolvable by a pure year → date function.
_COMPUTED_HOLIDAYS: dict[str, Callable[[int], date]] = {
    "mothers_day": _mothers_day,
    "fathers_day": _fathers_day,
    "thanksgiving": _thanksgiving,
    "easter": _easter,
}


def _next_computed_occurrence(category: str, today: date) -> date | None:
    """
    Next occurrence of a category whose date is not fixed in the Gregorian
    calendar, or None if the category isn't one of those (or the lunisolar
    table has run out).
    """
    compute = _COMPUTED_HOLIDAYS.get(category)
    if compute is not None:
        this_year = compute(today.year)
        return this_year if this_year > today else compute(today.year + 1)

    dates = _LUNISOLAR_DATES.get(category)
    if dates is not None:
        return next((d for d in dates if d > today), None)

    return None


# ===================================================================
# Next Occurrence Computation
# ===================================================================

def compute_next_occurrence(
    milestone_date: date,
    milestone_name: str,
    recurrence: str,
    occasion_category: str | None = None,
    milestone_type: str = "",
) -> date | None:
    """
    Compute the next future occurrence of a milestone from today.

    For yearly milestones:
      - Holidays whose date is not fixed in the Gregorian calendar
        (Mother's/Father's Day, Thanksgiving, Easter, and the lunisolar four)
        are computed from the occasion category, ignoring the stored date.
      - Fixed-date milestones: replace the year-2000 placeholder with
        the current year. If already past, use next year.
      - Feb 29 birthdays: clamp to Feb 28 in non-leap years.

    For one-time milestones:
      - Return the stored date if it is in the future, None otherwise.

    Args:
        milestone_date: The stored milestone date (year 2000 for yearly).
        milestone_name: Display name — used only to resolve the category when
                        `occasion_category` is absent (rows predating
                        migration 00027).
        recurrence: "yearly" or "one_time".
        occasion_category: The stable occasion key, when known. Preferred over
                        name matching, which is why a milestone called
                        "Grandmother's Birthday" no longer lands on Mother's Day.
        milestone_type: The stored type, when known. Confines name matching to
                        holidays, so a *custom* milestone called "Easter egg
                        hunt" keeps the date the user picked instead of being
                        rescheduled onto Easter.

    Returns:
        The next occurrence date, or None if the milestone has passed (one-time)
        or is a lunisolar holiday past the lookup table's horizon.
    """
    today = date.today()

    if recurrence == "one_time":
        return milestone_date if milestone_date > today else None

    # Yearly recurrence — categories with real calendar rules win over the
    # stored placeholder date, which is meaningless for them.
    category = resolve_occasion_category(
        occasion_category=occasion_category,
        milestone_name=milestone_name,
        milestone_type=milestone_type,
    )
    computed = _next_computed_occurrence(category, today)
    if computed is not None:
        return computed

    if category in _LUNISOLAR_DATES:
        # Past the table horizon — better to schedule nothing than to fall
        # through and fire on the meaningless placeholder date.
        logger.warning(
            "No lunisolar date on file for category %s after %s — "
            "skipping. Extend _LUNISOLAR_DATES.", category, today.isoformat(),
        )
        return None

    # Fixed-date yearly milestone (month/day from stored date)
    month, day = milestone_date.month, milestone_date.day

    # Handle Feb 29 in non-leap years
    if month == 2 and day == 29 and not calendar.isleap(today.year):
        this_year_date = date(today.year, 2, 28)
    else:
        this_year_date = date(today.year, month, day)

    if this_year_date > today:
        return this_year_date

    # This year's date has passed — use next year
    next_year = today.year + 1
    if month == 2 and day == 29 and not calendar.isleap(next_year):
        return date(next_year, 2, 28)
    return date(next_year, month, day)


# ===================================================================
# Notification Scheduling
# ===================================================================

async def schedule_milestone_notifications(
    milestone_id: str,
    user_id: str,
    milestone_date: date,
    milestone_name: str,
    recurrence: str,
    occasion_category: str | None = None,
    milestone_type: str = "",
) -> list[dict]:
    """
    Schedule 14-day, 7-day, and 3-day notifications for a milestone.

    Creates notification_queue entries in the database and publishes
    QStash messages for delayed delivery. Skips intervals where the
    scheduled_for date has already passed.

    Args:
        milestone_id: UUID of the milestone row.
        user_id: UUID of the user who owns the milestone.
        milestone_date: The stored milestone date.
        milestone_name: Display name (used for floating holiday detection).
        recurrence: "yearly" or "one_time".

    Returns:
        List of created notification_queue rows (dicts).
    """
    next_occurrence = compute_next_occurrence(
        milestone_date, milestone_name, recurrence, occasion_category,
        milestone_type,
    )
    if next_occurrence is None:
        logger.info(
            f"Milestone {milestone_id[:8]}... has no future occurrence — "
            f"skipping notification scheduling"
        )
        return []

    now = datetime.now(timezone.utc)
    next_dt = datetime.combine(next_occurrence, time.min, tzinfo=timezone.utc)

    client = get_service_client()
    created_notifications = []
    webhook_url = f"{WEBHOOK_BASE_URL}/api/v1/notifications/process"

    for days_before in NOTIFICATION_DAYS_BEFORE:
        scheduled_for = next_dt - timedelta(days=days_before)

        if scheduled_for <= now:
            logger.debug(
                f"Skipping {days_before}-day notification for milestone "
                f"{milestone_id[:8]}... — scheduled_for {scheduled_for.isoformat()} "
                f"is in the past"
            )
            continue

        # Insert into notification_queue
        row = {
            "user_id": user_id,
            "milestone_id": milestone_id,
            "scheduled_for": scheduled_for.isoformat(),
            "days_before": days_before,
            "status": "pending",
        }

        try:
            result = (
                client.table("notification_queue")
                .insert(row)
                .execute()
            )
            notification_row = result.data[0]
            created_notifications.append(notification_row)

            logger.info(
                f"Created notification_queue entry: id={notification_row['id'][:8]}..., "
                f"milestone={milestone_id[:8]}..., days_before={days_before}, "
                f"scheduled_for={scheduled_for.isoformat()}"
            )
        except Exception as exc:
            logger.error(
                f"Failed to insert notification_queue entry for milestone "
                f"{milestone_id[:8]}... ({days_before} days before): {exc}"
            )
            continue

        # Publish to QStash (if configured)
        if is_qstash_configured():
            not_before_ts = int(scheduled_for.timestamp())
            dedup_id = f"{milestone_id}-{days_before}"

            payload = {
                "notification_id": notification_row["id"],
                "user_id": user_id,
                "milestone_id": milestone_id,
                "days_before": days_before,
            }

            try:
                await publish_to_qstash(
                    destination_url=webhook_url,
                    body=payload,
                    not_before=not_before_ts,
                    deduplication_id=dedup_id,
                )
            except Exception as exc:
                logger.warning(
                    f"Failed to publish QStash message for notification "
                    f"{notification_row['id'][:8]}...: {exc}"
                )

    logger.info(
        f"Scheduled {len(created_notifications)} notifications for milestone "
        f"{milestone_id[:8]}... (next occurrence: {next_occurrence.isoformat()})"
    )
    return created_notifications


async def schedule_notifications_for_milestones(
    milestones: list[dict],
    user_id: str,
) -> list[dict]:
    """
    Schedule notifications for a batch of milestones.

    Called after vault creation or update to process all milestones
    at once. Iterates over the milestone rows (as returned by
    Supabase insert) and schedules notifications for each.

    Args:
        milestones: List of milestone row dicts from Supabase
                    (must include id, milestone_date, milestone_name,
                    recurrence).
        user_id: UUID of the user who owns the milestones.

    Returns:
        Combined list of all created notification_queue rows.
    """
    all_notifications = []

    for m in milestones:
        milestone_date_val = m["milestone_date"]
        if isinstance(milestone_date_val, str):
            milestone_date_val = date.fromisoformat(milestone_date_val)

        notifications = await schedule_milestone_notifications(
            milestone_id=m["id"],
            user_id=user_id,
            milestone_date=milestone_date_val,
            milestone_name=m["milestone_name"],
            recurrence=m["recurrence"],
            occasion_category=m.get("occasion_category"),
            milestone_type=m.get("milestone_type", ""),
        )
        all_notifications.extend(notifications)

    logger.info(
        f"Scheduled {len(all_notifications)} total notifications "
        f"across {len(milestones)} milestones for user {user_id[:8]}..."
    )
    return all_notifications
