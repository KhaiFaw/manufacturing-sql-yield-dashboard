\connect manufacturing_yield

CREATE TABLE IF NOT EXISTS manufacturing.plant (
    plant_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plant_code varchar(10) NOT NULL UNIQUE,
    plant_name varchar(100) NOT NULL,
    country varchar(60) NOT NULL,
    timezone_name varchar(60) NOT NULL
);

CREATE TABLE IF NOT EXISTS manufacturing.production_line (
    line_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    plant_id integer NOT NULL REFERENCES manufacturing.plant(plant_id),
    line_code varchar(20) NOT NULL UNIQUE,
    line_name varchar(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS manufacturing.product (
    product_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_code varchar(30) NOT NULL UNIQUE,
    product_name varchar(120) NOT NULL,
    product_family varchar(60) NOT NULL,
    target_cycle_seconds numeric(8,2) NOT NULL CHECK (target_cycle_seconds > 0)
);

CREATE TABLE IF NOT EXISTS manufacturing.test_station (
    station_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_code varchar(20) NOT NULL UNIQUE,
    station_name varchar(120) NOT NULL,
    test_type varchar(20) NOT NULL CHECK (test_type IN ('AOI', 'ICT', 'FCT'))
);

CREATE TABLE IF NOT EXISTS manufacturing.failure_mode (
    failure_mode_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    failure_code varchar(30) NOT NULL UNIQUE,
    failure_category varchar(60) NOT NULL,
    failure_description varchar(160) NOT NULL
);

CREATE TABLE IF NOT EXISTS manufacturing.production_lot (
    lot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lot_code varchar(40) NOT NULL UNIQUE,
    line_id integer NOT NULL REFERENCES manufacturing.production_line(line_id),
    product_id integer NOT NULL REFERENCES manufacturing.product(product_id),
    planned_start_date date NOT NULL
);

CREATE TABLE IF NOT EXISTS raw.test_result (
    raw_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_row_number text,
    serial_number text,
    lot_code text,
    line_code text,
    product_code text,
    station_code text,
    shift_name text,
    tested_at_text text,
    outcome_text text,
    failure_code text,
    cycle_time_seconds_text text,
    measurement_value_text text,
    lower_spec_limit_text text,
    upper_spec_limit_text text,
    operator_code text,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS manufacturing.test_result (
    test_result_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_row_number integer NOT NULL UNIQUE,
    serial_number varchar(30) NOT NULL UNIQUE,
    lot_id bigint NOT NULL REFERENCES manufacturing.production_lot(lot_id),
    line_id integer NOT NULL REFERENCES manufacturing.production_line(line_id),
    product_id integer NOT NULL REFERENCES manufacturing.product(product_id),
    station_id integer NOT NULL REFERENCES manufacturing.test_station(station_id),
    failure_mode_id integer REFERENCES manufacturing.failure_mode(failure_mode_id),
    shift_name varchar(12) NOT NULL CHECK (shift_name IN ('Day', 'Evening', 'Night')),
    tested_at timestamp NOT NULL,
    outcome varchar(4) NOT NULL CHECK (outcome IN ('PASS', 'FAIL')),
    cycle_time_seconds numeric(8,2) NOT NULL CHECK (cycle_time_seconds > 0),
    measurement_value numeric(12,4),
    lower_spec_limit numeric(12,4),
    upper_spec_limit numeric(12,4),
    operator_code varchar(20) NOT NULL,
    CONSTRAINT failure_mode_matches_outcome CHECK (
        (outcome = 'PASS' AND failure_mode_id IS NULL)
        OR (outcome = 'FAIL' AND failure_mode_id IS NOT NULL)
    ),
    CONSTRAINT valid_spec_limits CHECK (
        lower_spec_limit IS NULL OR upper_spec_limit IS NULL OR lower_spec_limit <= upper_spec_limit
    )
);

CREATE TABLE IF NOT EXISTS raw.rejected_test_result (
    raw_id bigint PRIMARY KEY,
    rejection_reason text NOT NULL,
    rejected_at timestamptz NOT NULL DEFAULT now()
);
