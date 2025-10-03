# Legacy R Code Archive

**Status**: ARCHIVED - DO NOT USE  
**Date Archived**: October 3, 2025  
**Reason**: Superseded by new YAML-based experiment system

---

## Files in This Directory

### 0_setup.R
**What it was**: Old setup script from early development  
**Why archived**: Not used in current pipeline  
**Replaced by**: scripts/init_database.R

### call_llm_batch.R
**What it was**: Batch processing for LLM calls  
**Why archived**: Unused feature, adds complexity  
**Replaced by**: run_benchmark_core.R processes narratives sequentially with proper logging

### db_utils.R (22 KB)
**What it was**: Original database utilities supporting PostgreSQL + SQLite  
**Why archived**: **Function name collision** with db_schema.R  
**Key conflicts**:
- `get_db_connection()` - Different signature than db_schema::get_db_connection()
**Replaced by**: db_schema.R (SQLite-focused, simpler)

### experiment_analysis.R (17 KB)
**What it was**: OLD analysis functions for experiments  
**Why archived**: Duplicates and overlaps with experiment_queries.R  
**Replaced by**: experiment_queries.R (cleaner, focused on new system)

### experiment_utils.R (16 KB) ⚠️ CRITICAL COLLISION
**What it was**: OLD R&D phase experiment tracking  
**Why archived**: **CRITICAL - Function name collisions**  
**Key conflicts**:
- `start_experiment()` - Different signature than experiment_logger::start_experiment()
- `list_experiments()` - Different signature than experiment_queries::list_experiments()
**Replaced by**: experiment_logger.R + experiment_queries.R

### store_llm_result.R (13 KB)
**What it was**: OLD result storage logic  
**Why archived**: Uses old database schema, conflicts with new approach  
**Replaced by**: experiment_logger::log_narrative_result()

---

## Why These Were Archived

### 1. Function Name Collisions
The biggest problem was **multiple functions with the same name** in different files:

```r
# OLD (experiment_utils.R)
start_experiment <- function(name, ...) { ... }

# NEW (experiment_logger.R)  
start_experiment <- function(conn, config) { ... }
```

R doesn't handle this well - whichever file loads last "wins", causing unpredictable behavior.

### 2. Two Different Paradigms
- **OLD**: Direct function calls, manual tracking, PostgreSQL support
- **NEW**: YAML configs, automatic tracking, SQLite-only, comprehensive logging

Trying to support both was creating confusion and maintenance burden.

### 3. Unused Features
- Batch processing (call_llm_batch.R) - never used
- PostgreSQL support (db_utils.R) - never deployed
- Complex analysis (experiment_analysis.R) - overlaps with simpler approach

---

## Migration Guide

If you have code using these functions:

| Old Function | New Function | Notes |
|--------------|--------------|-------|
| `experiment_utils::start_experiment()` | `experiment_logger::start_experiment()` | Different signature - takes conn + config |
| `experiment_utils::list_experiments()` | `experiment_queries::list_experiments()` | Same purpose, different impl |
| `db_utils::get_db_connection()` | `db_schema::get_db_connection()` | SQLite only, simpler |
| `store_llm_result::store_result()` | `experiment_logger::log_narrative_result()` | Integrated with new system |
| (no equivalent) | `run_experiment.R` | Use YAML config instead of direct calls |

---

## Can These Be Restored?

**Short answer**: Only if absolutely necessary, and with careful refactoring.

**Long answer**: 
- These files represent the R&D phase (Aug 2025)
- They were useful for exploration but added complexity
- The new system (Oct 2025) is cleaner and more maintainable
- If you need PostgreSQL support → Extract from db_utils.R
- If you need batch processing → Extract from call_llm_batch.R
- If you need specific analysis → Extract from experiment_analysis.R

**Better approach**: Extend the new system rather than restore old code.

---

## Preservation Rationale

These files are preserved (not deleted) for:

1. **Historical reference** - Understanding how the system evolved
2. **Code extraction** - If specific logic needs to be recovered
3. **Documentation** - Learning from what didn't work
4. **Reversibility** - Can restore if absolutely needed (but shouldn't)

---

## Future Plans

- **November 2025**: Review if any functions should be extracted and added to new system
- **December 2025**: If unused, consider removing entirely from git history
- **January 2026**: Decision on PostgreSQL support (if needed, refactor db_utils.R)

---

## Related Documentation

- [Code Organization Review](../../docs/20251003-code_organization_review.md) - Why cleanup was needed
- [Cleanup Summary](../../docs/20251003-cleanup_complete_summary.md) - What was done
- [New System Guide](../../docs/20251003-phase1_implementation_complete.md) - How new system works

---

**Last Updated**: October 3, 2025  
**Archived By**: Cleanup process  
**Status**: Preserved for reference only
