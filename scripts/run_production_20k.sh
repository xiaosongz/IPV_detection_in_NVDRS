#!/bin/bash

# Production run for 20k cases (40k narratives: LE + CME)
# Date: 2025-10-27
# Purpose: Process all 20k cases using best performing config (exp_012)

# Get the project root directory (one level up from scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate timestamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="logs/production_20k_${TIMESTAMP}.log"

# Function to log with timestamp
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Start logging (tee to both file and stdout)
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "Production Run: 20k Cases (40k narratives)"
log "Config: exp_100_production_20k_indicators_t02_high.yaml"
log "Log file: $LOGFILE"
log "=========================================="
log ""

# Check if production data file exists
DATA_FILE="data-raw/production_20k_cases.xlsx"
if [ ! -f "$DATA_FILE" ]; then
  log "ERROR: Production data file not found: $DATA_FILE"
  log "Please ensure the 20k cases file is available before running."
  exit 1
fi

log "Production data file found: $DATA_FILE"
log ""

# Use production database
DB_FILE="data/production_20k.db"
log "Using production database: $DB_FILE"

# Create production database if it doesn't exist
if [ ! -f "$DB_FILE" ]; then
  log "Creating new production database..."
  # Copy schema from existing database
  if [ -f "data/experiments.db" ]; then
    sqlite3 "$DB_FILE" < scripts/sql/create_production_schema.sql
    log "✓ Production database created with schema"
  else
    log "ERROR: Source database not found for schema copying"
    exit 1
  fi
else
  log "Production database already exists"
  # Backup existing production DB
  BACKUP_FILE="data/production_20k_backup_$(date +%Y%m%d_%H%M%S).db"
  log "Backing up existing production database to: $BACKUP_FILE"
  cp "$DB_FILE" "$BACKUP_FILE"
  log "✓ Production database backup completed"
fi
log ""

log "Starting production experiment..."
log "Processing 20k cases (expected ~40k narratives)"
log "This may take several hours depending on system performance."
log ""

# Set production database configuration
cp .db_config.production .db_config
log "Using production database configuration"

# Run the production experiment
Rscript scripts/run_experiment.R "configs/experiments/exp_100_production_20k_indicators_t02_high.yaml"

# Check if successful
if [ $? -eq 0 ]; then
  log "=========================================="
  log "✓ Production run completed successfully!"
  log "=========================================="
  log ""
  log "Results saved to database: $DB_FILE"
  log "Incremental CSV/JSON exports available in: benchmark_results/"
  log ""
  log "Quick summary:"
  log "  sqlite3 data/production_20k.db \"SELECT experiment_id, experiment_name, status, n_narratives_processed, f1_ipv, precision_ipv, recall_ipv FROM experiments WHERE experiment_name LIKE '%Production%' ORDER BY created_at DESC LIMIT 1;\""
  log ""
  log "Full results:"
  log "  Rscript scripts/view_experiment.R <experiment_id>"
else
  log "=========================================="
  log "✗ Production run failed!"
  log "=========================================="
  log "Check log file: $LOGFILE"
  log "Database state unchanged."
  exit 1
fi

log ""
log "Production run completed at: $(date)"
