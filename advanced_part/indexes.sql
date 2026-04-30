DROP INDEX IF EXISTS idx_flight_active_departure_time;
CREATE INDEX idx_flight_active_departure_time
    ON flight (departure_time)
    WHERE status IN ('SCHEDULED', 'BOARDING', 'DELAYED');

DROP INDEX IF EXISTS idx_time_slot_active_runway_time;
CREATE INDEX idx_time_slot_active_runway_time
    ON time_slot (runway_id, slot_start, slot_end)
    WHERE status IN ('PLANNED', 'ACTIVE');

DROP INDEX IF EXISTS idx_booking_flight_seat_unique;
CREATE UNIQUE INDEX idx_booking_flight_seat_unique ON booking (flight_id, seat);