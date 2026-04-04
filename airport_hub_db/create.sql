DROP TABLE IF EXISTS "Baggage" CASCADE;
DROP TABLE IF EXISTS "Crew assignment" CASCADE;
DROP TABLE IF EXISTS "Booking" CASCADE;
DROP TABLE IF EXISTS "Time_slot" CASCADE;
DROP TABLE IF EXISTS "Cargo" CASCADE;
DROP TABLE IF EXISTS "Flight" CASCADE;
DROP TABLE IF EXISTS "Allowed aircrafts" CASCADE;
DROP TABLE IF EXISTS "Aircraft" CASCADE;
DROP TABLE IF EXISTS "Passenger" CASCADE;
DROP TABLE IF EXISTS "Gate" CASCADE;
DROP TABLE IF EXISTS "Crew member" CASCADE;
DROP TABLE IF EXISTS "Runway" CASCADE;
DROP TABLE IF EXISTS "Aircraft type" CASCADE;

CREATE TABLE "Aircraft type" (
    "Aircraft type id" INT PRIMARY KEY,
    "Model" VARCHAR(30) NOT NULL UNIQUE,
    "Length" NUMERIC(5, 2) NOT NULL,
    "Max takeoff weight" NUMERIC(10, 2) NOT NULL,
    "Cruising speed" NUMERIC(6, 2) NOT NULL,
    "Max altitude" INT NOT NULL,
    "Max range" INT NOT NULL,
    "Max cargo volume" NUMERIC(8, 2) NOT NULL,
    CONSTRAINT aircraft_type_length_chk CHECK ("Length" > 0),
    CONSTRAINT aircraft_type_mtow_chk CHECK ("Max takeoff weight" > 0),
    CONSTRAINT aircraft_type_cruising_speed_chk CHECK ("Cruising speed" > 0),
    CONSTRAINT aircraft_type_max_altitude_chk CHECK ("Max altitude" > 0),
    CONSTRAINT aircraft_type_max_range_chk CHECK ("Max range" > 0),
    CONSTRAINT aircraft_type_max_cargo_volume_chk CHECK ("Max cargo volume" >= 0)
);

CREATE TABLE "Runway" (
    "Runway id" INT PRIMARY KEY,
    "Length" NUMERIC(6, 1) NOT NULL,
    "Width" NUMERIC(5, 1) NOT NULL,
    "Magnetic course" SMALLINT NOT NULL,
    CONSTRAINT runway_length_chk CHECK ("Length" > 0),
    CONSTRAINT runway_width_chk CHECK ("Width" > 0),
    CONSTRAINT runway_magnetic_course_chk CHECK ("Magnetic course" BETWEEN 1 AND 360)
);

CREATE TABLE "Crew member" (
    "Crew id" INT PRIMARY KEY,
    "Name" VARCHAR(20) NOT NULL,
    "Surname" VARCHAR(30) NOT NULL,
    "Role" VARCHAR(20) NOT NULL,
    "Company" VARCHAR(50) NOT NULL,
    "License" VARCHAR(20) NOT NULL UNIQUE,
    "Rest time" INTERVAL NOT NULL,
    CONSTRAINT crew_member_role_chk CHECK (
        "Role" IN ('CAPTAIN', 'FIRST_OFFICER', 'PURSER', 'FLIGHT_ATTENDANT', 'ENGINEER')
    ),
    CONSTRAINT crew_member_rest_time_chk CHECK ("Rest time" > INTERVAL '0 hour')
);

CREATE TABLE "Gate" (
    "Gate No" VARCHAR(8) PRIMARY KEY,
    "Type" VARCHAR(10) NOT NULL,
    "Status" VARCHAR(11) NOT NULL,
    CONSTRAINT gate_no_format_chk CHECK ("Gate No" ~ '^[A-Z0-9-]{1,8}$'),
    CONSTRAINT gate_type_chk CHECK ("Type" IN ('BUS', 'CARGO', 'REMOTE')),
    CONSTRAINT gate_status_chk CHECK ("Status" IN ('AVAILABLE', 'OCCUPIED', 'MAINTENANCE', 'BLOCKED'))
);

CREATE TABLE "Passenger" (
    "Passenger id" INT PRIMARY KEY,
    "Name" VARCHAR(20) NOT NULL,
    "Surname" VARCHAR(30) NOT NULL,
    "Middle name" VARCHAR(30),
    "Class" VARCHAR(10) NOT NULL,
    "Passport id" VARCHAR(20) NOT NULL UNIQUE,
    "Birth Date" DATE NOT NULL,
    CONSTRAINT passenger_class_chk CHECK (
        "Class" IN ('BASIC', 'BASIC PLUS', 'BASIC PRO', 'SILVER', 'GOLD', 'PLATINUM', 'INFINITE')
    ),
    CONSTRAINT passenger_birth_date_chk CHECK ("Birth Date" < CURRENT_DATE)
);

CREATE TABLE "Aircraft" (
    "Aircraft name" VARCHAR(12) PRIMARY KEY,
    "Aircraft type id" INT NOT NULL,
    "Business seats" SMALLINT NOT NULL,
    "Premium economy seats" SMALLINT NOT NULL,
    "Economy seats" SMALLINT NOT NULL,
    "Owner" VARCHAR(100) NOT NULL,
    CONSTRAINT aircraft_business_seats_chk CHECK ("Business seats" >= 0),
    CONSTRAINT aircraft_premium_economy_seats_chk CHECK ("Premium economy seats" >= 0),
    CONSTRAINT aircraft_economy_seats_chk CHECK ("Economy seats" >= 0),
    CONSTRAINT aircraft_aircraft_type_fk
        FOREIGN KEY ("Aircraft type id")
        REFERENCES "Aircraft type" ("Aircraft type id")
);

CREATE TABLE "Allowed aircrafts" (
    "Runway id" INT NOT NULL,
    "Aircraft type id" INT NOT NULL,
    CONSTRAINT allowed_aircrafts_pk PRIMARY KEY ("Runway id", "Aircraft type id"),
    CONSTRAINT allowed_aircrafts_runway_fk
        FOREIGN KEY ("Runway id")
        REFERENCES "Runway" ("Runway id"),
    CONSTRAINT allowed_aircrafts_aircraft_type_fk
        FOREIGN KEY ("Aircraft type id")
        REFERENCES "Aircraft type" ("Aircraft type id")
);

CREATE TABLE "Flight" (
    "Flight id" INT PRIMARY KEY,
    "Gate No" VARCHAR(4),
    "Flight No" VARCHAR(6) NOT NULL,
    "Depature time" TIMESTAMP NOT NULL,
    "Arrival time" TIMESTAMP NOT NULL,
    "Depature airport" CHAR(3) NOT NULL,
    "Arrival airport" CHAR(3) NOT NULL,
    "Flight type" VARCHAR(10) NOT NULL,
    "Status" VARCHAR(10) NOT NULL,
    "Aircraft name" VARCHAR(12) NOT NULL,
    "Actual arrival time" TIMESTAMP,
    "Actual departure time" TIMESTAMP,
    CONSTRAINT flight_gate_fk
        FOREIGN KEY ("Gate No")
        REFERENCES "Gate" ("Gate No"),
    CONSTRAINT flight_aircraft_fk
        FOREIGN KEY ("Aircraft name")
        REFERENCES "Aircraft" ("Aircraft name"),
    CONSTRAINT flight_no_format_chk CHECK ("Flight No" ~ '^[A-Z0-9]{2}[0-9]{1,4}$'),
    CONSTRAINT flight_arrival_after_departure_chk CHECK ("Arrival time" > "Depature time"),
    CONSTRAINT flight_departure_airport_chk CHECK ("Depature airport" ~ '^[A-Z]{3}$'),
    CONSTRAINT flight_arrival_airport_chk CHECK ("Arrival airport" ~ '^[A-Z]{3}$'),
    CONSTRAINT flight_airports_not_equal_chk CHECK ("Arrival airport" <> "Depature airport"),
    CONSTRAINT flight_type_chk CHECK ("Flight type" IN ('PASSENGER', 'CARGO')),
    CONSTRAINT flight_status_chk CHECK (
        "Status" IN ('SCHEDULED', 'BOARDING', 'DELAYED', 'DEPARTED', 'ARRIVED', 'CANCELLED')
    ),
    CONSTRAINT flight_actual_arrival_after_actual_departure_chk CHECK (
        "Actual arrival time" IS NULL
        OR "Actual departure time" IS NULL
        OR "Actual arrival time" > "Actual departure time"
    )
);

CREATE OR REPLACE FUNCTION set_default_actual_arrival_time()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW."Actual arrival time" IS NULL THEN
        NEW."Actual arrival time" := NEW."Arrival time";
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER flight_set_default_actual_arrival_time
BEFORE INSERT ON "Flight"
FOR EACH ROW
EXECUTE FUNCTION set_default_actual_arrival_time();

CREATE TABLE "Cargo" (
    "Cargo id" INT PRIMARY KEY,
    "Flight id" INT NOT NULL,
    "Type" VARCHAR(10) NOT NULL,
    "Weight" NUMERIC(8, 2) NOT NULL,
    "Volume" NUMERIC(8, 3) NOT NULL,
    "Hazard class" CHAR(1),
    CONSTRAINT cargo_flight_fk
        FOREIGN KEY ("Flight id")
        REFERENCES "Flight" ("Flight id"),
    CONSTRAINT cargo_type_chk CHECK ("Type" IN ('GENERAL', 'HAZARDOUS', 'PERISHABLE')),
    CONSTRAINT cargo_weight_chk CHECK ("Weight" > 0),
    CONSTRAINT cargo_volume_chk CHECK ("Volume" > 0),
    CONSTRAINT cargo_hazard_class_chk CHECK ("Hazard class" IN ('1', '2', '3', '4', '5', '6', '7', '8', '9'))
);

CREATE TABLE "Time_slot" (
    "Slot id" INT PRIMARY KEY,
    "Runway id" INT NOT NULL,
    "Flight id" INT NOT NULL,
    "Slot start" TIMESTAMP NOT NULL,
    "Slot end" TIMESTAMP NOT NULL,
    "Status" VARCHAR(10) NOT NULL,
    CONSTRAINT time_slot_runway_fk
        FOREIGN KEY ("Runway id")
        REFERENCES "Runway" ("Runway id"),
    CONSTRAINT time_slot_flight_fk
        FOREIGN KEY ("Flight id")
        REFERENCES "Flight" ("Flight id"),
    CONSTRAINT time_slot_end_after_start_chk CHECK ("Slot end" > "Slot start"),
    CONSTRAINT time_slot_status_chk CHECK ("Status" IN ('PLANNED', 'ACTIVE', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE "Booking" (
    "Booking id" INT PRIMARY KEY,
    "Passenger id" INT NOT NULL,
    "Price" NUMERIC(10, 2) NOT NULL,
    "Class" VARCHAR(16) NOT NULL,
    "Flight id" INT NOT NULL,
    "Seat" VARCHAR(3) NOT NULL,
    CONSTRAINT booking_passenger_fk
        FOREIGN KEY ("Passenger id")
        REFERENCES "Passenger" ("Passenger id"),
    CONSTRAINT booking_flight_fk
        FOREIGN KEY ("Flight id")
        REFERENCES "Flight" ("Flight id"),
    CONSTRAINT booking_price_chk CHECK ("Price" >= 0),
    CONSTRAINT booking_class_chk CHECK ("Class" IN ('BUSINESS', 'PREMIUM_ECONOMY', 'ECONOMY')),
    CONSTRAINT booking_seat_chk CHECK ("Seat" ~ '^[1-9][0-9]{0,2}[A-Z]$')
);

CREATE TABLE "Baggage" (
    "Baggage id" INT PRIMARY KEY,
    "Weight" NUMERIC(6, 2) NOT NULL,
    "Type" VARCHAR(9) NOT NULL,
    "Booking id" INT NOT NULL,
    CONSTRAINT baggage_booking_fk
        FOREIGN KEY ("Booking id")
        REFERENCES "Booking" ("Booking id"),
    CONSTRAINT baggage_weight_chk CHECK ("Weight" > 0),
    CONSTRAINT baggage_type_chk CHECK ("Type" IN ('CHECKED', 'CABIN', 'OVERSIZED'))
);

CREATE TABLE "Crew assignment" (
    "Assignment id" INT PRIMARY KEY,
    "Crew id" INT NOT NULL,
    "Flight id" INT NOT NULL,
    "Role" VARCHAR(20) NOT NULL,
    CONSTRAINT crew_assignment_crew_fk
        FOREIGN KEY ("Crew id")
        REFERENCES "Crew member" ("Crew id"),
    CONSTRAINT crew_assignment_flight_fk
        FOREIGN KEY ("Flight id")
        REFERENCES "Flight" ("Flight id"),
    CONSTRAINT crew_assignment_role_chk CHECK (
        "Role" IN ('CAPTAIN', 'FIRST_OFFICER', 'PURSER', 'FLIGHT_ATTENDANT', 'ENGINEER')
    )
);
