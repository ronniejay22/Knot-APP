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
from datetime import date, datetime, time, timedelta, timezone

from app.core.config import WEBHOOK_BASE_URL, is_qstash_configured
from app.db.supabase_client import get_service_client
from app.services.qstash import publish_to_qstash

logger = logging.getLogger(__name__)

NOTIFICATION_DAYS_BEFORE = [14, 7, 3]


# ===================================================================
# Floating Holiday Computation
# ===================================================================

def _mothers_day(year: int) -> date:
    """
    Compute Mother's Day for the given year.

    Mother's Day is the 2nd Sunday of May in the United States.
    """
    may_first = date(year, 5, 1)
    # weekday(): Monday=0, Sunday=6
    days_until_sunday = (6 - may_first.weekday()) % 7
    first_sunday = may_first + timedelta(days=days_until_sunday)
    return first_sunday + timedelta(days=7)


def _fathers_day(year: int) -> date:
    """
    Compute Father's Day for the given year.

    Father's Day is the 3rd Sunday of June in the United States.
    """
    june_first = date(year, 6, 1)
    days_until_sunday = (6 - june_first.weekday()) % 7
    first_sunday = june_first + timedelta(days=days_until_sunday)
    return first_sunday + timedelta(days=14)


def _is_floating_holiday(milestone_name: str) -> str | None:
    """
    Detect floating holidays by milestone name.

    Returns "mothers_day" or "fathers_day" if the milestone name
    contains "mother" or "father" (case-insensitive), else None.
    """
    name_lower = milestone_name.lower()
    if "mother" in name_lower:
        return "mothers_day"
    if "father" in name_lower:
        return "fathers_day"
    return None


# ===================================================================
# Next Occurrence Computation
# ===================================================================

def compute_next_occurrence(
    milestone_date: date,
    milestone_name: str,
    recurrence: str,
) -> date | None:
    """
    Compute the next future occurrence of a milestone from today.

    For yearly milestones:
      - Floating holidays (Mother's/Father's Day): compute the actual
        date for this year or next year using calendar rules.
      - Fixed-date milestones: replace the year-2000 placeholder with
        the current year. If already past, use next year.
      - Feb 29 birthdays: clamp to Feb 28 in non-leap years.

    For one-time milestones:
      - Return the stored date if it is in the future, None otherwise.

    Args:
        milestone_date: The stored milestone date (year 2000 for yearly).
        milestone_name: Display name used to detect floating holidays.
        recurrence: "yearly" or "one_time".

    Returns:
        The next occurrence date, or None if the milestone has passed
        (one-time only).
    """
    today = date.today()

    if recurrence == "one_time":
        return milestone_date if milestone_date > today else None

    # Yearly recurrence — check for floating holidays first
    floating = _is_floating_holiday(milestone_name)

    if floating == "mothers_day":
        this_year = _mothers_day(today.year)
        return this_year if this_year > today else _mothers_day(today.year + 1)

    if floating == "fathers_day":
        this_year = _fathers_day(today.year)
        return this_year if this_year > today else _fathers_day(today.year + 1)

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
        milestone_date, milestone_name, recurrence,
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
        )
        all_notifications.extend(notifications)

    logger.info(
        f"Scheduled {len(all_notifications)} total notifications "
        f"across {len(milestones)} milestones for user {user_id[:8]}..."
    )
    return all_notifications
