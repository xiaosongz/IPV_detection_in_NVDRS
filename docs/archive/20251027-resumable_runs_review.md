# Resumable Production Runs - Critical Review

**Date**: 2025-10-27
**Reviewer**: Claude Code
**Document**: `docs/20251027-resumable_production_runs_plan.md`

## Executive Summary

The resumable runs plan is **well-designed** overall, but has **8 critical issues** and **7 important gaps** that must be addressed before implementation. Most issues involve edge cases, error handling, and operational safety.

**Overall Assessment**: 7/10 - Solid foundation, needs refinement
**Recommendation**: Address critical issues before starting implementation

---

## Critical Issues (Must Fix)

### 1. ⚠️ **Source Data Validation Missing**

**Problem**: No mechanism to verify source data hasn't changed between runs.

```sql
-- Current source_narratives schema
CREATE TABLE source_narratives (
  narrative_id INTEGER PRIMARY KEY,
  incident_id TEXT,
  narrative_type TEXT,
  narrative_text TEXT,
  manual_flag_ind INTEGER,
  manual_flag INTEGER,
  data_source TEXT,  -- Only stores file path, not checksum
  loaded_at TEXT
);
```

**Risk**: User could:
1. Run 10k narratives from `all_suicide_nar.xlsx` (version 1)
2. Update the file to different content
3. Resume and process remaining 30k from version 2
4. Results are inconsistent - some from v1, some from v2

**Fix**:
```sql
-- Add checksum column
ALTER TABLE source_narratives ADD COLUMN data_checksum TEXT;

-- On resume, verify:
current_checksum = digest::digest(file = data_file, algo = "md5")
existing_checksum = dbGetQuery(conn, "SELECT DISTINCT data_checksum FROM source_narratives WHERE data_source = ?")

if (current_checksum != existing_checksum) {
  stop("Data file changed since original run. Cannot resume safely.")
}
```

**Severity**: HIGH - Silent data corruption
**Effort**: 0.5 day

---

### 2. ⚠️ **Experiment Status State Machine Unclear**

**Problem**: Plan doesn't define clear status transitions or validation.

Current code sets status to `"running"` on start, `"completed"` on finish. What about:
- Crashed runs? (Status stays "running")
- Failed runs? (No "failed" status defined)
- Cancelled runs? (No mechanism)
- Multiple resume attempts?

**Issue in pseudocode** (line 235):
```r
exp <- DBI::dbGetQuery(conn, "SELECT * FROM experiments WHERE experiment_id = ?", params = list(exp_id))
# Missing: What if exp is empty? What if status is already 'completed'?
```

**Fix**: Define clear state machine:

```
States: 'running' | 'completed' | 'failed' | 'cancelled'

Transitions:
  start_experiment() → 'running'
  finalize_experiment() → 'completed'
  on_error() → 'failed'
  user_cancel() → 'cancelled'

Resume validation:
  - Can resume from: 'running', 'failed'
  - Cannot resume from: 'completed' (warn and exit)
  - On resume: set status back to 'running'
```

```r
# In resume path, add validation:
if (nrow(exp) == 0) {
  stop("Experiment ID not found: ", exp_id)
}
if (exp$status == "completed") {
  stop("Cannot resume completed experiment. Already processed all narratives.")
}
if (exp$status == "cancelled") {
  message("Resuming cancelled experiment...")
}

# Set status to 'running' before processing
dbExecute(conn, "UPDATE experiments SET status = 'running' WHERE experiment_id = ?", params = list(exp_id))
```

**Severity**: HIGH - Operational confusion
**Effort**: 0.5 day

---

### 3. ⚠️ **Concurrent Resume Prevention Missing**

**Problem**: Two processes could resume the same experiment simultaneously.

**Scenario**:
```bash
# Terminal 1
RESUME=1 EXPERIMENT_ID=abc123 Rscript scripts/run_experiment.R config.yaml

# Terminal 2 (accidentally)
RESUME=1 EXPERIMENT_ID=abc123 Rscript scripts/run_experiment.R config.yaml
```

Both processes would:
1. Query remaining narratives (same set)
2. Start processing simultaneously
3. Unique index prevents duplicates BUT:
   - Wasted compute on duplicate work
   - Errors/retries in logs
   - Confusing metrics (double timing)

**Fix**: Add PID lock file:

```r
# In resume path, before querying remaining set:
lock_file <- paste0("data/.resume_lock_", experiment_id, ".pid")

if (file.exists(lock_file)) {
  pid <- readLines(lock_file)[1]
  # Check if process still running (platform-specific)
  if (system(paste0("kill -0 ", pid), ignore.stdout = TRUE, ignore.stderr = TRUE) == 0) {
    stop("Experiment ", experiment_id, " is already being resumed by PID ", pid)
  } else {
    message("Removing stale lock file from PID ", pid)
    file.remove(lock_file)
  }
}

# Create lock file
writeLines(as.character(Sys.getpid()), lock_file)

# Ensure cleanup
on.exit({
  if (file.exists(lock_file)) file.remove(lock_file)
}, add = TRUE)
```

**Severity**: MEDIUM - Wasted compute, confusion
**Effort**: 0.5 day

---

### 4. ⚠️ **Progress Tracking Missing**

**Problem**: No way to monitor progress during 24-35 hour run.

Current plan has no mechanism to answer:
- How many narratives completed vs remaining?
- Current rate (narratives/sec)?
- ETA to completion?
- Progress percentage?

**User experience**: Staring at a terminal for 30 hours with no feedback.

**Fix**: Add periodic progress reporting:

```r
# In run_benchmark_core.R, after processing each narrative:
if (i %% 100 == 0) {  # Every 100 narratives
  elapsed_sec <- as.numeric(Sys.time() - start_time)
  rate <- i / elapsed_sec
  remaining <- total_narratives - i
  eta_sec <- remaining / rate
  eta_time <- Sys.time() + eta_sec

  message(sprintf(
    "[PROGRESS] %d/%d (%.1f%%) | Rate: %.2f/sec | ETA: %s | Elapsed: %s",
    i, total_narratives,
    100 * i / total_narratives,
    rate,
    format(eta_time, "%Y-%m-%d %H:%M:%S"),
    format_duration(elapsed_sec)
  ))
}
```

Also store progress in database:

```sql
ALTER TABLE experiments ADD COLUMN n_narratives_completed INTEGER DEFAULT 0;
ALTER TABLE experiments ADD COLUMN last_progress_update TEXT;

-- Update periodically (every 100 narratives)
UPDATE experiments
SET n_narratives_completed = ?, last_progress_update = ?
WHERE experiment_id = ?;
```

This enables external monitoring:
```bash
# While production runs, in another terminal:
watch -n 60 'sqlite3 data/production_20k.db "
  SELECT experiment_name, n_narratives_completed, n_narratives_total,
         ROUND(100.0 * n_narratives_completed / n_narratives_total, 1) as pct_done
  FROM experiments WHERE status = \"running\"
"'
```

**Severity**: HIGH - Poor UX, no visibility into 30-hour runs
**Effort**: 0.5 day

---

### 5. ⚠️ **max_narratives Interaction Undefined**

**Problem**: Config has `max_narratives` setting. Behavior on resume is unclear.

```yaml
run:
  max_narratives: 1000000  # Process all
```

**Questions**:
1. Does `max_narratives` apply to the resumed set or total?
2. If original run had `max_narratives: 1000`, does resume respect this?
3. What if config YAML changed max_narratives between runs?

**Example scenario**:
- Original run: `max_narratives: 10000`, processed 5000, crashed
- Resume with: `max_narratives: 20000` in YAML
- Should it process 5000 more (original limit) or 15000 more (new limit)?

**Fix**: Use stored value from DB, ignore YAML:

```r
# In resume path:
exp <- dbGetQuery(conn, "SELECT * FROM experiments WHERE experiment_id = ?", params = list(exp_id))

# Use original n_narratives_total from DB, not from YAML
max_narratives <- exp$n_narratives_total

# Warn if YAML differs
if (!is.null(config$run$max_narratives) && config$run$max_narratives != max_narratives) {
  warning("YAML max_narratives (", config$run$max_narratives,
          ") differs from original experiment (", max_narratives,
          "). Using original value for consistency.")
}
```

**Severity**: MEDIUM - Inconsistent behavior
**Effort**: 0.25 day

---

### 6. ⚠️ **Incremental Export Handling Unclear**

**Problem**: Current system supports `save_incremental: true` for CSV/JSON exports during runs. On resume, unclear how this interacts.

Current behavior (from plan):
```yaml
run:
  save_incremental: true   # Saves results every N narratives
  save_csv_json: true
```

**Issues**:
1. Resume appends to existing CSV/JSON or overwrites?
2. If appending, row numbers/ordering might be wrong
3. If overwriting, loses previous progress if crash happens again

**Fix**: On resume, regenerate exports from DB:

```r
# In resume path, before starting:
if (!is.null(config$run$save_csv_json) && config$run$save_csv_json) {
  message("Regenerating exports from existing results...")

  # Export all results processed so far
  results <- dbGetQuery(conn, "SELECT * FROM narrative_results WHERE experiment_id = ?", params = list(exp_id))

  if (nrow(results) > 0) {
    csv_file <- paste0("benchmark_results/resume_checkpoint_", experiment_id, ".csv")
    write.csv(results, csv_file, row.names = FALSE)
    message("Checkpoint export: ", csv_file)
  }
}

# Then proceed with incremental saves for NEW results only
```

**Severity**: MEDIUM - Data loss risk on re-crash
**Effort**: 0.5 day

---

### 7. ⚠️ **Error Row Handling Strategy Incomplete**

**Problem**: Plan proposes "delete-then-insert" for retry errors, but this loses diagnostic information.

```sql
-- Plan suggests (line 97):
-- "delete error row first or perform INSERT OR REPLACE"
DELETE FROM narrative_results
WHERE experiment_id = ? AND incident_id = ? AND narrative_type = ? AND error_occurred = 1;

-- Then insert new attempt
```

**Issues**:
1. Original error message lost (can't diagnose patterns)
2. No record of how many retry attempts
3. Can't distinguish "succeeded on retry" vs "succeeded first try"

**Fix**: UPDATE instead of DELETE:

```sql
-- Option 1: Add attempt tracking (recommended)
ALTER TABLE narrative_results ADD COLUMN attempt_count INTEGER DEFAULT 1;
ALTER TABLE narrative_results ADD COLUMN first_error_message TEXT;
ALTER TABLE narrative_results ADD COLUMN last_attempt_at TEXT;

-- On retry, UPDATE the row:
UPDATE narrative_results SET
  detected = ?,
  confidence = ?,
  indicators = ?,
  rationale = ?,
  raw_response = ?,
  response_sec = ?,
  error_occurred = 0,
  error_message = NULL,
  attempt_count = attempt_count + 1,
  last_attempt_at = ?,
  processed_at = ?
WHERE experiment_id = ? AND incident_id = ? AND narrative_type = ?;

-- Preserve first_error_message for diagnostics:
UPDATE narrative_results SET
  first_error_message = error_message
WHERE first_error_message IS NULL AND error_occurred = 1;
```

**Severity**: MEDIUM - Loses diagnostic data
**Effort**: 0.5 day

---

### 8. ⚠️ **Seed Handling on Resume Not Defined**

**Problem**: Config has `seed: 1024` for reproducibility. On resume, unclear which seed is used.

```yaml
run:
  seed: 1024
```

Temperature-based sampling in LLM might produce different results if seed changes.

**Questions**:
1. Does resume use original seed or new seed?
2. Is seed set once per experiment or once per narrative?
3. Does it matter for deterministic (T=0.2) models?

**Current code** (from `experiment_logger.R`):
```r
# Stores run_seed in experiments table
run_seed = config$run$seed
```

**Fix**: Always use original seed on resume:

```r
# In resume path:
exp <- dbGetQuery(conn, "SELECT run_seed FROM experiments WHERE experiment_id = ?", params = list(exp_id))

# Set global seed to original value
if (!is.na(exp$run_seed)) {
  set.seed(exp$run_seed)
  message("Using original seed: ", exp$run_seed)
}

# Warn if YAML differs
if (!is.null(config$run$seed) && config$run$seed != exp$run_seed) {
  warning("YAML seed (", config$run$seed,
          ") differs from original (", exp$run_seed,
          "). Using original for reproducibility.")
}
```

**Severity**: LOW - Affects reproducibility
**Effort**: 0.25 day

---

## Important Issues (Should Fix)

### 9. Transaction Safety Not Discussed

**Problem**: Plan doesn't mention transaction handling for batch inserts.

**Risk**: If process crashes mid-batch (e.g., after processing 50 narratives but before commit), those 50 results are lost.

**Fix**: Use periodic commits:

```r
# In run_benchmark_core.R:
DBI::dbBegin(conn)
batch_size <- 0

for (i in seq_len(nrow(narratives))) {
  # Process narrative
  result <- call_llm(...)
  log_narrative_result(conn, experiment_id, result)

  batch_size <- batch_size + 1

  # Commit every 100 narratives
  if (batch_size >= 100) {
    DBI::dbCommit(conn)
    DBI::dbBegin(conn)
    batch_size <- 0
  }
}

# Commit remaining
if (batch_size > 0) {
  DBI::dbCommit(conn)
}
```

**Severity**: MEDIUM
**Effort**: 0.25 day

---

### 10. Metrics Finalization Logic Validated ✅

**Status**: **ALREADY CORRECT** - No changes needed

**Review**: The plan mentions `finalize_experiment()` and I verified the implementation:

```r
# From R/experiment_logger.R:237-313
finalize_experiment <- function(conn, experiment_id, csv_file = NULL, json_file = NULL) {
  # ...
  enhanced_metrics <- compute_enhanced_metrics(conn, experiment_id)
  # ...
}

compute_enhanced_metrics <- function(conn, experiment_id) {
  results <- DBI::dbGetQuery(conn,
    "SELECT detected, manual_flag_ind, is_true_positive, ...
     FROM narrative_results
     WHERE experiment_id = ? AND error_occurred = 0",
    params = list(experiment_id)
  )
  # Calculates metrics across ALL results for this experiment
}
```

**Conclusion**: Metrics are **correctly** recalculated across all results (both original + resumed). No changes needed.

---

### 11. Backup Strategy on Resume Unclear

**Problem**: `run_production_20k.sh` creates backup before starting:

```bash
BACKUP_FILE="data/production_20k_backup_$(date +%Y%m%d_%H%M%S).db"
cp "$DB_FILE" "$BACKUP_FILE"
```

**Question**: Should resume also create a backup before continuing?

**Recommendation**: Yes, for safety:

```bash
# In resume mode, before processing:
if [ "$RESUME" = "1" ]; then
  RESUME_BACKUP="data/production_20k_resume_backup_$(date +%Y%m%d_%H%M%S).db"
  cp "$DB_FILE" "$RESUME_BACKUP"
  log "✓ Resume backup created: $RESUME_BACKUP"
fi
```

**Severity**: LOW - Safety improvement
**Effort**: 0.1 day

---

### 12. Remaining Narratives Count Not Logged

**Problem**: User doesn't know how many narratives are left to process on resume.

**Fix**: Add logging:

```r
# In resume path, after building remaining set:
n_remaining <- nrow(remaining)
n_completed <- dbGetQuery(conn, "SELECT COUNT(*) as n FROM narrative_results WHERE experiment_id = ?", params = list(exp_id))$n

message("========================================")
message("RESUMING EXPERIMENT: ", exp_id)
message("========================================")
message("Completed: ", n_completed, " narratives")
message("Remaining: ", n_remaining, " narratives")
message("Total: ", n_completed + n_remaining, " narratives")
message("Progress: ", sprintf("%.1f%%", 100 * n_completed / (n_completed + n_remaining)))
message("========================================")
```

**Severity**: LOW - UX improvement
**Effort**: 0.1 day

---

### 13. Discovery Query Status Values Undefined

**Problem**: Auto-discover query uses `status != 'completed'`:

```bash
EXPERIMENT_ID=$(sqlite3 data/production_20k.db "
  SELECT experiment_id FROM experiments
  WHERE status != 'completed' AND experiment_name LIKE '%Production%'
  ORDER BY start_time DESC LIMIT 1;")
```

**Question**: What statuses exist? Documentation doesn't define them.

**Fix**: Add to plan:

```
Status Values:
- 'running'    : Currently processing
- 'completed'  : Finished successfully
- 'failed'     : Crashed or errored
- 'cancelled'  : User-cancelled

Discovery query should use:
WHERE status IN ('running', 'failed') AND ...
```

**Severity**: LOW - Documentation gap
**Effort**: 0.1 day

---

### 14. Error Categorization Missing

**Problem**: All errors treated equally. Some should retry (API timeout), others shouldn't (malformed narrative).

**Current**: Single `error_occurred` flag.

**Enhancement**: Add error category:

```sql
ALTER TABLE narrative_results ADD COLUMN error_category TEXT;

-- Categories:
-- 'api_error'      : Network/API issues (should retry)
-- 'parse_error'    : JSON parsing failed (might retry)
-- 'rate_limit'     : Rate limit hit (should retry with delay)
-- 'data_error'     : Bad input data (don't retry)
-- 'unknown'        : Unknown error type
```

Then in retry mode:

```r
# Only retry specific categories
if (retry_errors_only) {
  remaining <- dbGetQuery(conn, "
    SELECT s.* FROM source_narratives s
    INNER JOIN narrative_results r
      ON r.experiment_id = ? AND r.incident_id = s.incident_id
      AND r.narrative_type = s.narrative_type
    WHERE r.error_occurred = 1
      AND r.error_category IN ('api_error', 'rate_limit')
  ", params = list(exp_id))
}
```

**Severity**: LOW - Future enhancement
**Effort**: 1.0 day

---

### 15. Cleanup Utility Missing

**Problem**: Failed/abandoned experiments accumulate in database.

**Enhancement**: Add cleanup script:

```bash
# scripts/cleanup_experiments.sh
sqlite3 data/production_20k.db "
  SELECT experiment_id, experiment_name, status, start_time,
         (SELECT COUNT(*) FROM narrative_results WHERE experiment_id = e.experiment_id) as n_results
  FROM experiments e
  WHERE status IN ('running', 'failed')
    AND start_time < datetime('now', '-7 days')
  ORDER BY start_time DESC;
"

# Prompt user to delete abandoned experiments
```

**Severity**: LOW - Operational hygiene
**Effort**: 0.5 day

---

## Minor Issues / Suggestions

### 16. Log Markers for Resume Attempts

Current plan mentions "append mode" for logs but doesn't specify markers.

**Suggestion**:
```r
# In resume path:
cat("\n\n")
cat("========================================\n")
cat("RESUME ATTEMPT - ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("Experiment ID: ", experiment_id, "\n")
cat("Original start: ", exp$start_time, "\n")
cat("========================================\n\n")
```

---

### 17. Index on source_narratives

**Current schema**: Unique constraint on `(incident_id, narrative_type)` but no explicit index mentioned.

**Verify exists**:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS uq_source_narrative
  ON source_narratives(incident_id, narrative_type);
```

---

### 18. Resume Flag Validation

Plan uses environment variables but doesn't validate combinations:

```r
resume <- Sys.getenv("RESUME", "0") == "1"
exp_id <- Sys.getenv("EXPERIMENT_ID", "")
retry_errors <- Sys.getenv("RETRY_ERRORS_ONLY", "0") == "1"

# Add validation:
if (resume && exp_id == "") {
  stop("RESUME=1 requires EXPERIMENT_ID to be set")
}
if (retry_errors && !resume) {
  warning("RETRY_ERRORS_ONLY=1 has no effect without RESUME=1")
}
```

---

## Summary Table

| # | Issue | Severity | Effort | Category |
|---|-------|----------|--------|----------|
| 1 | Source data validation missing | HIGH | 0.5d | Data Integrity |
| 2 | Experiment status state machine | HIGH | 0.5d | State Management |
| 3 | Concurrent resume prevention | MEDIUM | 0.5d | Safety |
| 4 | Progress tracking missing | HIGH | 0.5d | UX |
| 5 | max_narratives interaction | MEDIUM | 0.25d | Logic |
| 6 | Incremental export handling | MEDIUM | 0.5d | Data Export |
| 7 | Error row handling strategy | MEDIUM | 0.5d | Error Handling |
| 8 | Seed handling on resume | LOW | 0.25d | Reproducibility |
| 9 | Transaction safety | MEDIUM | 0.25d | Data Integrity |
| 10 | Metrics finalization | ✅ OK | 0d | Validation |
| 11 | Backup strategy on resume | LOW | 0.1d | Safety |
| 12 | Remaining narratives not logged | LOW | 0.1d | UX |
| 13 | Discovery query status values | LOW | 0.1d | Documentation |
| 14 | Error categorization | LOW | 1.0d | Future |
| 15 | Cleanup utility | LOW | 0.5d | Operational |

**Total Effort (Critical + Important)**: ~4.0 days
**Total Effort (All issues)**: ~5.7 days

---

## Recommendations

### Phase 1: Must Fix Before Implementation (4 days)
- Issues #1-9 (critical + important)
- These address data integrity, safety, and usability

### Phase 2: After Initial Testing (1.5 days)
- Issues #11-15 (nice-to-have)
- Operational improvements based on real usage

### Phase 3: Future Enhancement (ongoing)
- Error categorization (#14)
- Advanced monitoring
- Multi-host distributed execution

---

## Verdict

**Overall Design**: ✅ Sound
**Implementation Readiness**: ⚠️ Needs work
**Risk Level**: MEDIUM with fixes, HIGH without

The core design (unique index + remaining-set query) is solid. Main gaps are around operational safety (concurrent runs, data validation) and user experience (progress tracking). With the fixes above, this would be production-ready.

**Recommended Action**: Address critical issues (#1-8) before starting implementation. Consider issues #9-13 based on timeline pressure.
