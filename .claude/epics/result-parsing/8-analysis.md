---
issue: 8
title: Fix experiment tracking test failures
analyzed: 2025-08-29T18:19:05Z
estimated_hours: 2-3
parallelization_factor: 2.5
---

# Parallel Work Analysis: Issue #8

## Overview
Fix 19 failing tests in the experiment_analysis test suite. The core functionality works but report generation and test expectations need updates. Also need to address database connection cleanup warnings.

## Parallel Streams

### Stream A: Fix Report Generation Functions
**Scope**: Fix the experiment_report() function to generate expected output format
**Files**:
- `R/experiment_analysis.R` - Fix report generation functions
- `R/experiment_utils.R` - Update any supporting utilities
**Agent Type**: backend-architect
**Can Start**: immediately
**Estimated Hours**: 1 hour
**Dependencies**: none

### Stream B: Update Test Expectations
**Scope**: Update test expectations to match actual output and add connection cleanup
**Files**:
- `tests/testthat/test-experiment_analysis.R` - Update test expectations
- `tests/testthat/test-experiment_utils.R` - Fix any related test issues
**Agent Type**: qa
**Can Start**: immediately  
**Estimated Hours**: 1 hour
**Dependencies**: none (can work in parallel with Stream A)

### Stream C: Database Connection Cleanup
**Scope**: Add proper database connection cleanup to prevent warnings
**Files**:
- `tests/testthat/test-experiment_analysis.R` - Add dbDisconnect calls
- `tests/testthat/test-db_utils.R` - Verify connection cleanup patterns
- `R/experiment_utils.R` - Ensure functions close connections properly
**Agent Type**: backend-architect
**Can Start**: immediately
**Estimated Hours**: 0.5 hours
**Dependencies**: none

### Stream D: Integration Verification
**Scope**: Verify both SQLite and PostgreSQL backends work correctly
**Files**:
- `tests/testthat/test-experiment_analysis.R` - Add backend-specific tests
- `tests/performance/test_experiment_tracking.R` - Create integration tests
**Agent Type**: test-automator
**Can Start**: after Streams A, B, C complete
**Estimated Hours**: 0.5 hours
**Dependencies**: Streams A, B, C

## Coordination Points

### Shared Files
Files that multiple streams need to modify:
- `tests/testthat/test-experiment_analysis.R` - Streams B & C (coordinate test updates vs cleanup)
- `R/experiment_utils.R` - Streams A & C (coordinate function fixes vs connection handling)

### Sequential Requirements
1. Streams A, B, C can run in parallel
2. Stream D must wait for A, B, C to complete
3. Final test run to verify all fixes

## Conflict Risk Assessment
- **Low Risk**: Streams work on different aspects of the same problem
- **Medium Risk**: Some shared files between streams, but changes are in different sections
- **Coordination Needed**: Streams B and C both modify test files but different aspects

## Parallelization Strategy

**Recommended Approach**: Hybrid

Launch Streams A, B, and C simultaneously since they address different aspects:
- Stream A fixes the functions that generate reports
- Stream B updates test expectations
- Stream C adds cleanup code

Stream D runs after the first three complete to verify everything works together.

## Expected Timeline

With parallel execution:
- Wall time: 1.5 hours (1h parallel + 0.5h verification)
- Total work: 3 hours
- Efficiency gain: 50%

Without parallel execution:
- Wall time: 3 hours

## Notes
- The 19 failing tests are mostly about report format expectations, not functional failures
- Core experiment tracking functionality is working
- Database connection warnings are about cleanup, not actual connection issues
- Tests need to work with both SQLite and PostgreSQL backends
- Focus on making tests more robust rather than just fixing current failures