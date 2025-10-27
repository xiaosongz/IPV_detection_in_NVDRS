# Resumable Production Runs: Design and Implementation Plan v2

**Date**: 2025-10-27
**Version**: 2.0 (Revised after critical review)
**Owner**: Research/Engineering
**Scope**: Production runs of ~42k narratives (20,946 cases × 2) with safe break/resume
**Estimated Runtime**: ~75-100 hours at 6.5 sec/narrative

## Revision History

- **v1.0** (2025-10-27): Initial design
- **v2.0** (2025-10-27): Added data integrity checks, state management, progress tracking, concurrent execution prevention, and operational improvements based on critical review
- **v2.1** (2025-10-27): **CORRECTED** - Fixed critical implementation issues:
  - Fixed undefined config in resume path
  - Corrected call_llm() signature to match actual implementation
  - Added missing logger initialization
  - Fixed progress accounting to track global completion
  - Completed transaction handling pattern
  - Fixed checksum implementation (unname + count retrieval)
  - Added deduplication before unique index creation
  - Simplified column migration (removed SQLite 3.35+ dependency)
  - Reused n_narratives_processed (removed redundant column)
  - Updated runtime estimates to match smoke test results (6.5 sec/narrative)

## Goals

- Allow long-running production experiments (~75-100 hours at 6.5 sec/narrative) to pause/crash and resume without reprocessing completed narratives
- Support resuming with the same experiment_id (run_id) to keep results unified in a single experiment record
- Persist source narratives in the database once and read only from DB thereafter (no repeated Excel reads)
- **Ensure data integrity** through MD5 checksum validation and state management
- **Provide progress visibility** during multi-day runs with real-time ETA
- **Prevent concurrent execution** of the same resume operation via PID locks
- Keep implementation minimally invasive and backward compatible with existing experiments

## Non‑Goals

- Parallel/distributed execution across multiple hosts (future work)
- Full-blown job queue with locks and worker heartbeats (out of scope for this iteration)
- Real-time web dashboard for monitoring (future enhancement)

## Design Overview

Resuming will be driven by the experiment_id. The pipeline will:

1. **Ensure source data integrity**: Verify data file hasn't changed via checksum validation
2. **Manage experiment state**: Clear state machine with proper validation and transitions
3. **Prevent concurrent execution**: PID-based locking mechanism
4. **Load source data once**: Excel → `source_narratives` table with unique constraint
5. **Track progress continuously**: Database updates and log markers every 100 narratives
6. **Identify remaining work**: Left-join `source_narratives` with `narrative_results` to find unprocessed rows
7. **Process incrementally**: Handle only remaining narratives, append results
8. **Finalize atomically**: Recalculate metrics across all results upon completion
9. **Enforce idempotency**: Unique index on `(experiment_id, incident_id, narrative_type)`

## Architecture Changes

### 1. Data Integrity Layer (NEW)

**Problem**: Original plan didn't verify data file consistency across resume attempts.

**Solution**: Add checksum tracking to `source_narratives`:

```sql
-- Migration 1: Add checksum column
ALTER TABLE source_narratives ADD COLUMN data_checksum TEXT;

-- On initial load, calculate and store:
data_checksum = unname(tools::md5sum(data_file))  -- unname() for scalar comparison

-- On resume, verify:
SELECT DISTINCT data_checksum
FROM source_narratives
WHERE data_source = ?
LIMIT 1;

-- If mismatch, STOP with error
```

**Implementation**:
```r
# In R/data_loader.R: load_source_data()

# Calculate checksum (unname to get scalar string)
current_checksum <- unname(tools::md5sum(excel_path))

# Check if data already loaded
existing <- DBI::dbGetQuery(conn,
  "SELECT data_checksum FROM source_narratives WHERE data_source = ? LIMIT 1",
  params = list(excel_path)
)

if (nrow(existing) > 0) {
  if (existing$data_checksum != current_checksum) {
    stop(
      "Data file has changed since original load!\n",
      "  Original checksum: ", existing$data_checksum, "\n",
      "  Current checksum:  ", current_checksum, "\n",
      "Cannot safely resume. Please start a new experiment."
    )
  }

  # Get actual count (not nrow of LIMIT 1 query)
  n_narratives <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(excel_path)
  )$n

  message("Data file checksum verified: ", current_checksum)
  message("Already loaded: ", n_narratives, " narratives")
  return(n_narratives)
}

# Store checksum with data
# ... (existing load logic)
# Update INSERT to include data_checksum
```

### 2. State Management Layer (NEW)

**Problem**: Original plan had unclear experiment status transitions.

**Solution**: Define clear state machine with validation.

#### Experiment States

```
States:
  'running'    : Experiment is actively processing narratives
  'completed'  : All narratives processed successfully
  'failed'     : Experiment encountered unrecoverable error
  'cancelled'  : User-cancelled experiment (future)

State Transitions:
  start_experiment()         → 'running'
  finalize_experiment()      → 'completed'
  on_critical_error()        → 'failed'
  user_cancel()              → 'cancelled' (future)
  resume_experiment()        → 'running' (from 'running' or 'failed')

Resume Validation Rules:
  - CAN resume from:    'running', 'failed'
  - CANNOT resume from: 'completed' (all work done)
  - WARNING for:        'cancelled' (confirm with user)
```

**Implementation**:
```r
# New function: R/experiment_logger.R

#' Validate Experiment for Resume
#'
#' Checks if an experiment can be safely resumed
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID to resume
#' @return List with validation results (can_resume, reason, experiment_data)
validate_experiment_for_resume <- function(conn, experiment_id) {
  exp <- DBI::dbGetQuery(conn,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  if (nrow(exp) == 0) {
    return(list(
      can_resume = FALSE,
      reason = paste0("Experiment ID not found: ", experiment_id),
      experiment = NULL
    ))
  }

  exp <- exp[1, ]  # Get first row

  # Check status
  if (exp$status == "completed") {
    return(list(
      can_resume = FALSE,
      reason = paste0(
        "Experiment is already completed.\n",
        "  Experiment: ", exp$experiment_name, "\n",
        "  Completed: ", exp$end_time, "\n",
        "  Processed: ", exp$n_narratives_processed, " narratives\n",
        "Use a new experiment to reprocess."
      ),
      experiment = exp
    ))
  }

  if (exp$status == "cancelled") {
    message("WARNING: Resuming a cancelled experiment.")
    message("If this was intentional, continuing...")
  }

  # Validate has narratives to process
  n_completed <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM narrative_results WHERE experiment_id = ?",
    params = list(experiment_id)
  )$n

  if (exp$status == "running" || exp$status == "failed") {
    return(list(
      can_resume = TRUE,
      reason = NULL,
      experiment = exp,
      n_completed = n_completed
    ))
  }

  return(list(
    can_resume = FALSE,
    reason = paste0("Unknown experiment status: ", exp$status),
    experiment = exp
  ))
}

#' Update Experiment Status
#'
#' Sets experiment status with timestamp
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param status New status ('running', 'completed', 'failed', 'cancelled')
update_experiment_status <- function(conn, experiment_id, status) {
  valid_statuses <- c("running", "completed", "failed", "cancelled")
  if (!(status %in% valid_statuses)) {
    stop("Invalid status: ", status, ". Must be one of: ", paste(valid_statuses, collapse = ", "))
  }

  DBI::dbExecute(conn,
    "UPDATE experiments SET status = ? WHERE experiment_id = ?",
    params = list(status, experiment_id)
  )

  message("Experiment status updated: ", status)
}
```

### 3. Concurrent Execution Prevention (NEW)

**Problem**: Multiple processes could resume the same experiment simultaneously.

**Solution**: PID-based lock file mechanism.

**Implementation**:
```r
# New function: R/experiment_logger.R

#' Acquire Resume Lock
#'
#' Creates a PID lock file to prevent concurrent resume
#'
#' @param experiment_id Experiment ID
#' @return Lock file path (for cleanup)
acquire_resume_lock <- function(experiment_id) {
  lock_file <- file.path(here::here("data"), paste0(".resume_lock_", experiment_id, ".pid"))

  # Check if lock exists
  if (file.exists(lock_file)) {
    pid <- as.integer(readLines(lock_file, warn = FALSE)[1])

    # Check if process is still running (Unix-like systems)
    if (.Platform$OS.type == "unix") {
      process_exists <- system(paste0("kill -0 ", pid),
                               ignore.stdout = TRUE,
                               ignore.stderr = TRUE) == 0
    } else {
      # Windows: check task list
      process_exists <- system(paste0("tasklist /FI \"PID eq ", pid, "\" 2>NUL | find \"", pid, "\" >NUL"),
                              ignore.stdout = TRUE) == 0
    }

    if (process_exists) {
      stop(
        "Experiment ", experiment_id, " is already being resumed!\n",
        "  Lock held by PID: ", pid, "\n",
        "  Lock file: ", lock_file, "\n",
        "If this is a stale lock (process crashed), remove the lock file manually."
      )
    } else {
      message("Removing stale lock file from PID ", pid)
      file.remove(lock_file)
    }
  }

  # Create new lock
  writeLines(as.character(Sys.getpid()), lock_file)
  message("Acquired resume lock: ", lock_file)

  return(lock_file)
}

#' Release Resume Lock
#'
#' Removes PID lock file
#'
#' @param lock_file Path to lock file
release_resume_lock <- function(lock_file) {
  if (file.exists(lock_file)) {
    file.remove(lock_file)
    message("Released resume lock: ", lock_file)
  }
}
```

### 4. Progress Tracking Layer (NEW)

**Problem**: No visibility during 75-100 hour runs.

**Solution**: Multi-level progress tracking.

#### Database Schema Addition

```sql
-- Migration 2: Add progress tracking columns
-- Note: Reuse existing n_narratives_processed for in-progress updates
ALTER TABLE experiments ADD COLUMN last_progress_update TEXT;
ALTER TABLE experiments ADD COLUMN estimated_completion_time TEXT;
```

#### Implementation

```r
# New function: R/experiment_logger.R

#' Update Progress
#'
#' Updates experiment progress in database and logs
#'
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param n_completed Number of narratives completed so far (global count including previous runs)
#' @param n_total Total narratives to process in this experiment
#' @param start_time Start time of current session
update_progress <- function(conn, experiment_id, n_completed, n_total, start_time) {
  elapsed_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  rate <- if (elapsed_sec > 0) n_completed / elapsed_sec else 0
  remaining <- n_total - n_completed
  eta_sec <- if (rate > 0) remaining / rate else NA
  eta_time <- if (!is.na(eta_sec)) Sys.time() + eta_sec else NA

  # Update database (reuse n_narratives_processed for in-progress tracking)
  DBI::dbExecute(conn,
    "UPDATE experiments SET
      n_narratives_processed = ?,
      last_progress_update = ?,
      estimated_completion_time = ?
    WHERE experiment_id = ?",
    params = list(
      n_completed,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      if (!is.na(eta_time)) format(eta_time, "%Y-%m-%d %H:%M:%S") else NA_character_,
      experiment_id
    )
  )

  # Log progress
  pct_complete <- 100 * n_completed / n_total
  message(sprintf(
    "[PROGRESS] %d/%d (%.1f%%) | Rate: %.2f/sec | ETA: %s | Elapsed: %s",
    n_completed, n_total,
    pct_complete,
    rate,
    if (!is.na(eta_time)) format(eta_time, "%Y-%m-%d %H:%M:%S") else "calculating...",
    format_duration(elapsed_sec)
  ))
}

#' Format Duration
#'
#' Formats seconds into human-readable duration
#'
#' @param seconds Number of seconds
#' @return Character string like "2h 15m" or "45s"
format_duration <- function(seconds) {
  if (seconds < 60) {
    return(sprintf("%.0fs", seconds))
  } else if (seconds < 3600) {
    return(sprintf("%.0fm %.0fs", seconds %/% 60, seconds %% 60))
  } else {
    hours <- seconds %/% 3600
    minutes <- (seconds %% 3600) %/% 60
    return(sprintf("%.0fh %.0fm", hours, minutes))
  }
}
```

## Schema Changes

### Migration 1: Idempotency and Data Integrity

**IMPORTANT**: Run deduplication BEFORE creating unique index to avoid migration failure.

```sql
-- Step 1: Deduplicate existing data (keep highest result_id)
DELETE FROM narrative_results
WHERE result_id NOT IN (
  SELECT MAX(result_id)
  FROM narrative_results
  GROUP BY experiment_id, incident_id, narrative_type
);

-- Step 2: Create unique index (now safe)
CREATE UNIQUE INDEX IF NOT EXISTS uq_result_per_exp_narrative
  ON narrative_results(experiment_id, incident_id, narrative_type);

-- Step 3: Data integrity (checksum tracking)
-- Note: Use R migration script for column existence check
ALTER TABLE source_narratives ADD COLUMN data_checksum TEXT;

-- Step 4: Progress tracking
-- Note: Reuse existing n_narratives_processed, only add these:
ALTER TABLE experiments ADD COLUMN last_progress_update TEXT;
ALTER TABLE experiments ADD COLUMN estimated_completion_time TEXT;
```

### Migration 2: Enhanced Error Handling (Optional)

```sql
-- Retry attempt tracking
ALTER TABLE narrative_results ADD COLUMN attempt_count INTEGER DEFAULT 1;
ALTER TABLE narrative_results ADD COLUMN first_error_message TEXT;
ALTER TABLE narrative_results ADD COLUMN last_attempt_at TEXT;

-- Error categorization for intelligent retry
ALTER TABLE narrative_results ADD COLUMN error_category TEXT;
-- Categories: 'api_error', 'parse_error', 'rate_limit', 'data_error', 'unknown'
```

## Resume Logic

### Configuration Priority

When resuming, configuration is loaded from the **database**, not the YAML file. This ensures consistency even if the YAML has been modified.

```r
# Resume path priorities:
1. Experiment record in database (AUTHORITATIVE)
2. YAML file (IGNORED on resume, used only for validation/warning)

# What gets loaded from DB:
- experiment_id, experiment_name
- model_name, model_provider, temperature, api_url
- system_prompt, user_template, prompt_version
- run_seed, data_file, n_narratives_total
- All previous metrics and state
```

### Resume Workflow

```r
# scripts/run_experiment.R (resume path)

if (Sys.getenv("RESUME", "0") == "1") {
  exp_id <- Sys.getenv("EXPERIMENT_ID", "")

  # Validate environment
  if (exp_id == "") {
    stop("RESUME=1 requires EXPERIMENT_ID to be set")
  }

  retry_errors <- Sys.getenv("RETRY_ERRORS_ONLY", "0") == "1"
  if (retry_errors) {
    message("RETRY_ERRORS_ONLY=1 enabled - will reprocess error rows only")
  }

  # Load YAML config for validation/warnings only (DB values are authoritative)
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript run_experiment.R <config.yaml>")
  }

  yaml_config <- tryCatch(
    yaml::read_yaml(args[1]),
    error = function(e) {
      warning("Could not load YAML config: ", e$message, "\nProceeding with DB values only.")
      NULL
    }
  )

  # Database connection
  conn <- get_db_connection()
  on.exit(DBI::dbDisconnect(conn), add = TRUE)

  # === STEP 1: Validate experiment ===
  validation <- validate_experiment_for_resume(conn, exp_id)
  if (!validation$can_resume) {
    stop(validation$reason)
  }
  exp <- validation$experiment
  n_previously_completed <- validation$n_completed

  # === STEP 2: Acquire lock ===
  lock_file <- acquire_resume_lock(exp_id)
  on.exit(release_resume_lock(lock_file), add = TRUE)

  # === STEP 3: Verify data integrity ===
  data_file <- exp$data_file
  if (!file.exists(data_file)) {
    stop("Data file not found: ", data_file)
  }

  # This will validate checksum automatically
  load_source_data(conn, data_file, force_reload = FALSE)

  # === STEP 4: Set status to running ===
  update_experiment_status(conn, exp_id, "running")

  # === STEP 5: Log resume attempt ===
  log_file <- file.path(exp$log_dir, "resume_log.txt")
  cat("\n\n", file = log_file, append = TRUE)
  cat("========================================\n", file = log_file, append = TRUE)
  cat("RESUME ATTEMPT - ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", file = log_file, append = TRUE)
  cat("Experiment ID: ", exp_id, "\n", file = log_file, append = TRUE)
  cat("Original start: ", exp$start_time, "\n", file = log_file, append = TRUE)
  cat("Previously completed: ", n_previously_completed, " narratives\n", file = log_file, append = TRUE)
  cat("========================================\n\n", file = log_file, append = TRUE)

  # === STEP 6: Build remaining set ===
  if (!retry_errors) {
    # Missing narratives only
    remaining <- DBI::dbGetQuery(conn, "
      SELECT s.incident_id, s.narrative_type, s.narrative_text,
             s.manual_flag_ind, s.manual_flag
      FROM source_narratives s
      LEFT JOIN narrative_results r
        ON r.experiment_id = ?
       AND r.incident_id = s.incident_id
       AND r.narrative_type = s.narrative_type
      WHERE r.result_id IS NULL
        AND s.data_source = ?
      ORDER BY s.narrative_id
    ", params = list(exp_id, data_file))
  } else {
    # Error rows only
    remaining <- DBI::dbGetQuery(conn, "
      SELECT s.incident_id, s.narrative_type, s.narrative_text,
             s.manual_flag_ind, s.manual_flag
      FROM source_narratives s
      INNER JOIN narrative_results r
        ON r.experiment_id = ?
       AND r.incident_id = s.incident_id
       AND r.narrative_type = s.narrative_type
      WHERE r.error_occurred = 1
        AND s.data_source = ?
      ORDER BY s.narrative_id
    ", params = list(exp_id, data_file))
  }

  # === STEP 7: Report progress ===
  n_remaining <- nrow(remaining)
  n_total <- n_previously_completed + n_remaining

  message("========================================")
  message("RESUMING EXPERIMENT: ", exp$experiment_name)
  message("========================================")
  message("Experiment ID: ", exp_id)
  message("Original start: ", exp$start_time)
  message("Completed: ", n_previously_completed, " narratives")
  message("Remaining: ", n_remaining, " narratives")
  message("Total: ", n_total, " narratives")
  message("Progress: ", sprintf("%.1f%%", 100 * n_previously_completed / n_total))
  message("========================================")

  if (n_remaining == 0) {
    message("No narratives remaining. Finalizing experiment...")
    finalize_experiment(conn, exp_id)
    message("✓ Experiment already complete!")
    quit(status = 0)
  }

  # === STEP 8: Validate configuration consistency ===
  # Use DB values, warn if YAML differs
  if (!is.null(yaml_config) && !is.null(yaml_config$run$seed) &&
      yaml_config$run$seed != exp$run_seed) {
    warning(
      "YAML seed (", yaml_config$run$seed, ") differs from original (", exp$run_seed, ").\n",
      "Using original seed for reproducibility."
    )
  }
  set.seed(exp$run_seed)

  if (!is.null(yaml_config) && !is.null(yaml_config$run$max_narratives) &&
      yaml_config$run$max_narratives != exp$n_narratives_total) {
    warning(
      "YAML max_narratives (", yaml_config$run$max_narratives,
      ") differs from original (", exp$n_narratives_total, ").\n",
      "Using original limit for consistency."
    )
  }

  # === STEP 9: Create backup before resume ===
  db_path <- get_experiments_db_path()
  backup_file <- paste0(db_path, ".resume_backup_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  file.copy(db_path, backup_file)
  message("Created resume backup: ", backup_file)

  # === STEP 10: Initialize logger ===
  logger <- init_experiment_logger(
    experiment_id = exp_id,
    log_dir = exp$log_dir,  # Reuse existing log directory
    experiment_name = exp$experiment_name
  )

  # Log resume attempt
  logger$info("========================================")
  logger$info(paste("RESUMING EXPERIMENT:", exp$experiment_name))
  logger$info(paste("Experiment ID:", exp_id))
  logger$info(paste("Original start:", exp$start_time))
  logger$info(paste("Completed:", n_previously_completed, "narratives"))
  logger$info(paste("Remaining:", n_remaining, "narratives"))
  logger$info("========================================")

  # === STEP 11: Run benchmark on remaining set ===
  # Build config from DB record for consistency
  resume_config <- list(
    experiment = list(
      name = exp$experiment_name,
      author = exp$prompt_author
    ),
    model = list(
      name = exp$model_name,
      provider = exp$model_provider,
      temperature = exp$temperature,
      api_url = exp$api_url
    ),
    prompt = list(
      system_prompt = exp$system_prompt,
      user_template = exp$user_template,
      version = exp$prompt_version
    ),
    data = list(
      file = exp$data_file
    ),
    run = list(
      seed = exp$run_seed,
      max_narratives = exp$n_narratives_total,
      save_incremental = TRUE,
      save_csv_json = TRUE
    )
  )

  run_benchmark_core(
    config = resume_config,
    conn = conn,
    experiment_id = exp_id,
    narratives = remaining,
    logger = logger,  # Pass logger
    resume = TRUE,
    retry_errors_only = retry_errors,
    n_previously_completed = n_previously_completed
  )

  # === STEP 11: Finalize ===
  finalize_experiment(conn, exp_id)

  message("========================================")
  message("✓ Resume completed successfully!")
  message("========================================")

  quit(status = 0)
}
```

## Modified Functions

### R/run_benchmark_core.R

```r
#' Run Benchmark Core
#'
#' Processes narratives and logs results (supports resume)
#'
#' @param config Experiment configuration
#' @param conn Database connection
#' @param experiment_id Experiment ID
#' @param narratives Data frame of narratives to process
#' @param logger Logger object from init_experiment_logger
#' @param resume Logical, TRUE if resuming
#' @param retry_errors_only Logical, TRUE if retrying errors only
#' @param n_previously_completed Number already completed (for progress tracking)
run_benchmark_core <- function(config, conn, experiment_id, narratives, logger,
                               resume = FALSE, retry_errors_only = FALSE,
                               n_previously_completed = 0) {
  n_total <- nrow(narratives)
  n_total_experiment <- n_previously_completed + n_total  # Global total
  start_time <- Sys.time()

  # Progress tracking
  update_interval <- 100  # Update every 100 narratives

  # Transaction management with cleanup
  transaction_open <- FALSE

  on.exit({
    if (transaction_open) {
      # On error, rollback; on normal exit, commit
      if (!is.null(geterrmessage()) && geterrmessage() != "") {
        tryCatch(DBI::dbRollback(conn), error = function(e) NULL)
        logger$error("Transaction rolled back due to error")
      } else {
        tryCatch(DBI::dbCommit(conn), error = function(e) NULL)
        logger$info("Final transaction committed")
      }
    }
  }, add = TRUE)

  DBI::dbBegin(conn)
  transaction_open <- TRUE
  batch_size <- 0

  logger$info(paste("Starting processing of", n_total, "narratives"))

  for (i in seq_len(n_total)) {
    row <- narratives[i, ]

    # Build prompts using substitute_template
    system_prompt <- config$prompt$system_prompt
    user_prompt <- substitute_template(config$prompt$user_template, row$narrative_text)

    # Call LLM with timing
    result <- tryCatch({
      tictoc::tic()
      response <- call_llm(
        user_prompt = user_prompt,
        system_prompt = system_prompt,
        api_url = config$model$api_url,
        model = config$model$name,
        temperature = config$model$temperature
      )
      timing <- tictoc::toc(quiet = TRUE)
      response_sec <- as.numeric(timing$toc - timing$tic)

      # Parse response
      parsed <- parse_llm_result(response, narrative_id = row$incident_id)

      # Add metadata
      parsed$response_sec <- response_sec
      parsed$incident_id <- as.character(row$incident_id)
      parsed$narrative_type <- row$narrative_type
      parsed$narrative_text <- row$narrative_text
      parsed$manual_flag_ind <- row$manual_flag_ind
      parsed$manual_flag <- row$manual_flag
      parsed$row_num <- i

      logger$performance(row$incident_id, response_sec, "OK")
      logger$api_call(row$incident_id, response_sec, "SUCCESS")

      parsed
    }, error = function(e) {
      logger$error(paste("LLM call failed for", row$incident_id), e)
      logger$performance(row$incident_id, 0, "ERROR")

      # Return error result
      list(
        incident_id = as.character(row$incident_id),
        narrative_type = row$narrative_type,
        narrative_text = row$narrative_text,
        row_num = i,
        detected = NA,
        confidence = NA,
        error_occurred = TRUE,
        error_message = as.character(e$message),
        response_sec = NA,
        manual_flag_ind = row$manual_flag_ind,
        manual_flag = row$manual_flag
      )
    })

    # Log result (with idempotency handling)
    if (retry_errors_only) {
      # Preserve first error message if not saved
      DBI::dbExecute(conn,
        "UPDATE narrative_results
         SET first_error_message = error_message
         WHERE experiment_id = ? AND incident_id = ? AND narrative_type = ?
           AND first_error_message IS NULL AND error_occurred = 1",
        params = list(experiment_id, row$incident_id, row$narrative_type)
      )

      # Delete error row before reinserting
      DBI::dbExecute(conn,
        "DELETE FROM narrative_results
         WHERE experiment_id = ? AND incident_id = ? AND narrative_type = ?",
        params = list(experiment_id, row$incident_id, row$narrative_type)
      )
    }

    # Try to insert, skip if exists (idempotency via unique index)
    tryCatch({
      log_narrative_result(conn, experiment_id, result)
    }, error = function(e) {
      if (grepl("UNIQUE constraint", e$message)) {
        logger$warn(paste("Skipping duplicate:", row$incident_id, row$narrative_type))
      } else {
        stop(e)
      }
    })

    batch_size <- batch_size + 1

    # Commit and update progress every 100 narratives
    if (batch_size >= update_interval) {
      DBI::dbCommit(conn)
      transaction_open <- FALSE

      # Update progress with GLOBAL count
      n_global_completed <- n_previously_completed + i
      update_progress(conn, experiment_id, n_global_completed,
                     n_total_experiment, start_time)

      DBI::dbBegin(conn)
      transaction_open <- TRUE
      batch_size <- 0
    }
  }

  # Commit remaining
  if (batch_size > 0) {
    DBI::dbCommit(conn)
    transaction_open <- FALSE
  }

  # Final progress update
  n_final_completed <- n_previously_completed + n_total
  update_progress(conn, experiment_id, n_final_completed,
                 n_total_experiment, start_time)

  logger$info(paste("✓ Processed", n_total, "narratives"))
}

#' Substitute Template
#'
#' Replaces <<TEXT>> placeholder with actual narrative text
#'
#' @param template Template string with <<TEXT>> placeholder
#' @param text Narrative text to substitute
#' @return String with text substituted
substitute_template <- function(template, text) {
  gsub("<<TEXT>>", text, template, fixed = TRUE)
}
```

### R/data_loader.R

Add checksum validation to existing `load_source_data()`:

```r
load_source_data <- function(conn, excel_path, force_reload = FALSE) {
  if (!file.exists(excel_path)) {
    stop("Data file not found: ", excel_path)
  }

  # Calculate checksum
  current_checksum <- as.character(tools::md5sum(excel_path))

  # Check if already loaded
  existing <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n, data_checksum FROM source_narratives
     WHERE data_source = ? GROUP BY data_checksum",
    params = list(excel_path)
  )

  if (nrow(existing) > 0 && !force_reload) {
    # Verify checksum matches
    if (existing$data_checksum != current_checksum) {
      stop(
        "Data file has changed since original load!\n",
        "  File: ", excel_path, "\n",
        "  Original checksum: ", existing$data_checksum, "\n",
        "  Current checksum:  ", current_checksum, "\n",
        "Cannot safely resume. Please start a new experiment."
      )
    }

    cat("Data already loaded and verified:", excel_path, "(", existing$n, "narratives)\n")
    cat("Checksum verified:", current_checksum, "\n")
    return(existing$n)
  }

  # ... existing load logic ...

  # When inserting, include checksum
  data_long$data_checksum <- current_checksum

  # ... rest of function ...
}
```

## CLI/Config Interface

### Environment Variables

```bash
# Resume mode
RESUME=1                          # Enable resume mode
EXPERIMENT_ID=<uuid>              # Target experiment to resume (required)
RETRY_ERRORS_ONLY=1               # Reprocess only error rows (optional)

# Example usage:
RESUME=1 EXPERIMENT_ID=abc-123-def Rscript scripts/run_experiment.R config.yaml
```

### Shell Script Helper

```bash
# scripts/resume_experiment.sh
#!/bin/bash

# Helper to resume the latest incomplete experiment

DB_FILE=${1:-"data/production_20k.db"}

# Find latest incomplete experiment
EXPERIMENT_ID=$(sqlite3 "$DB_FILE" "
  SELECT experiment_id FROM experiments
  WHERE status IN ('running', 'failed')
  ORDER BY start_time DESC
  LIMIT 1;
")

if [ -z "$EXPERIMENT_ID" ]; then
  echo "No incomplete experiments found in $DB_FILE"
  exit 1
fi

# Get experiment info
sqlite3 "$DB_FILE" "
  SELECT
    'Experiment: ' || experiment_name,
    'Status: ' || status,
    'Started: ' || start_time,
    'Completed: ' || COALESCE(n_narratives_completed, 0) || '/' || COALESCE(n_narratives_total, 0)
  FROM experiments
  WHERE experiment_id = '$EXPERIMENT_ID';
"

read -p "Resume this experiment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 0
fi

# Set production DB config
if [ -f ".db_config.production" ]; then
  cp .db_config.production .db_config
  echo "Using production database configuration"
fi

# Resume
CONFIG_FILE=${2:-"configs/experiments/exp_100_production_20k_indicators_t02_high.yaml"}

echo "Resuming experiment: $EXPERIMENT_ID"
RESUME=1 EXPERIMENT_ID="$EXPERIMENT_ID" Rscript scripts/run_experiment.R "$CONFIG_FILE"
```

## Monitoring During Execution

### Real-time Progress

```bash
# Terminal 1: Run production
./scripts/run_production_20k.sh

# Terminal 2: Monitor progress

# Option 1: Install watch (if Homebrew available)
brew install watch
watch -n 60 'sqlite3 data/production_20k.db "..."'

# Option 2: Use while loop (works on all systems, including macOS)
while true; do
  clear
  sqlite3 data/production_20k.db "
    SELECT
      experiment_name,
      status,
      n_narratives_processed || '/' || n_narratives_total as progress,
      ROUND(100.0 * n_narratives_processed / n_narratives_total, 1) || '%' as pct_done,
      estimated_completion_time as eta,
      last_progress_update
    FROM experiments
    WHERE status = 'running'
    ORDER BY start_time DESC
    LIMIT 1;
  "
  sleep 60
done

# Option 3: One-shot check (no loop)
sqlite3 data/production_20k.db "SELECT ..."
```

### Error Monitoring

```bash
# Check error rate during run
sqlite3 data/production_20k.db "
  SELECT
    e.experiment_name,
    COUNT(*) as total_processed,
    SUM(r.error_occurred) as errors,
    ROUND(100.0 * SUM(r.error_occurred) / COUNT(*), 2) as error_rate_pct,
    AVG(r.response_sec) as avg_response_sec
  FROM experiments e
  JOIN narrative_results r ON r.experiment_id = e.experiment_id
  WHERE e.status = 'running'
  GROUP BY e.experiment_id;
"
```

## Testing Strategy

### Test 1: Basic Resume Flow

```bash
# 1. Start experiment with 500 narratives, kill after 250
Rscript scripts/run_experiment.R configs/experiments/exp_101_production_smoke_test.yaml &
PID=$!
sleep 120  # Let it process ~250 narratives
kill $PID

# 2. Verify partial results
sqlite3 data/production_20k.db "
  SELECT COUNT(*) FROM narrative_results WHERE experiment_id = '<id>';
"  # Should show ~250

# 3. Resume
RESUME=1 EXPERIMENT_ID="<id>" Rscript scripts/run_experiment.R configs/experiments/exp_101_production_smoke_test.yaml

# 4. Verify completion
sqlite3 data/production_20k.db "
  SELECT status, n_narratives_processed FROM experiments WHERE experiment_id = '<id>';
"  # Should show 'completed', 500
```

### Test 2: Data Integrity Validation

```bash
# 1. Complete partial run
# ... (as above)

# 2. Modify data file (simulate data change)
echo "modified" >> data-raw/all_suicide_nar.xlsx

# 3. Attempt resume - should FAIL with checksum error
RESUME=1 EXPERIMENT_ID="<id>" Rscript scripts/run_experiment.R config.yaml
# Expected: Error about checksum mismatch
```

### Test 3: Idempotency Test

```bash
# 1. Complete full run
Rscript scripts/run_experiment.R config.yaml

# 2. Attempt to resume completed experiment - should STOP
RESUME=1 EXPERIMENT_ID="<id>" Rscript scripts/run_experiment.R config.yaml
# Expected: Error "Cannot resume completed experiment"
```

### Test 4: Error Retry

```bash
# 1. Inject errors manually
sqlite3 data/production_20k.db "
  UPDATE narrative_results
  SET error_occurred = 1, error_message = 'Simulated error'
  WHERE experiment_id = '<id>'
  LIMIT 10;
"

# 2. Set status to 'failed'
sqlite3 data/production_20k.db "
  UPDATE experiments SET status = 'failed' WHERE experiment_id = '<id>';
"

# 3. Resume with error retry only
RESUME=1 EXPERIMENT_ID="<id>" RETRY_ERRORS_ONLY=1 Rscript scripts/run_experiment.R config.yaml

# 4. Verify errors cleared
sqlite3 data/production_20k.db "
  SELECT COUNT(*) FROM narrative_results
  WHERE experiment_id = '<id>' AND error_occurred = 1;
"  # Should be 0
```

### Test 5: Progress Tracking

```bash
# 1. Start long run
./scripts/run_production_20k.sh &

# 2. Monitor progress in another terminal
watch -n 30 'sqlite3 data/production_20k.db "
  SELECT n_narratives_completed, n_narratives_total,
         estimated_completion_time, last_progress_update
  FROM experiments WHERE status = \"running\";
"'

# 3. Verify progress updates every 100 narratives
```

### Test 6: Concurrent Execution Prevention

```bash
# 1. Start resume
RESUME=1 EXPERIMENT_ID="<id>" Rscript scripts/run_experiment.R config.yaml &

# 2. Immediately try to resume again in another terminal
RESUME=1 EXPERIMENT_ID="<id>" Rscript scripts/run_experiment.R config.yaml
# Expected: Error "already being resumed by PID <pid>"
```

## Migration Steps

### Step 1: Database Migration

**Use R migration script** for proper error handling and column existence checks:

```r
# scripts/migrate_resumable_v2.R

library(DBI)
library(RSQLite)

message("========================================")
message("Resumable Runs v2 Migration")
message("========================================\n")

# Helper function
column_exists <- function(conn, table, column) {
  column %in% DBI::dbListFields(conn, table)
}

# Connect to database
db_path <- "data/production_20k.db"
if (!file.exists(db_path)) {
  stop("Database not found: ", db_path)
}

conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(conn), add = TRUE)

# === STEP 1: Deduplicate narrative_results ===
message("Checking for duplicate narrative results...")
dupes <- DBI::dbGetQuery(conn, "
  SELECT experiment_id, incident_id, narrative_type, COUNT(*) as c
  FROM narrative_results
  GROUP BY experiment_id, incident_id, narrative_type
  HAVING c > 1
")

if (nrow(dupes) > 0) {
  message("Found ", nrow(dupes), " duplicates. Deduplicating...")
  DBI::dbExecute(conn, "
    DELETE FROM narrative_results
    WHERE result_id NOT IN (
      SELECT MAX(result_id)
      FROM narrative_results
      GROUP BY experiment_id, incident_id, narrative_type
    )
  ")
  message("✓ Duplicates removed")
} else {
  message("✓ No duplicates found")
}

# === STEP 2: Create unique index ===
message("\nCreating unique index...")
DBI::dbExecute(conn, "
  CREATE UNIQUE INDEX IF NOT EXISTS uq_result_per_exp_narrative
  ON narrative_results(experiment_id, incident_id, narrative_type)
")
message("✓ Unique index created")

# === STEP 3: Add checksum column ===
message("\nAdding data integrity columns...")
if (!column_exists(conn, "source_narratives", "data_checksum")) {
  DBI::dbExecute(conn, "ALTER TABLE source_narratives ADD COLUMN data_checksum TEXT")
  message("✓ Added data_checksum to source_narratives")
} else {
  message("  data_checksum already exists")
}

# === STEP 4: Add progress tracking columns ===
message("\nAdding progress tracking columns...")
if (!column_exists(conn, "experiments", "last_progress_update")) {
  DBI::dbExecute(conn, "ALTER TABLE experiments ADD COLUMN last_progress_update TEXT")
  message("✓ Added last_progress_update")
} else {
  message("  last_progress_update already exists")
}

if (!column_exists(conn, "experiments", "estimated_completion_time")) {
  DBI::dbExecute(conn, "ALTER TABLE experiments ADD COLUMN estimated_completion_time TEXT")
  message("✓ Added estimated_completion_time")
} else {
  message("  estimated_completion_time already exists")
}

# === STEP 5: Add error tracking columns (optional) ===
message("\nAdding enhanced error tracking columns...")
if (!column_exists(conn, "narrative_results", "attempt_count")) {
  DBI::dbExecute(conn, "ALTER TABLE narrative_results ADD COLUMN attempt_count INTEGER DEFAULT 1")
  message("✓ Added attempt_count")
} else {
  message("  attempt_count already exists")
}

if (!column_exists(conn, "narrative_results", "first_error_message")) {
  DBI::dbExecute(conn, "ALTER TABLE narrative_results ADD COLUMN first_error_message TEXT")
  message("✓ Added first_error_message")
} else {
  message("  first_error_message already exists")
}

if (!column_exists(conn, "narrative_results", "last_attempt_at")) {
  DBI::dbExecute(conn, "ALTER TABLE narrative_results ADD COLUMN last_attempt_at TEXT")
  message("✓ Added last_attempt_at")
} else {
  message("  last_attempt_at already exists")
}

if (!column_exists(conn, "narrative_results", "error_category")) {
  DBI::dbExecute(conn, "ALTER TABLE narrative_results ADD COLUMN error_category TEXT")
  message("✓ Added error_category")
} else {
  message("  error_category already exists")
}

message("\n========================================")
message("✓ Migration completed successfully!")
message("========================================\n")

# Show summary
message("Database schema updated:")
message("  - Unique index on (experiment_id, incident_id, narrative_type)")
message("  - Checksum tracking for data integrity")
message("  - Progress tracking columns")
message("  - Enhanced error tracking")
message("\nYou can now use resumable runs.")
```

**To run migration**:
```bash
Rscript scripts/migrate_resumable_v2.R
```

### Step 2: Code Updates

Order of implementation:

1. **R/experiment_logger.R**: Add new functions
   - `validate_experiment_for_resume()`
   - `update_experiment_status()`
   - `acquire_resume_lock()`
   - `release_resume_lock()`
   - `update_progress()`
   - `format_duration()`

2. **R/data_loader.R**: Add checksum validation
   - Modify `load_source_data()` to calculate and verify checksums

3. **R/run_benchmark_core.R**: Add resume support
   - Add `resume`, `retry_errors_only`, `n_previously_completed` parameters
   - Add progress tracking calls
   - Add transaction batching

4. **scripts/run_experiment.R**: Add resume path
   - Parse RESUME/EXPERIMENT_ID/RETRY_ERRORS_ONLY env vars
   - Implement resume workflow
   - Add validation and error handling

5. **scripts/resume_experiment.sh**: Create helper script

6. **Update production script**: `scripts/run_production_20k.sh`
   - Add resume mode support
   - Add progress monitoring instructions

### Step 3: Testing

1. Run Test Suite 1-6 (as defined above)
2. Fix any issues found
3. Document any edge cases discovered

### Step 4: Documentation

1. Update README with resume instructions
2. Add troubleshooting section
3. Document monitoring commands

## Rollback Plan

If resumable runs cause issues:

```bash
# 1. Revert to previous code
git checkout HEAD~1 R/experiment_logger.R R/run_benchmark_core.R scripts/run_experiment.R

# 2. Database is still compatible (new columns optional)
# 3. Can still run experiments normally without resume flag
```

## Timeline (Updated)

- **Phase 1: Core Implementation** (3 days)
  - Day 1: Database migrations + data integrity layer
  - Day 2: State management + progress tracking
  - Day 3: Resume logic in orchestration layer

- **Phase 2: Safety & Monitoring** (1.5 days)
  - Day 1 AM: Concurrent execution prevention
  - Day 1 PM: Shell scripts and helpers
  - Day 2: Testing (all 6 test scenarios)

- **Phase 3: Documentation & Validation** (0.5 day)
  - Documentation updates
  - Final validation on test dataset

**Total: ~5 days** (vs 2-2.5 days in original plan, but with much better safety and usability)

## Success Criteria

1. ✅ Can resume experiment after crash/kill
2. ✅ No duplicate results due to idempotency constraint
3. ✅ Data integrity verified via checksums
4. ✅ Progress visible during long runs
5. ✅ Concurrent execution prevented
6. ✅ Error retries work correctly
7. ✅ Metrics recalculated correctly across all results
8. ✅ Backward compatible (non-resume mode unchanged)
9. ✅ All 6 test scenarios pass

## Future Enhancements

1. **Multi-host distributed execution**
   - Job queue system
   - Worker heartbeats
   - Centralized coordinator

2. **Advanced error handling**
   - Automatic categorization of errors
   - Intelligent retry with exponential backoff
   - Error pattern detection and alerting

3. **Web dashboard**
   - Real-time progress visualization
   - Error monitoring
   - Historical run comparison

4. **Checkpointing**
   - Snapshot experiments at intervals
   - Quick rollback to checkpoints
   - Checkpoint comparison tools

---

**Status**: Ready for implementation
**Risk Level**: LOW (with v2 improvements)
**Complexity**: MEDIUM
**Value**: HIGH (enables reliable 75-100 hour production runs)
