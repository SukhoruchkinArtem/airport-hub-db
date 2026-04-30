COPY aircraft_type (
  aircraft_type_id,
  model,
  length,
  max_takeoff_weight,
  cruising_speed,
  max_altitude,
  max_range,
  max_cargo_volume
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/aircraft_type.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY runway (
  runway_id,
  length,
  width,
  magnetic_course
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/runway.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY gate (
  gate_no,
  type,
  status
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/gate.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY crew_member (
  crew_id,
  name,
  surname,
  role,
  company,
  license,
  rest_time
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/crew_member.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY passenger (
  passenger_id,
  name,
  surname,
  middle_name,
  class,
  passport_id,
  birth_date
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/passenger.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY aircraft (
  aircraft_name,
  aircraft_type_id,
  business_seats,
  premium_economy_seats,
  economy_seats,
  owner
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/aircraft.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY allowed_aircrafts (
  runway_id,
  aircraft_type_id
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/allowed_aircrafts.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY flight (
  flight_id,
  gate_no,
  flight_no,
  departure_time,
  arrival_time,
  departure_airport,
  arrival_airport,
  flight_type,
  status,
  aircraft_name,
  actual_arrival_time,
  actual_departure_time
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/flight.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY booking (
  booking_id,
  passenger_id,
  price,
  class,
  flight_id,
  seat
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/booking.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY cargo (
  cargo_id,
  flight_id,
  type,
  weight,
  volume,
  hazard_class
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/cargo.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY time_slot (
  slot_id,
  runway_id,
  flight_id,
  slot_start,
  slot_end,
  status
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/time_slot.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY crew_assignment (
  assignment_id,
  crew_id,
  flight_id,
  role
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/crew_assignment.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY baggage (
  baggage_id,
  weight,
  type,
  booking_id
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/baggage.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
