"""Domain models, money/time formatting and the pure earnings math.

The earnings math mirrors public.job_earned_seconds() in the database and is
used only for live ticking between server snapshots; the server remains the
source of truth.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime

DIFFICULTY_COLORS = {
    1: "#6FA287",
    2: "#8598B5",
    3: "#D99A5B",
    4: "#CE8158",
    5: "#C96A5F",
}


def parse_ts(value: str | None) -> datetime | None:
    """Parse a Postgres/ISO timestamp (with or without timezone) to aware UTC."""
    if not value:
        return None
    text = value.replace("Z", "+00:00")
    # Postgres may emit microseconds with variable width; fromisoformat copes
    # since Python 3.11.
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


def fmt_money(amount: float) -> str:
    """1234567.5 -> '1 234 567.50 ₴'"""
    sign = "-" if amount < 0 else ""
    whole, frac = divmod(round(abs(amount) * 100), 100)
    grouped = f"{whole:,}".replace(",", " ")
    return f"{sign}{grouped}.{frac:02d} ₴"


def fmt_duration(total_seconds: int) -> str:
    """3725 -> '1:02:05'; 90061 -> '25:01:01' (hours keep growing, no days)."""
    total_seconds = max(0, int(total_seconds))
    hours, rem = divmod(total_seconds, 3600)
    minutes, seconds = divmod(rem, 60)
    return f"{hours}:{minutes:02d}:{seconds:02d}"


def fmt_datetime_local(dt: datetime | None) -> str:
    if dt is None:
        return ""
    return dt.astimezone().strftime("%d.%m.%Y %H:%M")


def fmt_date_local(dt: datetime | None) -> str:
    if dt is None:
        return ""
    return dt.astimezone().strftime("%d.%m.%Y")


# Deadline state thresholds shared across platforms.
DEADLINE_SOON_HOURS = 24


def fmt_deadline(dt: datetime | None, now: datetime | None = None) -> tuple[str, str]:
    """Human deadline text + state ('none'|'normal'|'soon'|'overdue').

    'сьогодні до 18:00', 'завтра 09:00', 'через 3 дні', or a plain date for
    far dates; overdue past the moment, 'soon' within 24h. now is injectable
    for tests; defaults to the local clock.
    """
    if dt is None:
        return "", "none"
    local = dt.astimezone()
    now_local = (now or datetime.now(UTC)).astimezone()
    delta = local - now_local
    secs = delta.total_seconds()
    hhmm = local.strftime("%H:%M")

    if secs < 0:
        state = "overdue"
    elif secs <= DEADLINE_SOON_HOURS * 3600:
        state = "soon"
    else:
        state = "normal"

    today = now_local.date()
    day_diff = (local.date() - today).days
    if state == "overdue":
        text = "прострочено · %s" % fmt_datetime_local(dt)
    elif day_diff == 0:
        text = "сьогодні до %s" % hhmm
    elif day_diff == 1:
        text = "завтра %s" % hhmm
    elif 2 <= day_diff <= 6:
        text = "через %d дн%s" % (day_diff, "і" if day_diff < 5 else "ів")
    else:
        text = local.strftime("%d.%m.%Y %H:%M")
    return text, state


@dataclass(frozen=True)
class Session:
    started_at: datetime
    ended_at: datetime | None  # None -> still running


def earned_seconds(sessions: Iterable[Session], reset_at: datetime, now: datetime) -> int:
    """Seconds inside `sessions` that fall after `reset_at` and before `now`.

    Mirrors public.job_earned_seconds().
    """
    total = 0.0
    for s in sessions:
        end = min(s.ended_at or now, now)
        start = max(s.started_at, reset_at)
        if end > start:
            total += (end - start).total_seconds()
    return int(total)


def total_seconds(sessions: Iterable[Session], now: datetime) -> int:
    """Full shared timer: the sum of all sessions, never reset."""
    total = 0.0
    for s in sessions:
        end = min(s.ended_at or now, now)
        if end > s.started_at:
            total += (end - s.started_at).total_seconds()
    return int(total)


def balance_for(seconds: int, hourly_rate: float) -> float:
    return round(seconds / 3600.0 * hourly_rate, 2)
