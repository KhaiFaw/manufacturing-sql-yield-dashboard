# Verification record

20 September 2026. Base source `665b459` plus local documentation, test and Compose changes.

## Executed checks

- Five Python 3.12 tests pass: generated CSVs match the committed fixture byte-for-byte, regeneration is deterministic, identifiers are unique, published pass/fail counts reconcile, and intentional whitespace/outcome variations remain present.
- `docker compose config --quiet` passes. The database now binds to loopback only, using the existing disposable example credentials.
- A separate `portfolio-audit` Compose project on PostgreSQL 16 was initialized from the checked-in CSVs. The SQL pipeline completed: 8,000 raw rows, 8,000 clean rows, zero rejected rows and 360 daily-summary rows.
- `database/06_regression.sql` verifies exactly 7,558 passes and 442 failures, then reconciles the detail, daily-yield, Pareto and station views.
- The load and regression script both passed a second time against the same database. This verifies rerunnable fixture loading.
- The proposed GitHub Actions workflow runs the Python suite and both SQL passes on a disposable Ubuntu runner. It has not been published or run remotely.
- The installed Microsoft PBIR authoring validator reported zero errors and one `PBIR_SCHEMA_UNREACHABLE` warning: the visual-container 2.11.0 schema could not be fetched. This is a partial validation, not a clean all-schema pass.

## Interpretation

All data is synthetic, generated with seed `20260813`. The existing dashboard screenshots are genuine Power BI captures of that synthetic dataset. A fresh Power BI Desktop refresh is a separate manual check; database correctness alone does not prove GUI rendering.

The loader casts numeric/date strings before quarantine. Malformed cast inputs are outside this fixture's test coverage and may stop the import. No production throughput, deployment readiness, real factory causality or operational availability is claimed.

The known local example database credentials are not production secrets. Keep this configuration on the loopback interface and use a dedicated configuration for any future deployment.
