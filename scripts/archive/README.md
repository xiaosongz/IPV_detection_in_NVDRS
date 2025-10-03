# Archived Scripts

These scripts are from the pre-YAML experiment tracking system (Aug-Sep 2025).

**DO NOT USE THESE SCRIPTS**

They have been superseded by the new YAML-based system.

## Use Instead

```bash
# New way (recommended):
Rscript scripts/run_experiment.R configs/experiments/exp_001.yaml
```

**That's it!** The script handles everything automatically:
- Database initialization (first time)
- Data loading (first time)
- LLM processing
- Logging
- Metrics computation
- Result storage

## What These Did

### Benchmark Scripts (Archived Aug-Sep 2025)
- `run_benchmark.R` - Original benchmark runner
- `run_benchmark_optimized.R` - Optimized version with batching
- `run_benchmark_updated.R` - Updated version
- `run_benchmark_andrea_09022025.R` - Andrea's experimental version

### Utility Scripts (Archived Oct 2025)
- `migrate_sqlite_to_postgres.R` - One-time PostgreSQL migration tool (unused)
- `init_database.R` - Standalone database initializer (now built into run_experiment.R)

All functionality is now available through `run_experiment.R` with YAML configs.

## Why Archived

These scripts had similar functionality with slight variations, causing confusion about which one to use. The new system consolidates everything into a single, configuration-driven approach.

### Old System Problems
- Manual script editing required for each experiment
- No systematic tracking
- Results only in CSV/JSON (no database)
- Hard to compare experiments
- Configuration embedded in code

### New System Benefits
- YAML configuration files (easy to version control)
- Full database tracking
- Comprehensive logging
- Easy experiment comparison
- No code changes needed

## Preservation Rationale

These files are preserved for:
1. **Reference** - Understanding evolution of the system
2. **Recovery** - If specific logic needs to be extracted
3. **Documentation** - Historical record of approaches tried

Last used: September 2025  
Archived: October 3, 2025
