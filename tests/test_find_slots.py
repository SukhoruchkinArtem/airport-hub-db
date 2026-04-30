from datetime import datetime, timedelta
import psycopg
import pytest


def _ts(year=2030, month=1, day=1, hour=10, minute=0):
    return datetime(year, month, day, hour, minute)


def _fetch_windows(db, runway_id, start, end, duration):
    db.execute(
        "SELECT * FROM find_available_runway_slots(%s::int, %s, %s, %s)",
        (runway_id, start, end, duration),
    )
    return db.fetchall()


def test_find_slots_empty_runway_returns_full_window(db, seed):
    """На ВПП нет слотов в окне.
    Ожидание: возвращается одно окно от p_from_ts до p_to_ts."""
    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=10), _ts(hour=14), timedelta(minutes=30)
    )
    assert rows == [(_ts(hour=10), _ts(hour=14))]


def test_find_slots_one_slot_returns_exact_two_windows(db, seed):
    """Один PLANNED слот посередине окна.
    Ожидание: точные окна до слота и после него."""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9201, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13)))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=10), _ts(hour=15), timedelta(minutes=30)
    )
    assert rows == [(_ts(hour=10), _ts(hour=12)), (_ts(hour=13), _ts(hour=15))]


def test_find_slots_window_exactly_duration_included(db, seed):
    """Окно ровно длины p_duration.
    Ожидание: окно попадает в результат"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9202, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13)))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=11), _ts(hour=14), timedelta(hours=1)
    )
    assert rows == [(_ts(hour=11), _ts(hour=12)), (_ts(hour=13), _ts(hour=14))]


def test_find_slots_window_one_minute_short_excluded(db, seed):
    """Оба окна на 1 минуту меньше p_duration.
    Ожидание: ни одно окно не попадает в результат"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9203, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13)))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=11), _ts(hour=14), timedelta(hours=1, minutes=1)
    )
    assert rows == []


def test_find_slots_adjacent_slots_cover_window_returns_empty(db, seed):
    """Два слота примыкают встык и покрывают всё окно.
    Ожидание: нулевое окно между ними не возвращается"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9204, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9205, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=13), _ts(hour=14)))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=12), _ts(hour=14), timedelta(minutes=1)
    )
    assert rows == []


@pytest.mark.parametrize("status", ["CANCELLED", "COMPLETED"])
def test_find_slots_inactive_slots_ignored(db, seed, status):
    """В окне есть CANCELLED/COMPLETED слот.
    Ожидание: он игнорируется, всё окно свободно"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9206, %s, %s, %s, %s, %s)
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13), status))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=10), _ts(hour=14), timedelta(minutes=30)
    )
    assert rows == [(_ts(hour=10), _ts(hour=14))]


def test_find_slots_multiple_slots_with_exact_gaps(db, seed):
    """Три PLANNED-слота с промежутками между ними.
    Ожидание: возвращаются точные окна до, между и после слотов"""
    for slot_id, start_h, end_h in [
        (9208, 11, 12),
        (9209, 13, 14),
        (9210, 15, 16),
    ]:
        db.execute("""
            INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
            VALUES (%s, %s, %s, %s, %s, 'PLANNED')
        """, (slot_id, seed["runway_id"], seed["flight_id"], _ts(hour=start_h), _ts(hour=end_h)))

    rows = _fetch_windows(
        db, seed["runway_id"], _ts(hour=10), _ts(hour=17), timedelta(minutes=30)
    )
    assert rows == [
        (_ts(hour=10), _ts(hour=11)),
        (_ts(hour=12), _ts(hour=13)),
        (_ts(hour=14), _ts(hour=15)),
        (_ts(hour=16), _ts(hour=17)),
    ]


def test_find_slots_invalid_time_range_raises(db, seed):
    """p_from_ts >= p_to_ts.
    Ожидание: функция отклоняет некорректный диапазон."""
    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        _fetch_windows(
            db, seed["runway_id"], _ts(hour=14), _ts(hour=10), timedelta(minutes=30)
        )
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_find_slots_missing_runway_raises(db, seed):
    """runway_id не существует.
    Ожидание: ошибка"""
    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        _fetch_windows(
            db, 999999, _ts(hour=10), _ts(hour=14), timedelta(minutes=30)
        )
    db.execute("ROLLBACK TO SAVEPOINT sp")
