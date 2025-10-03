# IPV Detection in NVDRS Using LLM APIs

A minimal function that detects intimate partner violence in death narratives. That's it.

---

## 🚀 Quick Start

**Get running in 5 minutes**: See [docs/QUICK_START.md](docs/QUICK_START.md) ⭐

**TL;DR**:
```bash
# 1. Install packages
Rscript -e "install.packages(c('here','DBI','RSQLite','yaml','readxl','dplyr','httr2','jsonlite'))"

# 2. Copy config (edit if needed)
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/test.yaml

# 3. Run
Rscript scripts/run_experiment.R configs/experiments/test.yaml
```

**Done!** Results in `data/experiments.db`, logs in `logs/experiments/`.

---

## What This Is

One function (`detect_ipv`) that sends text to an LLM and gets back IPV detection results. No magic, no complexity, just a simple API call wrapped in error handling.

## What This Is NOT

- NOT a complex R package with 50 dependencies
- NOT an abstraction layer that hides what's happening
- NOT a framework that dictates your workflow
- NOT a solution looking for a problem

## The Entire Implementation

```r
detect_ipv <- function(text, config = NULL) {
  # Default config
  if (is.null(config)) {
    config <- list(
      api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
      model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b")
    )
  }
  
  # Empty input = empty output
  if (is.null(text) || is.na(text) || trimws(text) == "") {
    return(list(detected = NA, confidence = 0))
  }
  
  # Call API
  tryCatch({
    response <- httr2::request(config$api_url) |>
      httr2::req_body_json(list(
        model = config$model,
        messages = list(list(role = "user", content = text))
      )) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    
    jsonlite::fromJSON(response$choices[[1]]$message$content)
  }, error = function(e) {
    list(detected = NA, confidence = 0, error = e$message)
  })
}
```

That's the whole thing. Minimal and clean. Done.

## Installation? Copy the Function

```r
# Step 1: Copy the detect_ipv function from above
# Step 2: Install dependencies
install.packages(c("httr2", "jsonlite"))
# Step 3: There is no step 3
```

## Setup

```r
# Point to your LLM
Sys.setenv(LLM_API_URL = "http://192.168.10.22:1234/v1/chat/completions")
Sys.setenv(LLM_MODEL = "openai/gpt-oss-120b")
```

## Usage

```r
# Single narrative
result <- detect_ipv("Husband shot wife during argument")
print(result$detected)  # TRUE or FALSE

# Batch processing (YOU control the loop)
data <- readxl::read_excel("your_data.xlsx")
data$ipv <- lapply(data$narrative, detect_ipv)

# Parallel? Your choice
library(parallel)
results <- mclapply(narratives, detect_ipv, mc.cores = 4)

# Custom prompt? Pass config
my_config <- list(
  api_url = "http://your-llm/v1/chat/completions",
  model = "your-model"
)
result <- detect_ipv(text, my_config)
```

That's it. No frameworks. No abstractions. Just a function call.

## Input/Output

You give it text. It returns:
```r
list(
  detected = TRUE/FALSE,
  confidence = 0.0-1.0,
  error = "message if failed"
)
```

## Optional: Storage & Experiment Tracking

The minimal `detect_ipv` function works standalone. But if you want to store results, track experiments, or analyze performance, there are optional storage utilities.

### Quick Storage (SQLite)

```r
# Process and store results locally
source("R/0_setup.R")

response <- call_llm("narrative text", "system prompt")
parsed <- parse_llm_result(response, narrative_id = "case_123")

# Store in local SQLite database (auto-creates schema)
conn <- get_db_connection("results.db")
store_llm_result(parsed, conn)
close_db_connection(conn)

# Batch processing with storage
results <- store_llm_results_batch(parsed_results, db_path = "results.db")
```

### Production Storage (PostgreSQL)

```r
# Scale to PostgreSQL for production workloads
# Create .env file with: POSTGRES_HOST, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD

conn <- connect_postgres()
store_llm_result(parsed, conn)

# Batch processing: ~250-500 records/second over network
batch_result <- store_llm_results_batch(parsed_results, conn = conn, chunk_size = 5000)
close_db_connection(conn)
```

### Experiment Tracking (R&D)

```r
# Track prompt experiments and compare performance
conn <- get_db_connection("experiments.db")
ensure_experiment_schema(conn)

# Register prompt versions
v1_id <- register_prompt(conn, "You are an IPV detector", "Analyze: {{narrative}}")
v2_id <- register_prompt(conn, "You are a forensic analyst", "Detect IPV in: {{narrative}}")

# A/B test different prompts
results <- ab_test_prompts(conn, v1_id, v2_id, test_narratives)
print(results$comparison)  # Shows performance metrics

close_db_connection(conn)
```

### Feature Comparison

| Feature | SQLite (Local) | PostgreSQL (Production) |
|---------|----------------|-------------------------|
| Setup | Zero config | Environment variables |
| Performance | 50-200/sec | 250-500/sec (network) |
| Concurrent users | Single user | Multi-user |
| Storage limit | Disk space | Server capacity |
| Best for | Development, analysis | Production, teams |

### Documentation

- **Storage Guide**: `docs/RESULT_STORAGE_GUIDE.md` - Comprehensive storage examples
- **SQLite Setup**: `docs/SQLITE_SETUP.md` - Local development setup  
- **PostgreSQL Setup**: `docs/POSTGRESQL_SETUP.md` - Production deployment
- **Troubleshooting**: `docs/TROUBLESHOOTING.md` - Common issues and solutions
- **Experiments**: `docs/EXPERIMENT_MODE_GUIDE.md` - R&D prompt optimization

Or don't use any of this. The minimal `detect_ipv` function works perfectly standalone.

## Key Files

### Core Implementation
- `docs/ULTIMATE_CLEAN.R` - The minimal version. Use this.
- `docs/CLEAN_IMPLEMENTATION.R` - Extended version with batching if you need it.

### Documentation
- `docs/RESULT_STORAGE_GUIDE.md` - Storage and experiment tracking (optional)
- `docs/SQLITE_SETUP.md` - Local development with SQLite (zero config)
- `docs/POSTGRESQL_SETUP.md` - Production deployment with PostgreSQL  
- `docs/TROUBLESHOOTING.md` - Common issues and solutions
- `docs/EXPERIMENT_MODE_GUIDE.md` - R&D prompt optimization (optional)

### Everything Else
Legacy complexity. Ignore it.

## Why This Approach?

Because 99% of "data science" code is just:
1. Read data
2. Call an API
3. Write results

The other 10,000 lines? Abstractions that make simple things complicated. 

This project rejects that. One function. Clear purpose. You control everything else.

---

## Quick Start: Running Experiments

### New System (October 2025) ⭐ **Use This**

The project now uses a YAML-based experiment tracking system for systematic evaluation.

**Just run the experiment** - everything else is automatic:

```bash
# 1. Create experiment config
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_experiment.yaml
# Edit your config (change model, prompts, temperature, etc.)

# 2. Run experiment (that's it!)
Rscript scripts/run_experiment.R configs/experiments/my_experiment.yaml
```

The script automatically:
- Initializes database (first time only)
- Loads data from Excel (first time only)
- Processes narratives with LLM
- Logs everything
- Computes metrics
- Saves results

**Query results**:
```r
library(DBI)
library(RSQLite)

conn <- dbConnect(RSQLite::SQLite(), "data/experiments.db")

# List all experiments
dbGetQuery(conn, "SELECT experiment_id, experiment_name, f1_ipv, recall_ipv, precision_ipv
                  FROM experiments ORDER BY created_at DESC")

# Get detailed results for specific experiment
dbGetQuery(conn, "SELECT * FROM narrative_results WHERE experiment_id = 'YOUR_ID'")

# Find false positives
dbGetQuery(conn, "SELECT incident_id, confidence, rationale 
                  FROM narrative_results 
                  WHERE experiment_id = 'YOUR_ID' AND is_false_positive = 1")

dbDisconnect(conn)
```

### Benefits of New System

- **Configuration-driven**: No code changes needed for new experiments
- **Configurable database**: Edit `.db_config` to change database location
- **Clean organization**: Database in `data/` directory, not root
- **Full tracking**: Every experiment stored in database with metadata
- **Comprehensive logging**: 4 log files per experiment for debugging
- **Easy comparison**: SQL queries to compare models/prompts
- **Faster data loading**: Excel → SQLite once, then 50-100x faster queries

**Configure database location**: Edit `.db_config` file in project root
```bash
# Default (recommended)
EXPERIMENTS_DB=data/experiments.db

# Or use absolute path
EXPERIMENTS_DB=/path/to/your/database.db
```

See [Database Configuration Guide](docs/20251003-database_configuration_guide.md) for details.

### Old System (Deprecated)

Old `run_benchmark*.R` scripts in `scripts/archive/` are deprecated.
Do not use them for new experiments. They required manual script editing and had no systematic tracking.

---

## Documentation

- **[Documentation Index](docs/20251003-INDEX.md)** - Complete guide to all documentation ⭐
- [Testing Instructions](docs/20251003-testing_instructions.md) - How to run tests
- [Phase 1 Complete](docs/20251003-phase1_implementation_complete.md) - Implementation guide
- [Phase 2 Complete](docs/20251003-phase2_implementation_complete.md) - Full system overview
- [Implementation Summary](docs/20251003-implementation_summary.md) - Quick reference
- [Cleanup Status](docs/20251003-cleanup_complete_summary.md) - Current status & recommendations
- [Code Organization Review](docs/20251003-code_organization_review.md) - Architecture & cleanup plan
- [Scripts README](scripts/README.md) - Script usage guide

---

## License

MIT. Do whatever you want with it.