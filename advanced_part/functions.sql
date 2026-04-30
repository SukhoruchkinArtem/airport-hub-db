DROP FUNCTION IF EXISTS calculate_booking_price(INT, VARCHAR);
CREATE OR REPLACE FUNCTION calculate_booking_price(
    p_flight_id INT,
    p_class VARCHAR
) RETURNS NUMERIC(10, 2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_duration_min NUMERIC;
    v_status VARCHAR(10);
    v_base_price NUMERIC(10, 2);
    v_multiplier NUMERIC(5, 2);
BEGIN
    SELECT EXTRACT(EPOCH FROM (arrival_time - departure_time)) / 60.0, status
    INTO v_duration_min, v_status
    FROM flight
    WHERE flight_id = p_flight_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Рейс % не найден', p_flight_id;
    END IF;
    IF v_duration_min <= 0 THEN
        RAISE EXCEPTION 'Телепортация пассажиров рейса % ещё не изобретена!', p_flight_id;
    END IF;
    v_base_price := 1000 + v_duration_min * 25;
    v_multiplier := CASE p_class
        WHEN 'ECONOMY' THEN 1.00
        WHEN 'PREMIUM_ECONOMY' THEN 1.50
        WHEN 'BUSINESS' THEN 3.00
    END;
    IF v_status = 'DELAYED' THEN
        v_base_price := v_base_price * 1.10;
    END IF;
    RETURN ROUND((v_base_price * v_multiplier)::NUMERIC, 2);
END;
$$;

DROP FUNCTION IF EXISTS book_seat(INT, INT, VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION book_seat(
    p_flight_id INT,
    p_passenger_id INT,
    p_class VARCHAR,
    p_seat VARCHAR
) RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_flight_type VARCHAR(10);
    v_flight_status VARCHAR(10);
    v_aircraft_name VARCHAR(12);
    v_capacity SMALLINT;
    v_booked INT;
    v_booking_id INT;
    v_price NUMERIC(10, 2);
BEGIN
    SELECT flight_type, status, aircraft_name
    INTO v_flight_type, v_flight_status, v_aircraft_name
    FROM flight
    WHERE flight_id = p_flight_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Рейс % не найден', p_flight_id;
    END IF;
    IF v_flight_type <> 'PASSENGER' THEN
        RAISE EXCEPTION 'Рейс % не пассажирский', p_flight_id;
    END IF;
    IF v_flight_status NOT IN ('SCHEDULED', 'DELAYED') THEN
        RAISE EXCEPTION 'Бронирование недоступно: рейс % уже %', p_flight_id, v_flight_status;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM passenger WHERE passenger_id = p_passenger_id) THEN
        RAISE EXCEPTION 'Пассажир % не найден', p_passenger_id;
    END IF;
    IF p_seat !~ '^[1-9][0-9]{0,2}[A-Z]$' THEN
        RAISE EXCEPTION 'Неверный формат места: %', p_seat;
    END IF;
    IF p_class NOT IN ('BUSINESS', 'PREMIUM_ECONOMY', 'ECONOMY') THEN
        RAISE EXCEPTION 'Неверный класс: %', p_class;
    END IF;

    PERFORM seat FROM booking
    WHERE flight_id = p_flight_id AND seat = p_seat
    FOR UPDATE;

    IF FOUND THEN
        RAISE EXCEPTION 'Место % на рейсе % уже занято', p_seat, p_flight_id;
    END IF;
    SELECT
        CASE p_class
            WHEN 'BUSINESS' THEN a.business_seats
            WHEN 'PREMIUM_ECONOMY' THEN a.premium_economy_seats
            WHEN 'ECONOMY' THEN a.economy_seats
        END
    INTO v_capacity
    FROM aircraft a
    WHERE a.aircraft_name = v_aircraft_name
    FOR UPDATE;

    SELECT COUNT(*) INTO v_booked
    FROM booking
    WHERE flight_id = p_flight_id AND class = p_class;

    IF v_booked >= v_capacity THEN
        RAISE EXCEPTION 'Все места класса % на рейсе % заняты', p_class, p_flight_id;
    END IF;
    v_price := calculate_booking_price(p_flight_id, p_class);
    INSERT INTO booking (passenger_id, price, class, flight_id, seat)
    VALUES (p_passenger_id, v_price, p_class, p_flight_id, p_seat)
    RETURNING booking_id INTO v_booking_id;

    RETURN v_booking_id;
    EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Место % на рейсе % уже занято', p_seat, p_flight_id;
END;
$$;

DROP FUNCTION IF EXISTS assign_crew_to_flight(INT, INT, VARCHAR);
CREATE OR REPLACE FUNCTION assign_crew_to_flight(
    p_flight_id INT,
    p_crew_id INT,
    p_role VARCHAR(20)
) RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_role VARCHAR(20);
    v_new_departure TIMESTAMP;
    v_new_arrival TIMESTAMP;
    v_rest_time INTERVAL;
    v_prev_arrival TIMESTAMP;
    v_assignment_id INT;
BEGIN
    SELECT role, rest_time INTO v_role, v_rest_time
    FROM crew_member WHERE crew_id = p_crew_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сотрудник % не найден', p_crew_id;
    END IF;
    IF p_flight_id NOT IN (SELECT flight_id FROM flight) THEN
        RAISE EXCEPTION 'Рейс % не найден', p_flight_id;
    END IF;
    IF v_role <> p_role THEN
        RAISE EXCEPTION 'Сотрудник % не может быть назначен на эту роль: %', p_crew_id, p_role;
    END IF;
    IF EXISTS (
        SELECT 1 FROM crew_assignment
        WHERE crew_id = p_crew_id AND flight_id = p_flight_id
    ) THEN
        RAISE EXCEPTION 'Сотрудник % уже назначен на рейс %', p_crew_id, p_flight_id;
    END IF;

    SELECT departure_time, arrival_time
    INTO v_new_departure, v_new_arrival
    FROM flight
    WHERE flight_id = p_flight_id;

    IF EXISTS (SELECT 1
        FROM crew_assignment ca
        JOIN flight f USING (flight_id)
        WHERE ca.crew_id = p_crew_id
          AND ca.flight_id <> p_flight_id
          AND f.status <> 'CANCELLED'
          AND NOT (f.arrival_time <= v_new_departure
                   OR f.departure_time >= v_new_arrival)
    ) THEN
        RAISE EXCEPTION 'Сотрудник % уже назначен на другой рейс в это время', p_crew_id;
    END IF;

    SELECT COALESCE(f.actual_arrival_time, f.arrival_time)
    INTO v_prev_arrival
    FROM crew_assignment ca
    JOIN flight f ON f.flight_id = ca.flight_id
    WHERE ca.crew_id = p_crew_id
      AND COALESCE(f.actual_arrival_time, f.arrival_time) <= v_new_departure
    ORDER BY 1 DESC
    LIMIT 1;

    IF v_prev_arrival IS NOT NULL
       AND (v_new_departure - v_prev_arrival) < v_rest_time THEN
        RAISE EXCEPTION 'Сотрудник % должен отдыхать!', p_crew_id;
    END IF;

    INSERT INTO crew_assignment (crew_id, flight_id, role)
    VALUES (p_crew_id, p_flight_id, p_role)
    RETURNING assignment_id INTO v_assignment_id;

    RETURN v_assignment_id;
END;
$$;

DROP FUNCTION IF EXISTS find_available_runway_slots(INT, TIMESTAMP, TIMESTAMP, INTERVAL);
CREATE OR REPLACE FUNCTION find_available_runway_slots(
    p_runway_id INT,
    p_from_ts TIMESTAMP,
    p_to_ts TIMESTAMP,
    p_duration INTERVAL
) RETURNS TABLE(window_start TIMESTAMP, window_end TIMESTAMP)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_from_ts >= p_to_ts THEN
      RAISE EXCEPTION 'Некорректный диапазон: p_from_ts должен быть меньше p_to_ts';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM runway WHERE runway_id = p_runway_id) THEN
      RAISE EXCEPTION 'ВПП % не найдена', p_runway_id;
    END IF;
    RETURN QUERY
      WITH busy_slots AS (
        SELECT GREATEST(slot_start, p_from_ts) AS slot_start, LEAST(slot_end, p_to_ts) AS slot_end
        FROM time_slot
        WHERE runway_id = p_runway_id AND status IN ('ACTIVE', 'PLANNED')
          AND slot_start < p_to_ts AND slot_end > p_from_ts
      ),
      slots_with_end AS (
        SELECT slot_start, slot_end
        FROM busy_slots
        UNION ALL
        SELECT p_to_ts AS slot_start, p_to_ts AS slot_end
      ),
      gaps AS (
        SELECT COALESCE(LAG(slot_end) OVER (ORDER BY slot_start, slot_end), p_from_ts) AS gap_start, slot_start AS gap_end
        FROM slots_with_end
      )
      SELECT gap_start, gap_end
      FROM gaps
      WHERE gap_end - gap_start >= p_duration;
END;
$$;
