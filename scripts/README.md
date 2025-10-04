# Scripts Directory

## Active Scripts

### run_experiment.R ⭐ **Main Workflow**
Main experiment runner. Runs experiments from YAML configuration files.

**Usage**:
```bash
Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
```

**What it does**:
1. **Auto-initializes database** (first time only)
2. Loads data from Excel into SQLite (first time only)
3. Runs LLM on specified narratives
4. Logs all details (4 log files per experiment)
5. Saves results to database
6. Computes performance metrics (precision, recall, F1)
7. Optionally exports CSV/JSON

**Input**: YAML configuration file  
**Output**: Database records + optional CSV/JSON files

**Note**: No setup needed! The script handles everything automatically.

### view_experiment.R 🔍 **Query Results**
View comprehensive details about completed experiments.

**Usage**:
```bash
# View latest experiment
Rscript scripts/view_experiment.R latest

# View specific experiment (use UUID from database)
Rscript scripts/view_experiment.R 60376368-2f1b-4b08-81a9-2f0ea815cd21

# List recent experiments
Rscript scripts/view_experiment.R
```

**What it shows**:
- Model configuration (name, temperature, API URL)
- Complete prompts (system + user templates)
- Data processing stats (total, processed, skipped)
- Performance metrics (accuracy, precision, recall, F1)
- Confusion matrix (TP, TN, FP, FN)
- Timing information (runtime, avg per narrative)
- Output file locations (CSV, JSON, logs)
- System info (R version, OS, hostname)

**Use cases**:
- Quick status check of running experiments
- Review completed experiment details
- Find output files for specific runs
- Compare prompts across experiments
- Document results for papers/reports

**See also**: [Experiment ID Guide](../docs/20251003-experiment_id_guide.md) for understanding UUIDs and querying experiments.

## Archived Scripts

See `archive/` directory for old scripts (pre-Oct 2025). **Do not use.**

The old scripts required manual editing for each experiment. The new system uses YAML configs instead.

## Coming Soon

Planned utilities (not yet implemented):

- `cleanup_logs.R` - Clean up old experiment logs
- `compare_experiments.R` - Interactive comparison tool
- `export_results.R` - Export to various formats

## Configuration Files

Experiment configs are stored in `configs/experiments/`:

- `exp_001_test_gpt_oss.yaml` - Template for GPT-OSS-120B experiments
- Create new configs by copying and editing templates

See [YAML Configuration Guide](../docs/20251003-unified_experiment_automation_plan.md) for details.

**Database location**: Configured in `.db_config` file (defaults to `data/experiments.db`)

## Workflow

**Typical workflow**:

```bash
# 1. Create experiment config
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_exp.yaml
# Edit my_exp.yaml with your settings

# 2. Run experiment
Rscript scripts/run_experiment.R configs/experiments/my_exp.yaml

# 3. View results
Rscript scripts/view_experiment.R latest
```

**Note**: No initialization step needed! The script does it automatically.

## Troubleshooting

**Script not found**: Make sure you're in the project root directory

**Database location**: Check `.db_config` file or run `Rscript -e 'source("R/db_config.R"); print_db_config()'`

**LLM API error**: Check that LM Studio is running at http://localhost:1234

**Config error**: Validate YAML syntax and file paths

**Experiment ID questions**: See [Experiment ID Guide](../docs/20251003-experiment_id_guide.md)

See [Testing Instructions](../docs/20251003-testing_instructions.md) for more help.

### sync_sqlite_to_postgres.sh 🔄 **Database Sync**
Syncs SQLite experiment database to PostgreSQL for analytics and visualization.

**Configuration**:
The script reads PostgreSQL connection settings from `.env` file in the repository root:
```bash
# .env file
PG_CONN_STR=postgresql://postgres:password@host:5433/postgres
```

**Usage**:
```bash
# Incremental sync (default - FAST, only syncs changes)
scripts/sync_sqlite_to_postgres.sh

# Full refresh (slower, drops and recreates tables)
FULL_REFRESH=1 scripts/sync_sqlite_to_postgres.sh

# Delete orphaned rows (rows in Postgres but not in SQLite)
DELETE_ORPHANS=1 scripts/sync_sqlite_to_postgres.sh

# Custom batch size for streaming
BATCH_SIZE=5000 scripts/sync_sqlite_to_postgres.sh

# Specify SQLite database path
scripts/sync_sqlite_to_postgres.sh /path/to/custom.db

# Override connection string (bypasses .env)
PG_CONN_STR=postgresql://user:pass@host:port/db scripts/sync_sqlite_to_postgres.sh
```

**Environment variables**:
- `PG_CONN_STR` - PostgreSQL connection string (reads from `.env` by default)
- `FULL_REFRESH` - Set to `1` for drop/recreate (default: `0` for incremental UPSERT)
- `DELETE_ORPHANS` - Set to `1` to remove Postgres rows not in SQLite (default: `0`)
- `BATCH_SIZE` - Rows per batch for streaming (default: `1000`)

**How it works**:

**Incremental Mode (default)**:
- Uses `INSERT ... ON CONFLICT DO UPDATE` (UPSERT) for all rows
- Streams data in batches to avoid memory issues
- Only updates changed rows based on primary keys
- ⚡ Much faster for large databases with small changes
- Keeps indexes intact (no rebuilding)
- Safe for concurrent reads

**Full Refresh Mode** (`FULL_REFRESH=1`):
- Drops and recreates all tables
- Reloads all data from scratch
- Rebuilds all indexes
- Use when schema changes or data corruption suspected
- First run auto-triggers full refresh if tables don't exist

**Orphan Cleanup** (`DELETE_ORPHANS=1`):
- Finds rows in Postgres not present in SQLite
- Deletes them to keep databases in sync
- Useful if you delete experiments from SQLite
- Only runs in incremental mode

**Performance**:
- Incremental: ~1-5 seconds for typical updates
- Full refresh: ~30-60 seconds for 100K rows
- Batch streaming prevents OOM on large datasets

**Requirements**:
- Python 3 with `psycopg[binary]` package
- Install: `pip3 install --user psycopg[binary]`

**Output**:
```
⚡ INCREMENTAL mode: using UPSERT for existing tables
📥 Syncing source_narratives...
✓ source_narratives: 1234 rows synced
📥 Syncing experiments...
✓ experiments: 42 rows synced
📥 Syncing narrative_results...
   ... 10000 rows synced
✓ narrative_results: 52341 rows synced
📇 Creating indexes...
============================================================
SQLite counts: experiments=42 narrative_results=52341 source_narratives=1234
PostgreSQL before/after:
  experiments: 40 -> 42 (synced 42)
  narrative_results: 50000 -> 52341 (synced 52341)
  source_narratives: 1200 -> 1234 (synced 1234)
  size bytes: 45678901 -> 48123456 (delta +2444555)

⚡ Incremental sync: 2345 UPSERTs performed
============================================================
✅ PostgreSQL sync complete.
Sync duration: 3 seconds
```
