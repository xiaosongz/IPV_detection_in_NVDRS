# Resumable Production Runs: Design and Implementation Plan

Date: 2025-10-27
Owner: Research/Engineering
Scope: Production runs of ~42k narratives (20,946 cases × 2) with safe break/resume

## Goals

- Allow long-running production experiments to pause/crash and resume without reprocessing completed narratives.
- Support resuming with the same experiment_id (run_id) to keep results unified in a single experiment record.
- Persist source narratives in the database once and read only from DB thereafter (no repeated Excel reads).
- Keep implementation minimally invasive and backward compatible.

## Non‑Goals

- Parallel/distributed execution across multiple hosts (future work).
- Full-blown job queue with locks and worker heartbeats (out of scope for this iteration).

## Design Overview

Resuming will be driven by the experiment_id. The pipeline will:

1) Ensure source data from Excel is loaded into `source_narratives` exactly once and referenced exclusively thereafter.
2) When resuming, identify remaining narratives for the given `experiment_id` by left‑joining `source_narratives` with `narrative_results` and selecting rows not yet processed (or optionally, those processed with `error_occurred = 1`).
3) Process only the remaining narratives, append results to `narrative_results`, and finalize the existing `experiments` record upon completion.
4) Enforce idempotency with a unique index on `(experiment_id, incident_id, narrative_type)` in `narrative_results` to prevent duplicates per experiment.

## Data Flow

- Initial ingest: `load_source_data(conn, data-raw/all_suicide_nar.xlsx)` populates `source_narratives (incident_id, narrative_type, narrative_text, ...)` with a `UNIQUE(incident_id, narrative_type)` per case/type.
- Normalized reads: All runs (new and resumed) pull input narratives exclusively from `source_narratives` via SQL. Excel is consulted only if `source_narratives` does not already contain the `data_source`.

## Schema Changes

Minimal changes to support idempotency and efficient resume.

1) Unique result per narrative per experiment

```sql
-- Prevent duplicate rows for the same (experiment, incident, type)
CREATE UNIQUE INDEX IF NOT EXISTS uq_result_per_exp_narrative
  ON narrative_results(experiment_id, incident_id, narrative_type);
```

2) Optional enhancements (can be deferred)

- Attempts tracking to aid diagnostics (optional):
  - `ALTER TABLE narrative_results ADD COLUMN attempt_count INTEGER DEFAULT 1;`
  - `ALTER TABLE narrative_results ADD COLUMN last_attempt_at TEXT;`
- Reference key for performance (optional):
  - `ALTER TABLE narrative_results ADD COLUMN src_narrative_id INTEGER;`
  - Populate with `source_narratives.narrative_id` and add index.

These are not strictly required for the first iteration; the unique index provides the core idempotency guarantee.

## Resume Logic

Target experiment selection:

- New run: create a fresh experiment via `start_experiment()` (current behavior).
- Resume run: use an existing `experiment_id` (provided via flag/env/config). Reuse the experiment record and prompts from DB to avoid YAML drift.

Remaining‑set query (missing‑only):

```sql
SELECT s.incident_id, s.narrative_type, s.narrative_text,
       s.manual_flag_ind, s.manual_flag
FROM source_narratives s
LEFT JOIN narrative_results r
  ON r.experiment_id = :experiment_id
 AND r.incident_id    = s.incident_id
 AND r.narrative_type = s.narrative_type
WHERE r.result_id IS NULL
ORDER BY s.narrative_id;
```

Remaining‑set query (retry errors only):

```sql
SELECT s.incident_id, s.narrative_type, s.narrative_text,
       s.manual_flag_ind, s.manual_flag
FROM source_narratives s
LEFT JOIN narrative_results r
  ON r.experiment_id = :experiment_id
 AND r.incident_id    = s.incident_id
 AND r.narrative_type = s.narrative_type
WHERE r.result_id IS NULL
   OR r.error_occurred = 1
ORDER BY s.narrative_id;
```

Idempotency during logging:

- Before insert, either:
  - Check if a row exists for `(experiment_id, incident_id, narrative_type)` and skip if present, or
  - Use `INSERT OR IGNORE` into `narrative_results` when the unique index is in place.
- For "retry errors only", either delete the error row first or perform an `INSERT OR REPLACE` update. Initial implementation will “delete‑then‑insert” for clarity.

## CLI/Config Interface

Add resume flags through either environment variables or command‑line args (simplest: env vars).

- Environment variables (preferred for shell scripting):
  - `RESUME=1` → resume mode
  - `EXPERIMENT_ID=<uuid>` → target experiment to resume (required when RESUME=1)
  - `RETRY_ERRORS_ONLY=1` → reprocess only rows with `error_occurred = 1` (optional)

- YAML (optional convenience):

```yaml
run:
  resume: true           # default false
  experiment_id: "..."   # when resume is true
  retry_errors_only: false
```

`scripts/run_experiment.R` will prefer explicit ENV flags over YAML if both are present.

## Orchestration Changes (R)

1) scripts/run_experiment.R

- Parse ENV flags: `RESUME`, `EXPERIMENT_ID`, `RETRY_ERRORS_ONLY`.
- If `RESUME=1` and `EXPERIMENT_ID` provided:
  - Load experiment record from DB.
  - Use stored prompts/model/api_url from DB for consistency, ignoring YAML deltas (warn if mismatched).
  - Build remaining set using the queries above.
  - Skip `start_experiment()`; attach logger to existing experiment’s `log_dir`.
  - Proceed to `run_benchmark_core()` with only remaining narratives.
- Else (new run): current behavior unchanged.

2) R/run_benchmark_core.R

- Accept additional parameters: `resume = FALSE`, `retry_errors_only = FALSE`, `experiment_id`.
- If `resume = TRUE`, assume input narratives are already filtered to “remaining set”.
- Guard each insert with either a pre‑existence check or `INSERT OR IGNORE` to avoid duplicates in race conditions.

3) R/experiment_logger.R

- Add ability to re‑use existing log directory for a known `experiment_id` without overwriting previous logs (append mode already used; retain behavior).

4) R/data_loader.R

- No functional change needed. It already loads Excel once and reuses DB thereafter. Ensure `check_data_loaded()` is invoked before loading.

## Shell Script Updates

1) scripts/run_production_20k.sh

- Add a `--resume` mode, e.g.:

```bash
# Resume latest incomplete production experiment by name (example)
RESUME=1 EXPERIMENT_ID="${EXPERIMENT_ID}" \
  Rscript scripts/run_experiment.R configs/experiments/exp_100_production_20k_indicators_t02_high.yaml
```

- Optionally add a helper to auto‑discover the latest incomplete experiment:

```bash
EXPERIMENT_ID=$(sqlite3 data/production_20k.db "
  SELECT experiment_id FROM experiments
  WHERE status != 'completed' AND experiment_name LIKE '%Production%'
  ORDER BY start_time DESC LIMIT 1;")
```

## Backward Compatibility

- New runs behave as before when `RESUME` is unset.
- The unique index prevents accidental duplication within the same experiment.
- Existing analyses and exports continue to function.

## Testing Strategy

1) Unit‑level SQL checks
   - Create a small DB fixture with `source_narratives` and partial `narrative_results`.
   - Verify remaining‑set queries return only unprocessed rows.

2) End‑to‑end smoke test
   - Run `exp_101_production_smoke_test.yaml` to process 50 narratives; kill the process.
   - Resume with `RESUME=1` on the same `experiment_id`; confirm total reaches 200 without duplicates.

3) Error retry test
   - Inject a few error rows (`error_occurred = 1`), run with `RETRY_ERRORS_ONLY=1`, and confirm those rows are recomputed and errors cleared.

4) Idempotency test
   - Attempt to process already‑completed narratives; ensure inserts are ignored and counts unchanged.

## Risks and Mitigations

- Prompt/config drift on resume
  - Mitigation: When resuming, read and use prompts/settings from the existing experiment record (ignore YAML deltas, warn user).

- Partial writes or race conditions
  - Mitigation: Unique index plus `INSERT OR IGNORE`/pre‑check.

- Large DB joins performance
  - Mitigation: Existing indexes on `source_narratives(incident_id, narrative_type)` and `narrative_results(experiment_id, incident_id, narrative_type)` support join performance; add composite index if needed.

## Migration Steps (One‑time)

1) Apply unique index migration (safe to run repeatedly):

```bash
sqlite3 data/production_20k.db "
  CREATE UNIQUE INDEX IF NOT EXISTS uq_result_per_exp_narrative
  ON narrative_results(experiment_id, incident_id, narrative_type);
"
```

2) Update R scripts per sections above.

3) Update production shell script to pass resume flags and optionally discover an incomplete experiment.

## Timeline (Estimate)

- Schema/index + helper SQL: 0.5 day
- Orchestration changes (R) + CLI/env handling: 1.0 day
- Testing (unit + E2E smoke): 0.5–1.0 day

Total: ~2–2.5 days including validation.

## Appendix: Pseudocode (Resume Path)

```r
# scripts/run_experiment.R (resume path)
if (Sys.getenv("RESUME", "0") == "1") {
  exp_id <- Sys.getenv("EXPERIMENT_ID", "")
  stopifnot(nzchar(exp_id))

  conn <- get_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # Load canonical config from DB for this experiment
  exp <- DBI::dbGetQuery(conn, "SELECT * FROM experiments WHERE experiment_id = ?", params = list(exp_id))

  # Build remaining set
  retry_only <- Sys.getenv("RETRY_ERRORS_ONLY", "0") == "1"
  remaining <- if (!retry_only) {
    sql_remaining_missing_only(conn, exp_id)
  } else {
    sql_remaining_retry_errors(conn, exp_id)
  }

  logger <- init_experiment_logger(exp_id)
  run_benchmark_core(db_config_from_exp(exp), conn, exp_id, remaining, logger, resume = TRUE, retry_errors_only = retry_only)

  finalize_experiment(conn, exp_id)  # if all done
  quit(status = 0)
}
```

