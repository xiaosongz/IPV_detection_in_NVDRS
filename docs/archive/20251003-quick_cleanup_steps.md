# Quick Cleanup Steps (30 minutes)

**Goal**: Quick wins to reduce confusion immediately, without breaking anything.

---

## Step 1: Archive Old Benchmark Scripts (5 min)

```bash
# Create archive directory
mkdir -p scripts/archive

# Move old scripts
mv scripts/run_benchmark.R scripts/archive/
mv scripts/run_benchmark_optimized.R scripts/archive/
mv scripts/run_benchmark_updated.R scripts/archive/
mv scripts/run_benchmark_andrea_09022025.R scripts/archive/

# Create README
cat > scripts/archive/README.md <<'EOF'
# Archived Scripts

These scripts are from the pre-YAML experiment tracking system (Aug-Sep 2025).

**DO NOT USE THESE SCRIPTS**

They have been superseded by the new YAML-based system.

## Use Instead

```bash
# New way (recommended):
Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
```

## What These Did

- `run_benchmark.R` - Original benchmark runner
- `run_benchmark_optimized.R` - Optimized version with batching
- `run_benchmark_updated.R` - Updated version
- `run_benchmark_andrea_09022025.R` - Andrea's experimental version

All functionality is now available through `run_experiment.R` with YAML configs.
EOF

echo "✅ Step 1 complete: Scripts archived"
```

---

## Step 2: Add scripts/README.md (5 min)

```bash
cat > scripts/README.md <<'EOF'
# Scripts Directory

## Active Scripts (Use These)

### run_experiment.R
Main experiment runner. Runs experiments from YAML configuration files.

**Usage**:
```bash
Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
```

**What it does**:
1. Loads data from Excel into SQLite (first time only)
2. Runs LLM on all narratives
3. Saves results to database
4. Computes performance metrics

### init_database.R
One-time database initialization.

**Usage**:
```bash
Rscript scripts/init_database.R
```

## Archived Scripts

See `archive/` directory for old scripts. Do not use.

## Coming Soon

- `cleanup_logs.R` - Clean up old experiment logs
- `compare_experiments.R` - Compare multiple experiments
EOF

echo "✅ Step 2 complete: README added"
```

---

## Step 3: Mark Legacy R Files (10 min)

Add deprecation notices to old files:

```bash
# Add notice to experiment_utils.R
cat > /tmp/deprecation_notice.txt <<'EOF'
#' @file experiment_utils.R
#' @section DEPRECATED:
#' **This file contains legacy functions from the R&D phase (Aug 2025).**
#'
#' For new code, use:
#' - `experiment_logger.R` for experiment tracking
#' - `experiment_queries.R` for querying results
#'
#' This file will be moved to R/legacy/ in the next cleanup cycle.
#'
EOF

# Prepend to file (macOS/BSD sed syntax)
sed -i '.bak' '1r /tmp/deprecation_notice.txt' R/experiment_utils.R

# Same for db_utils.R
cat > /tmp/deprecation_notice_db.txt <<'EOF'
#' @file db_utils.R
#' @section DEPRECATED:
#' **This file contains legacy database utilities (pre-Oct 2025).**
#'
#' For new code, use:
#' - `db_schema.R` for database schema management
#' - `data_loader.R` for loading data
#'
#' This file will be moved to R/legacy/ in the next cleanup cycle.
#'
EOF

sed -i '.bak' '1r /tmp/deprecation_notice_db.txt' R/db_utils.R

echo "✅ Step 3 complete: Deprecation notices added"
```

---

## Step 4: Update Main README.md (10 min)

Add clear usage instructions to the main README:

```bash
# Add this section to README.md after the installation section:

cat >> README.md <<'EOF'

## Quick Start: Running Experiments

### New System (Recommended)

The project now uses a YAML-based experiment tracking system.

**1. Initialize database (first time only)**:
```bash
Rscript scripts/init_database.R
```

**2. Create experiment config**:
```bash
# Copy template
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_experiment.yaml

# Edit your config
# - Change model name
# - Adjust temperature
# - Modify prompts
```

**3. Run experiment**:
```bash
Rscript scripts/run_experiment.R configs/experiments/my_experiment.yaml
```

**4. Query results**:
```r
library(DBI)
library(RSQLite)

conn <- dbConnect(RSQLite::SQLite(), "experiments.db")

# List all experiments
dbGetQuery(conn, "SELECT experiment_id, experiment_name, f1_ipv, recall_ipv
                  FROM experiments ORDER BY created_at DESC")

# Get detailed results
dbGetQuery(conn, "SELECT * FROM narrative_results WHERE experiment_id = 'YOUR_ID'")

dbDisconnect(conn)
```

### Old System (Deprecated)

Old `run_benchmark*.R` scripts in `scripts/archive/` are deprecated.
Do not use them for new experiments.

---

EOF

echo "✅ Step 4 complete: README updated"
```

---

## Step 5: Commit Changes (5 min)

```bash
git add -A
git commit -m "Cleanup: Archive old scripts and add documentation

- Moved old benchmark scripts to scripts/archive/
- Added scripts/README.md with clear usage instructions
- Added deprecation notices to experiment_utils.R and db_utils.R
- Updated main README.md with new system instructions

This is part of code organization cleanup (see docs/20251003-code_organization_review.md)
"

echo "✅ Step 5 complete: Changes committed"
```

---

## Verification

After running these steps, verify:

```bash
# 1. Check archive was created
ls -la scripts/archive/

# 2. Check READMEs exist
cat scripts/README.md
cat scripts/archive/README.md

# 3. Check deprecation notices
head -20 R/experiment_utils.R
head -20 R/db_utils.R

# 4. Verify nothing broke
Rscript -e "library(IPVdetection); packageVersion('IPVdetection')"

echo "✅ All steps verified"
```

---

## What This Accomplishes

1. **Immediate clarity** - Users know which scripts to use
2. **No breakage** - Old code still works, just marked deprecated
3. **Clear migration path** - Documentation shows new vs old
4. **Git history** - Changes are documented and reversible

## What It Doesn't Do

- Doesn't resolve function name collisions (Phase 3 of full cleanup)
- Doesn't remove old code (just archives/marks it)
- Doesn't create new R/legacy/ directory structure

**For full cleanup**, see `docs/20251003-code_organization_review.md`

---

## Time Estimate

- **Actual work**: 15-20 minutes
- **Testing/verification**: 5-10 minutes
- **Total**: 20-30 minutes

## Safety

All changes are:
- **Reversible** (git)
- **Non-breaking** (no code deletion)
- **Documented** (READMEs and commit messages)

If anything goes wrong:
```bash
git reset --hard HEAD~1
```
