COPY "Aircraft type" (
  "Aircraft type id",
  "Model",
  "Length",
  "Max takeoff weight",
  "Cruising speed",
  "Max altitude",
  "Max range",
  "Max cargo volume"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/aircraft_type.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Runway" (
  "Runway id",
  "Length",
  "Width",
  "Magnetic course"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/runway.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Gate" (
  "Gate No",
  "Type",
  "Status"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/gate.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Crew member" (
  "Crew id",
  "Name",
  "Surname",
  "Role",
  "Company",
  "License",
  "Rest time"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/crew_member.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Passenger" (
  "Passenger id",
  "Name",
  "Surname",
  "Middle name",
  "Class",
  "Passport id",
  "Birth Date"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/passenger.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Aircraft" (
  "Aircraft name",
  "Aircraft type id",
  "Business seats",
  "Premium economy seats",
  "Economy seats",
  "Owner"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/aircraft.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Allowed aircrafts" (
  "Runway id",
  "Aircraft type id"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/allowed_aircrafts.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Flight" (
  "Flight id",
  "Gate No",
  "Flight No",
  "Depature time",
  "Arrival time",
  "Depature airport",
  "Arrival airport",
  "Flight type",
  "Status",
  "Aircraft name",
  "Actual arrival time",
  "Actual departure time"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/flight.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Booking" (
  "Booking id",
  "Passenger id",
  "Price",
  "Class",
  "Flight id",
  "Seat"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/booking.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Cargo" (
  "Cargo id",
  "Flight id",
  "Type",
  "Weight",
  "Volume",
  "Hazard class"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/cargo.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Time_slot" (
  "Slot id",
  "Runway id",
  "Flight id",
  "Slot start",
  "Slot end",
  "Status"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/time_slot.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Crew assignment" (
  "Assignment id",
  "Crew id",
  "Flight id",
  "Role"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/crew_assignment.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY "Baggage" (
  "Baggage id",
  "Weight",
  "Type",
  "Booking id"
)
FROM '/Users/artemsuhoruckin/DataGripProjects/airport_hub_db/data/baggage.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
