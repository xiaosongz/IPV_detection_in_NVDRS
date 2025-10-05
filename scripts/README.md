# Scripts Directory Documentation

**Purpose**: Entry points and orchestration workflows for IPV detection experiments

**Usage Pattern**: Scripts are executed from command line using `Rscript` or shell interpreters. All scripts handle their own function sourcing via `source()` calls to the `R/` directory.

---

## Script Categories

### 1. Core Experiment Scripts
| Script | Purpose | Runtime | Dependencies |
|--------|---------|---------|--------------|
| `run_experiment.R` | Main experiment runner with YAML config | 1-60 min | R, SQLite, API access |
| `demo_workflow.R` | Quick demonstration for reviewers | <5 min | R, SQLite (optional API) |
| `view_experiment.R` | Results visualization and analysis | <1 min | R, SQLite |

### 2. Batch Execution Scripts
| Script | Purpose | Runtime | Dependencies |
|--------|---------|---------|--------------|
| `run_experiments_007_018.sh` | Batch experiments 007-018 | 2-4 hours | R, SQLite, API access |
| `run_experiments_019_021.sh` | Batch experiments 019-021 | 30-60 min | R, SQLite, API access |
| `run_experiments_022_036.sh` | Batch experiments 022-036 | 1-2 hours | R, SQLite, API access |
| `run_experiments_037_051.sh` | Batch experiments 037-051 | 1-2 hours | R, SQLite, API access |

### 3. Utility Scripts
| Script | Purpose | Runtime | Dependencies |
|--------|---------|---------|--------------|
| `sync_sqlite_to_postgres.sh` | Database synchronization | 5-30 min | PostgreSQL, psql |
| `run_benchmark_core.R` | Core benchmark execution (legacy) | 1-30 min | R, SQLite, API access |

---

## Detailed Script Documentation

### Core Experiment Scripts

#### `run_experiment.R`
**Main orchestrator for running experiments with database tracking**

**Usage**:
```bash
Rscript scripts/run_experiment.R <config.yaml>
```

**Examples**:
```bash
# Single experiment
Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml

# Test with synthetic data
Rscript scripts/run_experiment.R configs/experiments/exp_001_test_gpt_oss.yaml
```

**Workflow**:
1. Load and validate YAML configuration
2. Initialize database connection
3. Load source data (Excel/CSV)
4. Register experiment in database
5. Process narratives (batch or parallel)
6. Store results with metrics
7. Generate summary statistics

**Key Features**:
- Config-driven experiments via YAML
- Automatic database schema management
- Progress tracking and incremental saves
- Error handling and recovery
- Performance metrics (F1, precision, recall)
- Token usage tracking

**Runtime Expectations**:
- Small test (10 narratives): 1-5 minutes
- Medium experiment (100 narratives): 10-30 minutes
- Large experiment (1000+ narratives): 30-60 minutes

**Dependencies**:
- R packages: DBI, RSQLite, yaml, httr2, jsonlite
- Database: SQLite (automatically created)
- Optional: PostgreSQL (for sync)
- LLM API: OpenAI/Anthropic/local endpoint

---

#### `demo_workflow.R`
**Quick demonstration script for reviewer testing**

**Usage**:
```bash
Rscript scripts/demo_workflow.R
```

**Purpose**: Demonstrate full system functionality without requiring NVDRS access or API keys

**Workflow**:
1. Load synthetic example data (30 narratives)
2. Initialize demo database
3. Create demo configuration
4. Run small sample (10 narratives)
5. Generate basic metrics
6. Display results summary

**Key Features**:
- No API keys required (mock mode)
- Uses synthetic data only
- Completes in <5 minutes
- Self-contained demo database
- Basic accuracy metrics

**Runtime**: 2-5 minutes
**Output**: Demo database (`data/demo_experiments.db`) + console metrics

---

#### `view_experiment.R`
**Results visualization and analysis tool**

**Usage**:
```bash
Rscript scripts/view_experiment.R <experiment_id>
Rscript scripts/view_experiment.R <experiment_name>
```

**Examples**:
```bash
# View by ID
Rscript scripts/view_experiment.R exp_001_20241005_143022

# View by name (most recent)
Rscript scripts/view_experiment.R demo_synthetic_test

# List all experiments
Rscript scripts/view_experiment.R
```

**Features**:
- Experiment summary with metrics
- Prediction distribution
- Confidence score analysis
- Error case breakdown
- Narrative examples (true/false positives/negatives)

**Output**: Console report + optional CSV export

---

### Batch Execution Scripts

#### `run_experiments_037_051.sh`
**Batch execution for experiments 037-051 (baseline v4 series)**

**Usage**:
```bash
bash scripts/run_experiments_037_051.sh
```

**Coverage**:
- Experiments 037-039: Baseline v4 (T=0.0, 0.2, 0.8)
- Experiments 040-042: Indicators v4 (T=0.0, 0.2, 0.8)
- Experiments 043-045: Strict v4 (T=0.0, 0.2, 0.8)
- Experiments 046-048: Context v4 (T=0.0, 0.2, 0.8)
- Experiments 049-051: Chain-of-thought v4 (T=0.0, 0.2, 0.8)

**Runtime**: 1-2 hours
**Purpose**: Complete prompt version comparison with consistent temperature testing

---

#### `run_experiments_022_036.sh`
**Batch execution for experiments 022-036 (Qwen model series)**

**Usage**:
```bash
bash scripts/run_experiments_022_036.sh
```

**Coverage**:
- Experiments 022-024: Qwen baseline
- Experiments 025-027: Qwen indicators
- Experiments 028-030: Qwen strict
- Experiments 031-033: Qwen context
- Experiments 034-036: Qwen chain-of-thought

**Runtime**: 1-2 hours
**Purpose**: Cross-model comparison using Qwen models

---

#### `run_experiments_007_018.sh`
**Batch execution for experiments 007-018 (early baseline series)**

**Usage**:
```bash
bash scripts/run_experiments_007_018.sh
```

**Coverage**:
- Experiments 007-009: Baseline (T=0.0, 0.2, 0.8)
- Experiments 010-012: Indicators (T=0.0, 0.2, 0.8)
- Experiments 013-015: Strict (T=0.0, 0.2, 0.8)
- Experiments 016-018: Context (T=0.0, 0.2, 0.8)

**Runtime**: 2-4 hours
**Purpose**: Original prompt engineering series

---

#### `run_experiments_019_021.sh`
**Batch execution for experiments 019-021 (early chain-of-thought)**

**Usage**:
```bash
bash scripts/run_experiments_019_021.sh
```

**Coverage**:
- Experiments 019-021: Chain-of-thought (T=0.0, 0.2, 0.8)

**Runtime**: 30-60 minutes
**Purpose**: Initial chain-of-thought testing

---

### Utility Scripts

#### `sync_sqlite_to_postgres.sh`
**Database synchronization utility**

**Usage**:
```bash
# With environment variables
PG_CONN_STR=postgresql://user:pass@host:5433/db scripts/sync_sqlite_to_postgres.sh

# With individual variables
PG_HOST=localhost PG_PORT=5433 PG_USER=user PG_PASSWORD=pass PG_DATABASE=db scripts/sync_sqlite_to_postgres.sh
```

**Purpose**: Mirror SQLite results to PostgreSQL for dashboards and advanced analytics

**Features**:
- Automatic table creation
- Incremental sync (only new experiments)
- Data validation and integrity checks
- Progress reporting
- Error handling and rollback

**Runtime**: 5-30 minutes (depends on data volume)

**Environment Variables**:
- `PG_HOST`: PostgreSQL server host
- `PG_PORT`: PostgreSQL server port (default: 5432)
- `PG_USER`: PostgreSQL username
- `PG_PASSWORD`: PostgreSQL password
- `PG_DATABASE`: PostgreSQL database name
- `PG_CONN_STR`: Complete connection string (overrides individual vars)

---

## Workflow Sequences

### For Reviewers (Quick Validation)
```bash
# 1. Clone and setup
git clone <repository>
cd IPV_detection_in_NVDRS
Rscript -e "renv::restore()"

# 2. Run demo (no API keys needed)
Rscript scripts/demo_workflow.R

# 3. View demo results
Rscript scripts/view_experiment.R demo_synthetic_test
```

### For Researchers (Full Analysis)
```bash
# 1. Setup environment
cp .env.example .env
# Edit .env with API keys

# 2. Run single experiment
Rscript scripts/run_experiment.R configs/experiments/exp_037_baseline_v4_t00_medium.yaml

# 3. View results
Rscript scripts/view_experiment.R exp_037_baseline_v4_t00_medium

# 4. Run batch experiments
bash scripts/run_experiments_037_051.sh

# 5. Sync to PostgreSQL (optional)
PG_CONN_STR=postgresql://user:pass@host:5433/db scripts/sync_sqlite_to_postgres.sh
```

### For Production Runs (Large Scale)
```bash
# 1. Prepare environment
export OPENAI_API_KEY=your_key_here
export ANTHROPIC_API_KEY=your_key_here

# 2. Run all experiments
for batch in 007_018 019_021 022_036 037_051; do
  echo "Running batch: $batch"
  bash scripts/run_experiments_${batch}.sh
done

# 3. Sync results
PG_CONN_STR=postgresql://user:pass@host:5433/db scripts/sync_sqlite_to_postgres.sh

# 4. Generate analysis reports
Rscript -e "rmarkdown::render('analysis/20251005-experiment_comparison.Rmd')"
```

---

## Script Execution Best Practices

### Before Running Scripts
1. **Check Dependencies**: Ensure R packages are installed (`renv::restore()`)
2. **Verify Configuration**: Check `.env` file for API keys and database settings
3. **Validate Data**: Ensure source data files exist and are readable
4. **Check Disk Space**: Large experiments require several GB of free space

### During Execution
1. **Monitor Progress**: Scripts provide progress updates and timestamps
2. **Check Logs**: Experiment logs stored in `logs/experiments/<experiment_id>/`
3. **Handle Interruptions**: Scripts can be resumed using experiment IDs
4. **Resource Monitoring**: Watch memory usage for large datasets

### After Execution
1. **Verify Results**: Use `view_experiment.R` to check outcomes
2. **Backup Data**: Copy `data/experiments.db` for safekeeping
3. **Document Findings**: Update analysis notebooks with insights
4. **Clean Up**: Remove temporary files if needed

---

## Error Handling and Troubleshooting

### Common Issues
1. **API Key Errors**: Check `.env` file and API service status
2. **Database Locks**: Close all R sessions and retry
3. **Memory Issues**: Reduce `max_narratives` in config
4. **Network Timeouts**: Increase timeout values or check internet connection

### Recovery Procedures
1. **Failed Experiments**: Check logs in `logs/experiments/<experiment_id>/`
2. **Partial Results**: Use `view_experiment.R` to see completed work
3. **Database Corruption**: Restore from backup or reinitialize
4. **Package Conflicts**: Use `renv::restore()` to reset environment

### Support Resources
- **Test Suite**: `Rscript -e "testthat::test_dir('tests/testthat')"`
- **Integration Tests**: `Rscript tests/integration/run_integration_tests.R`
- **Documentation**: See `docs/` directory with `YYYYMMDD-` prefix
- **Configuration Examples**: See `configs/experiments/` directory

---

## Script Maintenance

### Adding New Scripts
1. Follow existing naming conventions
2. Include comprehensive header comments
3. Add error handling and logging
4. Update this README.md
5. Add tests to `tests/` directory

### Modifying Existing Scripts
1. Check for dependent scripts
2. Update documentation
3. Test with synthetic data first
4. Run full test suite
5. Update version in git

### Performance Optimization
1. Use parallel processing for large datasets
2. Implement incremental saving
3. Optimize database queries
4. Monitor memory usage
5. Profile execution time

---

**Last Updated**: October 5, 2025  
**Maintainer**: Research Team  
**Version**: 1.0 (Research Compendium)
```

Now let me add comprehensive header comments to all the scripts. Let me start with the main ones:
