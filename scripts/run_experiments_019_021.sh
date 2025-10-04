#!/bin/bash

# Run experiments 019-021 sequentially
# Date: 2025-10-03
# Purpose: Test the new "Chain-of-Thought with Calibrated Examples" prompt style

# Get the project root directory (one level up from scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate timestamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="logs/experiments_019_021_${TIMESTAMP}.log"

# Function to log with timestamp
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Start logging (tee to both file and stdout)
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "Running Experiments 019-021"
log "Log file: $LOGFILE"
log "=========================================="
log ""

# Array of experiment configs
experiments=(
  "exp_019_cot_t00_medium.yaml"
  "exp_020_cot_t00_high.yaml"
  "exp_021_cot_t02_high.yaml"
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
