-- 1. Для каждого пассажирского рейса показать число бронирований и общую выручку
SELECT
    f.flight_id,
    f.flight_no,
    f.departure_airport,
    f.arrival_airport,
    f.departure_time,
    f.status,
    COUNT(b.booking_id) AS bookings_count,
    COALESCE(SUM(b.price), 0) AS total_revenue
FROM flight f
LEFT JOIN booking b
    ON b.flight_id = f.flight_id
WHERE f.flight_type = 'PASSENGER'
GROUP BY
    f.flight_id,
    f.flight_no,
    f.departure_airport,
    f.arrival_airport,
    f.departure_time,
    f.status
ORDER BY total_revenue DESC, bookings_count DESC;

-- 2. Для каждого пассажира показать число бронирований и суммарную стоимость
SELECT
    p.passenger_id,
    p.surname,
    p.name,
    p.class,
    COUNT(b.booking_id) AS bookings_count,
    COALESCE(SUM(b.price), 0) AS total_spent
FROM passenger p
LEFT JOIN booking b
    ON b.passenger_id = p.passenger_id
GROUP BY
    p.passenger_id,
    p.surname,
    p.name,
    p.class
HAVING COUNT(b.booking_id) > 0
ORDER BY total_spent DESC, bookings_count DESC;

-- 3. Показать рейсы, у которых есть задержка вылета
SELECT
    flight_id,
    flight_no,
    departure_time,
    actual_departure_time,
    (actual_departure_time - departure_time) AS delay
FROM flight
WHERE actual_departure_time > departure_time;

-- 4. Для каждой ВПП показать количество слотов
SELECT
    r.runway_id,
    r.length,
    r.width,
    r.magnetic_course,
    COUNT(ts.slot_id) AS slots_count
FROM runway r
LEFT JOIN time_slot ts
    ON ts.runway_id = r.runway_id
GROUP BY
    r.runway_id,
    r.length,
    r.width,
    r.magnetic_course
ORDER BY slots_count DESC, r.runway_id;

-- 5. Для каждого члена экипажа показать, на сколько рейсов он назначен
SELECT
    cm.crew_id,
    cm.surname,
    cm.name,
    cm.role,
    cm.company,
    COUNT(ca.assignment_id) AS assignments_count
FROM crew_member cm
LEFT JOIN crew_assignment ca
    ON ca.crew_id = cm.crew_id
GROUP BY
    cm.crew_id,
    cm.surname,
    cm.name,
    cm.role,
    cm.company
HAVING COUNT(ca.assignment_id) > 0
ORDER BY assignments_count DESC, cm.crew_id;

-- 6. Для каждого грузового рейса показать количество груза и вес
SELECT
    f.flight_id,
    f.flight_no,
    f.departure_airport,
    f.arrival_airport,
    COUNT(c.cargo_id) AS cargo_count,
    COALESCE(SUM(c.weight), 0) AS total_cargo_weight
FROM flight f
LEFT JOIN cargo c
    ON c.flight_id = f.flight_id
WHERE f.flight_type = 'CARGO'
GROUP BY
    f.flight_id,
    f.flight_no,
    f.departure_airport,
    f.arrival_airport
ORDER BY total_cargo_weight DESC, cargo_count DESC;

-- 7. Для каждого выхода показать, сколько рейсов на него назначено
SELECT
    g.gate_no,
    g.type,
    g.status,
    COUNT(f.flight_id) AS flights_count
FROM gate g
LEFT JOIN flight f
    ON f.gate_no = g.gate_no
GROUP BY
    g.gate_no,
    g.type,
    g.status
ORDER BY flights_count DESC, g.gate_no;

-- 8. Показать бронирования вместе с пассажиром, рейсом и местом
SELECT
    b.booking_id,
    p.surname,
    p.name,
    f.flight_no,
    f.departure_airport,
    f.arrival_airport,
    b.class,
    b.seat,
    b.price
FROM booking b
JOIN passenger p
    ON p.passenger_id = b.passenger_id
JOIN flight f
    ON f.flight_id = b.flight_id
ORDER BY b.price DESC, b.booking_id;

-- 9. Показать пассажиров, у которых больше одного бронирования
SELECT
    p.passenger_id,
    p.surname,
    p.name,
    COUNT(b.booking_id) AS bookings_count
FROM passenger p
JOIN booking b
    ON b.passenger_id = p.passenger_id
GROUP BY
    p.passenger_id,
    p.surname,
    p.name
HAVING COUNT(b.booking_id) > 1
ORDER BY bookings_count DESC, p.passenger_id;

-- 10. Для каждого аэропорта показать число рейсов и число пассажиров
SELECT
    f.departure_airport,
    f.arrival_airport,
    COUNT(DISTINCT f.flight_id) AS flights_count,
    COUNT(DISTINCT b.passenger_id) AS passengers_count
FROM flight f
LEFT JOIN booking b
    ON b.flight_id = f.flight_id
WHERE f.flight_type = 'PASSENGER'
GROUP BY
    f.departure_airport,
    f.arrival_airport
ORDER BY passengers_count DESC, flights_count DESC;
