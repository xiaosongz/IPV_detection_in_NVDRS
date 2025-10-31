#!/bin/bash

# Smoke test for production pipeline validation
# Date: 2025-10-27
# Purpose: Quick validation (200 narratives, ~6-10 min) before full production run
# Uses production database to validate full pipeline

# Get the project root directory (one level up from scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate timestamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="logs/smoke_test_${TIMESTAMP}.log"

# Function to log with timestamp
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Start logging (tee to both file and stdout)
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "Production Smoke Test (200 narratives)"
log "Config: exp_101_production_smoke_test.yaml"
log "Log file: $LOGFILE"
log "=========================================="
log ""

# Check if production data file exists
DATA_FILE="data-raw/all_suicide_nar.xlsx"
if [ ! -f "$DATA_FILE" ]; then
  log "ERROR: Production data file not found: $DATA_FILE"
  exit 1
fi

log "Data file found: $DATA_FILE"
log ""

# Use production database for smoke test
DB_FILE="data/production_20k.db"
log "Using production database: $DB_FILE"

# Create production database if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
  log "Creating new production database..."
  if [ ! -f "scripts/sql/create_production_schema.sql" ]; then
    log "ERROR: Schema file not found: scripts/sql/create_production_schema.sql"
    exit 1
  fi
  sqlite3 "$DB_FILE" < scripts/sql/create_production_schema.sql
  log "✓ Production database created with schema"
else
  log "Production database already exists"
fi
log ""

# Set production database configuration
log "Setting up production database configuration..."
cp .db_config.production .db_config
log "✓ Using production database: $DB_FILE"
log ""

log "Starting smoke test..."
log "Processing 200 narratives (expected ~6-10 minutes)"
log ""

# Run the smoke test experiment
Rscript scripts/run_experiment.R "configs/experiments/exp_101_production_smoke_test.yaml"

# Check if successful
if [ $? -eq 0 ]; then
  log "=========================================="
  log "✓ Smoke test completed successfully!"
  log "=========================================="
  log ""
  log "Results saved to database: $DB_FILE"
  log ""
  log "Quick summary:"
  sqlite3 "$DB_FILE" "
    SELECT
      'Experiment: ' || experiment_name as info
    FROM experiments
    WHERE experiment_name LIKE '%Smoke Test%'
    ORDER BY created_at DESC LIMIT 1;

    SELECT
      'Total narratives: ' || COUNT(*) as stat
    FROM narrative_results
    WHERE experiment_id = (
      SELECT experiment_id FROM experiments
      WHERE experiment_name LIKE '%Smoke Test%'
      ORDER BY created_at DESC LIMIT 1
    );

    SELECT
      'IPV detected: ' || SUM(detected) || ' (' ||
      ROUND(SUM(detected) * 100.0 / COUNT(*), 2) || '%)' as stat
    FROM narrative_results
    WHERE experiment_id = (
      SELECT experiment_id FROM experiments
      WHERE experiment_name LIKE '%Smoke Test%'
      ORDER BY created_at DESC LIMIT 1
    );

    SELECT
      'Avg confidence: ' || ROUND(AVG(confidence), 3) as stat
    FROM narrative_results
    WHERE experiment_id = (
      SELECT experiment_id FROM experiments
      WHERE experiment_name LIKE '%Smoke Test%'
      ORDER BY created_at DESC LIMIT 1
    );

    SELECT
      'Avg response time: ' || ROUND(AVG(response_sec), 2) || 's' as stat
    FROM narrative_results
    WHERE experiment_id = (
      SELECT experiment_id FROM experiments
      WHERE experiment_name LIKE '%Smoke Test%'
      ORDER BY created_at DESC LIMIT 1
    );
  " | sed 's/^/  /'
  log ""
  log "Smoke test validation: PASSED ✓"
  log "System is ready for full production run."
  log ""
  log "To start production run:"
  log "  ./scripts/run_production_20k.sh"
  log ""
  log "To restore default database config:"
  log "  git checkout .db_config"
else
  log "=========================================="
  log "✗ Smoke test failed!"
  log "=========================================="
  log "Check log file: $LOGFILE"
  log "Review errors before attempting production run."
  exit 1
fi

log ""
log "Smoke test completed at: $(date)"
