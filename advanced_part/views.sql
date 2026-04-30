DROP VIEW IF EXISTS v_flight_operational;
CREATE OR REPLACE VIEW v_flight_operational AS
WITH booking_counts AS (
    SELECT
        flight_id,
        COUNT(*) FILTER (WHERE class = 'BUSINESS') AS business_booked,
        COUNT(*) FILTER (WHERE class = 'PREMIUM_ECONOMY') AS premium_economy_booked,
        COUNT(*) FILTER (WHERE class = 'ECONOMY') AS economy_booked
    FROM booking
    GROUP BY flight_id
)
SELECT
    f.flight_id,
    f.flight_no,
    f.status,
    f.flight_type,
    f.departure_airport,
    f.arrival_airport,
    f.departure_time,
    f.actual_departure_time,
    f.arrival_time,
    f.actual_arrival_time,
    EXTRACT(EPOCH FROM (f.actual_departure_time - f.departure_time)) / 60 AS delay_minutes,
    f.gate_no,
    f.aircraft_name,
    at.model AS aircraft_model,
    COALESCE(bc.business_booked, 0) AS business_booked,
    COALESCE(bc.premium_economy_booked, 0) AS premium_economy_booked,
    COALESCE(bc.economy_booked, 0) AS economy_booked,
    a.business_seats - COALESCE(bc.business_booked, 0) AS business_available,
    a.premium_economy_seats - COALESCE(bc.premium_economy_booked, 0) AS premium_economy_available,
    a.economy_seats - COALESCE(bc.economy_booked, 0) AS economy_available
FROM flight f
JOIN aircraft a USING (aircraft_name)
JOIN aircraft_type at USING (aircraft_type_id)
LEFT JOIN booking_counts bc USING (flight_id);

DROP VIEW IF EXISTS v_crew_rest_summary;
CREATE OR REPLACE VIEW v_crew_rest_summary AS
WITH prev_flights AS (
    SELECT
      *,
      LAG(f.flight_id) OVER (PARTITION BY ca.crew_id ORDER BY f.departure_time) AS prev_flight_id,
      LAG(COALESCE(f.actual_arrival_time, f.arrival_time)) OVER (PARTITION BY ca.crew_id ORDER BY f.departure_time) AS prev_actual_arrival,
      LAG(ca.assignment_id) OVER (PARTITION BY ca.crew_id ORDER BY f.departure_time) AS prev_assignment_id
    FROM crew_assignment ca
    JOIN flight f USING (flight_id)
)
SELECT
    c.crew_id,
    c.name,
    c.surname,
    c.role,
    c.company,
    c.license,
    p.assignment_id,
    p.flight_id,
    p.prev_assignment_id,
    p.prev_flight_id,
    p.prev_actual_arrival,
    p.departure_time AS current_departure,
    p.departure_time - p.prev_actual_arrival  AS actual_rest,
    c.rest_time AS required_rest,
    CASE
        WHEN p.prev_flight_id IS NULL THEN TRUE
        ELSE (p.departure_time - p.prev_actual_arrival) >= c.rest_time
    END AS is_ready_to_work
FROM crew_member c
LEFT JOIN prev_flights p USING (crew_id);
