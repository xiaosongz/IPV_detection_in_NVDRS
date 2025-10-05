# This file runs tests for the IPVdetection R package
# Run with: source("tests/testthat.R")

library(testthat)
library(here)

# Source all R functions that exist
r_files <- c(
  "IPVdetection-package.R",
  "build_prompt.R",
  "call_llm.R",
  "config_loader.R",
  "data_loader.R",
  "db_config.R",
  "db_schema.R",
  "experiment_logger.R",
  "experiment_queries.R",
  "parse_llm_result.R",
  "repair_json.R",
  "run_benchmark_core.R"
)

for (file in r_files) {
  file_path <- here::here("R", file)
  if (file.exists(file_path)) {
    source(file_path)
  } else {
    warning("File not found: ", file_path)
  }
}

# Run the tests
test_dir(here::here("tests", "testthat"))
