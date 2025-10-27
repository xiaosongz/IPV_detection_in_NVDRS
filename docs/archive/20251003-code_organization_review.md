# Code Organization Review & Refactoring Plan

**Date**: 2025-10-03
**Status**: CRITICAL - Code is working but messy, needs immediate cleanup

---

## Executive Summary

The implementation is **functional but disorganized**. Major issues:

1. **Function duplication** - Same functions defined in multiple files
2. **Old vs new paradigm conflict** - Legacy code coexists with new experiment tracking
3. **Script proliferation** - 5+ benchmark scripts doing similar things
4. **Unclear boundaries** - Overlap between `db_utils.R`, `experiment_utils.R`, `experiment_logger.R`
5. **No clear migration path** - Old code not deprecated, causing confusion

**Bottom line**: It works, but it's a maintenance nightmare. Needs systematic cleanup.

---

## Current File Inventory

### R/ Package Files (19 files, 4,139 lines)

#### ✅ **Core IPV Detection** (Keep as-is)
- `build_prompt.R` (40 lines) - Prompt construction
- `call_llm.R` (78 lines) - LLM API calls
- `parse_llm_result.R` (365 lines) - Parse JSON responses
- `metrics.R` (77 lines) - Performance metrics
- `utils.R` (56 lines) - Utility functions

#### ⚠️ **Database Layer** (OVERLAP/DUPLICATION)
- `db_utils.R` (706 lines) - **OLD** database utilities
- `db_schema.R` (154 lines) - **NEW** schema management
- `store_llm_result.R` (367 lines) - **OLD** result storage

**Problem**: `db_utils.R` has functions that overlap with new files:
- `get_db_connection()` defined in BOTH `db_utils.R` and `db_schema.R`
- Storage logic duplicated between `store_llm_result.R` and `experiment_logger.R`

#### ⚠️ **Experiment Tracking** (OVERLAP/DUPLICATION)
- `experiment_utils.R` (498 lines) - **OLD** experiment tracking (for R&D phase)
- `experiment_logger.R` (389 lines) - **NEW** experiment tracking (YAML-based)
- `experiment_queries.R` (194 lines) - **NEW** query helpers
- `experiment_analysis.R` (474 lines) - **OLD** analysis functions

**Problem**: **TWO DIFFERENT `start_experiment()` FUNCTIONS**:
1. `experiment_logger.R:9` - New YAML-based system (correct)
2. `experiment_utils.R:262` - Old legacy system (should be removed)

#### ✅ **New Automation System** (Keep, recently added)
- `config_loader.R` (180 lines) - YAML config loading ✅
- `data_loader.R` (136 lines) - Excel → SQLite loading ✅
- `run_benchmark_core.R` (101 lines) - Core benchmark logic ✅

#### ❓ **Other Files**
- `call_llm_batch.R` (298 lines) - Batch processing (is this used?)
- `IPVdetection-package.R` (11 lines) - Package metadata
- `0_setup.R` (15 lines) - Setup script (deprecated?)

### scripts/ Directory (7 files)

#### ⚠️ **Benchmark Script Proliferation**
- `run_benchmark.R` (14K, Sep 9) - Base version
- `run_benchmark_optimized.R` (15K, Sep 2) - Optimized version
- `run_benchmark_updated.R` (8.1K, Sep 9) - Updated version
- `run_benchmark_andrea_09022025.R` (12K, Sep 4) - Andrea's version

**Problem**: **4 different benchmark scripts**, all doing similar things with slight variations. Which one is canonical?

#### ✅ **New System Scripts** (Keep)
- `run_experiment.R` (7.9K, Oct 3) - **NEW** YAML-based runner ✅
- `init_database.R` (1.7K, Oct 3) - Database initialization ✅

#### ❓ **Other**
- `migrate_sqlite_to_postgres.R` (17K) - Migration tool (still needed?)

### tests/ Directory

**Structure**:
```
tests/
  testthat/            # Unit tests ✅
  integration/         # Integration tests ✅
  performance/         # Performance benchmarks ✅
  test_*.R             # Standalone test scripts (cleanup?)
  manual_test_*.R      # Manual tests (cleanup?)
```

**Issue**: Some standalone test files outside testthat structure

---

## Critical Problems

### 1. **Function Name Collisions**

```r
# TWO DIFFERENT start_experiment() functions:

# Version 1 (NEW - CORRECT):
# R/experiment_logger.R:9
start_experiment <- function(conn, config) { ... }

# Version 2 (OLD - REMOVE):
# R/experiment_utils.R:262
start_experiment <- function(name, ...) { ... }
```

**Impact**: R will use whichever file is sourced last. This is a ticking time bomb.

### 2. **Duplicate `get_db_connection()`**

```r
# R/db_utils.R - Old version (PostgreSQL-focused)
get_db_connection <- function(...) { ... }

# R/db_schema.R - New version (SQLite-focused)
get_db_connection <- function(...) { ... }
```

**Impact**: Inconsistent database connections

### 3. **Unclear Code Ownership**

| File | Purpose | Status | Should Be |
|------|---------|--------|-----------|
| `experiment_utils.R` | OLD R&D phase tracking | Legacy | Deprecate/Remove |
| `experiment_logger.R` | NEW YAML-based tracking | Current | Keep |
| `experiment_analysis.R` | OLD analysis | Legacy? | Merge or Remove |
| `db_utils.R` | OLD database layer | Legacy | Refactor |
| `db_schema.R` | NEW schema | Current | Keep |

### 4. **Script Confusion**

Users (and you!) don't know which script to run:
- `run_benchmark.R` vs `run_benchmark_optimized.R` vs `run_benchmark_updated.R`?
- Answer: **Use `run_experiment.R`** (new system), but this isn't documented

---

## Proposed Refactoring Plan

### Phase 1: Separate Old from New (1-2 hours)

**Create directory structure**:

```
R/
  # === CORE IPV DETECTION (stable) ===
  build_prompt.R
  call_llm.R
  parse_llm_result.R
  metrics.R
  utils.R

  # === NEW EXPERIMENT SYSTEM (keep) ===
  db_schema.R              # Database schema management
  data_loader.R            # Excel → SQLite loading
  config_loader.R          # YAML config loading
  experiment_logger.R      # Experiment tracking (start/log/finalize)
  experiment_queries.R     # Query helpers
  run_benchmark_core.R     # Core benchmark logic

  # === LEGACY (deprecate) ===
  legacy/
    db_utils.R             # Move here, mark deprecated
    experiment_utils.R     # Move here, mark deprecated
    experiment_analysis.R  # Move here or merge into experiment_queries.R
    store_llm_result.R     # Move here, mark deprecated
    call_llm_batch.R       # Move here if not used
    0_setup.R              # Remove if not used
```

**Actions**:
1. Create `R/legacy/` directory
2. Move old files to `R/legacy/`
3. Add deprecation warnings to legacy functions:
   ```r
   #' @deprecated Use experiment_logger::start_experiment() instead
   start_experiment <- function(...) {
     .Deprecated("experiment_logger::start_experiment")
     # ... old code ...
   }
   ```

### Phase 2: Consolidate Scripts (1 hour)

```
scripts/
  # === CURRENT SYSTEM (keep) ===
  run_experiment.R         # Main runner (YAML-based)
  init_database.R          # Database setup

  # === UTILITIES (keep) ===
  cleanup_logs.R           # Add from plan
  compare_experiments.R    # Add from plan

  # === ARCHIVE (move) ===
  archive/
    run_benchmark.R
    run_benchmark_optimized.R
    run_benchmark_updated.R
    run_benchmark_andrea_09022025.R
    migrate_sqlite_to_postgres.R  # Archive unless actively needed
```

**Actions**:
1. Create `scripts/archive/` directory
2. Move old benchmark scripts
3. Add `scripts/README.md`:
   ```markdown
   # Scripts Directory

   ## Current System
   - `run_experiment.R` - Run experiments from YAML configs
   - `init_database.R` - Initialize database

   ## Archive
   Old scripts preserved for reference. DO NOT USE.
   Use `run_experiment.R` instead.
   ```

### Phase 3: Resolve Function Conflicts (2 hours)

#### 3.1. Fix `start_experiment()` collision

**Keep**: `R/experiment_logger.R::start_experiment()`
**Remove**: `R/legacy/experiment_utils.R::start_experiment()`

**Migration**:
```r
# In R/legacy/experiment_utils.R
#' @deprecated This function is deprecated. Use experiment_logger::start_experiment() instead.
start_experiment <- function(name, ...) {
  .Deprecated("experiment_logger::start_experiment")
  stop("This function has been replaced. See ?experiment_logger::start_experiment for new usage.")
}
```

#### 3.2. Fix `get_db_connection()` collision

**Decision**: Keep SQLite-focused version in `db_schema.R`, rename old one

**Action**:
```r
# In R/legacy/db_utils.R
#' @deprecated Use db_schema::get_db_connection() for SQLite
get_db_connection_postgres <- function(...) { # Rename
  .Deprecated("db_schema::get_db_connection")
  # ... old PostgreSQL code ...
}
```

#### 3.3. Fix `list_experiments()` and `compare_experiments()`

Check which versions are correct and consolidate.

### Phase 4: Update Documentation (1 hour)

1. **Update README.md**:
   ```markdown
   # Running Experiments

   ## Current System (Use This)
   ```bash
   Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
   ```

   ## Old System (Deprecated)
   Old `run_benchmark*.R` scripts are archived. Do not use.
   ```

2. **Update NAMESPACE**: Remove deprecated exports

3. **Create MIGRATION.md**:
   ```markdown
   # Migration Guide: Old to New System

   If you have code using old functions:

   | Old Function | New Function | Notes |
   |--------------|--------------|-------|
   | `experiment_utils::start_experiment()` | `experiment_logger::start_experiment()` | Different signature |
   | `db_utils::get_db_connection()` | `db_schema::get_db_connection()` | SQLite only |
   ```

### Phase 5: Add Integration Tests (1 hour)

Create `tests/testthat/test-no_duplicates.R`:

```r
test_that("No duplicate function definitions", {
  # Get all function names
  pkg_env <- loadNamespace("IPVdetection")
  exported_fns <- ls(pkg_env)

  # Check for duplicates
  expect_equal(length(exported_fns), length(unique(exported_fns)),
    info = "Found duplicate exported function names")
})

test_that("Legacy functions show deprecation warnings", {
  # Test that old functions warn about deprecation
  expect_warning(
    experiment_utils::start_experiment(),
    "deprecated"
  )
})
```

---

## Immediate Actions (Today)

### Priority 1: Document Current State ✅
- [x] Create this review document

### Priority 2: Quick Wins (30 min)
- [ ] Add `scripts/README.md` explaining which script to use
- [ ] Add deprecation notice to top of `experiment_utils.R`:
  ```r
  #' @file experiment_utils.R
  #' @deprecated This file contains legacy functions from the R&D phase.
  #' For new code, use experiment_logger.R and experiment_queries.R instead.
  ```

### Priority 3: Archive Old Scripts (15 min)
- [ ] Create `scripts/archive/` directory
- [ ] Move 4 old benchmark scripts to archive
- [ ] Add `scripts/archive/README.md`:
  ```markdown
  # Archived Scripts

  These scripts are from the pre-YAML experiment system.
  They are preserved for reference only.

  **DO NOT USE THESE SCRIPTS**

  Use `scripts/run_experiment.R` instead.
  ```

---

## File-by-File Recommendations

### R/ Directory

| File | Action | Reason |
|------|--------|--------|
| `build_prompt.R` | **Keep** | Core functionality |
| `call_llm.R` | **Keep** | Core functionality |
| `parse_llm_result.R` | **Keep** | Core functionality |
| `metrics.R` | **Keep** | Core functionality |
| `utils.R` | **Keep** | Core functionality |
| `db_schema.R` | **Keep** | New system |
| `data_loader.R` | **Keep** | New system |
| `config_loader.R` | **Keep** | New system |
| `experiment_logger.R` | **Keep** | New system |
| `experiment_queries.R` | **Keep** | New system |
| `run_benchmark_core.R` | **Keep** | New system |
| `db_utils.R` | **Move to legacy/** | Old, conflicts with db_schema.R |
| `experiment_utils.R` | **Move to legacy/** | Old, conflicts with experiment_logger.R |
| `experiment_analysis.R` | **Review & merge** | May have useful functions for experiment_queries.R |
| `store_llm_result.R` | **Move to legacy/** | Old storage logic |
| `call_llm_batch.R` | **Review usage** | If unused, move to legacy/ |
| `0_setup.R` | **Remove** | Obsolete |

### scripts/ Directory

| File | Action | Reason |
|------|--------|--------|
| `run_experiment.R` | **Keep** | Current system |
| `init_database.R` | **Keep** | Current system |
| `run_benchmark*.R` (4 files) | **Archive** | Superseded by run_experiment.R |
| `migrate_sqlite_to_postgres.R` | **Archive** | One-time migration tool |

### New Files Needed

- [ ] `scripts/cleanup_logs.R` (from plan)
- [ ] `scripts/compare_experiments.R` (from plan)
- [ ] `R/legacy/README.md` (explains legacy code)
- [ ] `docs/MIGRATION.md` (migration guide)

---

## Risks of Current Mess

1. **Accidental usage of wrong function** - Name collisions cause unpredictable behavior
2. **Maintenance burden** - Hard to know which code to update
3. **Onboarding nightmare** - New contributors confused about which files to use
4. **Technical debt** - Mess grows over time if not addressed
5. **Testing gaps** - Can't test effectively with duplicate functions

---

## Benefits of Cleanup

1. **Clear structure** - Obvious which files do what
2. **No collisions** - One function, one name
3. **Easy maintenance** - Know exactly which code is active
4. **Better testing** - Can test without ambiguity
5. **Faster onboarding** - New contributors see clean structure

---

## Estimated Cleanup Time

| Phase | Time | Priority |
|-------|------|----------|
| Phase 1: Separate old/new | 1-2 hours | HIGH |
| Phase 2: Consolidate scripts | 1 hour | HIGH |
| Phase 3: Resolve conflicts | 2 hours | CRITICAL |
| Phase 4: Update docs | 1 hour | MEDIUM |
| Phase 5: Add tests | 1 hour | MEDIUM |
| **Total** | **6-7 hours** | |

---

## Decision Points

Before proceeding, answer these questions:

### Q1: Keep or Remove?
- **`call_llm_batch.R`** - Is this used anywhere? If not, archive it.
- **`experiment_analysis.R`** - Are these functions needed? Can they merge into `experiment_queries.R`?
- **`migrate_sqlite_to_postgres.R`** - Still needed or one-time use?

### Q2: PostgreSQL Support
- **`db_utils.R`** has PostgreSQL code. Do you still need PostgreSQL support?
  - **If YES**: Keep but refactor to avoid conflicts
  - **If NO**: Archive the PostgreSQL code

### Q3: Legacy Function Deprecation
- Should legacy functions:
  - **Option A**: Show warnings but still work (gentle migration)
  - **Option B**: Throw errors immediately (force migration)
  - **Recommendation**: Option A for now, Option B after 1-2 months

---

## Next Steps

1. **Review this document** - Confirm the analysis is accurate
2. **Answer decision points** - Clarify PostgreSQL, batch processing needs
3. **Execute Phase 1-2** - Quick wins (archive scripts, mark deprecated)
4. **Schedule Phase 3** - Resolve function conflicts (requires careful testing)
5. **Update CLAUDE.md** - Add "File Organization" section with clear rules

---

## Conclusion

The code **works**, but it's **organized poorly**. This is typical of fast iteration - you built features quickly, now it's time to consolidate.

**Recommendation**: Spend **one focused session** (6-7 hours) to clean this up **now**, before it gets worse. The longer you wait, the harder it becomes.

The new experiment system (YAML-based) is good. The core IPV detection is solid. The problem is the **transition period** - half old, half new. Clean separation will make everything easier.

**Key principle**: Keep it **minimal** (align with CLAUDE.md). Archive, don't delete. Deprecate, don't break.
