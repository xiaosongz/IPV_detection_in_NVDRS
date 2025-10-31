#!/bin/bash

# Resume Experiment Helper Script
# Finds and resumes the latest incomplete experiment

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Default database
DB_PATH="data/experiments.db"

# Parse command line arguments
RETRY_ERRORS=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --db)
      DB_PATH="$2"
      shift 2
      ;;
    --retry-errors)
      RETRY_ERRORS=1
      shift
      ;;
    --help)
      cat << EOF
Resume Experiment Helper

Usage:
  ./scripts/resume_experiment.sh [OPTIONS]

Options:
  --db PATH          Path to database (default: data/experiments.db)
  --retry-errors     Retry only errored narratives
  --help             Show this help message

Examples:
  # Resume latest incomplete experiment
  ./scripts/resume_experiment.sh

  # Resume with production database
  ./scripts/resume_experiment.sh --db data/production_20k.db

  # Retry only errors
  ./scripts/resume_experiment.sh --retry-errors

EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo ""
echo "========================================"
echo "Resume Experiment Helper"
echo "========================================"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
  echo "✗ ERROR: Database not found: $DB_PATH"
  echo ""
  exit 1
fi

echo "Database: $DB_PATH"
echo ""

# Find latest incomplete experiment
LATEST=$(sqlite3 "$DB_PATH" "
  SELECT experiment_id || '|' || experiment_name || '|' || status || '|' || 
         COALESCE(n_narratives_completed, 0) || '|' || COALESCE(n_narratives_total, 0) || '|' || 
         COALESCE(data_file, '')
  FROM experiments
  WHERE status IN ('running', 'failed')
  ORDER BY created_at DESC
  LIMIT 1
")

if [ -z "$LATEST" ]; then
  echo "No incomplete experiments found."
  echo ""
  echo "Experiments with status 'running' or 'failed' can be resumed."
  echo ""
  exit 0
fi

# Parse experiment info
IFS='|' read -r EXP_ID EXP_NAME STATUS N_COMPLETED N_TOTAL DATA_FILE <<< "$LATEST"

echo "Found incomplete experiment:"
echo "  ID: $EXP_ID"
echo "  Name: $EXP_NAME"
echo "  Status: $STATUS"

if [ "$N_TOTAL" -gt 0 ]; then
  PCT_COMPLETE=$(awk "BEGIN {printf \"%.1f\", ($N_COMPLETED / $N_TOTAL) * 100}")
  echo "  Progress: $N_COMPLETED / $N_TOTAL ($PCT_COMPLETE%)"
fi

if [ -n "$DATA_FILE" ]; then
  echo "  Data file: $DATA_FILE"
fi

echo ""

# Check if config file exists (try to guess from experiment name)
CONFIG_FILE=""
if [ -n "$DATA_FILE" ] && [[ "$DATA_FILE" == *"all_suicide_nar"* ]]; then
  # Production data
  CONFIG_FILE="configs/experiments/exp_100_production_20k_indicators_t02_high.yaml"
elif [[ "$EXP_NAME" == *"Test"* ]] || [[ "$EXP_NAME" == *"test"* ]]; then
  # Test experiment
  CONFIG_FILE="configs/experiments/exp_900_test_resume.yaml"
fi

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  echo "Detected config file: $CONFIG_FILE"
else
  echo "Could not auto-detect config file."
  echo "Please specify the original config file:"
  read -p "Config file path: " CONFIG_FILE
  
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "✗ ERROR: Config file not found: $CONFIG_FILE"
    exit 1
  fi
fi

echo ""

# Check for stale lock
LOCK_FILE="data/.resume_lock_${EXP_ID}.pid"
if [ -f "$LOCK_FILE" ]; then
  LOCKED_PID=$(cat "$LOCK_FILE")
  echo "⚠ WARNING: Lock file exists (PID: $LOCKED_PID)"
  
  # Check if process is running (Unix only)
  if ps -p "$LOCKED_PID" > /dev/null 2>&1; then
    echo "  Process $LOCKED_PID is still running!"
    echo "  Another resume may be in progress."
    echo ""
    read -p "Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  else
    echo "  Process $LOCKED_PID is not running (stale lock)."
    echo "  Removing stale lock file..."
    rm -f "$LOCK_FILE"
    echo "  ✓ Lock removed"
  fi
  echo ""
fi

# Confirm resume
echo "========================================"
echo "Ready to resume"
echo "========================================"
echo ""
echo "Mode: $([ $RETRY_ERRORS -eq 1 ] && echo 'Retry errors only' || echo 'Process missing narratives')"
echo "Config: $CONFIG_FILE"
echo ""
read -p "Continue? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "========================================"
echo "Resuming experiment..."
echo "========================================"
echo ""

# Set environment variables
export RESUME=1
export EXPERIMENT_ID="$EXP_ID"

if [ $RETRY_ERRORS -eq 1 ]; then
  export RETRY_ERRORS_ONLY=1
fi

# If using non-default database, set it
if [ "$DB_PATH" != "data/experiments.db" ]; then
  export EXPERIMENTS_DB="$DB_PATH"
fi

# Run resume
Rscript scripts/run_experiment.R "$CONFIG_FILE"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "========================================"
  echo "✓ Resume completed successfully"
  echo "========================================"
  echo ""
else
  echo ""
  echo "========================================"
  echo "✗ Resume failed (exit code: $EXIT_CODE)"
  echo "========================================"
  echo ""
  echo "Check error logs in: logs/experiments/$EXP_ID/"
  echo ""
fi

exit $EXIT_CODE
