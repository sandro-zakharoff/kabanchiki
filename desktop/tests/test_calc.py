"""Pure-math tests for the earnings/timer calculations (mirror of the SQL)."""

import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from kabanchiki_admin.models import (
    Session,
    acorn_unit,
    earned_seconds,
    fmt_acorns,
    fmt_acorns_words,
    fmt_duration,
    live_acorns,
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


def test_live_acorns_only_ever_whole():
    # 30 min at 60/h: exactly 30 acorns (1800 s banked as 1800*60 acorn-seconds)
    assert live_acorns(1800 * 60, 0, 60) == 30
    # half an acorn earned is not shown as anything yet — and is not lost either
    assert live_acorns(1800 * 1, 0, 1) == 0
    # ticking forward: the same floor the server applies, never a fraction
    assert live_acorns(0, 1799, 100) == 49
    assert live_acorns(0, 1800, 100) == 50
    # the carried remainder matures without the tick ever going backwards
    assert live_acorns(1800 * 1, 1800, 1) == 1
    assert live_acorns(0, 0, 100) == 0


def test_acorn_unit_declension():
    # Ukrainian: one / few / many, driven by the last two digits
    assert acorn_unit(1) == "жолудь"
    assert acorn_unit(2) == "жолуді"
    assert acorn_unit(4) == "жолуді"
    assert acorn_unit(5) == "жолудів"
    assert acorn_unit(0) == "жолудів"
    # the teens are the trap: 11-14 take the 'many' form, not the 'one'/'few'
    assert acorn_unit(11) == "жолудів"
    assert acorn_unit(12) == "жолудів"
    assert acorn_unit(14) == "жолудів"
    assert acorn_unit(21) == "жолудь"
    assert acorn_unit(22) == "жолуді"
    assert acorn_unit(25) == "жолудів"
    assert acorn_unit(111) == "жолудів"
    assert acorn_unit(121) == "жолудь"
    # sign never changes the form
    assert acorn_unit(-3) == "жолуді"
    assert acorn_unit(1, "en") == "acorn"
    assert acorn_unit(5, "en") == "acorns"


def test_fmt_acorns():
    assert fmt_acorns(0) == "0"
    assert fmt_acorns(1234567) == "1 234 567"
    assert fmt_acorns(-12) == "-12"
    # the mark is an icon, so the number carries no unit of its own
    assert "₴" not in fmt_acorns(100)


def test_fmt_acorns_words():
    assert fmt_acorns_words(1) == "1 жолудь"
    assert fmt_acorns_words(883) == "883 жолуді"  # ...83 -> few
    assert fmt_acorns_words(885) == "885 жолудів"  # ...85 -> many
    assert fmt_acorns_words(1234) == "1 234 жолуді"
    assert fmt_acorns_words(2, "en") == "2 acorns"


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
