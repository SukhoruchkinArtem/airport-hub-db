import os
import pytest
import psycopg

DB_PARAMS = {
    "host": os.environ.get("PG_HOST", "localhost"),
    "port": int(os.environ.get("PG_PORT", 5432)),
    "dbname": os.environ.get("PG_DB", "postgres"),
    "user": os.environ.get("PG_USER", "artemsuhoruckin"),
    "password": os.environ.get("PG_PASSWORD", ""),
}


@pytest.fixture(scope="session")
def db_conn():
    """
    Одно соединение с БД для тестов.
    """
    conn = psycopg.connect(**DB_PARAMS)
    yield conn
    conn.close()


@pytest.fixture
def db(db_conn):
    """
    Курсор внутри одного теста.
    """
    cursor = db_conn.cursor()
    try:
        yield cursor
    finally:
        db_conn.rollback()
        cursor.close()


@pytest.fixture
def seed(db):
    """
    Набор тестовых данных.
    """
    db.execute("""
        INSERT INTO aircraft_type
            (aircraft_type_id, model, length, max_takeoff_weight,
             cruising_speed, max_altitude, max_range, max_cargo_volume)
        VALUES (9001, 'Test Model', 30.00, 70000.00, 800.00, 11000, 5000, 30.00)
    """)

    db.execute("""
        INSERT INTO runway (runway_id, length, width, magnetic_course)
        VALUES (9001, 3000.0, 45.0, 90)
    """)

    db.execute("""
        INSERT INTO gate (gate_no, type, status)
        VALUES ('T1', 'BUS', 'AVAILABLE')
    """)

    db.execute("""
        INSERT INTO aircraft
            (aircraft_name, aircraft_type_id, business_seats,
             premium_economy_seats, economy_seats, owner)
        VALUES ('TEST-01', 9001, 5, 10, 20, 'Test Airlines')
    """)

    db.execute("""
        INSERT INTO passenger
            (passenger_id, name, surname, class, passport_id, birth_date)
        VALUES (9001, 'Ivan', 'Testov', 'GOLD', 'TEST000001', '1990-01-01')
    """)

    db.execute("""
        INSERT INTO crew_member
            (crew_id, name, surname, role, company, license, rest_time)
        VALUES (9001, 'Petr', 'Pilotov', 'CAPTAIN', 'Test Air', 'LIC-TEST-01', '8 hours')
    """)

    db.execute("""
        INSERT INTO flight
            (flight_id, gate_no, flight_no, departure_time, arrival_time,
             departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9001, 'T1', 'SU9001',
                NOW() + INTERVAL '2 hours', NOW() + INTERVAL '5 hours',
                'SVO', 'LED', 'PASSENGER', 'SCHEDULED', 'TEST-01')
    """)

    # Грузовой рейс: для поломки book_seat.
    db.execute("""
        INSERT INTO flight
            (flight_id, gate_no, flight_no, departure_time, arrival_time,
             departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9002, 'T1', 'SU9002',
                NOW() + INTERVAL '10 hours', NOW() + INTERVAL '13 hours',
                'SVO', 'LED', 'CARGO', 'SCHEDULED', 'TEST-01')
    """)

    # Пассажирский рейс, который уже отбыл: для поломки book_seat.
    db.execute("""
        INSERT INTO flight
            (flight_id, gate_no, flight_no, departure_time, arrival_time,
             departure_airport, arrival_airport, flight_type, status, aircraft_name,
             actual_departure_time)
        VALUES (9003, 'T1', 'SU9003',
                NOW() - INTERVAL '1 hour', NOW() + INTERVAL '2 hours',
                'SVO', 'LED', 'PASSENGER', 'DEPARTED', 'TEST-01',
                NOW() - INTERVAL '1 hour')
    """)

    # Рейс в статусе DELAYED: бронирование ещё разрешено.
    db.execute("""
        INSERT INTO flight
            (flight_id, gate_no, flight_no, departure_time, arrival_time,
             departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9004, 'T1', 'SU9004',
                NOW() + INTERVAL '4 hours', NOW() + INTERVAL '7 hours',
                'SVO', 'LED', 'PASSENGER', 'DELAYED', 'TEST-01')
    """)

    # Рейс в статусе BOARDING: покупка билета во время посадки запрещена.
    db.execute("""
        INSERT INTO flight
            (flight_id, gate_no, flight_no, departure_time, arrival_time,
             departure_airport, arrival_airport, flight_type, status, aircraft_name)
        VALUES (9005, 'T1', 'SU9005',
                NOW() + INTERVAL '30 minutes', NOW() + INTERVAL '3 hours',
                'SVO', 'LED', 'PASSENGER', 'BOARDING', 'TEST-01')
    """)

    yield {
        "flight_id": 9001,
        "cargo_flight_id": 9002,
        "departed_flight_id": 9003,
        "delayed_flight_id": 9004,
        "boarding_flight_id": 9005,
        "passenger_id": 9001,
        "crew_id": 9001,
        "runway_id": 9001,
        "aircraft_name": "TEST-01",
    }
