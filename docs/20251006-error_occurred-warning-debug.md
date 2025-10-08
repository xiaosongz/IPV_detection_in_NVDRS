# Debug Note: “Unknown or uninitialised column: `error_occurred`”

Date: 2025-10-06

## Summary
- Symptom: During experiment finalization, R printed repeated warnings:
  - `Unknown or uninitialised column: 'error_occurred'.`
- Outcome: Metrics computed and results saved, but the warnings appeared once per processed narrative.
- Fix: Added defensive defaults to the in-memory results tibble and a lightweight schema migration to ensure `error_occurred` (and related columns) exist on legacy databases.

## Context
Example run output (trimmed):

```
Step 8: Computing metrics...
...
Warning messages:
1: Unknown or uninitialised column: `error_occurred`.
...
10: Unknown or uninitialised column: `error_occurred`.
```

The experiment completed with valid metrics and persisted outputs. The warnings were noisy but non-fatal.

## Root Cause
- Some code paths referenced `error_occurred` on a tibble that didn’t include the column.
  - The database schema defines `error_occurred` on `narrative_results` (see `R/db_schema.R`).
  - If an existing/legacy SQLite file predated this column, or a tibble was constructed without it, downstream references triggered dplyr’s “Unknown or uninitialised column” warning.

## Investigation Steps
1. Grepped for usage to find where the column mattered and where warnings could originate.
   - References found in `scripts/run_experiment.R`, `R/experiment_logger.R`, `R/experiment_queries.R`, schema and tests.
2. Verified schema creation includes `error_occurred` and an index, but identified that:
   - Legacy databases might not have been migrated.
   - `get_experiment_results()` returned a tibble reflecting whatever columns exist in the DB; if missing, R code referencing `error_occurred` would warn.

## Fix Implemented
1. Results tibble hardening
   - File: `R/experiment_queries.R`
   - Change: `get_experiment_results()` now guarantees presence of expected columns, adding defaults if missing:
     - `error_occurred` (default `0L`)
     - `is_true_positive`, `is_true_negative`, `is_false_positive`, `is_false_negative` (default `NA_integer_`)
   - Effect: Downstream code can safely reference these columns without dplyr warnings.

2. Lightweight schema migration for legacy DBs
   - File: `R/db_schema.R`
   - Add: `ensure_error_columns(conn)`; invoked in both `init_experiment_db()` and `get_db_connection()`.
   - Behavior: Uses `PRAGMA table_info(narrative_results)` to detect missing columns and runs:
     - `ALTER TABLE narrative_results ADD COLUMN error_occurred INTEGER DEFAULT 0`
     - `ALTER TABLE narrative_results ADD COLUMN error_message TEXT`
     - Ensures index: `CREATE INDEX IF NOT EXISTS idx_error ON narrative_results(error_occurred)`
   - Effect: Existing SQLite files are auto-migrated; SQL filters on `error_occurred = 0` keep working.

## Verification
1. Re-run an experiment (same config):
   - `Rscript scripts/run_experiment.R configs/experiments/exp_001_test_gpt_oss.yaml`
   - Expectation: No “Unknown or uninitialised column: `error_occurred`” warnings.
2. Optional quick schema check (no full run):
   - `R -q -e "source('R/0_setup.R'); con <- get_db_connection(); DBI::dbDisconnect(con)"`
   - This triggers `ensure_error_columns()` on connect.

## Impact
- User-facing behavior is unchanged except warnings are eliminated.
- Metrics (accuracy/precision/recall/F1) are unaffected. Note that `NA` recall/F1 is expected when there are no positives or denominators are zero.

## Files Changed (Code)
- `R/experiment_queries.R`: Ensure expected columns on results tibble.
- `R/db_schema.R`: Add `ensure_error_columns()` and call it from init/connect.

## Future Guardrails
- Keep result-tibble hardening in query helpers that feed downstream analytics.
- Always include minimal migration helpers in schema modules and call them both on init and on connect.

## Changelog Suggestion
- Fix: Remove `error_occurred` warnings by hardening `get_experiment_results()` and adding legacy DB migration for error columns.

