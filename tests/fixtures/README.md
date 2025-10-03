# Test Fixtures

Test data and databases for the test suite.

---

## Files

### test_experiments.db (636 KB)
**Purpose**: Test database for integration tests  
**Created by**: Phase 1 tests  
**Used by**: 
- tests/run_phase1_test.R
- tests/manual_test_experiment_setup.R

**Schema**: Same as production experiments.db

---

## Usage

Tests should use `get_test_db_path()` from R/db_config.R to get the correct path.

```r
source("R/db_config.R")
test_db <- get_test_db_path()
conn <- DBI::dbConnect(RSQLite::SQLite(), test_db)
```

---

## Configuration

Override test database name via environment variable:
```bash
TEST_DB=my_test.db Rscript tests/run_phase1_test.R
```

---

**Note**: Test databases are gitignored - each test run may recreate them.
