\connect manufacturing_yield

CREATE INDEX IF NOT EXISTS idx_test_result_tested_at ON manufacturing.test_result (tested_at);
CREATE INDEX IF NOT EXISTS idx_test_result_line_date ON manufacturing.test_result (line_id, tested_at);
CREATE INDEX IF NOT EXISTS idx_test_result_station_date ON manufacturing.test_result (station_id, tested_at);
CREATE INDEX IF NOT EXISTS idx_test_result_failure_mode ON manufacturing.test_result (failure_mode_id) WHERE outcome = 'FAIL';
CREATE INDEX IF NOT EXISTS idx_test_result_product_outcome ON manufacturing.test_result (product_id, outcome);
CREATE INDEX IF NOT EXISTS idx_lot_line_product ON manufacturing.production_lot (line_id, product_id);

CREATE OR REPLACE VIEW analytics.v_test_detail AS
SELECT
    tr.test_result_id,
    tr.serial_number,
    tr.tested_at,
    tr.tested_at::date AS test_date,
    extract(isoyear FROM tr.tested_at)::integer AS test_year,
    extract(week FROM tr.tested_at)::integer AS test_week,
    pl.plant_code,
    pl.plant_name,
    ln.line_code,
    ln.line_name,
    p.product_code,
    p.product_name,
    p.product_family,
    lot.lot_code,
    s.station_code,
    s.station_name,
    s.test_type,
    tr.shift_name,
    tr.operator_code,
    tr.outcome,
    (tr.outcome = 'PASS')::integer AS pass_count,
    (tr.outcome = 'FAIL')::integer AS fail_count,
    tr.cycle_time_seconds,
    p.target_cycle_seconds,
    tr.cycle_time_seconds - p.target_cycle_seconds AS cycle_variance_seconds,
    tr.measurement_value,
    tr.lower_spec_limit,
    tr.upper_spec_limit,
    fm.failure_code,
    fm.failure_category,
    fm.failure_description
FROM manufacturing.test_result tr
JOIN manufacturing.production_lot lot ON lot.lot_id = tr.lot_id
JOIN manufacturing.production_line ln ON ln.line_id = tr.line_id
JOIN manufacturing.plant pl ON pl.plant_id = ln.plant_id
JOIN manufacturing.product p ON p.product_id = tr.product_id
JOIN manufacturing.test_station s ON s.station_id = tr.station_id
LEFT JOIN manufacturing.failure_mode fm ON fm.failure_mode_id = tr.failure_mode_id;

CREATE OR REPLACE VIEW analytics.v_yield_daily AS
SELECT test_date, plant_code, line_code, product_code,
       count(*) AS tested_units,
       sum(pass_count) AS passed_units,
       sum(fail_count) AS failed_units,
       round(100.0 * sum(pass_count) / nullif(count(*), 0), 2) AS first_pass_yield_pct,
       round(avg(cycle_time_seconds), 2) AS avg_cycle_seconds
FROM analytics.v_test_detail
GROUP BY test_date, plant_code, line_code, product_code;

CREATE OR REPLACE VIEW analytics.v_failure_pareto AS
SELECT failure_code, failure_category, failure_description,
       count(*) AS failure_count,
       round(100.0 * count(*) / nullif(sum(count(*)) OVER (), 0), 2) AS failure_pct,
       round(100.0 * sum(count(*)) OVER (ORDER BY count(*) DESC, failure_code)
             / nullif(sum(count(*)) OVER (), 0), 2) AS cumulative_failure_pct
FROM analytics.v_test_detail
WHERE outcome = 'FAIL'
GROUP BY failure_code, failure_category, failure_description;

CREATE OR REPLACE VIEW analytics.v_station_performance AS
SELECT station_code, station_name, test_type,
       count(*) AS tested_units,
       sum(fail_count) AS failed_units,
       round(100.0 * sum(pass_count) / nullif(count(*), 0), 2) AS yield_pct,
       round(avg(cycle_time_seconds), 2) AS avg_cycle_seconds,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY cycle_time_seconds)::numeric, 2) AS p95_cycle_seconds
FROM analytics.v_test_detail
GROUP BY station_code, station_name, test_type;
