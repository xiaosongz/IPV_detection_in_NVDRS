# Tests Directory Structure

## Directory Organization

```
tests/
├── README.md                     # This file
├── integration_tests/            # Integration and real data tests
│   └── test_real_data.R         # Script to test with real NVDRS data
├── test_data/                   # Test input data and configurations
│   ├── test_config.yml          # Test configuration file
│   └── test_sample.csv          # Sample test data (20 records)
└── test_results/                # Test output and reports
    ├── test_results.csv         # Detection results from test run
    └── test_report.txt          # Detailed test report

nvdrsipvdetector/tests/testthat/ # Package unit tests (separate)
```

## Running Tests

### Unit Tests
```r
# Run all package unit tests
devtools::test()

# Or from command line
Rscript -e "testthat::test_package('nvdrsipvdetector')"
```

### Integration Tests
```r
# Run integration test with real data
source("tests/integration_tests/test_real_data.R")
```

### Test Data
- **test_sample.csv**: First 20 records from sui_all_flagged.xlsx
- **test_config.yml**: Mock configuration for testing without real LLM

### Test Results
- **test_results.csv**: IPV detection results from last test run
- **test_report.txt**: Detailed report with validation metrics

## Test Coverage
- Unit tests: 97 passing, 3 skipped (API-dependent)
- Integration test: Successfully processes real NVDRS data
- Mock validation: 55% accuracy with keyword-based mock LLM

## Notes
- Unit tests use mock responses and don't require actual LLM API
- Integration tests can run with or without real LLM connection
- All tests are non-destructive and use temporary files