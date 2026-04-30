DROP TABLE IF EXISTS baggage CASCADE;
DROP TABLE IF EXISTS crew_assignment CASCADE;
DROP TABLE IF EXISTS booking CASCADE;
DROP TABLE IF EXISTS time_slot CASCADE;
DROP TABLE IF EXISTS cargo CASCADE;
DROP TABLE IF EXISTS flight CASCADE;
DROP TABLE IF EXISTS allowed_aircrafts CASCADE;
DROP TABLE IF EXISTS aircraft CASCADE;
DROP TABLE IF EXISTS passenger CASCADE;
DROP TABLE IF EXISTS gate CASCADE;
DROP TABLE IF EXISTS crew_member CASCADE;
DROP TABLE IF EXISTS runway CASCADE;
DROP TABLE IF EXISTS aircraft_type CASCADE;

CREATE TABLE aircraft_type (
    aircraft_type_id INT PRIMARY KEY,
    model VARCHAR(30) NOT NULL UNIQUE,
    length NUMERIC(5, 2) NOT NULL,
    max_takeoff_weight NUMERIC(10, 2) NOT NULL,
    cruising_speed NUMERIC(6, 2) NOT NULL,
    max_altitude INT NOT NULL,
    max_range INT NOT NULL,
    max_cargo_volume NUMERIC(8, 2) NOT NULL,
    CONSTRAINT aircraft_type_length_chk CHECK (length > 0),
    CONSTRAINT aircraft_type_mtow_chk CHECK (max_takeoff_weight > 0),
    CONSTRAINT aircraft_type_cruising_speed_chk CHECK (cruising_speed > 0),
    CONSTRAINT aircraft_type_max_altitude_chk CHECK (max_altitude > 0),
    CONSTRAINT aircraft_type_max_range_chk CHECK (max_range > 0),
    CONSTRAINT aircraft_type_max_cargo_volume_chk CHECK (max_cargo_volume >= 0)
);

CREATE TABLE runway (
    runway_id INT PRIMARY KEY,
    length NUMERIC(6, 1) NOT NULL,
    width NUMERIC(5, 1) NOT NULL,
    magnetic_course SMALLINT NOT NULL,
    CONSTRAINT runway_length_chk CHECK (length > 0),
    CONSTRAINT runway_width_chk CHECK (width > 0),
    CONSTRAINT runway_magnetic_course_chk CHECK (magnetic_course BETWEEN 1 AND 360)
);

CREATE TABLE crew_member (
    crew_id INT PRIMARY KEY,
    name VARCHAR(20) NOT NULL,
    surname VARCHAR(30) NOT NULL,
    role VARCHAR(20) NOT NULL,
    company VARCHAR(50) NOT NULL,
    license VARCHAR(20) NOT NULL UNIQUE,
    rest_time INTERVAL NOT NULL,
    CONSTRAINT crew_member_role_chk CHECK (
        role IN ('CAPTAIN', 'FIRST_OFFICER', 'PURSER', 'FLIGHT_ATTENDANT', 'ENGINEER')
    ),
    CONSTRAINT crew_member_rest_time_chk CHECK (rest_time > INTERVAL '0 hour')
);

CREATE TABLE gate (
    gate_no VARCHAR(8) PRIMARY KEY,
    type VARCHAR(10) NOT NULL,
    status VARCHAR(11) NOT NULL,
    CONSTRAINT gate_no_format_chk CHECK (gate_no ~ '^[A-Z0-9-]{1,8}$'),
    CONSTRAINT gate_type_chk CHECK (type IN ('BUS', 'CARGO', 'REMOTE')),
    CONSTRAINT gate_status_chk CHECK (status IN ('AVAILABLE', 'OCCUPIED', 'MAINTENANCE', 'BLOCKED'))
);

CREATE TABLE passenger (
    passenger_id INT PRIMARY KEY,
    name VARCHAR(20) NOT NULL,
    surname VARCHAR(30) NOT NULL,
    middle_name VARCHAR(30),
    class VARCHAR(10) NOT NULL,
    passport_id VARCHAR(20) NOT NULL UNIQUE,
    birth_date DATE NOT NULL,
    CONSTRAINT passenger_class_chk CHECK (
        class IN ('BASIC', 'BASIC PLUS', 'BASIC PRO', 'SILVER', 'GOLD', 'PLATINUM', 'INFINITE')
    ),
    CONSTRAINT passenger_birth_date_chk CHECK (birth_date < CURRENT_DATE)
);

CREATE TABLE aircraft (
    aircraft_name VARCHAR(12) PRIMARY KEY,
    aircraft_type_id INT NOT NULL,
    business_seats SMALLINT NOT NULL,
    premium_economy_seats SMALLINT NOT NULL,
    economy_seats SMALLINT NOT NULL,
    owner VARCHAR(100) NOT NULL,
    CONSTRAINT aircraft_business_seats_chk CHECK (business_seats >= 0),
    CONSTRAINT aircraft_premium_economy_seats_chk CHECK (premium_economy_seats >= 0),
    CONSTRAINT aircraft_economy_seats_chk CHECK (economy_seats >= 0),
    CONSTRAINT aircraft_aircraft_type_fk
        FOREIGN KEY (aircraft_type_id)
        REFERENCES aircraft_type (aircraft_type_id)
);

CREATE TABLE allowed_aircrafts (
    runway_id INT NOT NULL,
    aircraft_type_id INT NOT NULL,
    CONSTRAINT allowed_aircrafts_pk PRIMARY KEY (runway_id, aircraft_type_id),
    CONSTRAINT allowed_aircrafts_runway_fk
        FOREIGN KEY (runway_id)
        REFERENCES runway (runway_id),
    CONSTRAINT allowed_aircrafts_aircraft_type_fk
        FOREIGN KEY (aircraft_type_id)
        REFERENCES aircraft_type (aircraft_type_id)
);

CREATE TABLE flight (
    flight_id INT PRIMARY KEY,
    gate_no VARCHAR(4),
    flight_no VARCHAR(6) NOT NULL,
    departure_time TIMESTAMP NOT NULL,
    arrival_time TIMESTAMP NOT NULL,
    departure_airport CHAR(3) NOT NULL,
    arrival_airport CHAR(3) NOT NULL,
    flight_type VARCHAR(10) NOT NULL,
    status VARCHAR(10) NOT NULL,
    aircraft_name VARCHAR(12) NOT NULL,
    actual_arrival_time TIMESTAMP,
    actual_departure_time TIMESTAMP,
    CONSTRAINT flight_gate_fk
        FOREIGN KEY (gate_no)
        REFERENCES gate (gate_no),
    CONSTRAINT flight_aircraft_fk
        FOREIGN KEY (aircraft_name)
        REFERENCES aircraft (aircraft_name),
    CONSTRAINT flight_no_format_chk CHECK (flight_no ~ '^[A-Z0-9]{2}[0-9]{1,4}$'),
    CONSTRAINT flight_arrival_after_departure_chk CHECK (arrival_time > departure_time),
    CONSTRAINT flight_departure_airport_chk CHECK (departure_airport ~ '^[A-Z]{3}$'),
    CONSTRAINT flight_arrival_airport_chk CHECK (arrival_airport ~ '^[A-Z]{3}$'),
    CONSTRAINT flight_airports_not_equal_chk CHECK (arrival_airport <> departure_airport),
    CONSTRAINT flight_type_chk CHECK (flight_type IN ('PASSENGER', 'CARGO')),
    CONSTRAINT flight_status_chk CHECK (
        status IN ('SCHEDULED', 'BOARDING', 'DELAYED', 'DEPARTED', 'ARRIVED', 'CANCELLED')
    ),
    CONSTRAINT flight_actual_arrival_after_actual_departure_chk CHECK (
        actual_arrival_time IS NULL
        OR actual_departure_time IS NULL
        OR actual_arrival_time >= actual_departure_time
    )
);

CREATE TABLE cargo (
    cargo_id INT PRIMARY KEY,
    flight_id INT NOT NULL,
    type VARCHAR(10) NOT NULL,
    weight NUMERIC(8, 2) NOT NULL,
    volume NUMERIC(8, 3) NOT NULL,
    hazard_class CHAR(1),
    CONSTRAINT cargo_flight_fk
        FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id),
    CONSTRAINT cargo_type_chk CHECK (type IN ('GENERAL', 'HAZARDOUS', 'PERISHABLE')),
    CONSTRAINT cargo_weight_chk CHECK (weight > 0),
    CONSTRAINT cargo_volume_chk CHECK (volume > 0),
    CONSTRAINT cargo_hazard_class_chk CHECK (hazard_class IN ('1', '2', '3', '4', '5', '6', '7', '8', '9'))
);

CREATE TABLE time_slot (
    slot_id INT PRIMARY KEY,
    runway_id INT NOT NULL,
    flight_id INT NOT NULL,
    slot_start TIMESTAMP NOT NULL,
    slot_end TIMESTAMP NOT NULL,
    status VARCHAR(10) NOT NULL,
    CONSTRAINT time_slot_runway_fk
        FOREIGN KEY (runway_id)
        REFERENCES runway (runway_id),
    CONSTRAINT time_slot_flight_fk
        FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id),
    CONSTRAINT time_slot_end_after_start_chk CHECK (slot_end > slot_start),
    CONSTRAINT time_slot_status_chk CHECK (status IN ('PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE booking (
    booking_id INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    passenger_id INT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    class VARCHAR(16) NOT NULL,
    flight_id INT NOT NULL,
    seat VARCHAR(3) NOT NULL,
    CONSTRAINT booking_passenger_fk
        FOREIGN KEY (passenger_id)
        REFERENCES passenger (passenger_id),
    CONSTRAINT booking_flight_fk
        FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id),
    CONSTRAINT booking_price_chk CHECK (price >= 0),
    CONSTRAINT booking_class_chk CHECK (class IN ('BUSINESS', 'PREMIUM_ECONOMY', 'ECONOMY')),
    CONSTRAINT booking_seat_chk CHECK (seat ~ '^[1-9][0-9]{0,2}[A-Z]$')
);

CREATE TABLE baggage (
    baggage_id INT PRIMARY KEY,
    weight NUMERIC(6, 2) NOT NULL,
    type VARCHAR(9) NOT NULL,
    booking_id INT NOT NULL,
    CONSTRAINT baggage_booking_fk
        FOREIGN KEY (booking_id)
        REFERENCES booking (booking_id),
    CONSTRAINT baggage_weight_chk CHECK (weight > 0),
    CONSTRAINT baggage_type_chk CHECK (type IN ('CHECKED', 'CABIN', 'OVERSIZED'))
);

CREATE TABLE crew_assignment (
    assignment_id INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    crew_id INT NOT NULL,
    flight_id INT NOT NULL,
    role VARCHAR(20) NOT NULL,
    CONSTRAINT crew_assignment_crew_fk
        FOREIGN KEY (crew_id)
        REFERENCES crew_member (crew_id),
    CONSTRAINT crew_assignment_flight_fk
        FOREIGN KEY (flight_id)
        REFERENCES flight (flight_id),
    CONSTRAINT crew_assignment_role_chk CHECK (
        role IN ('CAPTAIN', 'FIRST_OFFICER', 'PURSER', 'FLIGHT_ATTENDANT', 'ENGINEER')
    )
);
