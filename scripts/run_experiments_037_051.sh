#!/bin/bash

# Run experiments 037-051 sequentially
# Date: 2025-10-03
# Purpose: Test new prompts (v0.4.x) with improved JSON formatting instructions

# Get the project root directory (one level up from scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Create logs directory if it doesn't exist
mkdir -p logs

# Generate timestamped log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="logs/experiments_037_051_${TIMESTAMP}.log"

# Function to log with timestamp
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

# Start logging (tee to both file and stdout)
exec > >(tee -a "$LOGFILE") 2>&1

log "=========================================="
log "Running Experiments 037-051"
log "Log file: $LOGFILE"
log "=========================================="
log ""

# Array of experiment configs
experiments=(
  "exp_019_cot_t00_medium.yaml"
  "exp_020_cot_t00_high.yaml"
  "exp_021_cot_t02_high.yaml"
  "exp_037_baseline_v4_t00_medium.yaml"
  "exp_038_baseline_v4_t00_high.yaml"
  "exp_039_baseline_v4_t02_high.yaml"
  "exp_040_indicators_v4_t00_medium.yaml"
  "exp_041_indicators_v4_t00_high.yaml"
  "exp_042_indicators_v4_t02_high.yaml"
  "exp_043_strict_v4_t00_medium.yaml"
  "exp_044_strict_v4_t00_high.yaml"
  "exp_045_strict_v4_t02_high.yaml"
  "exp_046_context_v4_t00_medium.yaml"
  "exp_047_context_v4_t00_high.yaml"
  "exp_048_context_v4_t02_high.yaml"
  "exp_049_cot_v4_t00_medium.yaml"
  "exp_050_cot_v4_t00_high.yaml"
  "exp_051_cot_v4_t02_high.yaml"
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
