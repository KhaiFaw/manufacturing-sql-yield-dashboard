\connect manufacturing_yield
\set ON_ERROR_STOP on

TRUNCATE TABLE raw.rejected_test_result, manufacturing.test_result, raw.test_result RESTART IDENTITY;
TRUNCATE TABLE manufacturing.production_lot, manufacturing.failure_mode,
    manufacturing.test_station, manufacturing.product, manufacturing.production_line,
    manufacturing.plant RESTART IDENTITY CASCADE;

CREATE TEMP TABLE stage_plant (plant_code text, plant_name text, country text, timezone_name text);
CREATE TEMP TABLE stage_line (line_code text, plant_code text, line_name text);
CREATE TEMP TABLE stage_product (product_code text, product_name text, product_family text, target_cycle_seconds numeric);
CREATE TEMP TABLE stage_station (station_code text, station_name text, test_type text);
CREATE TEMP TABLE stage_failure (failure_code text, failure_category text, failure_description text);
CREATE TEMP TABLE stage_lot (lot_code text, line_code text, product_code text, planned_start_date date);

\copy stage_plant FROM '/project/data/plants.csv' WITH (FORMAT csv, HEADER true)
\copy stage_line FROM '/project/data/lines.csv' WITH (FORMAT csv, HEADER true)
\copy stage_product FROM '/project/data/products.csv' WITH (FORMAT csv, HEADER true)
\copy stage_station FROM '/project/data/stations.csv' WITH (FORMAT csv, HEADER true)
\copy stage_failure FROM '/project/data/failure_modes.csv' WITH (FORMAT csv, HEADER true)
\copy stage_lot FROM '/project/data/production_lots.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO manufacturing.plant (plant_code, plant_name, country, timezone_name)
SELECT upper(trim(plant_code)), trim(plant_name), trim(country), trim(timezone_name) FROM stage_plant;

INSERT INTO manufacturing.production_line (plant_id, line_code, line_name)
SELECT p.plant_id, upper(trim(s.line_code)), trim(s.line_name)
FROM stage_line s JOIN manufacturing.plant p ON p.plant_code = upper(trim(s.plant_code));

INSERT INTO manufacturing.product (product_code, product_name, product_family, target_cycle_seconds)
SELECT upper(trim(product_code)), trim(product_name), trim(product_family), target_cycle_seconds FROM stage_product;

INSERT INTO manufacturing.test_station (station_code, station_name, test_type)
SELECT upper(trim(station_code)), trim(station_name), upper(trim(test_type)) FROM stage_station;

INSERT INTO manufacturing.failure_mode (failure_code, failure_category, failure_description)
SELECT upper(trim(failure_code)), trim(failure_category), trim(failure_description) FROM stage_failure;

INSERT INTO manufacturing.production_lot (lot_code, line_id, product_id, planned_start_date)
SELECT upper(trim(s.lot_code)), l.line_id, p.product_id, s.planned_start_date
FROM stage_lot s
JOIN manufacturing.production_line l ON l.line_code = upper(trim(s.line_code))
JOIN manufacturing.product p ON p.product_code = upper(trim(s.product_code));

\copy raw.test_result (source_row_number, serial_number, lot_code, line_code, product_code, station_code, shift_name, tested_at_text, outcome_text, failure_code, cycle_time_seconds_text, measurement_value_text, lower_spec_limit_text, upper_spec_limit_text, operator_code) FROM '/project/data/raw_test_results.csv' WITH (FORMAT csv, HEADER true)

-- Cleaning is entirely SQL: whitespace/case standardization, outcome mapping,
-- type casting, key validation, de-duplication, and referential integrity.
WITH normalized AS (
    SELECT r.*,
        trim(r.source_row_number)::integer AS clean_source_row_number,
        upper(trim(r.serial_number)) AS clean_serial_number,
        upper(trim(r.lot_code)) AS clean_lot_code,
        upper(trim(r.line_code)) AS clean_line_code,
        upper(trim(r.product_code)) AS clean_product_code,
        upper(trim(r.station_code)) AS clean_station_code,
        initcap(lower(trim(r.shift_name))) AS clean_shift_name,
        trim(r.tested_at_text)::timestamp AS clean_tested_at,
        CASE upper(trim(r.outcome_text)) WHEN 'PASS' THEN 'PASS' WHEN 'OK' THEN 'PASS'
             WHEN 'FAIL' THEN 'FAIL' WHEN 'NG' THEN 'FAIL' END AS clean_outcome,
        nullif(upper(trim(r.failure_code)), '') AS clean_failure_code,
        trim(r.cycle_time_seconds_text)::numeric(8,2) AS clean_cycle_time,
        nullif(trim(r.measurement_value_text), '')::numeric(12,4) AS clean_measurement,
        nullif(trim(r.lower_spec_limit_text), '')::numeric(12,4) AS clean_lsl,
        nullif(trim(r.upper_spec_limit_text), '')::numeric(12,4) AS clean_usl,
        upper(trim(r.operator_code)) AS clean_operator_code,
        row_number() OVER (PARTITION BY upper(trim(r.serial_number)) ORDER BY r.raw_id) AS duplicate_rank
    FROM raw.test_result r
), resolved AS (
    SELECT n.*, lot.lot_id, line.line_id, product.product_id, station.station_id, fm.failure_mode_id
    FROM normalized n
    LEFT JOIN manufacturing.production_lot lot ON lot.lot_code = n.clean_lot_code
    LEFT JOIN manufacturing.production_line line ON line.line_code = n.clean_line_code
    LEFT JOIN manufacturing.product product ON product.product_code = n.clean_product_code
    LEFT JOIN manufacturing.test_station station ON station.station_code = n.clean_station_code
    LEFT JOIN manufacturing.failure_mode fm ON fm.failure_code = n.clean_failure_code
)
INSERT INTO manufacturing.test_result (
    source_row_number, serial_number, lot_id, line_id, product_id, station_id,
    failure_mode_id, shift_name, tested_at, outcome, cycle_time_seconds,
    measurement_value, lower_spec_limit, upper_spec_limit, operator_code
)
SELECT clean_source_row_number, clean_serial_number, lot_id, line_id, product_id, station_id,
       failure_mode_id, clean_shift_name, clean_tested_at, clean_outcome, clean_cycle_time,
       clean_measurement, clean_lsl, clean_usl, clean_operator_code
FROM resolved
WHERE duplicate_rank = 1
  AND lot_id IS NOT NULL AND line_id IS NOT NULL AND product_id IS NOT NULL AND station_id IS NOT NULL
  AND clean_shift_name IN ('Day', 'Evening', 'Night')
  AND clean_outcome IN ('PASS', 'FAIL')
  AND clean_cycle_time > 0
  AND ((clean_outcome = 'PASS' AND failure_mode_id IS NULL)
    OR (clean_outcome = 'FAIL' AND failure_mode_id IS NOT NULL));

-- Quarantine any row that failed validation instead of silently losing it.
INSERT INTO raw.rejected_test_result (raw_id, rejection_reason)
SELECT r.raw_id, 'Row failed normalization, key resolution, or domain validation'
FROM raw.test_result r
LEFT JOIN manufacturing.test_result t ON t.source_row_number = trim(r.source_row_number)::integer
WHERE t.test_result_id IS NULL;

ANALYZE manufacturing.test_result;
