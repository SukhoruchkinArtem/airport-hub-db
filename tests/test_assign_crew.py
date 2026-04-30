import threading
import time
import psycopg
import pytest
from conftest import DB_PARAMS

def _expect_error(db, sql, params):
    db.execute("SAVEPOINT sp")
    with pytest.raises(psycopg.Error):
        db.execute(sql, params)
    db.execute("ROLLBACK TO SAVEPOINT sp")


def test_assign_crew_success(db, seed):
    """Сотрудник не назначен ни на один рейс.
    Ожидание: возвращается assignment_id, появляется запись в crew_assignment."""
    db.execute(
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )
    aid = db.fetchone()[0]
    assert aid is not None

    db.execute(
        "SELECT COUNT(*) FROM crew_assignment WHERE assignment_id = %s",
        (aid,),
    )
    assert db.fetchone()[0] == 1


def test_assign_crew_invalid_role_raises(db, seed):
    """Роль сотрудника CAPTAIN, передаём FIRST_OFFICER.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'FIRST_OFFICER')",
        (seed["flight_id"], seed["crew_id"]),
    )


def test_assign_crew_missing_flight_raises(db, seed):
    """flight_id не существует.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (999999, seed["crew_id"]),
    )


def test_assign_crew_missing_crew_raises(db, seed):
    """crew_id не существует.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], 999999),
    )


def test_assign_crew_duplicate_assignment_raises(db, seed):
    """Сотрудник уже назначен на этот рейс.
    Ожидание: повторное назначение отклоняется"""
    db.execute(
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )

    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )


def test_assign_crew_time_overlap_raises(db, seed):
    """Сотрудник уже назначен на пересекающийся по времени рейс.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9101, 'T1', 'SU9101',
            NOW() + INTERVAL '3 hours', NOW() + INTERVAL '6 hours',
            'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'TEST-01')
    """)
    db.execute(
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )

    _expect_error(
        db,
        "SELECT assign_crew_to_flight(9101, %s::int, 'CAPTAIN')",
        (seed["crew_id"],),
    )


def test_assign_crew_rest_time_violated_raises(db, seed):
    """Предыдущий рейс закончился < rest_time назад.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name,
            actual_arrival_time, actual_departure_time)
        VALUES (9102, 'T1', 'SU9102',
            NOW() - INTERVAL '4 hours', NOW() - INTERVAL '1 hour',
            'SVO', 'LED', 'PASSENGER', 'ARRIVED', 'TEST-01',
            NOW() - INTERVAL '1 hour', NOW() - INTERVAL '4 hours')
    """)
    db.execute(
        "SELECT assign_crew_to_flight(9102, %s::int, 'CAPTAIN')",
        (seed["crew_id"],),
    )

    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )


def test_assign_crew_rest_time_exactly_enough_succeeds(db, seed):
    """Разница между рейсами ровно rest_time (8h).
    Ожидание: успех"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name,
            actual_arrival_time, actual_departure_time)
        VALUES (9103, 'T1', 'SU9103',
            NOW() - INTERVAL '9 hours', NOW() - INTERVAL '6 hours',
            'SVO', 'LED', 'PASSENGER', 'ARRIVED', 'TEST-01',
            NOW() - INTERVAL '6 hours', NOW() - INTERVAL '9 hours')
    """)
    db.execute(
        "SELECT assign_crew_to_flight(9103, %s::int, 'CAPTAIN')",
        (seed["crew_id"],),
    )
    db.execute(
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )
    assert db.fetchone()[0] is not None


def test_assign_crew_rest_time_one_minute_short_raises(db, seed):
    """Разница между рейсами на 1 минуту меньше rest_time.
    Ожидание: ошибка"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name,
            actual_arrival_time, actual_departure_time)
        VALUES (9104, 'T1', 'SU9104',
            NOW() - INTERVAL '8 hours 59 minutes', NOW() - INTERVAL '5 hours 59 minutes',
            'SVO', 'LED', 'PASSENGER', 'ARRIVED', 'TEST-01',
            NOW() - INTERVAL '5 hours 59 minutes', NOW() - INTERVAL '8 hours 59 minutes')
    """)
    db.execute(
        "SELECT assign_crew_to_flight(9104, %s::int, 'CAPTAIN')",
        (seed["crew_id"],),
    )

    _expect_error(
        db,
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )


def test_assign_crew_cancelled_previous_flight_ignored(db, seed):
    """Сотрудник был назначен на отменённый рейс.
    Ожидание: отменённый рейс не создаёт конфликта и не ломает rest_time"""
    db.execute("""
        INSERT INTO flight (flight_id, gate_no, flight_no, departure_time, arrival_time,
            departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9105, 'T1', 'SU9105',
            NOW() + INTERVAL '2 hours 30 minutes', NOW() + INTERVAL '4 hours',
            'SVO', 'LED', 'PASSENGER', 'CANCELLED', 'TEST-01')
    """)
    db.execute("""
        INSERT INTO crew_assignment (crew_id, flight_id, role)
        VALUES (%s, 9105, 'CAPTAIN')
    """, (seed["crew_id"],))

    db.execute(
        "SELECT assign_crew_to_flight(%s::int, %s::int, 'CAPTAIN')",
        (seed["flight_id"], seed["crew_id"]),
    )
    assert db.fetchone()[0] is not None


def test_assign_crew_concurrent_overlap_only_one_succeeds(db_conn):
    """Два одновременных назначения одного сотрудника на пересекающиеся рейсы.
    Ожидание: ровно одно назначение успешно"""
    setup_cur = db_conn.cursor()
    try:
        setup_cur.execute("""
            INSERT INTO aircraft_type (aircraft_type_id, model, length, max_takeoff_weight,
                cruising_speed, max_altitude, max_range, max_cargo_volume)
            VALUES (9981, 'Crew Concurrent Test', 30.00, 70000.00, 800.00, 11000, 5000, 30.00)
        """)
        setup_cur.execute("""
            INSERT INTO aircraft (aircraft_name, aircraft_type_id, business_seats,
                premium_economy_seats, economy_seats, owner)
            VALUES ('CREW-01', 9981, 5, 10, 20, 'Test')
        """)
        setup_cur.execute("""
            INSERT INTO crew_member (crew_id, name, surname, role, company, license, rest_time)
            VALUES (9981, 'Concurrent', 'Captain', 'CAPTAIN', 'Test Air', 'LIC-CONC-01', '8 hours')
        """)
        setup_cur.execute("""
            INSERT INTO flight (flight_id, flight_no, departure_time, arrival_time,
                departure_airport, arrival_airport, flight_type, status, aircraft_name)
            VALUES
                (9981, 'AC9981', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '5 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'CREW-01'),
                (9982, 'AC9982', NOW() + INTERVAL '3 hours', NOW() + INTERVAL '6 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'CREW-01')
        """)
        db_conn.commit()

        results = []
        errors = []
        first_inserted = threading.Event()

        def first_assignment():
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("SELECT assign_crew_to_flight(9981, 9981, 'CAPTAIN')")
                results.append(cur.fetchone()[0])
                first_inserted.set()
                time.sleep(1.0)
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
                first_inserted.set()
            finally:
                conn.close()

        def second_assignment():
            first_inserted.wait(timeout=5)
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("SELECT assign_crew_to_flight(9982, 9981, 'CAPTAIN')")
                results.append(cur.fetchone()[0])
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
            finally:
                conn.close()

        t1 = threading.Thread(target=first_assignment)
        t2 = threading.Thread(target=second_assignment)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert len(results) == 1
        assert len(errors) == 1

        check = db_conn.cursor()
        check.execute("SELECT COUNT(*) FROM crew_assignment WHERE crew_id = 9981")
        assert check.fetchone()[0] == 1

    finally:
        cleanup = db_conn.cursor()
        cleanup.execute("DELETE FROM crew_assignment WHERE crew_id = 9981")
        cleanup.execute("DELETE FROM flight WHERE flight_id IN (9981, 9982)")
        cleanup.execute("DELETE FROM crew_member WHERE crew_id = 9981")
        cleanup.execute("DELETE FROM aircraft WHERE aircraft_name = 'CREW-01'")
        cleanup.execute("DELETE FROM aircraft_type WHERE aircraft_type_id = 9981")
        db_conn.commit()
