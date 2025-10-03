# Phase 1 Testing Instructions

## ✅ Implementation Status: COMPLETE & READY

All Phase 1 code is implemented and structurally validated. Now needs functional testing with R.

---

## 🔧 What Was Built

### Core Files (All Bug-Fixed & Ready)
1. **R/db_schema.R** - 3-table SQLite database with indexes
2. **R/data_loader.R** - Excel → SQLite loading
3. **R/config_loader.R** - YAML config with validation  
4. **R/experiment_logger.R** - Experiment tracking + logging + metrics computation
5. **R/experiment_queries.R** - Query helpers

### Key Bug Fixes Applied
- ✅ Fixed `finalize_experiment()` to compute metrics from database (not rely on external function)
- ✅ Added `compute_enhanced_metrics()` that computes precision, recall, F1 from confusion matrix
- ✅ Updated config to use `mlx-community/gpt-oss-120b` model
- ✅ Updated config to use `http://localhost:1234/v1/chat/completions` (no env var needed)

---

## 🧪 How to Test

### Option 1: Standalone Test Script (Recommended)

```bash
cd /Volumes/DATA/git/IPV_detection_in_NVDRS

# Open RStudio and run:
source('run_phase1_test.R')

# OR from terminal if R is in PATH:
R CMD BATCH run_phase1_test.R

# OR:
Rscript run_phase1_test.R
```

This script tests ALL Phase 1 functionality:
- ✅ Library loading
- ✅ Function loading
- ✅ Database creation
- ✅ Config validation
- ✅ Data loading (Excel → SQLite)
- ✅ Experiment creation
- ✅ Logger initialization
- ✅ Query functions

### Option 2: Manual Testing in RStudio

```r
# Set working directory
setwd("/Volumes/DATA/git/IPV_detection_in_NVDRS")

# Load libraries
library(here)
library(DBI)
library(RSQLite)
library(yaml)
library(uuid)
library(dplyr)
library(tibble)
library(readxl)
library(jsonlite)
library(tidyr)

# Load functions
source(here("R", "db_schema.R"))
source(here("R", "data_loader.R"))
source(here("R", "config_loader.R"))
source(here("R", "experiment_logger.R"))
source(here("R", "experiment_queries.R"))

# Create test database
conn <- init_experiment_db(here("test_experiments.db"))

# Load config
config <- load_experiment_config(here("configs", "experiments", "exp_001_test_gpt_oss.yaml"))
validate_config(config)

# Load data
load_source_data(conn, config$data$file)

# Create experiment
experiment_id <- start_experiment(conn, config)
cat("Experiment ID:", experiment_id, "\n")

# Test logger
logger <- init_experiment_logger(experiment_id)
logger$info("Test message")

# Query experiments
list_experiments(conn)

# Cleanup
dbDisconnect(conn)
```

---

## 📦 Required Packages

Install these if missing:

```r
install.packages(c("DBI", "RSQLite", "yaml", "uuid"))
```

All other packages (dplyr, readxl, etc.) are already used in existing code.

---

## 🎯 Expected Test Output

```
========================================
Phase 1 Implementation Test
========================================

Step 1: Loading libraries...
✓ All libraries loaded

Step 2: Loading new functions...
✓ Functions loaded

Step 3: Cleaning up old test files...
✓ Cleanup complete

Step 4: Creating test database...
✓ Database created with 3 tables
  Tables: source_narratives, experiments, narrative_results

Step 5: Loading configuration...
  Config loaded
✓ Configuration validated
  Model: mlx-community/gpt-oss-120b
  API URL: http://localhost:1234/v1/chat/completions
  Temperature: 0.1
  Max narratives: 10

Step 6: Loading source data...
Loading data from: data-raw/suicide_IPV_manuallyflagged.xlsx
Loaded XXX narratives into database

Summary by narrative type:
# A tibble: 2 × 3
  narrative_type     n n_positive
  <chr>          <int>      <int>
1 cme              XXX         XX
2 le               XXX         XX

✓ Loaded XXX narratives

Step 7: Querying narratives...
✓ Retrieved 5 sample narratives
  Columns: narrative_id, incident_id, narrative_type, narrative_text, ...

Step 8: Creating experiment record...
✓ Experiment created
  ID: [UUID]

Step 9: Testing logger...
✓ Logger initialized
  Log directory: logs/experiments/[UUID]
  Log files created:
    ✓ experiment.log
    ✓ api_calls.log
    ✓ errors.log
    ✓ performance.log

Step 10: Testing query functions...
✓ Found 1 experiment(s)

Step 11: Database inspection...
  source_narratives: XXX rows
  experiments: 1 rows
  narrative_results: 0 rows

========================================
✅ ALL TESTS PASSED!
========================================

Test artifacts created:
  Database: test_experiments.db
  Logs: logs/experiments/[UUID]

Next step: Implement Phase 2 (run_experiment.R orchestrator)
```

---

## 🔍 What to Look For

### Success Indicators
- ✅ All steps complete without errors
- ✅ Database file `test_experiments.db` exists
- ✅ Log directory created with 4 log files
- ✅ Source data loaded (check narrative count matches Excel)
- ✅ Experiment record created (check UUID format)
- ✅ Query returns 1 experiment

### Potential Issues & Solutions

**Issue: Package not found**
```r
# Solution:
install.packages("package_name")
```

**Issue: File not found**
```
# Solution: Check working directory
getwd()
setwd("/Volumes/DATA/git/IPV_detection_in_NVDRS")
```

**Issue: Database creation fails**
```
# Solution: Check write permissions
file.access(getwd(), mode = 2)  # Should return 0
```

**Issue: Config validation fails**
```
# Solution: Check YAML syntax and file paths
yaml::read_yaml("configs/experiments/exp_001_test_gpt_oss.yaml")
```

---

## 📊 Inspect Test Results

After testing, you can inspect the database:

```bash
# Open SQLite
sqlite3 test_experiments.db

# View schema
.schema

# Query experiments
SELECT experiment_id, experiment_name, status, model_name 
FROM experiments;

# Query source narratives
SELECT COUNT(*), narrative_type 
FROM source_narratives 
GROUP BY narrative_type;

# Exit
.quit
```

Or from R:

```r
conn <- dbConnect(RSQLite::SQLite(), "test_experiments.db")

# View experiments
dbGetQuery(conn, "SELECT * FROM experiments")

# View source narratives summary
dbGetQuery(conn, "
  SELECT narrative_type, COUNT(*) as n, SUM(manual_flag_ind) as n_positive
  FROM source_narratives
  GROUP BY narrative_type
")

dbDisconnect(conn)
```

---

## ✅ Validation Checklist

Before moving to Phase 2, verify:

- [ ] Test script runs without errors
- [ ] Database file created (test_experiments.db)
- [ ] All 3 tables exist (source_narratives, experiments, narrative_results)
- [ ] Source data loaded (hundreds of narratives)
- [ ] Experiment record created with UUID
- [ ] 4 log files created
- [ ] Query functions return data
- [ ] No errors in output

---

## 🚀 Next Steps After Testing

Once Phase 1 tests pass:

1. **Commit Phase 1 code**
   ```bash
   git add -A
   git commit -m "Phase 1: Core infrastructure implemented and tested"
   ```

2. **Move to Phase 2**: Implement orchestration
   - R/run_benchmark_core.R
   - scripts/run_experiment.R
   - Test with 10 narratives
   - Make real LLM API calls

3. **Validate against existing benchmark**
   - Run same data with new system
   - Compare results with existing CSV/JSON outputs
   - Verify metrics match

---

## 📞 If Tests Fail

1. **Check error message** - Read carefully, it will tell you what's wrong
2. **Verify packages installed** - Run `library(package_name)` for each
3. **Check file paths** - Ensure working directory is correct
4. **Verify data file exists** - Check `data-raw/suicide_IPV_manuallyflagged.xlsx`
5. **Share error output** - Copy the full error for debugging

---

## 💡 Tips

- Run from RStudio for easier debugging
- Check each step's output before moving to next
- The test database is throwaway - delete and rerun anytime
- Log files help debug issues
- SQLite is just a file - easy to inspect and delete

---

**Status**: Ready for your testing! Let me know results. 🎯
