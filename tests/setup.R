# Setup script for testing
# This ensures tests can find files regardless of working directory

library(here)
library(testthat)

# Set the project root
here::i_am("tests/setup.R")

# Helper function to read test prompt
read_test_prompt <- function() {
  prompt_file <- here::here("tests", "test_promt.txt")
  if (!file.exists(prompt_file)) {
    skip("Test prompt file not found")
  }
  readLines(prompt_file, warn = FALSE) |>
    paste(collapse = "\n")
}