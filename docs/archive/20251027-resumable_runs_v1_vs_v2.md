# Resumable Runs Plan: v1 vs v2 Comparison

**Date**: 2025-10-27

## Overview

**v1** (9.6KB): Initial design with basic resume logic
**v2** (33KB): Production-ready with safety, monitoring, and error handling

## Key Additions in v2

### 1. Data Integrity Layer (NEW) 🔒

**Problem**: v1 didn't verify data file consistency across resume attempts.

**v2 Solution**:
```sql
ALTER TABLE source_narratives ADD COLUMN data_checksum TEXT;
```

- Calculates MD5 checksum on initial load
- Verifies checksum on resume
- **STOPS** if data file changed (prevents silent corruption)

**Impact**: **CRITICAL** - Prevents mixed-version data

---

### 2. State Management Layer (NEW) 🎛️

**Problem**: v1 had unclear experiment status transitions.

**v2 Solution**:
```
States: 'running' | 'completed' | 'failed' | 'cancelled'

Transitions:
  start_experiment()    → 'running'
  finalize_experiment() → 'completed'
  resume_experiment()   → 'running' (from 'running'/'failed')
```

**New Functions**:
- `validate_experiment_for_resume()` - Checks if experiment can resume
- `update_experiment_status()` - Updates status with validation

**Impact**: **HIGH** - Clear operational rules, prevents resuming completed experiments

---

### 3. Concurrent Execution Prevention (NEW) 🔐

**Problem**: v1 allowed multiple processes to resume same experiment.

**v2 Solution**: PID-based lock file

```r
acquire_resume_lock(experiment_id)
# Creates: data/.resume_lock_<exp_id>.pid
# Checks: If PID still running, STOP
# Cleanup: Automatic on exit
```

**Impact**: **MEDIUM** - Prevents wasted compute and log confusion

---

### 4. Progress Tracking Layer (NEW) 📊

**Problem**: v1 had no visibility during 75-100 hour runs.

**v2 Solution**: Multi-level progress tracking

**Database**:
```sql
ALTER TABLE experiments ADD COLUMN n_narratives_completed INTEGER DEFAULT 0;
ALTER TABLE experiments ADD COLUMN last_progress_update TEXT;
ALTER TABLE experiments ADD COLUMN estimated_completion_time TEXT;
```

**Console Logging**:
```
[PROGRESS] 5000/41892 (11.9%) | Rate: 0.45/sec | ETA: 2025-10-29 14:23:15 | Elapsed: 3h 5m
```

**External Monitoring**:
```bash
watch -n 60 'sqlite3 data/production_20k.db "SELECT ..."'
```

**Impact**: **HIGH** - Essential UX for multi-day runs

---

### 5. Enhanced Error Handling (NEW) ⚠️

**Problem**: v1 "delete-then-insert" for error retries lost diagnostic data.

**v2 Solution**: UPDATE with attempt tracking

```sql
ALTER TABLE narrative_results ADD COLUMN attempt_count INTEGER DEFAULT 1;
ALTER TABLE narrative_results ADD COLUMN first_error_message TEXT;
ALTER TABLE narrative_results ADD COLUMN error_category TEXT;
```

**Logic**:
- First attempt: Insert with attempt_count=1
- Retry: UPDATE existing row, increment attempt_count
- Keep first_error_message for diagnostics
- Categorize errors (api_error, parse_error, etc.)

**Impact**: **MEDIUM** - Better debugging and intelligent retry

---

### 6. Configuration Consistency (NEW) ⚙️

**Problem**: v1 unclear on YAML vs DB config priority.

**v2 Solution**: **Database is authoritative**

When resuming:
- ✅ Use model/prompt/seed from DB (ignore YAML)
- ⚠️ Warn if YAML differs from DB
- 🛡️ Prevents config drift mid-experiment

**Impact**: **MEDIUM** - Ensures reproducibility

---

### 7. Transaction Safety (NEW) 💾

**Problem**: v1 didn't mention transaction handling.

**v2 Solution**: Batched commits

```r
DBI::dbBegin(conn)
# Process 100 narratives
DBI::dbCommit(conn)
DBI::dbBegin(conn)
# Next 100...
```

**Impact**: Prevents losing work if crash mid-batch

---

### 8. Comprehensive Testing (NEW) 🧪

**v1**: Mentioned testing but vague

**v2**: 6 detailed test scenarios
1. Basic resume flow
2. Data integrity validation
3. Idempotency test
4. Error retry
5. Progress tracking
6. Concurrent execution prevention

Each with exact commands and expected outcomes.

---

### 9. Shell Helper Script (NEW) 🛠️

**v2 adds**: `scripts/resume_experiment.sh`

```bash
# Auto-discovers latest incomplete experiment
# Shows summary
# Prompts for confirmation
# Resumes with correct DB config

./scripts/resume_experiment.sh
```

**Impact**: **LOW** - Nice UX improvement

---

### 10. Monitoring Commands (NEW) 📈

**v2 adds** complete monitoring section:

```bash
# Real-time progress
watch -n 60 'sqlite3 ... progress query'

# Error rate monitoring
sqlite3 ... error rate query

# Backup verification
ls -lh data/*.resume_backup*
```

---

## Comparison Table

| Feature | v1 | v2 | Importance |
|---------|----|----|------------|
| Basic resume logic | ✅ | ✅ | HIGH |
| Unique index (idempotency) | ✅ | ✅ | HIGH |
| Data checksum validation | ❌ | ✅ | **CRITICAL** |
| State machine validation | ❌ | ✅ | HIGH |
| Progress tracking | ❌ | ✅ | HIGH |
| Concurrent execution prevention | ❌ | ✅ | MEDIUM |
| Transaction batching | ❌ | ✅ | MEDIUM |
| Error attempt tracking | ❌ | ✅ | MEDIUM |
| Config consistency checks | ❌ | ✅ | MEDIUM |
| Detailed testing plan | Partial | ✅ | HIGH |
| Shell helpers | ❌ | ✅ | LOW |
| Monitoring commands | ❌ | ✅ | MEDIUM |
| Backup strategy | ❌ | ✅ | LOW |

## Code Changes Summary

### New Functions (v2)

**R/experiment_logger.R**:
- `validate_experiment_for_resume(conn, experiment_id)`
- `update_experiment_status(conn, experiment_id, status)`
- `acquire_resume_lock(experiment_id)`
- `release_resume_lock(lock_file)`
- `update_progress(conn, experiment_id, n_completed, n_total, start_time)`
- `format_duration(seconds)`

**Modified Functions**:
- `load_source_data()` - Add checksum validation
- `run_benchmark_core()` - Add resume params, progress tracking, transaction batching

**New Scripts**:
- `scripts/resume_experiment.sh` - Auto-discover and resume helper
- `scripts/sql/migration_resumable_v2.sql` - Database migrations

### Lines of Code

**v1 pseudocode**: ~25 lines
**v2 implementation**: ~300+ lines (complete, production-ready)

---

## Implementation Effort

**v1 estimate**: 2-2.5 days
**v2 estimate**: ~5 days

**Breakdown**:
- Core implementation: 3 days
- Safety & monitoring: 1.5 days
- Testing & docs: 0.5 day

**Why longer?**
- Data integrity checks
- State management
- Progress tracking infrastructure
- Comprehensive testing
- **But**: Much safer and more usable

---

## Migration Path

### From v1 → v2

If you've already implemented v1:

1. **Apply database migrations** (backward compatible)
   ```bash
   sqlite3 data/production_20k.db < scripts/sql/migration_resumable_v2.sql
   ```

2. **Add new functions** to R files (non-breaking)
   - New functions don't affect existing code
   - Old resume path still works

3. **Update resume logic** gradually
   - Can deploy in stages
   - Each addition is independent

4. **Test thoroughly** before production

---

## Risk Assessment

| Aspect | v1 Risk | v2 Risk |
|--------|---------|---------|
| Data corruption | **HIGH** | LOW |
| Operational confusion | HIGH | LOW |
| Wasted compute | MEDIUM | LOW |
| Lost progress | MEDIUM | LOW |
| Poor UX | HIGH | LOW |
| Implementation bugs | MEDIUM | MEDIUM |

---

## Recommendation

**For Production (75-100h runs)**: Use **v2**

**Rationale**:
- Data integrity is **non-negotiable** for 100-hour runs
- Progress tracking is **essential** for sanity
- Extra 2.5 days of development **worth it** for safety

**For Quick Testing**: v1 might be acceptable
- But only if data file won't change
- And only for short runs (<2 hours)

---

## v2 Adoption Checklist

- [ ] Apply database migrations
- [ ] Implement new functions in R/experiment_logger.R
- [ ] Update R/data_loader.R with checksum logic
- [ ] Modify R/run_benchmark_core.R for progress tracking
- [ ] Update scripts/run_experiment.R with full resume workflow
- [ ] Create scripts/resume_experiment.sh helper
- [ ] Run all 6 test scenarios
- [ ] Document monitoring commands
- [ ] Train team on resume procedures
- [ ] Deploy to production

**Estimated total time**: 1 week (including testing and docs)

---

## Quick Start (v2)

```bash
# 1. Apply migrations
sqlite3 data/production_20k.db < scripts/sql/migration_resumable_v2.sql

# 2. Start production run
./scripts/run_production_20k.sh

# 3. If crash/kill happens, resume with:
./scripts/resume_experiment.sh

# Or manually:
RESUME=1 EXPERIMENT_ID=<id> ./scripts/run_production_20k.sh
```

---

**Prepared by**: Claude Code
**Status**: v2 recommended for production use
**Last Updated**: 2025-10-27
