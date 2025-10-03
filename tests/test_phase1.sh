#!/bin/bash

# Test Phase 1 Implementation
# This script helps run the test regardless of R installation location

set -e  # Exit on error

cd "$(dirname "$0")"

echo "======================================"
echo "Phase 1 Implementation Test"
echo "======================================"
echo ""

# Try to find R or Rscript
if command -v Rscript &> /dev/null; then
    echo "✓ Found Rscript in PATH"
    Rscript tests/manual_test_experiment_setup.R
elif command -v R &> /dev/null; then
    echo "✓ Found R in PATH (using R --vanilla)"
    R --vanilla < tests/manual_test_experiment_setup.R
else
    echo "✗ R/Rscript not found in PATH"
    echo ""
    echo "Please run manually from RStudio:"
    echo "  source('tests/manual_test_experiment_setup.R')"
    echo ""
    echo "Or provide the full path to R/Rscript"
    exit 1
fi

echo ""
echo "======================================"
echo "Test Complete!"
echo "======================================"
