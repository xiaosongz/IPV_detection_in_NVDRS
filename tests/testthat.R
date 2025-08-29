# This file runs tests for standalone R functions (not an R package)
# Run with: source("tests/testthat.R")

library(testthat)
library(here)

# Source all R functions
source(here::here("R", "0_setup.R"))
source(here::here("R", "build_prompt.R"))
source(here::here("R", "call_llm.R"))
source(here::here("R", "parse_llm_result.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))
source(here::here("R", "experiment_utils.R"))
source(here::here("R", "experiment_analysis.R"))
source(here::here("R", "utils.R"))

# Run the tests
test_dir(here::here("tests", "testthat"))
