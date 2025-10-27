# Benchmark Automation Improvement Plan

**Author**: Claude
**Date**: 2025-10-03
**Problem**: Manual benchmark configuration is error-prone and lacks systematic experiment tracking

---

## Executive Summary

Transform manual benchmark scripts into an automated experiment tracking system with:
1. **Experiment Registry** - SQLite database tracking all experiment runs
2. **Configuration Files** - YAML/JSON for experiment specifications
3. **Automated Execution** - Run experiments from config, auto-save metadata
4. **Performance Metrics** - Compare experiments systematically

**Philosophy**: Keep it minimal. No MLflow/W&B dependencies. Use SQLite + R native tools.

---

## Current State Analysis

### Problems Identified

```r
# Current script issues (scripts/run_benchmark_andrea_09022025.R):
# 1. Hardcoded configurations (line 29)
MODELS <- c("openai/gpt-oss-120b", "qwen/qwen3-30b-a3b-2507")

# 2. Manual prompt editing (lines 66-110)
system_prompt <- r"(ROLE: Identify...)"

# 3. Duplicate code blocks (lines 309-383)
all_results_1 <- run_all_narratives(...)
all_results_2 <- run_all_narratives(...)
all_results_3 <- run_all_narratives(...)

# 4. No experiment-level tracking
# - No start/end times
# - No prompt versioning
# - No systematic comparison
# - No author/platform info
```

### What's Good (Keep These)

- ✅ Incremental saving (lines 249-283)
- ✅ CSV + JSON dual output
- ✅ Progress indicators
- ✅ Error handling with tryCatch
- ✅ Metrics computation (`compute_model_performance`)

---

## Database Schema Design

### Two-Table Structure

**Principle**: Separate experiment metadata from narrative-level results.

```sql
-- =============================================================================
-- TABLE 1: experiments (run-level metadata)
-- =============================================================================
CREATE TABLE experiments (
  experiment_id TEXT PRIMARY KEY,           -- UUID or timestamp-based ID
  experiment_name TEXT,                     -- e.g., "prompt_v2_gpt4_temp01"

  -- Configuration
  model_name TEXT NOT NULL,
  model_provider TEXT,                      -- openai, anthropic, local
  temperature REAL NOT NULL,
  system_prompt TEXT NOT NULL,
  user_template TEXT NOT NULL,
  prompt_version TEXT,                      -- e.g., "v2.1_andrea"
  prompt_author TEXT,                       -- who wrote this prompt

  -- Dataset info
  data_file TEXT,
  n_narratives_total INTEGER,
  n_narratives_processed INTEGER,
  n_narratives_skipped INTEGER,

  -- Timing
  start_time TEXT NOT NULL,                 -- ISO 8601 format
  end_time TEXT,
  total_runtime_sec REAL,
  avg_time_per_narrative_sec REAL,

  -- Platform/Environment
  api_url TEXT,
  r_version TEXT,
  os_info TEXT,
  hostname TEXT,

  -- Results summary (computed after run)
  n_positive_detected INTEGER,              -- LLM said IPV
  n_negative_detected INTEGER,              -- LLM said no IPV
  n_positive_manual INTEGER,                -- Manual flags
  n_negative_manual INTEGER,

  -- Performance metrics (overall)
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
  notes TEXT                                -- free-form notes
);

-- =============================================================================
-- TABLE 2: narrative_results (prediction-level details)
-- =============================================================================
CREATE TABLE narrative_results (
  result_id INTEGER PRIMARY KEY AUTOINCREMENT,
  experiment_id TEXT NOT NULL,              -- FK to experiments

  -- Identifiers
  incident_id TEXT NOT NULL,
  narrative_type TEXT NOT NULL,             -- "cme" or "le"
  row_num INTEGER,

  -- Input
  narrative_text TEXT,

  -- Manual labels
  manual_flag_ind BOOLEAN,                  -- individual narrative flag
  manual_flag BOOLEAN,                      -- case-level flag

  -- LLM output
  detected BOOLEAN,
  confidence REAL,
  indicators TEXT,                          -- JSON array as string
  rationale TEXT,
  reasoning_steps TEXT,                     -- for reasoning models

  -- Timing
  response_sec REAL,
  processed_at TEXT,

  -- Raw data (for debugging)
  raw_response TEXT,                        -- full LLM response
  error_occurred BOOLEAN DEFAULT 0,
  error_message TEXT,

  -- Comparison
  is_true_positive BOOLEAN,                 -- detected=T, manual=T
  is_true_negative BOOLEAN,                 -- detected=F, manual=F
  is_false_positive BOOLEAN,                -- detected=T, manual=F
  is_false_negative BOOLEAN,                -- detected=F, manual=T

  FOREIGN KEY (experiment_id) REFERENCES experiments(experiment_id)
);

-- Indexes for fast queries
CREATE INDEX idx_experiment_id ON narrative_results(experiment_id);
CREATE INDEX idx_incident_id ON narrative_results(incident_id);
CREATE INDEX idx_manual_flag ON narrative_results(manual_flag_ind);
CREATE INDEX idx_detected ON narrative_results(detected);
CREATE INDEX idx_error ON narrative_results(error_occurred);
```

---

## Implementation Plan

### Phase 1: Database Infrastructure (2-3 hours)

**Files to create:**

1. **R/db_schema.R** - Database initialization
```r
#' Initialize experiment tracking database
#'
#' Creates SQLite database with experiments and narrative_results tables
#'
#' @param db_path Path to SQLite database file
#' @export
init_experiment_db <- function(db_path = here::here("experiments.db")) {
  # Create tables using DBI/RSQLite
  # Return connection object
}
```

2. **R/experiment_logger.R** - Logging functions
```r
#' Start new experiment run
#'
#' @return experiment_id (UUID)
start_experiment <- function(conn, config) { }

#' Log single narrative result
log_narrative_result <- function(conn, experiment_id, result) { }

#' Finalize experiment with summary metrics
finalize_experiment <- function(conn, experiment_id, metrics) { }
```

3. **R/experiment_queries.R** - Query helpers
```r
#' Get all experiments
list_experiments <- function(conn, filter = NULL) { }

#' Compare multiple experiments
compare_experiments <- function(conn, experiment_ids) { }

#' Get narrative-level results for experiment
get_narrative_results <- function(conn, experiment_id) { }
```

**Tests to add:**
- `tests/testthat/test-db_schema.R`
- `tests/testthat/test-experiment_logger.R`
- `tests/testthat/test-experiment_queries.R`

---

### Phase 2: Configuration System (1-2 hours)

**Use YAML for experiment configs** (human-readable, version-controllable)

**File structure:**
```
configs/
  prompts/
    prompt_v1_baseline.txt
    prompt_v2_andrea.txt
    prompt_v3_simplified.txt
  experiments/
    exp_001_baseline.yaml
    exp_002_gpt4_variations.yaml
    exp_003_reasoning_models.yaml
```

**Example config** (`configs/experiments/exp_001_baseline.yaml`):
```yaml
experiment:
  name: "baseline_gpt4_temp01"
  description: "Andrea's prompt v2 with GPT-4, temp=0.1"
  author: "andrea"

model:
  name: "openai/gpt-4o"
  provider: "openai"
  api_url: "${LLM_API_URL}"  # environment variable
  temperature: 0.1

prompts:
  system_prompt_file: "configs/prompts/prompt_v2_andrea.txt"
  user_template_file: "configs/prompts/user_template_v1.txt"
  version: "v2.1"

data:
  file: "data-raw/suicide_IPV_manuallyflagged.xlsx"

output:
  dir: "benchmark_results"
  save_incremental: true

notes: |
  Testing Andrea's improved prompt with explicit IPV indicators.
  Expecting higher recall on shelter/restraining order cases.
```

**Files to create:**

4. **R/load_config.R**
```r
#' Load experiment configuration from YAML
#'
#' @param config_path Path to YAML config file
#' @return List with experiment configuration
#' @export
load_experiment_config <- function(config_path) {
  # Use yaml::read_yaml()
  # Expand environment variables
  # Validate required fields
}
```

5. **R/validate_config.R**
```r
#' Validate experiment configuration
#'
#' @param config Configuration list
#' @return TRUE or stop with error
validate_config <- function(config) {
  # Check required fields
  # Verify files exist
  # Validate parameter ranges
}
```

---

### Phase 3: Refactor Benchmark Script (2-3 hours)

**New streamlined script**: `scripts/run_experiment.R`

```r
#!/usr/bin/env Rscript

#' Run Experiment from Configuration File
#'
#' Usage:
#'   Rscript scripts/run_experiment.R configs/experiments/exp_001_baseline.yaml
#'   Rscript scripts/run_experiment.R configs/experiments/exp_002_gpt4_variations.yaml

library(here)
library(DBI)
library(RSQLite)
source(here("R", "load_config.R"))
source(here("R", "experiment_logger.R"))
source(here("R", "run_benchmark_core.R"))

# Get config file from command line
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript run_experiment.R <config.yaml>")
}

config_path <- args[1]
cat("Loading configuration from:", config_path, "\n")

# Load and validate config
config <- load_experiment_config(config_path)
validate_config(config)

# Connect to database
db_path <- here("experiments.db")
conn <- dbConnect(RSQLite::SQLite(), db_path)

# Initialize experiment in database
experiment_id <- start_experiment(conn, config)
cat("Started experiment:", experiment_id, "\n")

# Run benchmark (refactored from existing code)
tryCatch({
  results <- run_benchmark_core(
    config = config,
    conn = conn,
    experiment_id = experiment_id
  )

  # Compute metrics
  metrics <- compute_model_performance(results,
                                       detected_col = "detected",
                                       manual_col = "manual_flag_ind",
                                       verbose = TRUE)

  # Finalize experiment
  finalize_experiment(conn, experiment_id, metrics)

  cat("Experiment completed successfully!\n")
  cat("Experiment ID:", experiment_id, "\n")
  cat("View results: query_experiment(conn, '", experiment_id, "')\n", sep = "")

}, error = function(e) {
  cat("ERROR:", as.character(e), "\n")
  # Mark experiment as failed
  dbExecute(conn,
    "UPDATE experiments SET notes = ? WHERE experiment_id = ?",
    params = list(paste("FAILED:", e$message), experiment_id))
}, finally = {
  dbDisconnect(conn)
})
```

**Files to create:**

6. **R/run_benchmark_core.R** - Refactored from `run_all_narratives()`
```r
#' Core benchmark execution logic
#'
#' @param config Experiment configuration
#' @param conn Database connection
#' @param experiment_id Experiment ID for logging
#' @return Tibble with results
run_benchmark_core <- function(config, conn, experiment_id) {
  # Load data
  # Process narratives with logging
  # Save incremental results
  # Return final results
}
```

---

### Phase 4: Analysis & Reporting Tools (1-2 hours)

**Create convenience functions for experiment analysis:**

7. **R/experiment_reports.R**
```r
#' Generate experiment comparison report
#'
#' @param conn Database connection
#' @param experiment_ids Vector of experiment IDs to compare
#' @export
compare_experiments_report <- function(conn, experiment_ids) {
  # Query metrics for all experiments
  # Create comparison table
  # Optionally: generate plots
}

#' Find best performing experiment
#'
#' @param conn Database connection
#' @param metric Metric to optimize (f1_ipv, recall_ipv, etc.)
#' @export
find_best_experiment <- function(conn, metric = "f1_ipv") {
  # Query and rank experiments
}

#' Analyze disagreements between model and manual flags
#'
#' @param conn Database connection
#' @param experiment_id Experiment to analyze
#' @export
analyze_disagreements <- function(conn, experiment_id) {
  # Get false positives and false negatives
  # Return narratives for manual review
}
```

8. **scripts/compare_experiments.R** - Interactive analysis script
```r
#!/usr/bin/env Rscript

#' Compare Multiple Experiments
#'
#' Usage:
#'   Rscript scripts/compare_experiments.R exp_id_1 exp_id_2 exp_id_3

library(here)
library(DBI)
library(RSQLite)
source(here("R", "experiment_reports.R"))

# Get experiment IDs from command line
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript compare_experiments.R <exp_id_1> <exp_id_2> [...]")
}

conn <- dbConnect(RSQLite::SQLite(), here("experiments.db"))
report <- compare_experiments_report(conn, args)
print(report)
dbDisconnect(conn)
```

---

## Usage Examples

### Before (Current Manual Process)

```r
# 1. Edit script manually
# Change line 29: MODELS <- c("new-model")
# Change lines 66-110: system_prompt <- r"(...new prompt...)"
# Change line 316: temperature = 0.2

# 2. Run script
Rscript scripts/run_benchmark_andrea_09022025.R

# 3. Manually track results in spreadsheet or memory
# 4. Repeat for each experiment
```

### After (Automated Process)

```bash
# 1. Create experiment config (one time per experiment type)
cat > configs/experiments/exp_005_reasoning_model.yaml <<EOF
experiment:
  name: "qwen3_reasoning_temp0"
  author: "xiaosong"
model:
  name: "qwen3-30b-a3b-thinking-2507-mlx"
  temperature: 0.0
prompts:
  system_prompt_file: "configs/prompts/prompt_v2_andrea.txt"
  user_template_file: "configs/prompts/user_template_v1.txt"
data:
  file: "data-raw/suicide_IPV_manuallyflagged.xlsx"
EOF

# 2. Run experiment
Rscript scripts/run_experiment.R configs/experiments/exp_005_reasoning_model.yaml

# 3. Query results
Rscript -e "
library(DBI); library(RSQLite)
conn <- dbConnect(RSQLite::SQLite(), 'experiments.db')
dbGetQuery(conn, 'SELECT experiment_name, f1_ipv, recall_ipv, precision_ipv
                  FROM experiments ORDER BY f1_ipv DESC LIMIT 10')
"

# 4. Compare experiments
Rscript scripts/compare_experiments.R exp_id_1 exp_id_2 exp_id_3

# 5. Find disagreements for manual review
Rscript -e "
source('R/experiment_reports.R')
analyze_disagreements(conn, 'exp_005_reasoning_model')
"
```

---

## Query Examples

### Common Queries

```r
library(DBI)
library(RSQLite)

conn <- dbConnect(RSQLite::SQLite(), "experiments.db")

# 1. List all experiments
dbGetQuery(conn, "
  SELECT experiment_id, experiment_name, model_name, temperature,
         f1_ipv, recall_ipv, precision_ipv,
         total_runtime_sec, created_at
  FROM experiments
  ORDER BY created_at DESC
")

# 2. Best F1 scores
dbGetQuery(conn, "
  SELECT experiment_name, model_name, temperature,
         f1_ipv, precision_ipv, recall_ipv
  FROM experiments
  WHERE f1_ipv IS NOT NULL
  ORDER BY f1_ipv DESC
  LIMIT 5
")

# 3. Compare same prompt across models
dbGetQuery(conn, "
  SELECT model_name, temperature, f1_ipv, recall_ipv
  FROM experiments
  WHERE prompt_version = 'v2.1'
  ORDER BY model_name, temperature
")

# 4. Find false negatives for specific experiment
dbGetQuery(conn, "
  SELECT incident_id, narrative_type,
         substr(narrative_text, 1, 100) as narrative_preview,
         confidence, rationale
  FROM narrative_results
  WHERE experiment_id = 'exp_005_reasoning_model'
    AND is_false_negative = 1
  ORDER BY confidence DESC
")

# 5. Average response time by model
dbGetQuery(conn, "
  SELECT e.model_name,
         AVG(nr.response_sec) as avg_response_sec,
         COUNT(*) as n_narratives
  FROM experiments e
  JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
  GROUP BY e.model_name
  ORDER BY avg_response_sec
")

# 6. Error rate by experiment
dbGetQuery(conn, "
  SELECT e.experiment_name,
         COUNT(*) as total,
         SUM(CASE WHEN error_occurred THEN 1 ELSE 0 END) as errors,
         ROUND(100.0 * SUM(CASE WHEN error_occurred THEN 1 ELSE 0 END) / COUNT(*), 2) as error_rate
  FROM experiments e
  JOIN narrative_results nr ON e.experiment_id = nr.experiment_id
  GROUP BY e.experiment_id
  ORDER BY error_rate DESC
")

dbDisconnect(conn)
```

---

## Migration Strategy

### Step 1: Create Infrastructure (Don't break existing code)

- Create new R files in `R/` directory
- Add tests in `tests/testthat/`
- Initialize database: `experiments.db`
- Create `configs/` directory structure

### Step 2: Parallel Testing

- Keep existing `run_benchmark_andrea_09022025.R` working
- Create new `scripts/run_experiment.R`
- Run both for one experiment, verify identical results

### Step 3: Gradual Migration

- Convert recent experiments to YAML configs
- Populate database with historical results (if desired)
- Update documentation

### Step 4: Deprecate Old Script

- Archive old scripts to `scripts/archive/`
- Update README with new workflow

---

## Benefits Summary

### Before → After

| Aspect | Before | After |
|--------|--------|-------|
| **Configuration** | Edit script manually | YAML config file |
| **Tracking** | CSV files only | SQLite database + files |
| **Comparison** | Manual spreadsheet work | SQL queries |
| **Reproducibility** | Hope you remember settings | All metadata stored |
| **Collaboration** | Share scripts | Share configs |
| **Error recovery** | Start over | Resume from database |
| **Analysis** | Custom scripts each time | Reusable query functions |

### Key Improvements

1. **Reproducibility**: Every experiment fully documented with prompts, models, timing, platform
2. **Efficiency**: No manual editing, just run different configs
3. **Comparison**: Systematic comparison across experiments via SQL
4. **Collaboration**: Share configs instead of scripts
5. **Debugging**: Narrative-level details for deep dives
6. **Minimal**: SQLite + R native tools, no external dependencies

---

## File Checklist

### New Files to Create

**R functions:**
- [ ] `R/db_schema.R` - Database initialization
- [ ] `R/experiment_logger.R` - Logging functions
- [ ] `R/experiment_queries.R` - Query helpers
- [ ] `R/load_config.R` - Config loading
- [ ] `R/validate_config.R` - Config validation
- [ ] `R/run_benchmark_core.R` - Refactored core logic
- [ ] `R/experiment_reports.R` - Analysis functions

**Scripts:**
- [ ] `scripts/run_experiment.R` - Main experiment runner
- [ ] `scripts/compare_experiments.R` - Comparison tool
- [ ] `scripts/init_database.R` - Database setup helper

**Tests:**
- [ ] `tests/testthat/test-db_schema.R`
- [ ] `tests/testthat/test-experiment_logger.R`
- [ ] `tests/testthat/test-load_config.R`
- [ ] `tests/testthat/test-run_benchmark_core.R`

**Config templates:**
- [ ] `configs/prompts/prompt_v2_andrea.txt`
- [ ] `configs/prompts/user_template_v1.txt`
- [ ] `configs/experiments/exp_template.yaml`
- [ ] `configs/experiments/exp_001_baseline.yaml`

**Documentation:**
- [ ] `docs/EXPERIMENT_TRACKING.md` - Usage guide
- [ ] Update `README.md` with new workflow

---

## Dependencies

**Required R packages** (add to `DESCRIPTION`):
```r
Imports:
    DBI (>= 1.1.0),
    RSQLite (>= 2.3.0),
    yaml (>= 2.3.0),
    uuid (>= 1.1.0)  # for generating experiment IDs
```

**Install commands:**
```r
install.packages(c("DBI", "RSQLite", "yaml", "uuid"))
```

---

## Timeline Estimate

| Phase | Time | Priority |
|-------|------|----------|
| Phase 1: Database | 2-3 hours | HIGH |
| Phase 2: Configs | 1-2 hours | HIGH |
| Phase 3: Refactor | 2-3 hours | MEDIUM |
| Phase 4: Reports | 1-2 hours | LOW |
| **Total** | **6-10 hours** | |

**Recommendation**: Implement Phase 1-2 first (database + configs). This gives immediate value. Phase 3-4 can follow iteratively.

---

## Community Standards Alignment

This plan follows industry best practices from:

1. **MLflow** - Experiment tracking structure (runs + artifacts)
2. **Weights & Biases** - Configuration-driven experiments
3. **DVC** - Versioned experiment configs
4. **R-Tidyverse** - DBI for databases, here::here() for paths
5. **SQLite** - Lightweight, file-based, no server needed

While avoiding over-engineering:
- ❌ No web UI (can query with R/SQL)
- ❌ No cloud sync (local SQLite is enough)
- ❌ No complex abstractions (keep it functional)

---

## Questions to Answer Before Implementation

1. **Database location**: Single `experiments.db` in project root, or per-dataset?
2. **Prompt versioning**: Track in git, or store full text in database?
3. **Historical data**: Backfill existing benchmark results, or start fresh?
4. **Output files**: Keep CSV/JSON files, or database-only?
5. **Reasoning steps**: Store for all models, or only reasoning models?

---

## Next Steps

1. **Review this plan** - Does it meet your needs?
2. **Answer questions above** - Clarify requirements
3. **Prioritize phases** - Which parts are most valuable first?
4. **Start implementation** - Begin with Phase 1 (database)

---

**Philosophy alignment check**:
- ✅ Minimal implementation (SQLite + R, no external services)
- ✅ User controls execution (configs instead of magic)
- ✅ No unnecessary abstractions (functional approach)
- ✅ Fail fast on config errors
- ✅ One function per file principle
- ✅ No mock services (real database tests)

This plan transforms your manual benchmark process into a systematic, reproducible workflow while staying true to the project's minimalist philosophy.
