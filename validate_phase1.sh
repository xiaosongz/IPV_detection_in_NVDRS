#!/bin/bash
# Validate Phase 1 Implementation - Structure Only

echo "========================================="
echo "Phase 1 Structure Validation"
echo "========================================="
echo ""

PASS=0
FAIL=0

check_file() {
    if [ -f "$1" ]; then
        echo "✓ $1"
        ((PASS++))
    else
        echo "✗ $1 MISSING"
        ((FAIL++))
    fi
}

check_dir() {
    if [ -d "$1" ]; then
        echo "✓ $1/"
        ((PASS++))
    else
        echo "✗ $1/ MISSING"
        ((FAIL++))
    fi
}

echo "Core R Functions:"
check_file "R/db_schema.R"
check_file "R/data_loader.R"
check_file "R/config_loader.R"
check_file "R/experiment_logger.R"
check_file "R/experiment_queries.R"

echo ""
echo "Scripts:"
check_file "scripts/init_database.R"
check_file "run_phase1_test.R"

echo ""
echo "Configuration:"
check_file "configs/experiments/exp_001_test_gpt_oss.yaml"
check_dir "configs/experiments"
check_dir "configs/prompts"

echo ""
echo "Tests:"
check_file "tests/manual_test_experiment_setup.R"

echo ""
echo "Infrastructure:"
check_dir "logs/experiments"
check_file ".gitignore"

echo ""
echo "Documentation:"
check_file "docs/EXPERIMENT_IMPLEMENTATION_STATUS.md"
check_file "PHASE1_IMPLEMENTATION_COMPLETE.md"

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "========================================="

if [ $FAIL -eq 0 ]; then
    echo "✅ Structure validation PASSED"
    exit 0
else
    echo "✗ Structure validation FAILED"
    exit 1
fi
