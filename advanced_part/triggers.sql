DROP TRIGGER IF EXISTS trg_flight_status_check ON flight;
DROP FUNCTION IF EXISTS fn_flight_status_check();

CREATE OR REPLACE FUNCTION fn_flight_status_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT (
        (OLD.status = 'SCHEDULED' AND NEW.status IN ('BOARDING', 'DELAYED', 'CANCELLED')) OR
        (OLD.status = 'BOARDING' AND NEW.status IN ('DEPARTED', 'DELAYED', 'CANCELLED')) OR
        (OLD.status = 'DELAYED' AND NEW.status IN ('BOARDING', 'CANCELLED')) OR
        (OLD.status = 'DEPARTED' AND NEW.status = 'ARRIVED')
    ) THEN
        RAISE EXCEPTION 'Недопустимый статус рейса: % в %', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'DEPARTED' AND NEW.actual_departure_time IS NULL THEN
        NEW.actual_departure_time := NOW();
    END IF;
    IF NEW.status = 'ARRIVED' AND NEW.actual_arrival_time IS NULL THEN
        NEW.actual_arrival_time := NOW();
    END IF;
    IF NEW.status = 'CANCELLED' THEN
        UPDATE time_slot
        SET status = 'CANCELLED'
        WHERE flight_id = NEW.flight_id
          AND status = 'PLANNED';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_flight_status_check
BEFORE UPDATE OF status ON flight
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION fn_flight_status_check();

DROP TRIGGER IF EXISTS trg_prevent_timeslot_overlap ON time_slot;
DROP FUNCTION IF EXISTS fn_prevent_timeslot_overlap();

CREATE OR REPLACE FUNCTION fn_prevent_timeslot_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM 1 FROM runway WHERE runway_id = NEW.runway_id FOR UPDATE;
    IF EXISTS(SELECT 1
              FROM time_slot
              WHERE runway_id = NEW.runway_id
                AND slot_id <> NEW.slot_id
                AND status IN ('PLANNED', 'ACTIVE')
                AND NOT (slot_end <= NEW.slot_start OR slot_start >= NEW.slot_end)) THEN
    RAISE EXCEPTION 'ВПП % занята в это время', NEW.runway_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_timeslot_overlap
BEFORE INSERT OR UPDATE ON time_slot
FOR EACH ROW
WHEN (NEW.status IN ('PLANNED', 'ACTIVE'))
EXECUTE FUNCTION fn_prevent_timeslot_overlap();
