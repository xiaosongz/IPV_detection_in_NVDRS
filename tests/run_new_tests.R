#!/usr/bin/env Rscript
#
# Run the new test suite
# Usage: Rscript tests/run_new_tests.R

library(testthat)
library(here)

# Source all R files (excluding legacy)
message("Loading R files...")
r_files <- list.files(here("R"), pattern = "\\.[Rr]$", full.names = TRUE, recursive = FALSE)
r_files <- r_files[!grepl("legacy", r_files)]

for (file in r_files) {
  tryCatch({
    source(file)
    message(sprintf("  ✓ %s", basename(file)))
  }, error = function(e) {
    message(sprintf("  ✗ %s: %s", basename(file), e$message))
  })
}

# Run tests
message("\nRunning tests...")
test_results <- test_dir(
  here("tests", "testthat"),
  reporter = "progress",
  stop_on_failure = FALSE
)

# Summary
message("\n" , strrep("=", 60))
message("TEST SUMMARY")
message(strrep("=", 60))

if (length(test_results) > 0) {
  n_pass <- sum(sapply(test_results, function(x) attr(x, "passed")))
  n_fail <- sum(sapply(test_results, function(x) attr(x, "failed")))
  n_skip <- sum(sapply(test_results, function(x) attr(x, "skipped")))
  
  message(sprintf("Passed:  %d", n_pass))
  message(sprintf("Failed:  %d", n_fail))
  message(sprintf("Skipped: %d", n_skip))
  
  if (n_fail > 0) {
    message("\n❌ TESTS FAILED")
    quit(status = 1)
  } else {
    message("\n✅ ALL TESTS PASSED")
    quit(status = 0)
  }
} else {
  message("No test results")
  quit(status = 1)
}
