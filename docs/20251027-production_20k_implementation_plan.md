# Production Run: 20k Cases Implementation Plan

**Date**: 2025-10-27
**Branch**: `feature/20k-production-run`
**Target**: 20,946 cases (41,892 narratives: LE + CME)
**Data File**: `data-raw/all_suicide_nar.xlsx`

## Implemented Components

### 1. Branch Setup
- ✅ Created `feature/20k-production-run` branch
- ✅ Isolated development from main branch

### 2. Top Performing Configuration Identification
- ✅ Analyzed existing experiments to find best performing model
- ✅ **Selected**: Indirect Indicators (T=0.2, Reasoning=High) 
  - F1 Score: 0.8077 (highest from testing)
  - Configuration: `exp_012_indicators_t02_high.yaml`
  - Model: mlx-community/gpt-oss-120b
  - Temperature: 0.2
  - Reasoning: High

### 3. Production Configuration
- ✅ Created `configs/experiments/exp_100_production_20k_indicators_t02_high.yaml`
- ✅ Updated data source to `data-raw/all_suicide_nar.xlsx`
- ✅ Configured for all 41,892 narratives (no limit)
- ✅ Enabled incremental saving and CSV/JSON exports

### 4. Data Import Module Updates
- ✅ Modified `R/data_loader.R` to handle new file format
- ✅ Added format detection for:
  - **New format**: `all_suicide_nar.xlsx` (IncidentID, NarrativeCME, NarrativeLE)
  - **Legacy format**: Manual flag columns included
- ✅ Handles production data with no manual flags (NA values)
- ✅ Tested compatibility with new file structure

### 5. Production Database Setup
- ✅ Created dedicated production database: `data/production_20k.db`
- ✅ Extracted schema: `scripts/sql/create_production_schema.sql`
- ✅ Configuration file: `.db_config.production`
- ✅ Automatic backup before runs
- ✅ Isolated from testing database (prevents performance impact)

### 6. Production Script
- ✅ Created `scripts/run_production_20k.sh`
- ✅ Comprehensive logging with timestamps
- ✅ Database validation and backup procedures
- ✅ Error handling and rollback capabilities
- ✅ Progress tracking and status reporting

## Data File Analysis

### File: `data-raw/all_suicide_nar.xlsx`
- **Rows**: 20,946 cases
- **Columns**: IncidentID, IncidentYear, SiteID, NarrativeCME, NarrativeLE
- **Expected narratives**: ~41,892 (2 per case)
- **No manual flags**: Pure production data for IPV detection

### Database Size Estimates
- **Current DB**: 79MB (18,817 narratives)
- **Production DB**: ~255MB after completion
- **Disk Space Required**: 300MB minimum (includes backups)
- **Performance**: Optimized indexes for large dataset

## Production Execution Plan

### Phase 0: Smoke Test (Recommended)
Before starting the full 24-35 hour production run, validate the pipeline with a quick smoke test:

**Option 1: Automated Script (Recommended)**
```bash
./scripts/run_smoke_test.sh
```

**Option 2: Manual Commands**
```bash
# Set up production database configuration
cp .db_config.production .db_config

# Run smoke test (200 narratives, ~6-10 minutes)
Rscript scripts/run_experiment.R configs/experiments/exp_101_production_smoke_test.yaml

# Check results
sqlite3 data/production_20k.db "
  SELECT experiment_name, status, n_narratives_processed
  FROM experiments
  WHERE experiment_name LIKE '%Smoke Test%'
  ORDER BY created_at DESC LIMIT 1;
"

# Optional: Restore default config after smoke test
git checkout .db_config
```

This validates:
- MLX server connectivity and stability
- Data file loading and format handling
- Database operations and incremental saves
- Logging and error handling
- JSON parsing and metrics calculation

### Phase 1: Pre-Run Validation
1. **Verify MLX Server Status**
   ```bash
   curl http://localhost:1234/v1/models | grep gpt-oss-120b
   ```

2. **Check Data File**
   ```bash
   ls -lh data-raw/all_suicide_nar.xlsx
   Rscript -e "library(readxl); df <- read_excel('data-raw/all_suicide_nar.xlsx'); cat('Rows:', nrow(df), '\n')"
   ```

3. **Verify Schema File** (DB will be auto-created by script)
   ```bash
   ls -l scripts/sql/create_production_schema.sql
   ```

4. **Check Disk Space** (Need ~300MB minimum)
   ```bash
   df -h .
   ```

### Phase 2: Production Run
1. **Execute Production Script**
   ```bash
   ./scripts/run_production_20k.sh
   ```

2. **Monitor Progress**
   - Log file: `logs/production_20k_YYYYMMDD_HHMMSS.log`
   - Database: `data/production_20k.db`
   - Exports: `benchmark_results/`

3. **Estimated Runtime**
   - 41,892 narratives (20,946 cases × 2)
   - **Actual measured**: 6.5 seconds per narrative (from smoke test)
   - **Total**: ~75 hours of processing time
   - **Updated estimate for 40k narratives**: ~100 hours

### Phase 3: Post-Run Analysis
1. **Quick Summary** (automatically shown by script)
   - Experiment name and status
   - Total narratives processed
   - IPV detection count and rate
   - Average confidence score
   - Average response time

2. **Detailed Results by Narrative Type**
   ```bash
   Rscript scripts/view_experiment.R <experiment_id>
   ```

3. **Manual Query Examples**
   ```sql
   # Detection rate by narrative type
   sqlite3 data/production_20k.db "
     SELECT
       narrative_type,
       COUNT(*) as total,
       SUM(detected) as ipv_detected,
       ROUND(SUM(detected) * 100.0 / COUNT(*), 2) as detection_rate_pct,
       ROUND(AVG(confidence), 3) as avg_confidence
     FROM narrative_results
     GROUP BY narrative_type;
   "
   ```

3. **Export Results**
   - CSV: Available in `benchmark_results/`
   - JSON: Available in `benchmark_results/`
   - Database: Complete results in `data/production_20k.db`

## Quality Assurance

### Automated Checks
- ✅ File format validation
- ✅ Database schema integrity
- ✅ Configuration validation
- ✅ MLX server connectivity
- ✅ Incremental saving (prevents data loss)

### Error Handling
- ✅ Database backup before run
- ✅ Rollback on failure
- ✅ Comprehensive logging with timestamps
- ✅ Progress tracking (incremental saves)
- ⚠️ Timing metrics (response time per narrative)

## Configuration Details

### Model Configuration
```yaml
model:
  name: "mlx-community/gpt-oss-120b"
  provider: "mlx"
  api_url: "http://localhost:1234/v1/chat/completions"
  temperature: 0.2
```

### Prompt Configuration
- **Version**: v0.3.2_indicators
- **Reasoning**: High
- **Features**: Direct/indirect IPV indicators
- **JSON parsing**: Strict format validation

### Run Configuration
```yaml
run:
  seed: 1024
  max_narratives: 1000000  # Process all
  save_incremental: true
  save_csv_json: true
```

## Monitoring Commands

### During Run
```bash
# Check progress
tail -f logs/production_20k_*.log

# Database size
ls -lh data/production_20k.db

# Current records
sqlite3 data/production_20k.db "SELECT COUNT(*) FROM narrative_results;"
```

### Post-Run Analysis
```bash
# Overall statistics
Rscript -e "
library(DBI)
conn <- dbConnect(RSQLite::SQLite(), 'data/production_20k.db')
summary <- dbGetQuery(conn, '
  SELECT 
    COUNT(*) as total_narratives,
    SUM(CASE WHEN detected = 1 THEN 1 ELSE 0 END) as ipv_positive,
    AVG(confidence) as avg_confidence,
    AVG(response_sec) as avg_response_time
  FROM narrative_results
')
print(summary)
dbDisconnect(conn)
"

# Detection rate by narrative type
sqlite3 data/production_20k.db "
SELECT 
  narrative_type,
  COUNT(*) as total,
  SUM(detected) as ipv_detected,
  ROUND(SUM(detected) * 100.0 / COUNT(*), 2) as detection_rate_pct
FROM narrative_results 
GROUP BY narrative_type;
"
```

## Rollback Plan

If issues occur during production run:

1. **Stop the process**
   ```bash
   pkill -f "run_experiment.R"
   ```

2. **Restore database backup**
   ```bash
   cp data/production_20k_backup_YYYYMMDD_HHMMSS.db data/production_20k.db
   ```

3. **Review logs**
   ```bash
   less logs/production_20k_*.log
   ```

4. **Identify and fix issues before re-running**

## Success Criteria

### Technical Success
- [ ] All 41,892 narratives processed (20,946 cases × 2)
- [ ] No database errors or data corruption
- [ ] All exports generated successfully (CSV/JSON)
- [ ] Response times within acceptable range (2-3 sec/narrative)
- [ ] Complete logs with no critical errors

### Analytical Success
- [ ] Reasonable IPV detection rate (expected 5-15%)
- [ ] Confidence scores properly distributed
- [ ] No systematic errors in JSON parsing
- [ ] LE and CME narratives processed equally

### Operational Success
- [ ] Complete run without manual intervention
- [ ] Logs capture all necessary information
- [ ] Database integrity maintained
- [ ] Results easily accessible for analysis

## Next Steps

After successful production run:

1. **Analyze Results**
   - Overall IPV prevalence
   - LE vs CME detection rates
   - Confidence score distribution
   - Response time analysis

2. **Quality Validation**
   - Manual review of high-confidence detections
   - Cross-validation with known cases
   - Error analysis

3. **Reporting**
   - Generate comprehensive report
   - Create visualizations
   - Document findings for publication

4. **Database Sync**
   - Sync to PostgreSQL for dashboards
   - Create backup archives
   - Prepare data for analysis

---

## Verification History

### 2025-10-27 - Pre-Production Review (Round 1)
- ✅ Fixed critical bug: Updated `run_production_20k.sh` to use correct data file path
  - Changed from: `data-raw/production_20k_cases.xlsx` (incorrect)
  - Changed to: `data-raw/all_suicide_nar.xlsx` (correct)
- ✅ Updated narrative count references (40k → 41,892)
- ✅ Verified all components ready for production
- ✅ MLX server confirmed running with correct model
- ✅ Data file verified (8.6MB, 20,946 rows, correct structure)

### 2025-10-27 - Pre-Production Review (Round 2)
- ✅ Fixed DB initialization guard (removed incorrect `experiments.db` dependency)
- ✅ Updated quick summary queries to show production-relevant metrics
  - Removed: F1/precision/recall (require ground truth)
  - Added: Total narratives, IPV detection rate, avg confidence, avg response time
- ✅ Fixed resource monitoring claims (clarified timing metrics only)
- ✅ Updated pre-run validation steps (removed incorrect schema check)
- ✅ Added disk space validation (300MB minimum)
- ✅ Created smoke test configuration (`exp_101_production_smoke_test.yaml`)
  - 200 narratives, ~6-10 minutes runtime
  - Validates full pipeline before 24-35h production run

### 2025-10-27 - Smoke Test Results (Round 4)
- ✅ Successfully executed smoke test with 192 narratives
- ✅ Measured actual performance metrics:
  - Response time: 6.5 seconds per narrative (average)
  - Range: 3-16 seconds per narrative
  - Error rate: 0% (perfect JSON parsing)
  - Confidence: 88.8% average
  - IPV detection rate: 8.3%
- ✅ Updated runtime estimates based on actual measurements
  - 41,892 narratives at 6.5 sec/narrative = ~75 hours
  - Updated estimate for all 40k narratives: ~100 hours
- ✅ Fixed data loading issue:
  - Issue: Duplicate incident_id+narrative_type combinations in source data
  - Solution: Added deduplication logic to data loader
  - Result: Successfully loaded 35,312 unique narratives

---

**Prepared by**: Droid AI Assistant
**Status**: Ready for execution
**Last Updated**: 2025-10-27 (Post-review corrections)
