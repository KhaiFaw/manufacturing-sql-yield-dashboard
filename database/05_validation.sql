\connect manufacturing_yield

DO $$
DECLARE
    test_count integer;
    orphan_count integer;
    bad_outcome_count integer;
BEGIN
    SELECT count(*) INTO test_count FROM manufacturing.test_result;
    IF test_count < 1000 OR test_count > 10000 THEN
        RAISE EXCEPTION 'Expected 1,000-10,000 clean test rows, found %', test_count;
    END IF;

    SELECT count(*) INTO orphan_count
    FROM manufacturing.test_result tr
    LEFT JOIN manufacturing.production_lot l ON l.lot_id = tr.lot_id
    WHERE l.lot_id IS NULL;
    IF orphan_count <> 0 THEN RAISE EXCEPTION 'Found % orphaned results', orphan_count; END IF;

    SELECT count(*) INTO bad_outcome_count
    FROM manufacturing.test_result
    WHERE (outcome = 'PASS' AND failure_mode_id IS NOT NULL)
       OR (outcome = 'FAIL' AND failure_mode_id IS NULL);
    IF bad_outcome_count <> 0 THEN RAISE EXCEPTION 'Found % inconsistent outcomes', bad_outcome_count; END IF;

    RAISE NOTICE 'Validation passed: % clean test records, no orphan keys, outcomes consistent.', test_count;
END $$;

SELECT
    (SELECT count(*) FROM raw.test_result) AS raw_rows,
    (SELECT count(*) FROM manufacturing.test_result) AS clean_rows,
    (SELECT count(*) FROM raw.rejected_test_result) AS rejected_rows,
    (SELECT count(*) FROM analytics.v_yield_daily) AS daily_summary_rows;
