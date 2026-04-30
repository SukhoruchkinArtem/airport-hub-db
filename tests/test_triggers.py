from datetime import datetime
import threading
import time
import psycopg
import pytest
from conftest import DB_PARAMS


# trg_flight_status_check
@pytest.mark.parametrize("from_status,to_status", [
    ("SCHEDULED", "BOARDING"),
    ("SCHEDULED", "DELAYED"),
    ("SCHEDULED", "CANCELLED"),
    ("BOARDING", "DEPARTED"),
    ("BOARDING", "DELAYED"),
    ("BOARDING", "CANCELLED"),
    ("DELAYED", "BOARDING"),
    ("DELAYED", "CANCELLED"),
    ("DEPARTED", "ARRIVED"),
])
def test_fsm_allowed_transition(db, seed, from_status, to_status):
    """Рейс вставлен сразу в from_status.
    Шаги: UPDATE на to_status.
    Ожидание: успех"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9300, 'T1', 'SU9300', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '4 hours',
                'SVO', 'LED', 'PASSENGER', %s, 'TEST-01')
    """, (from_status,))
    db.execute("UPDATE flight SET status = %s WHERE flight_id = 9300", (to_status,))
    db.execute("SELECT status FROM flight WHERE flight_id = 9300")
    assert db.fetchone()[0] == to_status


@pytest.mark.parametrize("from_status,to_status", [
    ("SCHEDULED", "ARRIVED"),
    ("SCHEDULED", "DEPARTED"),
    ("ARRIVED", "BOARDING"),
    ("CANCELLED", "SCHEDULED"),
    ("DEPARTED", "SCHEDULED"),
])
def test_fsm_disallowed_transition_raises(db, seed, from_status, to_status):
    """Рейс в from_status.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9301, 'T1', 'SU9301', NOW() + INTERVAL '1 hour', NOW() + INTERVAL '4 hours',
                'SVO', 'LED', 'PASSENGER', %s, 'TEST-01')
    """, (from_status,))

    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        db.execute("UPDATE flight SET status = %s WHERE flight_id = 9301", (to_status,))
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_fsm_departed_sets_actual_departure_time(db, seed):
    """SCHEDULED → BOARDING → DEPARTED.
    Ожидание: actual_departure_time проставлено триггером."""
    db.execute("UPDATE flight SET status = 'BOARDING' WHERE flight_id = %s", (seed["flight_id"],))
    db.execute("UPDATE flight SET status = 'DEPARTED' WHERE flight_id = %s", (seed["flight_id"],))
    db.execute("SELECT actual_departure_time FROM flight WHERE flight_id = %s", (seed["flight_id"],))
    assert db.fetchone()[0] is not None


def test_fsm_arrived_sets_actual_arrival_time(db, seed):
    """SCHEDULED → BOARDING → DEPARTED → ARRIVED.
    Ожидание: actual_arrival_time проставлено триггером."""
    db.execute("UPDATE flight SET status = 'BOARDING' WHERE flight_id = %s", (seed["flight_id"],))
    db.execute("UPDATE flight SET status = 'DEPARTED' WHERE flight_id = %s", (seed["flight_id"],))
    db.execute("UPDATE flight SET status = 'ARRIVED' WHERE flight_id = %s", (seed["flight_id"],))
    db.execute("SELECT actual_arrival_time FROM flight WHERE flight_id = %s", (seed["flight_id"],))
    assert db.fetchone()[0] is not None


def test_fsm_cancelled_cascades_only_planned_slots(db, seed):
    """У рейса PLANNED-слот и ACTIVE-слот.
    Шаги: рейс стал CANCELLED.
    Ожидание: PLANNED стал CANCELLED, ACTIVE остался ACTIVE."""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9301, %s, %s, NOW() + INTERVAL '1 hour', NOW() + INTERVAL '2 hours', 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"]))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9302, %s, %s, NOW() + INTERVAL '3 hours', NOW() + INTERVAL '4 hours', 'ACTIVE')
    """, (seed["runway_id"], seed["flight_id"]))

    db.execute("UPDATE flight SET status = 'CANCELLED' WHERE flight_id = %s", (seed["flight_id"],))

    db.execute("SELECT status FROM time_slot WHERE slot_id = 9301")
    assert db.fetchone()[0] == "CANCELLED"
    db.execute("SELECT status FROM time_slot WHERE slot_id = 9302")
    assert db.fetchone()[0] == "ACTIVE"


# trg_prevent_timeslot_overlap
def _ts(hour=10, minute=0):
    return datetime(2030, 1, 1, hour, minute)


def test_overlap_non_overlapping_slots_succeed(db, seed):
    """Два слота на одной ВПП без пересечения.
    Ожидание: оба INSERT успешны."""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9401, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9402, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=12), _ts(hour=13)))


def test_overlap_different_runways_succeed(db, seed):
    """Пересекающиеся слоты на разных ВПП.
    Ожидание: оба INSERT успешны."""
    db.execute("INSERT INTO runway (runway_id, length, width, magnetic_course) VALUES (9402, 3000.0, 45.0, 270)")
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9403, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9404, 9402, %s, %s, %s, 'PLANNED')
    """, (seed["flight_id"], _ts(hour=10), _ts(hour=11)))


def test_overlap_overlapping_slots_raise(db, seed):
    """Первый слот 10:00–11:00.
    Шаги: вставить второй 10:30–11:30.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9405, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))

    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        db.execute("""
            INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
            VALUES (9406, %s, %s, %s, %s, 'PLANNED')
        """, (seed["runway_id"], seed["flight_id"], _ts(hour=10, minute=30), _ts(hour=11, minute=30)))
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_overlap_adjacent_slots_succeed(db, seed):
    """Первый слот 10:00–11:00.
    Шаги: вставить второй 11:00–12:00.
    Ожидание: успех"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9407, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9408, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=11), _ts(hour=12)))


def test_overlap_update_to_conflict_raises(db, seed):
    """Два непересекающихся слота.
    Шаги: UPDATE второго в диапазон первого.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9409, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9410, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=14), _ts(hour=15)))

    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        db.execute("UPDATE time_slot SET slot_start = %s, slot_end = %s WHERE slot_id = 9410",
                   (_ts(hour=10, minute=30), _ts(hour=11, minute=30)))
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_overlap_slot_inside_another_raises(db, seed):
    """Слот 10:00–13:00.
    Шаги: попытка вставить слот 11:00–12:00.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9412, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=13)))

    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        db.execute("""
            INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
            VALUES (9413, %s, %s, %s, %s, 'PLANNED')
        """, (seed["runway_id"], seed["flight_id"], _ts(hour=11), _ts(hour=12)))
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_overlap_update_self_succeeds(db, seed):
    """Один слот.
    Шаги: UPDATE того же слота.
    Ожидание: успех"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9411, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))

    db.execute("UPDATE time_slot SET status = 'ACTIVE' WHERE slot_id = 9411")
    db.execute("UPDATE time_slot SET slot_start = %s, slot_end = %s WHERE slot_id = 9411",
               (_ts(hour=10, minute=30), _ts(hour=11, minute=30)))


def test_overlap_existing_inactive_slot_ignored(db, seed):
    """В таблице уже есть CANCELLED слот.
    Шаги: вставляем PLANNED слот в тот же интервал.
    Ожидание: успех"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9414, %s, %s, %s, %s, 'CANCELLED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9415, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))


def test_overlap_new_inactive_slot_ignored(db, seed):
    """Есть PLANNED слот.
    Шаги: вставляем CANCELLED-слот в тот же интервал.
    Ожидание: успех"""
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9416, %s, %s, %s, %s, 'PLANNED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))
    db.execute("""
        INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
        VALUES (9417, %s, %s, %s, %s, 'CANCELLED')
    """, (seed["runway_id"], seed["flight_id"], _ts(hour=10), _ts(hour=11)))


def test_overlap_concurrent_same_runway_only_one_succeeds(db_conn):
    """Две одновременных вставки пересекающихся PLANNED слотов на одну ВПП.
    Ожидание: успешно только одно.
    """
    setup_cur = db_conn.cursor()
    try:
        setup_cur.execute("""
            INSERT INTO aircraft_type (aircraft_type_id, model, length, max_takeoff_weight,
                cruising_speed, max_altitude, max_range, max_cargo_volume)
            VALUES (9971, 'Slot Concurrent Test', 30.00, 70000.00, 800.00, 11000, 5000, 30.00)
        """)
        setup_cur.execute("""
            INSERT INTO aircraft (aircraft_name, aircraft_type_id, business_seats,
                premium_economy_seats, economy_seats, owner)
            VALUES ('SLOT-01', 9971, 5, 10, 20, 'Test')
        """)
        setup_cur.execute("INSERT INTO runway (runway_id, length, width, magnetic_course) VALUES (9971, 3000.0, 45.0, 90)")
        setup_cur.execute("""
            INSERT INTO flight (flight_id, flight_no, departure_time, arrival_time,
                departure_airport, arrival_airport, flight_type, status, aircraft_name)
            VALUES
                (9971, 'SL9971', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '5 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'SLOT-01'),
                (9972, 'SL9972', NOW() + INTERVAL '3 hours', NOW() + INTERVAL '6 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'SLOT-01')
        """)
        db_conn.commit()

        results = []
        errors = []
        first_inserted = threading.Event()

        def first_slot():
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("""
                    INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
                    VALUES (9971, 9971, 9971, TIMESTAMP '2030-01-01 10:00', TIMESTAMP '2030-01-01 11:00', 'PLANNED')
                """)
                results.append("first")
                first_inserted.set()
                time.sleep(1.0)
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
                first_inserted.set()
            finally:
                conn.close()

        def second_slot():
            first_inserted.wait(timeout=5)
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("""
                    INSERT INTO time_slot (slot_id, runway_id, flight_id, slot_start, slot_end, status)
                    VALUES (9972, 9971, 9972, TIMESTAMP '2030-01-01 10:30', TIMESTAMP '2030-01-01 11:30', 'PLANNED')
                """)
                results.append("second")
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
            finally:
                conn.close()

        t1 = threading.Thread(target=first_slot)
        t2 = threading.Thread(target=second_slot)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert len(results) == 1
        assert len(errors) == 1

        check = db_conn.cursor()
        check.execute("SELECT COUNT(*) FROM time_slot WHERE runway_id = 9971 AND status = 'PLANNED'")
        assert check.fetchone()[0] == 1

    finally:
        cleanup = db_conn.cursor()
        cleanup.execute("DELETE FROM time_slot WHERE runway_id = 9971")
        cleanup.execute("DELETE FROM flight WHERE flight_id IN (9971, 9972)")
        cleanup.execute("DELETE FROM runway WHERE runway_id = 9971")
        cleanup.execute("DELETE FROM aircraft WHERE aircraft_name = 'SLOT-01'")
        cleanup.execute("DELETE FROM aircraft_type WHERE aircraft_type_id = 9971")
        db_conn.commit()
