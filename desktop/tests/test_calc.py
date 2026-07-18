"""Pure-math tests for the earnings/timer calculations (mirror of the SQL)."""

import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from kabanchiki_admin.models import (
    Session,
    balance_for,
    earned_seconds,
    fmt_duration,
    fmt_money,
    parse_ts,
    total_seconds,
)

T0 = datetime(2026, 7, 1, 12, 0, 0, tzinfo=UTC)


def at(minutes: float) -> datetime:
    return T0 + timedelta(minutes=minutes)


def test_single_open_session_ticks():
    sessions = [Session(started_at=at(0), ended_at=None)]
    assert earned_seconds(sessions, reset_at=at(0), now=at(30)) == 1800
    assert total_seconds(sessions, now=at(30)) == 1800


def test_reset_mid_session_splits_earnings_but_not_timer():
    sessions = [Session(started_at=at(0), ended_at=at(60))]
    # withdrawal approved at minute 45 -> only the last 15 minutes count
    assert earned_seconds(sessions, reset_at=at(45), now=at(60)) == 900
    assert total_seconds(sessions, now=at(60)) == 3600


def test_multiple_sessions_with_gap():
    sessions = [
        Session(started_at=at(0), ended_at=at(10)),
        Session(started_at=at(20), ended_at=at(35)),
        Session(started_at=at(50), ended_at=None),
    ]
    # reset before everything, now at minute 55: 10 + 15 + 5 minutes
    assert earned_seconds(sessions, reset_at=at(-5), now=at(55)) == 30 * 60
    # reset inside the gap: only 15 + 5 minutes
    assert earned_seconds(sessions, reset_at=at(15), now=at(55)) == 20 * 60
    # total timer never resets
    assert total_seconds(sessions, now=at(55)) == 30 * 60


def test_reset_after_all_sessions_is_zero():
    sessions = [Session(started_at=at(0), ended_at=at(10))]
    assert earned_seconds(sessions, reset_at=at(10), now=at(60)) == 0


def test_balance_rounding():
    # 1799 s at 100 ₴/h -> 49.97 (round half up on the cent boundary is fine)
    assert balance_for(1800, 100.0) == 50.0
    assert balance_for(3600, 55.5) == 55.5
    assert balance_for(0, 100.0) == 0.0


def test_fmt_money():
    assert fmt_money(0) == "0.00 ₴"
    assert fmt_money(1234567.5) == "1 234 567.50 ₴"
    assert fmt_money(-12.3) == "-12.30 ₴"


def test_fmt_duration():
    assert fmt_duration(0) == "0:00:00"
    assert fmt_duration(3725) == "1:02:05"
    assert fmt_duration(90061) == "25:01:01"


def test_parse_ts_variants():
    a = parse_ts("2026-07-01T12:00:00+00:00")
    b = parse_ts("2026-07-01T12:00:00Z")
    c = parse_ts("2026-07-01T14:00:00+02:00")
    assert a == b == c == T0
    assert parse_ts(None) is None
    assert parse_ts("") is None
