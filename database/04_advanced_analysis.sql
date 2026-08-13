\connect manufacturing_yield

-- Q1. JOIN + GROUP BY: overall yield by plant and line.
SELECT d.plant_name, d.line_name, count(*) AS tested_units,
       sum(d.pass_count) AS passed_units,
       round(100.0 * sum(d.pass_count) / count(*), 2) AS yield_pct
FROM analytics.v_test_detail d
GROUP BY d.plant_name, d.line_name
ORDER BY yield_pct;

-- Q2. Subquery: lines performing below the fleet-wide average yield.
SELECT line_code, line_yield_pct
FROM (
    SELECT line_code, 100.0 * avg(pass_count) AS line_yield_pct
    FROM analytics.v_test_detail
    GROUP BY line_code
) line_summary
WHERE line_yield_pct < (SELECT 100.0 * avg(pass_count) FROM analytics.v_test_detail)
ORDER BY line_yield_pct;

-- Q3. CTE + RANK(): rank failure modes within every line.
WITH failures AS (
    SELECT line_code, failure_description, count(*) AS failure_count
    FROM analytics.v_test_detail
    WHERE outcome = 'FAIL'
    GROUP BY line_code, failure_description
), ranked AS (
    SELECT *, RANK() OVER (PARTITION BY line_code ORDER BY failure_count DESC) AS failure_rank
    FROM failures
)
SELECT * FROM ranked WHERE failure_rank <= 3 ORDER BY line_code, failure_rank, failure_description;

-- Q4. LAG(): day-over-day yield movement by line.
WITH daily AS (
    SELECT test_date, line_code, 100.0 * avg(pass_count) AS yield_pct
    FROM analytics.v_test_detail
    GROUP BY test_date, line_code
)
SELECT test_date, line_code, round(yield_pct, 2) AS yield_pct,
       round(yield_pct - LAG(yield_pct) OVER (PARTITION BY line_code ORDER BY test_date), 2) AS yield_change_pp
FROM daily
ORDER BY line_code, test_date;

-- Q5. Rolling average: 7-observation yield trend for each line.
WITH daily AS (
    SELECT test_date, line_code, 100.0 * avg(pass_count) AS yield_pct
    FROM analytics.v_test_detail
    GROUP BY test_date, line_code
)
SELECT test_date, line_code, round(yield_pct, 2) AS daily_yield_pct,
       round(avg(yield_pct) OVER (
           PARTITION BY line_code ORDER BY test_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 2) AS rolling_7_day_yield_pct
FROM daily
ORDER BY line_code, test_date;

-- Q6. Pareto with cumulative contribution; window aggregates retain each failure mode row.
SELECT failure_code, failure_description, failure_count, failure_pct, cumulative_failure_pct,
       CASE WHEN cumulative_failure_pct <= 80 THEN 'Vital few' ELSE 'Remaining' END AS pareto_class
FROM analytics.v_failure_pareto
ORDER BY failure_count DESC;

-- Q7. Detect the largest negative week-over-week change for each station.
WITH weekly AS (
    SELECT date_trunc('week', tested_at)::date AS week_start, station_code,
           100.0 * avg(pass_count) AS yield_pct
    FROM analytics.v_test_detail
    GROUP BY 1, 2
), changes AS (
    SELECT *, yield_pct - LAG(yield_pct) OVER (PARTITION BY station_code ORDER BY week_start) AS wow_change_pp
    FROM weekly
), ranked AS (
    SELECT *, RANK() OVER (PARTITION BY station_code ORDER BY wow_change_pp) AS deterioration_rank
    FROM changes WHERE wow_change_pp IS NOT NULL
)
SELECT week_start, station_code, round(yield_pct, 2) AS yield_pct,
       round(wow_change_pp, 2) AS wow_change_pp
FROM ranked WHERE deterioration_rank = 1
ORDER BY wow_change_pp;
