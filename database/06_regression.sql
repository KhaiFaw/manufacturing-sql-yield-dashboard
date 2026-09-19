\set ON_ERROR_STOP on
\connect manufacturing_yield

-- These assertions are intentionally specific to the committed synthetic fixture.
DO $$
BEGIN
    IF (SELECT count(*) FROM raw.test_result) <> 8000
       OR (SELECT count(*) FROM manufacturing.test_result) <> 8000
       OR (SELECT count(*) FROM raw.rejected_test_result) <> 0 THEN
        RAISE EXCEPTION 'Seeded dataset row-count regression';
    END IF;
    IF (SELECT count(*) FROM manufacturing.test_result WHERE outcome='PASS') <> 7558
       OR (SELECT count(*) FROM manufacturing.test_result WHERE outcome='FAIL') <> 442 THEN
        RAISE EXCEPTION 'Seeded outcome-count regression';
    END IF;
    IF (SELECT count(*) FROM analytics.v_test_detail) <> 8000
       OR (SELECT sum(tested_units) FROM analytics.v_yield_daily) <> 8000
       OR (SELECT sum(failure_count) FROM analytics.v_failure_pareto) <> 442
       OR (SELECT sum(tested_units) FROM analytics.v_station_performance) <> 8000 THEN
        RAISE EXCEPTION 'Analytics views no longer reconcile with source';
    END IF;
    RAISE NOTICE 'Synthetic fixture and four analytics views reconcile.';
END $$;
