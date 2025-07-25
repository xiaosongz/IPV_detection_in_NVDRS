# IPV Detection System - Testing Framework Design

## Overview

This document outlines the comprehensive testing framework for the IPV Detection system, covering unit tests, integration tests, performance tests, and end-to-end validation.

## Testing Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Test Orchestration                        │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐   │
│  │ Test Runner │  │   Coverage  │  │   CI/CD Pipeline │   │
│  │  (testthat) │  │   (covr)    │  │  (GitHub Actions)│   │
│  └─────────────┘  └─────────────┘  └──────────────────┘   │
└─────────────────────────┬───────────────────────────────────┘
                          │
    ┌─────────────────────┴─────────────────────────────┐
    │                                                    │
┌───▼──────────┐  ┌────────────────┐  ┌────────────────┐
│  Unit Tests  │  │Integration Tests│  │Performance Tests│
├──────────────┤  ├────────────────┤  ├────────────────┤
│ • Config     │  │ • Provider     │  │ • Load Testing │
│ • Logger     │  │ • Pipeline     │  │ • Memory Usage │
│ • Validators │  │ • End-to-End   │  │ • API Limits   │
│ • Providers  │  │ • Error Cases  │  │ • Scalability  │
└──────────────┘  └────────────────┘  └────────────────┘
```

## Test Categories

### 1. Unit Tests

#### Configuration Management Tests
```R
# tests/testthat/test-config.R
test_that("ConfigManager loads valid configuration", {
  # Test successful loading
  # Test validation
  # Test environment overrides
  # Test error handling
})

test_that("ConfigManager handles missing files gracefully", {
  # Test missing config file
  # Test fallback to example
  # Test error messages
})

test_that("Configuration validation catches errors", {
  # Test missing sections
  # Test invalid values
  # Test type mismatches
})
```

#### Logger Tests
```R
# tests/testthat/test-logger.R
test_that("Logger writes to correct outputs", {
  # Test console output
  # Test file output
  # Test log levels
  # Test rotation
})

test_that("Logger formats messages correctly", {
  # Test text format
  # Test JSON format
  # Test context inclusion
  # Test timestamp format
})
```

#### Provider Tests
```R
# tests/testthat/test-providers.R
test_that("OpenAI provider handles API responses", {
  # Mock API responses
  # Test successful processing
  # Test error handling
  # Test rate limiting
})

test_that("Ollama provider handles connection issues", {
  # Test connection checking
  # Test timeout handling
  # Test fallback behavior
})

test_that("Provider factory creates correct instances", {
  # Test provider selection
  # Test configuration passing
  # Test error cases
})
```

### 2. Integration Tests

#### End-to-End Processing Tests
```R
# tests/testthat/test-integration.R
test_that("Complete processing pipeline works", {
  # Load test data
  # Process with mock provider
  # Validate output structure
  # Check progress tracking
})

test_that("Checkpoint recovery works correctly", {
  # Start processing
  # Interrupt midway
  # Resume from checkpoint
  # Verify completeness
})

test_that("Multiple providers produce consistent results", {
  # Process same data with different providers
  # Compare results
  # Check consistency metrics
})
```

### 3. Performance Tests

#### Load Testing
```R
# tests/performance/test-load.R
test_performance <- function() {
  # Test different batch sizes
  # Measure processing time
  # Monitor memory usage
  # Check API rate limits
  
  results <- list(
    batch_10 = measure_performance(batch_size = 10),
    batch_20 = measure_performance(batch_size = 20),
    batch_50 = measure_performance(batch_size = 50)
  )
  
  # Generate performance report
  create_performance_report(results)
}
```

## Test Data Management

### Mock Data Generation
```R
# tests/fixtures/generate_test_data.R

#' Generate test narratives
generate_test_narratives <- function(n = 100, 
                                   include_ipv = 0.3,
                                   include_na = 0.1) {
  narratives <- vector("character", n)
  
  # Templates for different scenarios
  ipv_templates <- c(
    "Victim was shot by her boyfriend during a domestic dispute...",
    "The decedent's husband had a history of violence...",
    "Police responded to a domestic violence call..."
  )
  
  non_ipv_templates <- c(
    "Single vehicle accident on highway...",
    "Work-related injury at construction site...",
    "Medical emergency with no signs of trauma..."
  )
  
  # Generate narratives
  for (i in 1:n) {
    if (runif(1) < include_na) {
      narratives[i] <- NA
    } else if (runif(1) < include_ipv) {
      narratives[i] <- sample(ipv_templates, 1)
    } else {
      narratives[i] <- sample(non_ipv_templates, 1)
    }
  }
  
  return(data.frame(
    IncidentID = sprintf("TEST%06d", 1:n),
    NarrativeCME = narratives,
    NarrativeLE = narratives  # Simplified for testing
  ))
}
```

### Mock API Responses
```R
# tests/fixtures/mock_responses.R

#' Create mock OpenAI response
mock_openai_response <- function(narratives) {
  results <- lapply(seq_along(narratives), function(i) {
    list(
      sequence = i,
      rationale = "Test rationale",
      key_facts_summary = "Test summary",
      family_friend_mentioned = sample(c("yes", "no", "unclear"), 1),
      intimate_partner_mentioned = sample(c("yes", "no", "unclear"), 1),
      violence_mentioned = sample(c("yes", "no", "unclear"), 1),
      substance_abuse_mentioned = sample(c("yes", "no", "unclear"), 1),
      ipv_between_intimate_partners = sample(c("yes", "no", "unclear"), 1)
    )
  })
  
  list(
    choices = list(
      list(
        message = list(
          content = jsonlite::toJSON(results, auto_unbox = TRUE)
        )
      )
    )
  )
}
```

## Test Utilities

### Test Helpers
```R
# tests/testthat/helper-testing.R

#' Create temporary test configuration
create_test_config <- function(modifications = list()) {
  base_config <- list(
    api = list(
      openai = list(
        key_env = "TEST_OPENAI_KEY",
        endpoint = "https://test.api.openai.com/v1/chat/completions",
        model = "gpt-test"
      )
    ),
    processing = list(
      batch_size = 5,
      max_retries = 1
    ),
    cache = list(
      enabled = FALSE,
      directory = tempdir()
    ),
    logging = list(
      level = "ERROR",
      directory = tempdir()
    )
  )
  
  # Apply modifications
  modifyList(base_config, modifications)
}

#' Set up test environment
setup_test_env <- function() {
  # Set test environment variables
  Sys.setenv(IPVD_ENV = "test")
  Sys.setenv(TEST_OPENAI_KEY = "test-key-123")
  
  # Create temp directories
  test_dirs <- list(
    cache = tempdir(),
    logs = tempdir(),
    output = tempdir()
  )
  
  return(test_dirs)
}

#' Clean up test environment
cleanup_test_env <- function(test_dirs) {
  # Remove temp files
  unlink(test_dirs$cache, recursive = TRUE)
  unlink(test_dirs$logs, recursive = TRUE)
  unlink(test_dirs$output, recursive = TRUE)
  
  # Clear environment variables
  Sys.unsetenv("IPVD_ENV")
  Sys.unsetenv("TEST_OPENAI_KEY")
}
```

## Continuous Integration

### GitHub Actions Workflow
```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macOS-latest]
        r-version: ['4.2', '4.3', 'release']
    
    steps:
    - uses: actions/checkout@v3
    
    - uses: r-lib/actions/setup-r@v2
      with:
        r-version: ${{ matrix.r-version }}
    
    - uses: r-lib/actions/setup-r-dependencies@v2
      with:
        extra-packages: |
          any::covr
          any::lintr
    
    - name: Run tests
      run: |
        Rscript -e 'testthat::test_dir("tests")'
    
    - name: Generate coverage report
      run: |
        Rscript -e 'covr::codecov()'
    
    - name: Lint code
      run: |
        Rscript -e 'lintr::lint_dir("R")'
```

## Test Execution Strategy

### Local Testing
```bash
# Run all tests
Rscript -e 'testthat::test_dir("tests")'

# Run specific test file
Rscript -e 'testthat::test_file("tests/testthat/test-config.R")'

# Run with coverage
Rscript -e 'covr::package_coverage()'

# Run performance tests
Rscript tests/performance/run_performance_tests.R
```

### Pre-commit Hooks
```bash
#!/bin/bash
# .git/hooks/pre-commit

# Run tests
echo "Running tests..."
Rscript -e 'testthat::test_dir("tests/testthat", stop_on_failure = TRUE)'

# Check code style
echo "Checking code style..."
Rscript -e 'lintr::lint_dir("R", linters = lintr::linters_with_defaults())'

# Check documentation
echo "Checking documentation..."
Rscript -e 'roxygen2::roxygenize()'
```

## Quality Metrics

### Code Coverage Targets
- Overall: ≥80%
- Core functions: ≥90%
- Error handling: ≥95%
- Provider implementations: ≥85%

### Performance Benchmarks
- Processing time: <5 seconds per batch of 20 narratives
- Memory usage: <500MB for 1000 narratives
- API efficiency: <50% of rate limit usage
- Cache hit rate: >90% on repeated runs

### Test Success Criteria
- All unit tests pass
- Integration tests complete without errors
- Performance within acceptable bounds
- No memory leaks detected
- Cross-platform compatibility verified

## Test Reporting

### Test Dashboard
```R
# tests/dashboard/test_dashboard.R

generate_test_dashboard <- function() {
  # Collect test results
  unit_results <- testthat::test_dir("tests/testthat")
  coverage_results <- covr::package_coverage()
  performance_results <- read_performance_results()
  
  # Generate HTML dashboard
  rmarkdown::render(
    "tests/dashboard/dashboard.Rmd",
    output_file = "test_results.html",
    params = list(
      unit_results = unit_results,
      coverage = coverage_results,
      performance = performance_results,
      timestamp = Sys.time()
    )
  )
}
```

## Future Enhancements

1. **Mutation Testing**: Verify test quality by introducing code mutations
2. **Property-Based Testing**: Generate random test cases automatically
3. **Visual Regression Testing**: For any UI components
4. **Stress Testing**: Extreme load and edge cases
5. **Security Testing**: Vulnerability scanning and penetration testing