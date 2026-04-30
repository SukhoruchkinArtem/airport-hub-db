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


def test_book_seat_success(db, seed):
    """Рейс PASSENGER+SCHEDULED, место свободно.
    Шаги: вызвать book_seat.
    Ожидание: возвращается booking_id, в booking появилась запись."""
    db.execute(
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["flight_id"], seed["passenger_id"]),
    )
    booking_id = db.fetchone()[0]
    assert booking_id is not None

    db.execute(
        "SELECT COUNT(*) FROM booking WHERE flight_id = %s AND seat = '1A'",
        (seed["flight_id"],),
    )
    assert db.fetchone()[0] == 1


def test_book_seat_delayed_flight_succeeds(db, seed):
    """Рейс задержан, но ещё не началась посадка.
    Ожидание: бронирование разрешено"""
    db.execute(
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1B')",
        (seed["delayed_flight_id"], seed["passenger_id"]),
    )
    assert db.fetchone()[0] is not None


def test_book_seat_boarding_flight_raises(db, seed):
    """Рейс уже в статусе BOARDING.
    Ожидание: покупка билета во время посадки запрещена"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1C')",
        (seed["boarding_flight_id"], seed["passenger_id"]),
    )


def test_book_seat_duplicate_raises(db, seed):
    """Место уже забронировано.
    Шаги: попытаться забронировать то же место.
    Ожидание: ошибка, в booking осталась только одна запись."""
    db.execute(
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["flight_id"], seed["passenger_id"]),
    )

    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["flight_id"], seed["passenger_id"]),
    )

    db.execute(
        "SELECT COUNT(*) FROM booking WHERE flight_id = %s AND seat = '1A'",
        (seed["flight_id"],),
    )
    assert db.fetchone()[0] == 1


def test_book_seat_cargo_flight_raises(db, seed):
    """Рейс грузовой.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["cargo_flight_id"], seed["passenger_id"]),
    )


def test_book_seat_departed_flight_raises(db, seed):
    """Рейс уже вылетел.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["departed_flight_id"], seed["passenger_id"]),
    )


def test_book_seat_invalid_class_raises(db, seed):
    """Неверный класс.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'FIRST_CLASS', '1A')",
        (seed["flight_id"], seed["passenger_id"]),
    )


def test_book_seat_invalid_seat_format_raises(db, seed):
    """Формат места не соответствует регулярке.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', 'XYZ')",
        (seed["flight_id"], seed["passenger_id"]),
    )


def test_book_seat_missing_flight_raises(db, seed):
    """flight_id не существует.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (999999, seed["passenger_id"]),
    )


def test_book_seat_missing_passenger_raises(db, seed):
    """passenger_id не существует.
    Ожидание: ошибка"""
    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'ECONOMY', '1A')",
        (seed["flight_id"], 999999),
    )


def test_book_seat_class_capacity_exceeded_raises(db, seed):
    """Предусловие: 5 мест бизнес класса уже заняты.
    Шаги: попытка забронировать 6-е место.
    Ожидание: ошибка"""
    for seat in ("1A", "2A", "3A", "4A", "5A"):
        db.execute(
            "SELECT book_seat(%s::int, %s::int, 'BUSINESS', %s)",
            (seed["flight_id"], seed["passenger_id"], seat),
        )

    _expect_error(
        db,
        "SELECT book_seat(%s::int, %s::int, 'BUSINESS', '6A')",
        (seed["flight_id"], seed["passenger_id"]),
    )


def test_book_seat_concurrent_same_seat_only_one_succeeds(db_conn):
    """Два человека параллельно бронируют одно и то же место.
    Ожидание: ровно одно бронирование успешно, второе — с ошибкой.
    """
    setup_cur = db_conn.cursor()
    try:
        setup_cur.execute("""
            INSERT INTO aircraft_type (aircraft_type_id, model, length, max_takeoff_weight,
                cruising_speed, max_altitude, max_range, max_cargo_volume)
            VALUES (9991, 'Concurrent Seat Test', 30.00, 70000.00, 800.00, 11000, 5000, 30.00)
        """)
        setup_cur.execute("""
            INSERT INTO aircraft (aircraft_name, aircraft_type_id, business_seats,
                premium_economy_seats, economy_seats, owner)
            VALUES ('CONC-01', 9991, 5, 10, 20, 'Test')
        """)
        setup_cur.execute("""
            INSERT INTO passenger (passenger_id, name, surname, class, passport_id, birth_date)
            VALUES (9991, 'Conc', 'Test', 'GOLD', 'CONC000001', '1990-01-01')
        """)
        setup_cur.execute("""
            INSERT INTO flight (flight_id, flight_no, departure_time, arrival_time,
                departure_airport, arrival_airport, flight_type, status, aircraft_name)
            VALUES (9991, 'SU9991', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '5 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'CONC-01')
        """)
        db_conn.commit()

        results = []
        errors = []
        barrier = threading.Barrier(2)

        def book():
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                barrier.wait()
                cur.execute("SELECT book_seat(9991, 9991, 'ECONOMY', '1A')")
                results.append(cur.fetchone()[0])
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
            finally:
                conn.close()

        t1 = threading.Thread(target=book)
        t2 = threading.Thread(target=book)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert len(results) == 1
        assert len(errors) == 1

    finally:
        cleanup = db_conn.cursor()
        cleanup.execute("DELETE FROM booking WHERE flight_id = 9991")
        cleanup.execute("DELETE FROM flight WHERE flight_id = 9991")
        cleanup.execute("DELETE FROM passenger WHERE passenger_id = 9991")
        cleanup.execute("DELETE FROM aircraft WHERE aircraft_name = 'CONC-01'")
        cleanup.execute("DELETE FROM aircraft_type WHERE aircraft_type_id = 9991")
        db_conn.commit()


def test_book_seat_concurrent_capacity_only_one_succeeds(db_conn):
    """В бизнес классе есть только 1 место.
    Шаги: два соединения одновременно бронируют разные места.
    Ожидание: успешно только одно бронирование.
    """
    setup_cur = db_conn.cursor()
    try:
        setup_cur.execute("""
            INSERT INTO aircraft_type (aircraft_type_id, model, length, max_takeoff_weight,
                cruising_speed, max_altitude, max_range, max_cargo_volume)
            VALUES (9992, 'Concurrent Capacity Test', 30.00, 70000.00, 800.00, 11000, 5000, 30.00)
        """)
        setup_cur.execute("""
            INSERT INTO aircraft (aircraft_name, aircraft_type_id, business_seats,
                premium_economy_seats, economy_seats, owner)
            VALUES ('CONC-02', 9992, 1, 10, 20, 'Test')
        """)
        setup_cur.execute("""
            INSERT INTO passenger (passenger_id, name, surname, class, passport_id, birth_date)
            VALUES
                (9992, 'Cap', 'One', 'GOLD', 'CONC000002', '1990-01-01'),
                (9993, 'Cap', 'Two', 'GOLD', 'CONC000003', '1990-01-01')
        """)
        setup_cur.execute("""
            INSERT INTO flight (flight_id, flight_no, departure_time, arrival_time,
                departure_airport, arrival_airport, flight_type, status, aircraft_name)
            VALUES (9992, 'SU9992', NOW() + INTERVAL '2 hours', NOW() + INTERVAL '5 hours',
                    'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'CONC-02')
        """)
        db_conn.commit()

        results = []
        errors = []
        first_inserted = threading.Event()

        def first_booking():
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("SELECT book_seat(9992, 9992, 'BUSINESS', '1A')")
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

        def second_booking():
            first_inserted.wait(timeout=5)
            conn = psycopg.connect(**DB_PARAMS)
            try:
                cur = conn.cursor()
                cur.execute("SELECT book_seat(9992, 9993, 'BUSINESS', '1B')")
                results.append(cur.fetchone()[0])
                conn.commit()
            except psycopg.Error as exc:
                errors.append(exc)
                conn.rollback()
            finally:
                conn.close()

        t1 = threading.Thread(target=first_booking)
        t2 = threading.Thread(target=second_booking)
        t1.start(); t2.start()
        t1.join(); t2.join()

        assert len(results) == 1
        assert len(errors) == 1

        check = db_conn.cursor()
        check.execute("SELECT COUNT(*) FROM booking WHERE flight_id = 9992 AND class = 'BUSINESS'")
        assert check.fetchone()[0] == 1

    finally:
        cleanup = db_conn.cursor()
        cleanup.execute("DELETE FROM booking WHERE flight_id = 9992")
        cleanup.execute("DELETE FROM flight WHERE flight_id = 9992")
        cleanup.execute("DELETE FROM passenger WHERE passenger_id IN (9992, 9993)")
        cleanup.execute("DELETE FROM aircraft WHERE aircraft_name = 'CONC-02'")
        cleanup.execute("DELETE FROM aircraft_type WHERE aircraft_type_id = 9992")
        db_conn.commit()
