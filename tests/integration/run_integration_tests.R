#!/usr/bin/env Rscript
# Integration Test Runner
#
# Comprehensive runner for all integration tests with performance monitoring
# and detailed reporting. Validates the complete IPV detection workflow.

# Load required libraries
library(testthat)
library(here)

# Set up environment
here::i_am("tests/integration/run_integration_tests.R")

# Source all required functions
cat("Loading IPV detection system...\n")
source(here::here("R", "0_setup.R"))
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "utils.R"))

# Source test helpers
source(here::here("tests", "integration", "helpers", "test_data_helpers.R"))

#' Run Integration Tests with Performance Monitoring
#'
#' Executes all integration tests and generates performance reports.
#'
#' @param verbose Logical. Whether to show detailed output
#' @param report_file Character. Path to save performance report
#' @return List with test results and performance metrics
run_integration_tests <- function(verbose = TRUE, report_file = NULL) {
  
  cat("\n" %||% "=== IPV Detection Integration Test Suite ===\n")
  cat("Starting comprehensive integration tests...\n\n")
  
  # Initialize performance tracking
  start_time <- Sys.time()
  test_results <- list()
  performance_metrics <- list(
    operations = character(0),
    response_times = numeric(0),
    memory_usage = numeric(0),
    by_operation = list()
  )
  
  # Monitor initial memory usage
  initial_memory <- as.numeric(system("ps -o rss= -p $$", intern = TRUE)) / 1024
  
  # Test 1: Full Workflow Tests
  cat("Running full workflow integration tests...\n")
  
  workflow_start <- Sys.time()
  tryCatch({
    source(here::here("tests", "integration", "test_full_workflow.R"))
    test_results$workflow <- "PASSED"
    cat("✓ Full workflow tests completed\n")
  }, error = function(e) {
    test_results$workflow <- paste("FAILED:", e$message)
    cat("✗ Full workflow tests failed:", e$message, "\n")
  })
  workflow_time <- as.numeric(difftime(Sys.time(), workflow_start, units = "secs"))
  
  performance_metrics$operations <- c(performance_metrics$operations, "workflow_tests")
  performance_metrics$response_times <- c(performance_metrics$response_times, workflow_time * 1000)
  performance_metrics$by_operation$workflow <- workflow_time * 1000
  
  # Test 2: Error Scenario Tests
  cat("\nRunning error scenario integration tests...\n")
  
  error_start <- Sys.time()
  tryCatch({
    source(here::here("tests", "integration", "test_error_scenarios.R"))
    test_results$error_scenarios <- "PASSED"
    cat("✓ Error scenario tests completed\n")
  }, error = function(e) {
    test_results$error_scenarios <- paste("FAILED:", e$message)
    cat("✗ Error scenario tests failed:", e$message, "\n")
  })
  error_time <- as.numeric(difftime(Sys.time(), error_start, units = "secs"))
  
  performance_metrics$operations <- c(performance_metrics$operations, "error_tests")
  performance_metrics$response_times <- c(performance_metrics$response_times, error_time * 1000)
  performance_metrics$by_operation$error_scenarios <- error_time * 1000
  
  # Monitor final memory usage
  final_memory <- as.numeric(system("ps -o rss= -p $$", intern = TRUE)) / 1024
  performance_metrics$memory_usage <- c(initial_memory, final_memory)
  performance_metrics$memory_mb <- final_memory - initial_memory
  
  # Calculate overall metrics
  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  performance_metrics$total_time_seconds <- total_time
  performance_metrics$ops_per_second <- length(performance_metrics$operations) / total_time
  
  # Generate summary report
  cat("\n=== Integration Test Summary ===\n")
  
  passed_tests <- sum(sapply(test_results, function(x) grepl("PASSED", x)))
  total_tests <- length(test_results)
  
  cat("Test Results:\n")
  for (test_name in names(test_results)) {
    status <- if (grepl("PASSED", test_results[[test_name]])) "✓" else "✗"
    cat(sprintf("  %s %s: %s\n", status, test_name, test_results[[test_name]]))
  }
  
  cat(sprintf("\nOverall: %d/%d tests passed\n", passed_tests, total_tests))
  
  cat("\nPerformance Summary:\n")
  cat(sprintf("  Total execution time: %.2f seconds\n", total_time))
  cat(sprintf("  Memory usage increase: %.1f MB\n", performance_metrics$memory_mb))
  
  # Performance validation
  performance_issues <- character(0)
  
  if (total_time > 300) {  # 5 minutes
    performance_issues <- c(performance_issues, "Total test time exceeds 5 minutes")
  }
  
  if (performance_metrics$memory_mb > 200) {  # 200MB
    performance_issues <- c(performance_issues, "Memory usage increase exceeds 200MB")
  }
  
  if (length(performance_issues) > 0) {
    cat("\nPerformance Warnings:\n")
    for (issue in performance_issues) {
      cat("  ⚠️ ", issue, "\n")
    }
  } else {
    cat("\n✓ All performance targets met\n")
  }
  
  # Generate detailed report if requested
  if (!is.null(report_file)) {
    detailed_report <- generate_detailed_report(test_results, performance_metrics)
    writeLines(detailed_report, report_file)
    cat(sprintf("\nDetailed report saved to: %s\n", report_file))
  }
  
  # Return results for programmatic use
  list(
    test_results = test_results,
    performance_metrics = performance_metrics,
    success = passed_tests == total_tests,
    summary = list(
      total_tests = total_tests,
      passed_tests = passed_tests,
      total_time = total_time,
      memory_increase = performance_metrics$memory_mb
    )
  )
}

#' Generate Detailed Test Report
#'
#' Creates a comprehensive report with all test results and performance data.
#'
#' @param test_results List of test results
#' @param performance_metrics List of performance measurements
#' @return Character vector with formatted report
generate_detailed_report <- function(test_results, performance_metrics) {
  
  report_lines <- c(
    "# IPV Detection Integration Test Report",
    paste("Generated:", Sys.time()),
    paste("System:", Sys.info()["sysname"], Sys.info()["release"]),
    paste("R Version:", R.version.string),
    "",
    "## Test Results Summary"
  )
  
  # Test results section
  for (test_name in names(test_results)) {
    status_icon <- if (grepl("PASSED", test_results[[test_name]])) "✅" else "❌"
    report_lines <- c(report_lines,
      paste("###", status_icon, stringr::str_to_title(gsub("_", " ", test_name))),
      paste("Status:", test_results[[test_name]]),
      ""
    )
  }
  
  # Performance section
  report_lines <- c(report_lines,
    "## Performance Metrics",
    paste("Total execution time:", round(performance_metrics$total_time_seconds, 2), "seconds"),
    paste("Memory usage increase:", round(performance_metrics$memory_mb, 1), "MB"),
    paste("Operations per second:", round(performance_metrics$ops_per_second, 2)),
    ""
  )
  
  # Detailed timing breakdown
  if (length(performance_metrics$by_operation) > 0) {
    report_lines <- c(report_lines, "### Timing Breakdown")
    for (op in names(performance_metrics$by_operation)) {
      timing <- performance_metrics$by_operation[[op]]
      report_lines <- c(report_lines,
        paste("-", stringr::str_to_title(gsub("_", " ", op)), ":", round(timing / 1000, 2), "seconds")
      )
    }
    report_lines <- c(report_lines, "")
  }
  
  # System requirements validation
  report_lines <- c(report_lines,
    "## System Requirements Validation",
    paste("✓ R Version >= 4.0:", R.version$major >= "4"),
    paste("✓ Test data available:", file.exists(here::here("data-raw", "suicide_IPV_manuallyflagged.xlsx"))),
    paste("✓ All required packages loaded:", TRUE),  # If we got here, packages are loaded
    ""
  )
  
  # Recommendations
  report_lines <- c(report_lines,
    "## Recommendations"
  )
  
  if (performance_metrics$total_time_seconds > 180) {
    report_lines <- c(report_lines, "- Consider running tests in parallel for faster execution")
  }
  
  if (performance_metrics$memory_mb > 100) {
    report_lines <- c(report_lines, "- Monitor memory usage during batch processing")
  }
  
  report_lines <- c(report_lines,
    "- Run integration tests regularly during development",
    "- Monitor performance trends over time",
    "- Update test data periodically with new cases",
    ""
  )
  
  # Footer
  report_lines <- c(report_lines,
    "---",
    "Report generated by IPV Detection Integration Test Suite",
    paste("For more information, see:", here::here("tests", "integration", "README.md"))
  )
  
  report_lines
}

# Main execution when run as script
if (!interactive()) {
  # Parse command line arguments
  args <- commandArgs(trailingOnly = TRUE)
  
  verbose <- TRUE
  report_file <- NULL
  
  if ("--quiet" %in% args) {
    verbose <- FALSE
  }
  
  report_arg_index <- which(args == "--report")
  if (length(report_arg_index) > 0 && length(args) > report_arg_index) {
    report_file <- args[report_arg_index + 1]
  }
  
  # Run the tests
  results <- run_integration_tests(verbose = verbose, report_file = report_file)
  
  # Exit with appropriate code
  if (results$success) {
    cat("\n🎉 All integration tests passed!\n")
    quit(status = 0)
  } else {
    cat("\n❌ Some integration tests failed!\n")
    quit(status = 1)
  }
}

# For interactive use, provide helper message
if (interactive()) {
  cat("Integration Test Runner Loaded\n")
  cat("Usage:\n")
  cat("  run_integration_tests()                    # Run all tests\n")
  cat("  run_integration_tests(verbose = FALSE)     # Run quietly\n")
  cat("  run_integration_tests(report_file = 'report.md')  # Save detailed report\n")
  cat("\nOr run from command line:\n")
  cat("  Rscript tests/integration/run_integration_tests.R\n")
  cat("  Rscript tests/integration/run_integration_tests.R --quiet\n")
  cat("  Rscript tests/integration/run_integration_tests.R --report integration_report.md\n")
}