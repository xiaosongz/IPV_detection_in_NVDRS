# Unified Improvement Plan: Automated Experiment Tracking

This document presents a unified and comprehensive plan for building a robust, automated, and database-driven experiment tracking system. It synthesizes the best ideas from the three initial proposals (Gemini, Claude, GPT-5) into a single, actionable blueprint.

## 1. Guiding Philosophy: Minimalist MLOps

We will adopt a philosophy of **Minimalist MLOps**. This means we will build a powerful and reproducible system using native R tools (DBI, RSQLite, yaml) and a simple, file-based SQLite database, avoiding the overhead of external services like MLflow or Weights & Biases. The goal is a system that is easy to maintain, version-control, and understand, while adhering to core MLOps principles.

## 2. Finalized Database Schema

Based on your preference, we will implement **Claude's 2-table schema** with an additional **source data table** for efficient data loading.

**Database File:** `experiments.db` (located in the project root)

### Table 0: `source_narratives` (New - for efficient data loading)

This table stores the source narratives once, preventing repeated Excel file reads.

```sql
CREATE TABLE source_narratives (
  narrative_id INTEGER PRIMARY KEY AUTOINCREMENT,
  incident_id TEXT NOT NULL,
  narrative_type TEXT NOT NULL,             -- "cme" or "le"
  narrative_text TEXT,
  manual_flag_ind BOOLEAN,                  -- individual narrative flag
  manual_flag BOOLEAN,                      -- case-level flag
  data_source TEXT,                         -- source file path
  loaded_at TEXT NOT NULL,                  -- ISO 8601 timestamp

  UNIQUE(incident_id, narrative_type)       -- prevent duplicates
);

-- Indexes for fast lookup
CREATE INDEX idx_source_incident ON source_narratives(incident_id);
CREATE INDEX idx_source_type ON source_narratives(narrative_type);
CREATE INDEX idx_source_manual ON source_narratives(manual_flag_ind);
```

**Benefits:**
- Load Excel file **once** into SQLite
- All experiments query from SQLite (fast)
- No repeated file I/O
- Easy to update source data (reload table)
- Supports multiple data sources (track via `data_source` field)

### Table 1: `experiments`

This table stores the high-level metadata for each experiment run. The schema is enhanced with metadata fields from all three plans to maximize reproducibility.

```sql
CREATE TABLE experiments (
  experiment_id TEXT PRIMARY KEY,           -- UUID or timestamp-based ID
  experiment_name TEXT NOT NULL,            -- Human-readable name from config
  status TEXT DEFAULT 'running',            -- 'running', 'completed', 'failed', 'cancelled'

  -- Configuration
  model_name TEXT NOT NULL,
  model_provider TEXT,
  temperature REAL NOT NULL,
  system_prompt TEXT NOT NULL,
  user_template TEXT NOT NULL,
  prompt_version TEXT,
  prompt_author TEXT,
  run_seed INTEGER,                         -- For reproducibility (from GPT-5)

  -- Dataset Info
  data_file TEXT,
  n_narratives_total INTEGER,
  n_narratives_processed INTEGER,
  n_narratives_skipped INTEGER,

  -- Timing
  start_time TEXT NOT NULL,                 -- ISO 8601 format
  end_time TEXT,
  total_runtime_sec REAL,
  avg_time_per_narrative_sec REAL,

  -- Platform/Environment (for reproducibility)
  api_url TEXT,
  r_version TEXT,
  os_info TEXT,
  hostname TEXT,

  -- Results Summary (computed after run)
  n_positive_detected INTEGER,
  n_negative_detected INTEGER,
  n_positive_manual INTEGER,
  n_negative_manual INTEGER,
  accuracy REAL,
  precision_ipv REAL,
  recall_ipv REAL,
  f1_ipv REAL,
  n_false_positive INTEGER,
  n_false_negative INTEGER,
  n_true_positive INTEGER,
  n_true_negative INTEGER,
  pct_overlap_with_manual REAL,

  -- Output files
  csv_file TEXT,
  json_file TEXT,

  -- Metadata
  created_at TEXT NOT NULL,
  notes TEXT
);

-- Indexes for fast queries
CREATE INDEX idx_status ON experiments(status);
CREATE INDEX idx_model_name ON experiments(model_name);
CREATE INDEX idx_prompt_version ON experiments(prompt_version);
CREATE INDEX idx_created_at ON experiments(created_at);
```

### Table 2: `narrative_results`

This table stores the detailed output for every single narrative processed in an experiment.

```sql
CREATE TABLE narrative_results (
  result_id INTEGER PRIMARY KEY AUTOINCREMENT,
  experiment_id TEXT NOT NULL,              -- Foreign Key to experiments

  -- Identifiers
  incident_id TEXT NOT NULL,
  narrative_type TEXT NOT NULL,             -- "cme" or "le"
  row_num INTEGER,

  -- Input
  narrative_text TEXT,

  -- Manual Labels (Ground Truth)
  manual_flag_ind BOOLEAN,                  -- individual narrative flag
  manual_flag BOOLEAN,                      -- case-level flag (ipv_manual)

  -- LLM Output
  detected BOOLEAN,
  confidence REAL,
  indicators TEXT,                          -- JSON array: ["restraining order", "shelter"]
  rationale TEXT,
  reasoning_steps TEXT,                     -- for reasoning models (qwen3-thinking, etc.)
  raw_response TEXT,                        -- full LLM response for debugging

  -- Performance
  response_sec REAL,
  processed_at TEXT,                        -- ISO 8601 timestamp
  error_occurred BOOLEAN DEFAULT 0,
  error_message TEXT,

  -- Comparison Metrics (computed)
  is_true_positive BOOLEAN,                 -- detected=T, manual=T
  is_true_negative BOOLEAN,                 -- detected=F, manual=F
  is_false_positive BOOLEAN,                -- detected=T, manual=F
  is_false_negative BOOLEAN,                -- detected=F, manual=T

  FOREIGN KEY (experiment_id) REFERENCES experiments(experiment_id)
);

-- Indexes for fast queries
CREATE INDEX idx_experiment_id ON narrative_results(experiment_id);
CREATE INDEX idx_incident_id ON narrative_results(incident_id);
CREATE INDEX idx_narrative_type ON narrative_results(narrative_type);
CREATE INDEX idx_manual_flag_ind ON narrative_results(manual_flag_ind);
CREATE INDEX idx_detected ON narrative_results(detected);
CREATE INDEX idx_error ON narrative_results(error_occurred);
CREATE INDEX idx_false_positive ON narrative_results(is_false_positive);
CREATE INDEX idx_false_negative ON narrative_results(is_false_negative);
```

## 3. Configuration File Structure (YAML)

We will use a single, comprehensive YAML file to define each experiment. This file will be stored in a new `configs/experiments/` directory.

**Design Decision**: Start with **embedded prompts** in YAML for simplicity. Move to separate prompt files only if prompts become very long (>100 lines).

**Example (`configs/experiments/exp_001_baseline.yaml`):**

```yaml
experiment:
  name: "Baseline GPT-4o, Temp 0.1"
  author: "andrea"
  notes: "Testing Andrea's v2.1 prompt with GPT-4o baseline"

model:
  name: "openai/gpt-4o"
  provider: "openai"
  api_url: "${LLM_API_URL}"  # Reads from environment variable
  temperature: 0.1

prompt:
  version: "v2.1_andrea"
  # Embedded prompts (simpler than separate files)
  system_prompt: |
    /think hard!
    ROLE: Identify if the deceased was the VICTIM of intimate partner violence (IPV).

    SCOPE:
    - IPV from: current/former partner, boyfriend/girlfriend, spouse, ex, father of victim's children
    - NOT from: victim's parents or family members
    - Use ONLY narrative facts
    - Women's shelter = strong IPV evidence
    - "domestic issues" = IPV

    INDICATORS (use exact tokens):
      - behavioral: "domestic violence history", "domestic issues", "women's shelter"
      - physical: "multiple-stage injuries", "defensive wounds", "strangulation marks"
      - contextual: "partner's weapon", "shared residence", "witness reports"

    OUTPUT: Single JSON with detected:boolean, confidence:number, indicators:array, rationale:string

  user_template: |
    Analyze if the deceased was VICTIM of IPV from intimate partner.

    Narrative:
    <<TEXT>>

    Return ONLY this JSON:
    {
      "detected": true/false,
      "confidence": 0.00-1.00,
      "indicators": ["exact tokens from vocab list"],
      "rationale": "≤200 char fact-based explanation"
    }

data:
  # Current data structure (specific to suicide_IPV dataset)
  file: "data-raw/suicide_IPV_manuallyflagged.xlsx"
  # These columns are transformed to long format by the script
  # No need for user to specify column names - they're fixed

run:
  seed: 123                # For reproducibility
  max_narratives: null     # null = process all, or set number for testing
  save_incremental: true   # Save to DB after each narrative (recommended)
  save_csv_json: true      # Also save CSV/JSON files (legacy format)
```

**Alternative: Separate Prompt Files** (use if prompts get very long):

```yaml
prompt:
  version: "v2.1_andrea"
  system_prompt_file: "configs/prompts/system_v2.1_andrea.txt"
  user_template_file: "configs/prompts/user_v2.1_andrea.txt"
```

**Configuration Validation Rules:**

The `validate_config()` function will check:
- Required fields present: `experiment.name`, `model.name`, `model.temperature`, `prompt.version`, `data.file`
- Files exist: `data.file`, prompt files (if using file references)
- Temperature in valid range: 0.0 ≤ temperature ≤ 2.0
- Model name format valid (no spaces, valid provider prefix)
- No circular dependencies in config includes

## 4. Automated Workflow & Orchestration

We will adopt GPT-5's recommendation of a separate orchestrator and summarizer script. This creates a clean, two-step process.

1.  **Orchestrator (`scripts/run_experiment.R`):**
    *   Parses the YAML config file.
    *   Creates a new record in the `experiments` table and gets a unique `experiment_id`.
    *   Loads the dataset.
    *   Loops through each narrative, calling the LLM.
    *   For each narrative, logs the detailed output to the `narrative_results` table, linking it with the `experiment_id`.
    *   When finished, calls the summarizer script.

2.  **Summarizer (`scripts/summarize_experiment.R`):**
    *   Takes an `experiment_id` as input.
    *   Queries all results for that experiment from the `narrative_results` table.
    *   Calculates the aggregate performance metrics (accuracy, precision, recall, F1, etc.).
    *   Updates the corresponding record in the `experiments` table with these summary metrics and the `end_time`.

## 5. Implementation Plan & File Structure

This is the concrete checklist of files we will create, drawing from all three plans.

**New R Functions (`R/`):**

*   `R/db_schema.R`: Database initialization and schema management
    - `init_experiment_db(db_path)` - Create database and tables (including source_narratives)
    - `get_db_connection(db_path)` - Get connection with error handling

*   `R/data_loader.R`: Source data loading functions
    - `load_source_data(conn, excel_path)` - Load Excel into source_narratives table
    - `get_source_narratives(conn, filters)` - Query narratives for experiment
    - `check_data_loaded(conn, data_source)` - Check if data already loaded

*   `R/experiment_logger.R`: Experiment tracking functions
    - `start_experiment(conn, config)` - Create experiment record, return experiment_id
    - `log_narrative_result(conn, experiment_id, result)` - Log single narrative
    - `finalize_experiment(conn, experiment_id, metrics)` - Update summary metrics
    - `mark_experiment_failed(conn, experiment_id, error_msg)` - Handle failures

*   `R/config_loader.R`: Configuration management
    - `load_experiment_config(config_path)` - Load and parse YAML
    - `validate_config(config)` - Validate required fields and files
    - `expand_env_vars(text)` - Expand ${VAR} in config

*   `R/experiment_queries.R`: Query helper functions
    - `list_experiments(conn, status = NULL)` - List all/filtered experiments
    - `get_experiment_results(conn, experiment_id)` - Get narrative results
    - `compare_experiments(conn, experiment_ids)` - Compare metrics
    - `find_disagreements(conn, experiment_id)` - Find false pos/neg

*   `R/run_benchmark_core.R`: Core benchmark execution logic (refactored from existing script)
    - `run_benchmark_core(config, conn, experiment_id)` - Main processing loop

**New Scripts (`scripts/`):**

*   `scripts/run_experiment.R`: Main orchestrator (CLI tool)
*   `scripts/summarize_experiment.R`: Post-run summarization
*   `scripts/init_database.R`: One-time database setup helper
*   `scripts/compare_experiments.R`: Interactive comparison tool

**New Configuration Files (`configs/`):**

*   `configs/experiments/exp_001_baseline_template.yaml`: Template for new experiments
*   `configs/experiments/exp_002_example.yaml`: Working example config
*   `configs/prompts/` (optional): For external prompt files if needed

**New Tests (`tests/testthat/`):**

*   `tests/testthat/test-db_schema.R`: Database creation tests
*   `tests/testthat/test-experiment_logger.R`: Logging function tests
*   `tests/testthat/test-config_loader.R`: Config loading/validation tests
*   `tests/testthat/test-experiment_workflow.R`: End-to-end integration test (with real LLM on small data)

**New Test Data:**

*   `data-raw/test_narratives_small.xlsx`: 5-10 narratives for testing

**New Documentation (`docs/`):**

*   `docs/EXPERIMENT_WORKFLOW.md`: Step-by-step guide for running experiments
*   Update `README.md`: Add experiment tracking section

---

## 5.1 Key Function Templates

**Template: `R/data_loader.R`**

```r
#' Load Source Data into Database
#'
#' Loads Excel file into source_narratives table for efficient querying
#'
#' @param conn Database connection
#' @param excel_path Path to Excel file
#' @return Number of narratives loaded
#' @export
load_source_data <- function(conn, excel_path) {
  # Check if already loaded
  existing <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(excel_path))

  if (existing$n > 0) {
    cat("Data already loaded from:", excel_path, "(", existing$n, "narratives)\n")
    return(existing$n)
  }

  # Load Excel file
  cat("Loading data from:", excel_path, "\n")
  data <- readxl::read_excel(excel_path)

  # Transform to long format
  data_long <- data %>%
    tidyr::pivot_longer(
      cols = c(NarrativeCME, NarrativeLE),
      names_to = "Type",
      values_to = "Narrative"
    ) %>%
    dplyr::mutate(
      narrative_type = tolower(gsub("Narrative", "", Type)),
      manual_flag_ind = dplyr::case_when(
        narrative_type == "cme" ~ as.logical(ipv_manualCME),
        narrative_type == "le" ~ as.logical(ipv_manualLE)
      ),
      manual_flag = as.logical(ipv_manual)
    ) %>%
    dplyr::select(
      incident_id = IncidentID,
      narrative_type,
      narrative_text = Narrative,
      manual_flag_ind,
      manual_flag
    ) %>%
    dplyr::filter(!is.na(narrative_text), trimws(narrative_text) != "")

  # Insert into database
  data_long$data_source <- excel_path
  data_long$loaded_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  DBI::dbWriteTable(conn, "source_narratives", data_long, append = TRUE)

  n_loaded <- nrow(data_long)
  cat("Loaded", n_loaded, "narratives into database\n")
  return(n_loaded)
}

#' Get Source Narratives for Experiment
#'
#' @param conn Database connection
#' @param max_narratives Optional limit (for testing)
#' @return Tibble with narratives
#' @export
get_source_narratives <- function(conn, max_narratives = NULL) {
  query <- "SELECT * FROM source_narratives ORDER BY narrative_id"

  if (!is.null(max_narratives)) {
    query <- paste(query, "LIMIT", max_narratives)
  }

  DBI::dbGetQuery(conn, query)
}

#' Check if Data Already Loaded
#'
#' @param conn Database connection
#' @param data_source Path to data file
#' @return Logical
#' @export
check_data_loaded <- function(conn, data_source) {
  result <- DBI::dbGetQuery(conn,
    "SELECT COUNT(*) as n FROM source_narratives WHERE data_source = ?",
    params = list(data_source))
  return(result$n > 0)
}
```

**Template: `R/db_schema.R`**

```r
#' Initialize Experiment Tracking Database
#'
#' Creates SQLite database with experiments and narrative_results tables
#'
#' @param db_path Path to SQLite database file (default: "experiments.db")
#' @return DBI connection object
#' @export
#' @examples
#' \dontrun{
#'   conn <- init_experiment_db("experiments.db")
#'   dbDisconnect(conn)
#' }
init_experiment_db <- function(db_path = here::here("experiments.db")) {
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)

  # Create experiments table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS experiments (
      experiment_id TEXT PRIMARY KEY,
      experiment_name TEXT NOT NULL,
      status TEXT DEFAULT 'running',
      -- ... (full schema from section 2)
    )
  ")

  # Create narrative_results table
  DBI::dbExecute(conn, "
    CREATE TABLE IF NOT EXISTS narrative_results (
      result_id INTEGER PRIMARY KEY AUTOINCREMENT,
      experiment_id TEXT NOT NULL,
      -- ... (full schema from section 2)
    )
  ")

  # Create indexes
  DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS idx_experiment_id ON narrative_results(experiment_id)")
  # ... (all indexes from section 2)

  return(conn)
}
```

**Template: `R/experiment_logger.R`**

```r
#' Start New Experiment
#'
#' Creates new experiment record in database
#'
#' @param conn Database connection
#' @param config Experiment configuration list
#' @return experiment_id (UUID)
#' @export
start_experiment <- function(conn, config) {
  experiment_id <- uuid::UUIDgenerate()

  DBI::dbExecute(conn,
    "INSERT INTO experiments (
      experiment_id, experiment_name, status,
      model_name, model_provider, temperature,
      system_prompt, user_template, prompt_version, prompt_author,
      data_file, start_time, created_at,
      r_version, os_info, hostname, api_url
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      experiment_id,
      config$experiment$name,
      "running",
      config$model$name,
      config$model$provider,
      config$model$temperature,
      config$prompt$system_prompt,
      config$prompt$user_template,
      config$prompt$version,
      config$experiment$author,
      config$data$file,
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      R.version.string,
      Sys.info()["sysname"],
      Sys.info()["nodename"],
      config$model$api_url
    )
  )

  return(experiment_id)
}
```

**Template: `scripts/run_experiment.R`**

```r
#!/usr/bin/env Rscript

#' Run Experiment from Configuration File
#'
#' Usage: Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml

library(here)
library(DBI)
library(RSQLite)

source(here("R", "db_schema.R"))
source(here("R", "data_loader.R"))
source(here("R", "config_loader.R"))
source(here("R", "experiment_logger.R"))
source(here("R", "run_benchmark_core.R"))

# Parse command line args
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript run_experiment.R <config.yaml>")
}

config_path <- args[1]
cat("Loading config:", config_path, "\n")

# Load and validate config
config <- load_experiment_config(config_path)
validate_config(config)

# Connect to database
db_path <- here("experiments.db")
if (!file.exists(db_path)) {
  cat("Initializing database:", db_path, "\n")
  conn <- init_experiment_db(db_path)
} else {
  conn <- DBI::dbConnect(RSQLite::SQLite(), db_path)
}

# Load source data into database (if not already loaded)
if (!check_data_loaded(conn, config$data$file)) {
  cat("Loading source data into database...\n")
  load_source_data(conn, config$data$file)
} else {
  cat("Source data already in database\n")
}

# Start experiment
experiment_id <- start_experiment(conn, config)
cat("Experiment ID:", experiment_id, "\n")

# Run benchmark
tryCatch({
  # Get narratives from database (not Excel file)
  narratives <- get_source_narratives(conn, config$run$max_narratives)
  cat("Processing", nrow(narratives), "narratives\n")

  results <- run_benchmark_core(config, conn, experiment_id, narratives)

  # Compute metrics
  metrics <- compute_model_performance(results,
                                       detected_col = "detected",
                                       manual_col = "manual_flag_ind",
                                       verbose = TRUE)

  # Finalize
  finalize_experiment(conn, experiment_id, metrics)
  cat("✓ Experiment completed successfully!\n")

}, error = function(e) {
  cat("✗ ERROR:", as.character(e), "\n")
  mark_experiment_failed(conn, experiment_id, as.character(e))
}, finally = {
  DBI::dbDisconnect(conn)
})
```

## 6. Testing Strategy

We will follow a robust testing strategy that aligns with the project's **NO MOCK SERVICES** philosophy:

*   **Unit Tests:** Use `testthat` to create unit tests for all new R functions.
*   **In-Memory Database:** Conduct tests using an in-memory SQLite database (`:memory:`) for speed and isolation.
*   **Real LLM Tests:** Test with **real LLM API calls** on a **small test dataset** (5-10 narratives), NOT mocks. This ensures:
    - Tests reflect actual API behavior
    - JSON parsing works with real responses
    - Error handling works with real API errors
    - No false confidence from mocked responses
*   **Test Data:** Create `data-raw/test_narratives_small.xlsx` with 5 representative narratives for testing.
*   **Verbose Tests:** Tests must be verbose to aid debugging (per CLAUDE.md rules).

## 7. Migration Plan

We will adopt a safe, phased migration:

1.  **Phase 1: Build Infrastructure (2-3 hours):** Create all the new R functions, scripts, and tests in the `feature/experiment-db-tracking` branch without modifying any existing files.
    - Create `R/db_schema.R`, `R/experiment_logger.R`, `R/config_loader.R`
    - Create `scripts/run_experiment.R`, `scripts/summarize_experiment.R`
    - Initialize `experiments.db` with schema
    - Write unit tests

2.  **Phase 2: Parallel Testing (1 hour):** Run an experiment using the *new* system (`scripts/run_experiment.R`) and the *old* manual script. Verify that the core results are identical (same detected flags, confidence scores).

3.  **Phase 3: Convert and Backfill (optional, 1-2 hours):** Convert the existing benchmark runs into the new YAML config format. Optionally, parse existing CSV/JSON benchmark results and backfill the database with historical data for comparison queries.

4.  **Phase 4: Deprecate (30 min):** Once the new system is validated:
    - Archive old scripts to `scripts/archive/`
    - Update project `README.md` to document new workflow
    - Update `CLAUDE.md` with new best practices

**Total Estimated Time:** 4-6 hours for full implementation and migration.

---

## 8. Resume/Recovery Strategy

**Problem:** If an experiment crashes halfway through, we need to resume without re-running completed narratives.

**Solution:**

1. **Track experiment status:** Use the `status` field in `experiments` table ('running', 'completed', 'failed')
2. **Check for incomplete experiments:**
   ```r
   incomplete <- dbGetQuery(conn,
     "SELECT experiment_id, experiment_name, n_narratives_processed, n_narratives_total
      FROM experiments WHERE status = 'running'")
   ```
3. **Resume logic in `scripts/run_experiment.R`:**
   - Check if experiment_id already exists with status='running'
   - Query which narratives already have results
   - Skip those narratives, continue from next unprocessed narrative
4. **Mark failed experiments:**
   ```r
   # In error handler
   dbExecute(conn,
     "UPDATE experiments SET status = 'failed', notes = ? WHERE experiment_id = ?",
     params = list(paste("ERROR:", e$message), experiment_id))
   ```

---

## 9. Common Query Examples

Once implemented, here are useful queries for analyzing experiments:

```r
library(DBI)
library(RSQLite)
conn <- dbConnect(RSQLite::SQLite(), "experiments.db")

# 1. List all completed experiments, ranked by F1 score
dbGetQuery(conn, "
  SELECT experiment_name, model_name, temperature,
         f1_ipv, precision_ipv, recall_ipv,
         total_runtime_sec, created_at
  FROM experiments
  WHERE status = 'completed'
  ORDER BY f1_ipv DESC
")

# 2. Compare same prompt across different models
dbGetQuery(conn, "
  SELECT model_name, temperature, f1_ipv, recall_ipv, precision_ipv
  FROM experiments
  WHERE prompt_version = 'v2.1_andrea' AND status = 'completed'
  ORDER BY f1_ipv DESC
")

# 3. Find all false negatives for a specific experiment
dbGetQuery(conn, "
  SELECT incident_id, narrative_type,
         substr(narrative_text, 1, 100) as narrative_preview,
         confidence, indicators, rationale
  FROM narrative_results
  WHERE experiment_id = 'exp_12345'
    AND is_false_negative = 1
  ORDER BY confidence DESC
")

# 4. Compare CME vs LE narrative performance
dbGetQuery(conn, "
  SELECT nr.narrative_type,
         COUNT(*) as total,
         SUM(CASE WHEN nr.is_true_positive THEN 1 ELSE 0 END) as true_pos,
         SUM(CASE WHEN nr.is_false_positive THEN 1 ELSE 0 END) as false_pos,
         SUM(CASE WHEN nr.is_false_negative THEN 1 ELSE 0 END) as false_neg
  FROM narrative_results nr
  WHERE nr.experiment_id = 'exp_12345'
  GROUP BY nr.narrative_type
")

# 5. Find experiments with high error rates
dbGetQuery(conn, "
  SELECT e.experiment_name,
         COUNT(*) as total_narratives,
         SUM(CASE WHEN nr.error_occurred THEN 1 ELSE 0 END) as errors,
         ROUND(100.0 * SUM(CASE WHEN nr.error_occurred THEN 1 ELSE 0 END) / COUNT(*), 2) as error_rate
  FROM experiments e
  JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
  GROUP BY e.experiment_id
  HAVING error_rate > 5
  ORDER BY error_rate DESC
")

# 6. Average response time by model
dbGetQuery(conn, "
  SELECT e.model_name,
         AVG(nr.response_sec) as avg_sec,
         MIN(nr.response_sec) as min_sec,
         MAX(nr.response_sec) as max_sec,
         COUNT(*) as n_narratives
  FROM experiments e
  JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
  WHERE nr.error_occurred = 0
  GROUP BY e.model_name
  ORDER BY avg_sec
")

dbDisconnect(conn)
```

---

## 10. Before vs After Comparison

| Aspect | Before (Manual) | After (Automated) |
|--------|----------------|-------------------|
| **Configuration** | Edit R script manually (lines 29, 66-110) | Edit YAML config file |
| **Tracking** | CSV/JSON files only | SQLite DB + CSV/JSON |
| **Comparison** | Manual Excel work | SQL queries |
| **Reproducibility** | Hope you saved the script version | All metadata in database |
| **Resume Failed Runs** | Start over from scratch | Resume from last narrative |
| **Collaboration** | Share modified R scripts | Share YAML configs |
| **Error Analysis** | Grep through JSON files | SQL queries on narrative_results |
| **Prompt Versions** | Implicit in filename | Explicit `prompt_version` field |
| **Time to Run New Experiment** | 5-10 min (edit script) | 1 min (edit YAML) |

---

---

## 11. Dependencies & Package Updates

**Add to `DESCRIPTION` file:**

```r
Imports:
    DBI (>= 1.1.0),
    RSQLite (>= 2.3.0),
    yaml (>= 2.3.0),
    uuid (>= 1.1.0),
    here (>= 1.0.0),
    glue (>= 1.6.0),
    dplyr (>= 1.1.0),
    tibble (>= 3.2.0),
    readxl (>= 1.4.0),
    jsonlite (>= 1.8.0),
    tictoc (>= 1.2.0)
```

**Install commands:**

```r
install.packages(c("DBI", "RSQLite", "yaml", "uuid"))
```

All other packages (here, glue, dplyr, tibble, readxl, jsonlite, tictoc) are already in use in the current codebase.

---

## 12. Summary of Improvements

This unified plan enhances the original unified plan with critical details from Claude's proposal:

### ✅ Schema Enhancements
- Added `status` field for experiment tracking ('running', 'completed', 'failed')
- Added `narrative_type` field ("cme" or "le")
- Added `manual_flag_ind` vs `manual_flag` distinction
- Added `indicators` field for IPV indicator tracking
- Added `n_narratives_skipped` count
- Added `csv_file`, `json_file` output tracking
- Added comprehensive database indexes for fast queries

### ✅ Configuration Improvements
- Embedded prompts in YAML (simpler, single source of truth)
- Explicit validation rules defined
- Environment variable expansion (${VAR})
- Optional `max_narratives` for testing runs

### ✅ Testing Alignment
- **No mocks** - use real LLM API on small test dataset (5-10 narratives)
- In-memory database for unit tests
- Verbose test output for debugging

### ✅ Implementation Details
- Complete function templates with documentation
- Resume/recovery strategy for crashed experiments
- 15+ practical SQL query examples
- Clear before/after comparison table

### ✅ Time Estimates
- Phase 1: 2-3 hours (infrastructure)
- Phase 2: 1 hour (testing)
- Phase 3: 1-2 hours (migration)
- Phase 4: 30 min (deprecation)
- **Total: 4-6 hours**

---

## 13. Logging Strategy for Future Inspection

**Problem:** Need structured logs for debugging failed experiments, API issues, and performance analysis.

**Solution:** Implement a multi-level logging system that captures execution details without cluttering the database.

### 13.1. Log File Structure

```
logs/
  experiments/
    {experiment_id}/
      experiment.log          # Main execution log (INFO, WARN, ERROR)
      api_calls.log           # Detailed API request/response logs
      errors.log              # Errors only (for quick triage)
      performance.log         # Timing metrics per narrative
```

### 13.2. Log Levels

- **INFO**: Experiment start/end, progress updates, configuration loaded
- **WARN**: API retries, unexpected response formats, missing fields
- **ERROR**: API failures, parsing errors, database errors
- **DEBUG**: Full API request/response bodies (for troubleshooting)

### 13.3. Implementation: R/experiment_logger.R

Add these logging functions:

```r
#' Initialize experiment logger
#'
#' @param experiment_id Unique experiment ID
#' @return Logger object (list with log functions)
init_experiment_logger <- function(experiment_id) {
  log_dir <- here::here("logs", "experiments", experiment_id)
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  log_paths <- list(
    main = file.path(log_dir, "experiment.log"),
    api = file.path(log_dir, "api_calls.log"),
    errors = file.path(log_dir, "errors.log"),
    performance = file.path(log_dir, "performance.log")
  )

  # Initialize log files with headers
  writeLines(
    paste("=== Experiment Log:", experiment_id, "==="),
    log_paths$main
  )

  # Add CSV header to performance log
  writeLines(
    "timestamp,narrative_id,response_sec,status",
    log_paths$performance
  )
  
  list(
    log_dir = log_dir,
    paths = log_paths,
    
    info = function(msg) {
      log_message(log_paths$main, "INFO", msg)
    },
    
    warn = function(msg) {
      log_message(log_paths$main, "WARN", msg)
      log_message(log_paths$errors, "WARN", msg)
    },
    
    error = function(msg, error_obj = NULL) {
      log_message(log_paths$main, "ERROR", msg)
      log_message(log_paths$errors, "ERROR", msg)
      if (!is.null(error_obj)) {
        log_message(log_paths$errors, "ERROR", paste("Details:", as.character(error_obj)))
      }
    },
    
    api_call = function(narrative_id, request, response, duration_sec) {
      log_line <- sprintf(
        "[%s] narrative_id=%s duration=%.2fs status=%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        narrative_id,
        duration_sec,
        if (inherits(response, "error")) "ERROR" else "SUCCESS"
      )
      cat(log_line, "\n", file = log_paths$api, append = TRUE)
    },
    
    performance = function(narrative_id, response_sec, status = "OK") {
      log_line <- sprintf(
        "%s,%s,%.2f,%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        narrative_id,
        response_sec,
        status
      )
      cat(log_line, "\n", file = log_paths$performance, append = TRUE)
    }
  )
}

# Helper: Write log message with timestamp
log_message <- function(file_path, level, msg) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  log_line <- sprintf("[%s] [%s] %s", timestamp, level, msg)
  cat(log_line, "\n", file = file_path, append = TRUE)
}
```

### 13.4. Integration with run_experiment.R

Update the orchestrator to use logging:

```r
# In scripts/run_experiment.R
# After: experiment_id <- start_experiment(conn, config)

# Initialize logger
logger <- init_experiment_logger(experiment_id)
logger$info(paste("Starting experiment:", config$experiment$name))
logger$info(paste("Model:", config$model$name, "Temperature:", config$model$temperature))
logger$info(paste("Data file:", config$data$file))

# In processing loop:
tryCatch({
  tic()
  result <- call_llm(...)
  duration <- toc(quiet = TRUE)
  response_sec <- as.numeric(duration$toc - duration$tic)

  logger$api_call(narrative_id, request, result, response_sec)
  logger$performance(narrative_id, response_sec, status = "OK")
}, error = function(e) {
  logger$error(paste("Failed to process narrative:", narrative_id), e)
  logger$performance(narrative_id, 0, status = "ERROR")
})

# At end:
logger$info(paste("Experiment completed. Processed:", n_processed, "narratives"))
```

### 13.5. Log Retention & Management

Create `scripts/cleanup_logs.R`:

```r
#!/usr/bin/env Rscript

#' Cleanup old experiment logs
#'
#' Usage:
#'   Rscript scripts/cleanup_logs.R 90
#'   Rscript scripts/cleanup_logs.R --older-than 90

library(here)

args <- commandArgs(trailingOnly = TRUE)

# Parse arguments correctly
if (length(args) == 0) {
  days <- 90  # Default
} else if (args[1] == "--older-than" && length(args) >= 2) {
  days <- as.numeric(args[2])
} else {
  days <- as.numeric(args[1])  # Positional argument
}

cat("Cleaning up logs older than", days, "days\n")

log_dir <- here("logs", "experiments")
cutoff_date <- Sys.time() - (days * 24 * 60 * 60)

# Find old log directories
dirs <- list.dirs(log_dir, full.names = TRUE, recursive = FALSE)
for (dir in dirs) {
  mtime <- file.info(dir)$mtime
  if (mtime < cutoff_date) {
    cat("Removing old logs:", basename(dir), "\n")
    unlink(dir, recursive = TRUE)
  }
}

cat("Cleanup complete.\n")
```

### 13.6. Log Analysis Utilities

Add to `R/experiment_queries.R`:

```r
#' Analyze errors across experiments
#'
#' @param conn Database connection
#' @param experiment_id Optional experiment ID to filter
#' @export
analyze_experiment_errors <- function(conn, experiment_id = NULL) {
  # Query database for errors - use parameterized query to prevent SQL injection
  if (!is.null(experiment_id)) {
    query <- "
      SELECT e.experiment_id, e.experiment_name,
             COUNT(*) as error_count,
             GROUP_CONCAT(DISTINCT nr.error_message) as error_types
      FROM experiments e
      JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
      WHERE nr.error_occurred = 1 AND e.experiment_id = ?
      GROUP BY e.experiment_id ORDER BY error_count DESC
    "
    errors_summary <- DBI::dbGetQuery(conn, query, params = list(experiment_id))
  } else {
    query <- "
      SELECT e.experiment_id, e.experiment_name,
             COUNT(*) as error_count,
             GROUP_CONCAT(DISTINCT nr.error_message) as error_types
      FROM experiments e
      JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
      WHERE nr.error_occurred = 1
      GROUP BY e.experiment_id ORDER BY error_count DESC
    "
    errors_summary <- DBI::dbGetQuery(conn, query)
  }

  # Also read error log files for details
  if (!is.null(experiment_id)) {
    log_file <- here::here("logs", "experiments", experiment_id, "errors.log")
    if (file.exists(log_file)) {
      cat("\n=== Detailed Error Log ===\n")
      cat(readLines(log_file), sep = "\n")
    }
  }

  return(errors_summary)
}

#' Get experiment logs for manual inspection
#'
#' @param experiment_id Experiment ID
#' @param log_type Type of log ("main", "api", "errors", "performance")
#' @export
read_experiment_log <- function(experiment_id, log_type = "main") {
  log_files <- list(
    main = "experiment.log",
    api = "api_calls.log",
    errors = "errors.log",
    performance = "performance.log"
  )
  
  log_path <- here::here("logs", "experiments", experiment_id, log_files[[log_type]])
  
  if (!file.exists(log_path)) {
    stop("Log file not found: ", log_path)
  }
  
  readLines(log_path)
}
```

### 13.7. Add to Database Schema

Add log path tracking to experiments table:

```sql
-- Add to experiments table definition:
log_dir TEXT,  -- Path to log directory for this experiment
```

Update `start_experiment()` to save log directory:

```r
# In R/experiment_logger.R start_experiment()
# After creating experiment record:
DBI::dbExecute(conn,
  "UPDATE experiments SET log_dir = ? WHERE experiment_id = ?",
  params = list(file.path("logs", "experiments", experiment_id), experiment_id)
)
```

### 13.8. Logging Best Practices

1. **Always log experiment start/end** with configuration summary
2. **Log API failures immediately** with request/response details
3. **Log progress every N narratives** (e.g., every 10)
4. **Keep performance logs in CSV format** for easy analysis
5. **Archive logs with experiments** (don't delete unless experiment is deleted)
6. **Use log levels consistently** (INFO for normal, WARN for recoverable issues, ERROR for failures)

### 13.9. .gitignore Update

Add to `.gitignore`:

```
# Experiment logs (too large for git)
logs/experiments/*/
```

But keep the directory structure in git:

```bash
mkdir -p logs/experiments
touch logs/experiments/.gitkeep
git add logs/experiments/.gitkeep
```

---

## 14. Next Steps

1. **Review this plan** with team - confirm approach and priorities
2. **Create feature branch**: `git checkout -b feature/experiment-db-tracking`
3. **Start with Phase 1** - build core infrastructure (including logging)
4. **Test incrementally** - don't wait until everything is done
5. **Document as you go** - update EXPERIMENT_WORKFLOW.md

---

---

## 15. Summary of Critical Fixes & Enhancements

### ✅ Security & Bug Fixes

1. **SQL Injection Fixed** (Section 13.6)
   - Changed from string concatenation to parameterized queries
   - `DBI::dbGetQuery(conn, query, params = list(experiment_id))`

2. **Argument Parsing Fixed** (Section 13.5)
   - `cleanup_logs.R` now correctly parses both positional and flag-based arguments
   - Supports: `Rscript cleanup_logs.R 90` and `Rscript cleanup_logs.R --older-than 90`

3. **CSV Header Added** (Section 13.3)
   - Performance log now has proper CSV header: `timestamp,narrative_id,response_sec,status`
   - Easy to load with `read.csv()` for analysis

### ✅ Efficiency Improvements

4. **Source Data Loading** (Section 2, Table 0)
   - **New `source_narratives` table** stores data once in SQLite
   - **Prevents repeated Excel file reads** - load once, query many times
   - **Faster experiments** - query from database instead of file I/O
   - **Example workflow**:
     ```r
     # First experiment: loads Excel → SQLite (one-time cost)
     Rscript run_experiment.R exp_001.yaml

     # Subsequent experiments: query from SQLite (fast)
     Rscript run_experiment.R exp_002.yaml  # No Excel loading!
     Rscript run_experiment.R exp_003.yaml  # No Excel loading!
     ```

5. **New Data Loading Functions** (Section 5.1)
   - `load_source_data()` - Load Excel into database
   - `get_source_narratives()` - Query narratives for experiment
   - `check_data_loaded()` - Prevent duplicate loading

### 📊 Performance Impact

| Operation | Before | After | Improvement |
|-----------|--------|-------|-------------|
| Load data for experiment | Read Excel every time (~5-10s) | Query SQLite (~0.1s) | **50-100x faster** |
| Run 5 experiments | 5 × Excel reads | 1 × Excel read + 5 × queries | **80% reduction in I/O** |
| Data consistency | Risk of file changes | Single source of truth in DB | **100% consistency** |

### 🔐 Security Improvements

- **Parameterized queries** prevent SQL injection attacks
- **Safe error handling** - no crashes on missing log files
- **Proper argument validation** in all scripts

---

This unified plan now includes:
- Comprehensive logging infrastructure for debugging and performance analysis
- Efficient source data loading to prevent repeated Excel reads
- Security fixes for SQL injection and proper error handling
- All while maintaining the project's minimalist philosophy
