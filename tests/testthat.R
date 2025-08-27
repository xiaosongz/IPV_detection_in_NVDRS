# This file is part of the standard testthat setup
# Run tests with: devtools::test() or testthat::test_local()

library(testthat)
library(here)

# Source the functions to test
source(here::here("R", "call_llm.R"))

# Run the tests
test_check("IPV_detection_in_NVDRS")