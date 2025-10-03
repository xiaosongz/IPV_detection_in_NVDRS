# Scripts Directory

## Active Scripts (Use These)

### run_experiment.R ⭐
Main experiment runner. Runs experiments from YAML configuration files.

**Usage**:
```bash
Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
```

**What it does**:
1. Loads data from Excel into SQLite (first time only)
2. Runs LLM on specified narratives
3. Logs all details (4 log files per experiment)
4. Saves results to database
5. Computes performance metrics (precision, recall, F1)
6. Optionally exports CSV/JSON

**Input**: YAML configuration file  
**Output**: Database records + optional CSV/JSON files

### init_database.R
One-time database initialization.

**Usage**:
```bash
Rscript scripts/init_database.R [optional_db_path]
```

**What it does**:
- Creates `experiments.db` with 3 tables
- Sets up indexes for fast queries
- Shows table schemas

**When to use**: First time setup, or to recreate database

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

## Workflow

**Typical workflow**:

```bash
# 1. Initialize database (first time only)
Rscript scripts/init_database.R

# 2. Create experiment config
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_exp.yaml
# Edit my_exp.yaml with your settings

# 3. Run experiment  
Rscript scripts/run_experiment.R configs/experiments/my_exp.yaml

# 4. Query results
sqlite3 experiments.db "SELECT * FROM experiments ORDER BY created_at DESC LIMIT 1;"
```

## Troubleshooting

**Script not found**: Make sure you're in the project root directory

**Database error**: Run `init_database.R` first

**LLM API error**: Check that LM Studio is running at http://localhost:1234

**Config error**: Validate YAML syntax and file paths

See [Testing Instructions](../docs/20251003-testing_instructions.md) for more help.
