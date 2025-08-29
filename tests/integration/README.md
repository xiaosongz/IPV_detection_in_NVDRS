# Integration Test Suite

## Overview
Comprehensive integration testing for the IPV detection system, validating end-to-end workflows, database backends, and production scenarios.

## Test Structure

### Core Test Files

#### `test_full_workflow.R`
Complete end-to-end testing of the detection pipeline:
- LLM integration
- Result parsing
- Database storage
- Error handling

#### `test_error_scenarios.R`
Validation of error handling and recovery:
- Network failures
- Database errors
- Invalid inputs
- Resource exhaustion

#### `test_database_backends.R`
Database-specific testing:
- SQLite operations
- PostgreSQL operations
- Transaction handling
- Connection pooling

#### `test_concurrent_access.R`
Parallel operation testing:
- Multiple simultaneous detections
- Database locking behavior
- Race condition prevention
- Thread safety

#### `test_production_scenarios.R`
Real-world usage patterns:
- Mixed workloads
- Peak load handling
- Long-running operations
- Resource management

### Helper Files

#### `helpers/test_data_helpers.R`
Test data generation and utilities:
- Sample narrative creation
- Expected result generation
- Database setup/teardown
- Mock data providers

#### `run_integration_tests.R`
Test orchestration script:
- Sequential test execution
- Parallel test options
- Result aggregation
- Report generation

## Running Tests

### Quick Start
```r
# Run all integration tests
source("tests/integration/run_integration_tests.R")
run_all_integration_tests()
```

### Individual Test Suites
```r
# Run specific test file
testthat::test_file("tests/integration/test_full_workflow.R")

# Run with specific database
Sys.setenv(TEST_DB = "postgres")
testthat::test_file("tests/integration/test_database_backends.R")
```

### Parallel Execution
```r
# Run tests in parallel (faster but may have conflicts)
run_all_integration_tests(parallel = TRUE, cores = 4)
```

## Test Configuration

### Environment Variables
```bash
# Database configuration
TEST_DB=sqlite|postgres     # Database backend to test
TEST_DB_PATH=/path/to/db   # SQLite database path
TEST_PG_HOST=localhost      # PostgreSQL host
TEST_PG_PORT=5432          # PostgreSQL port
TEST_PG_USER=testuser      # PostgreSQL user
TEST_PG_PASS=testpass      # PostgreSQL password
TEST_PG_DB=testdb          # PostgreSQL database

# Test behavior
TEST_VERBOSE=TRUE          # Verbose output
TEST_CLEANUP=TRUE          # Clean up after tests
TEST_PARALLEL=FALSE        # Run tests in parallel
```

### Test Data
Test data is stored in:
- `data-raw/`: Sample narratives and expected results
- `tests/testthat/fixtures/`: Mock responses and configurations
- Generated dynamically by `test_data_helpers.R`

## Test Coverage

### Functional Coverage
- ✅ Detection accuracy
- ✅ Result parsing
- ✅ Database operations
- ✅ Error handling
- ✅ Edge cases

### Non-functional Coverage
- ✅ Performance requirements
- ✅ Resource constraints
- ✅ Concurrent operations
- ✅ Recovery mechanisms
- ✅ Security validations

## Continuous Integration

### GitHub Actions
```yaml
# .github/workflows/integration-tests.yml
name: Integration Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
    steps:
      - uses: actions/checkout@v2
      - uses: r-lib/actions/setup-r@v2
      - run: Rscript tests/integration/run_integration_tests.R
```

### Local Pre-commit
```bash
# .git/hooks/pre-commit
#!/bin/bash
Rscript tests/integration/run_integration_tests.R --quick
```

## Troubleshooting

### Common Issues

#### Database Connection Errors
```r
# Check database availability
DBI::dbCanConnect(RSQLite::SQLite(), ":memory:")
DBI::dbCanConnect(RPostgres::Postgres(), ...)
```

#### Test Timeouts
```r
# Increase timeout for slow operations
options(testthat.progress.max_fails = 99999)
withr::local_options(list(timeout = 300))
```

#### Memory Issues
```r
# Monitor memory usage
pryr::mem_used()
gc()
```

### Debug Mode
```r
# Enable detailed logging
options(
  ipv.debug = TRUE,
  testthat.verbose = TRUE
)

# Run single test with debugging
debugonce(test_full_workflow)
testthat::test_file("tests/integration/test_full_workflow.R")
```

## Performance Benchmarks

Integration tests also collect performance metrics:

### Metrics Collected
- Execution time per test
- Memory usage
- Database query counts
- Error rates

### Baseline Requirements
- Full suite: < 5 minutes
- Individual test: < 30 seconds
- Memory usage: < 500MB
- Database queries: < 1000 per test

## Maintenance

### Adding New Tests
1. Create test file in `tests/integration/`
2. Follow naming convention: `test_<feature>.R`
3. Use helper functions from `test_data_helpers.R`
4. Update this README with test description
5. Add to `run_integration_tests.R` if needed

### Updating Test Data
1. Place new samples in `data-raw/`
2. Update `test_data_helpers.R` generators
3. Document expected results
4. Version control test data changes

### Test Review Schedule
- **Weekly**: Review failing tests
- **Monthly**: Update test data
- **Quarterly**: Performance baseline review
- **Annually**: Full test suite audit

## Related Documentation
- [Performance Characteristics](../PERFORMANCE_CHARACTERISTICS.md)
- [Production Validation](../PRODUCTION_VALIDATION.md)
- [Main README](../../README.md)

## Contact
For test-related issues, open a GitHub issue with the `testing` label.