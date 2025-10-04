#!/bin/bash

# Run experiments 007-018 sequentially
# Date: 2025-10-03
# Purpose: Test 12 prompt strategies with different temperature/reasoning configurations

# Get the project root directory (one level up from scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate timestamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="logs/experiments_007_018_${TIMESTAMP}.log"

# Function to log with timestamp
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Start logging (tee to both file and stdout)
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "Running Experiments 007-018"
log "Log file: $LOGFILE"
log "=========================================="
log ""

# Array of experiment configs
experiments=(
  "exp_007_baseline_t00_medium.yaml"
  "exp_008_baseline_t00_high.yaml"
  "exp_009_baseline_t02_high.yaml"
  "exp_010_indicators_t00_medium.yaml"
  "exp_011_indicators_t00_high.yaml"
  "exp_012_indicators_t02_high.yaml"
  "exp_013_strict_t00_medium.yaml"
  "exp_014_strict_t00_high.yaml"
  "exp_015_strict_t02_high.yaml"
  "exp_016_context_t00_medium.yaml"
  "exp_017_context_t00_high.yaml"
  "exp_018_context_t02_high.yaml"
)

# Counter for progress
total=${#experiments[@]}
current=0

# Run each experiment
for exp in "${experiments[@]}"; do
  current=$((current + 1))
  log "----------------------------------------"
  log "[$current/$total] Running: $exp"
  log "----------------------------------------"

  # Run the experiment using R script (from project root)
  Rscript scripts/run_experiment.R "configs/experiments/$exp"

  # Check if successful
  if [ $? -eq 0 ]; then
    log "✓ $exp completed successfully"
  else
    log "✗ $exp failed"
    log "Check log file: $LOGFILE"
    exit 1
  fi

  log ""
done

log "=========================================="
log "All experiments completed!"
log "=========================================="
log ""
log "Log saved to: $LOGFILE"
log ""
log "View results:"
log "  sqlite3 data/experiments.db \"SELECT experiment_id, experiment_name, status, accuracy, f1_ipv FROM experiments WHERE experiment_name LIKE '%2025-10-03%' ORDER BY created_at;\""
