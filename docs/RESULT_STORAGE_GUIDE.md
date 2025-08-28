# Result Storage & Experiment Tracking Guide

## Philosophy

Following Unix philosophy: simple tools that do one thing well. You compose them as needed.

## Quick Start

### Basic Mode (Production)

```r
source("R/0_setup.R")

# Process a narrative
result <- call_llm(
  user_prompt = "Victim shot by ex-husband",
  system_prompt = "Detect IPV: TRUE/FALSE + confidence"
)

# Parse the result
parsed <- parse_llm_result(result$response)

# Store it (optional - you control when/if to store)
conn <- connect_db()
store_llm_result(parsed, conn)
dbDisconnect(conn)
```

That's it. One table, three functions.

### Experiment Mode (R&D)

For prompt optimization during research:

```r
source("R/0_setup.R")

# Setup experiment database
conn <- connect_db("experiments.db")
ensure_experiment_schema(conn)

# Register prompt versions
v1_id <- register_prompt(
  conn,
  system_prompt = "You are an IPV detector",
  user_prompt_template = "Analyze: {{narrative}}",
  version_tag = "baseline"
)

v2_id <- register_prompt(
  conn,
  system_prompt = "You are a forensic IPV analyst",
  user_prompt_template = "Detect IPV in: {{narrative}}",
  version_tag = "forensic"
)

# Run A/B test
results <- ab_test_prompts(
  conn,
  prompt_v1_id = v1_id,
  prompt_v2_id = v2_id,
  test_data = test_narratives
)

# View comparison
print(results$comparison)
dbDisconnect(conn)
```

## Core Functions

### Storage Functions

**`parse_llm_result(response, narrative_id = NULL)`**
- Parses JSON/text response from LLM
- Returns structured list with detected, confidence, details
- Handles malformed responses gracefully

**`store_llm_result(parsed_result, conn = NULL)`**
- Stores parsed result in SQLite database
- Auto-creates schema if missing
- Returns TRUE on success

**`connect_db(db_path = NULL)`**
- Creates/connects to SQLite database
- Default: "llm_results.db" in project root
- Returns DBI connection object

### Experiment Functions (Optional)

**`register_prompt(conn, system_prompt, user_prompt_template, ...)`**
- Registers prompt for tracking
- Auto-deduplicates identical prompts
- Returns prompt_id

**`start_experiment(conn, prompt_id, description = NULL)`**
- Starts new experiment batch
- Returns experiment_id

**`store_experiment_result(conn, experiment_id, narrative_id, detected, confidence, ...)`**
- Stores result linked to experiment
- Tracks all metrics for analysis

**`ab_test_prompts(conn, prompt_v1_id, prompt_v2_id, test_data)`**
- Runs paired A/B test on same narratives
- McNemar's test for detection differences
- Paired t-test for confidence differences

## Database Schema

### Simple Mode (Default)

One table: `llm_results`
```sql
CREATE TABLE llm_results (
    id INTEGER PRIMARY KEY,
    narrative_id TEXT,
    detected BOOLEAN,
    confidence REAL,
    victim_name TEXT,
    perpetrator_name TEXT,
    -- ... other extracted fields ...
    created_at TIMESTAMP
);
```

### Experiment Mode (Optional)

Four tables for R&D:
- `prompt_versions` - Deduplicated prompts with SHA256 hashes
- `experiments` - Batch tracking with metadata
- `experiment_results` - Results linked to experiments
- `ground_truth` - Manual labels for validation

## Common Patterns

### Batch Processing

```r
# You control the loop
data <- read_excel("narratives.xlsx")
conn <- connect_db()

for (i in 1:nrow(data)) {
  result <- call_llm(data$narrative[i], system_prompt)
  parsed <- parse_llm_result(result$response, data$id[i])
  store_llm_result(parsed, conn)
}

dbDisconnect(conn)
```

### Parallel Processing

```r
# You control parallelization
library(parallel)

process_narrative <- function(text, id) {
  result <- call_llm(text, system_prompt)
  parse_llm_result(result$response, id)
}

# Process in parallel
parsed_results <- mclapply(
  1:nrow(data),
  function(i) process_narrative(data$narrative[i], data$id[i]),
  mc.cores = detectCores()
)

# Store sequentially (SQLite doesn't like parallel writes)
conn <- connect_db()
lapply(parsed_results, store_llm_result, conn = conn)
dbDisconnect(conn)
```

### Error Recovery

```r
# You control error handling
safe_process <- function(narrative, conn, max_retries = 3) {
  for (attempt in 1:max_retries) {
    tryCatch({
      result <- call_llm(narrative, system_prompt)
      parsed <- parse_llm_result(result$response)
      store_llm_result(parsed, conn)
      return(parsed)
    }, error = function(e) {
      if (attempt == max_retries) {
        warning(paste("Failed after", max_retries, "attempts:", e$message))
        return(NULL)
      }
      Sys.sleep(2^attempt)  # Exponential backoff
    })
  }
}
```

### Prompt Evolution Tracking

```r
# Track how prompts improve over time
conn <- connect_db("experiments.db")
ensure_experiment_schema(conn)

# Load ground truth
truth <- read_excel("manual_labels.xlsx")
load_ground_truth(conn, truth$id, truth$is_ipv)

# Test each prompt version
versions <- c("v1", "v2", "v3")
for (v in versions) {
  prompt_id <- register_prompt(conn, prompts[[v]]$system, prompts[[v]]$user, v)
  exp_id <- start_experiment(conn, prompt_id, paste("Testing", v))
  
  # Run on test set
  for (i in 1:nrow(test_data)) {
    result <- call_llm(test_data$narrative[i], prompts[[v]]$system)
    parsed <- parse_llm_result(result$response)
    store_experiment_result(
      conn, exp_id, test_data$id[i],
      parsed$detected, parsed$confidence
    )
  }
}

# Compare all versions
comparison <- compare_experiments(conn, model = "gpt-4")
print(comparison$summary)
```

## Query Examples

### Basic Queries

```r
conn <- connect_db()

# Count IPV detections
dbGetQuery(conn, "SELECT COUNT(*) FROM llm_results WHERE detected = TRUE")

# Average confidence
dbGetQuery(conn, "SELECT AVG(confidence) FROM llm_results WHERE detected = TRUE")

# Recent results
recent <- dbGetQuery(conn, "
  SELECT * FROM llm_results 
  ORDER BY created_at DESC 
  LIMIT 10
")
```

### Experiment Queries

```r
# Best performing prompt
best <- dbGetQuery(conn, "
  SELECT prompt_id, accuracy, avg_confidence
  FROM experiment_accuracy
  ORDER BY accuracy DESC
  LIMIT 1
")

# Prompt evolution
evolution <- dbGetQuery(conn, "
  SELECT version_tag, accuracy, precision, recall
  FROM experiment_accuracy
  ORDER BY experiment_id
")
```

## Performance Characteristics

- **Parsing**: ~1000 results/second
- **SQLite Storage**: >1000 inserts/second
- **Memory**: Minimal, streaming design
- **Disk**: ~1KB per result

## Troubleshooting

### Common Issues

**"no such table: llm_results"**
```r
conn <- connect_db()
ensure_db_schema(conn)  # Creates tables
```

**"database is locked"**
- SQLite doesn't handle concurrent writes well
- Use sequential writes or PostgreSQL wrapper

**"could not parse JSON"**
```r
# Parser handles malformed JSON
parsed <- parse_llm_result(bad_json)
print(parsed$error)  # See what went wrong
```

## Philosophy Reminders

1. **You own the workflow** - These are tools, not a framework
2. **Start simple** - Use basic mode until you need experiments
3. **No magic** - Every function does one clear thing
4. **Compose freely** - Mix with any R packages you like
5. **30 lines** - Core detection is still just 30 lines

## Why Not PostgreSQL?

Following Unix philosophy:
- SQLite is zero-configuration
- Works on every system
- No server to manage
- Sufficient for millions of records

If you need PostgreSQL, wrap our functions:
```r
# Your PostgreSQL wrapper (you control it)
store_to_postgres <- function(parsed, pg_conn) {
  # Your PostgreSQL-specific code
}
```

## Summary

Three functions for storage. Four tables if you need experiments. Zero frameworks. Total control.

The Unix way: simple tools, composed by you.