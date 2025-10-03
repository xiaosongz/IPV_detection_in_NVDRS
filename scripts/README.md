# Scripts Directory

## Active Script (Only One!)

### run_experiment.R ⭐ **This is All You Need**
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

**Typical workflow** (Just 2 steps!):

```bash
# 1. Create experiment config
cp configs/experiments/exp_001_test_gpt_oss.yaml configs/experiments/my_exp.yaml
# Edit my_exp.yaml with your settings

# 2. Run experiment (that's it!)
Rscript scripts/run_experiment.R configs/experiments/my_exp.yaml

# 3. Query results
sqlite3 experiments.db "SELECT * FROM experiments ORDER BY created_at DESC LIMIT 1;"
```

**Note**: No initialization step needed! The script does it automatically.

## Troubleshooting

**Script not found**: Make sure you're in the project root directory

**Database error**: Run `init_database.R` first

**LLM API error**: Check that LM Studio is running at http://localhost:1234

**Config error**: Validate YAML syntax and file paths

See [Testing Instructions](../docs/20251003-testing_instructions.md) for more help.
