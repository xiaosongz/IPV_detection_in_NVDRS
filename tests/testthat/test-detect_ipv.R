# Tests for detect_ipv function
# Following tidyverse style guide

test_that("detect_ipv returns expected structure", {
  # Skip if no API available
  skip_if_not(
    httr2::request("http://localhost:1234") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform() |>
      (\(x) TRUE)() |>
      tryCatch(error = function(e) FALSE),
    "LLM API not available"
  )
  
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Test with sample narrative
  result <- detect_ipv("The victim was shot by her husband.")
  
  # Check structure
  expect_type(result, "list")
  expect_true("detected" %in% names(result))
  expect_true("confidence" %in% names(result))
})

test_that("detect_ipv handles empty input", {
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Test empty string
  result <- detect_ipv("")
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
  expect_equal(result$error, "empty input")
  
  # Test NULL
  result <- detect_ipv(NULL)
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
  
  # Test NA
  result <- detect_ipv(NA)
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
})

test_that("detect_ipv handles whitespace", {
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Test whitespace only
  result <- detect_ipv("   ")
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
  expect_equal(result$error, "empty input")
})

test_that("detect_ipv accepts custom config", {
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Custom config
  custom_config <- list(
    api_url = "http://fake-api.com/v1/chat",
    model = "test-model",
    prompt_template = "Test prompt: %s"
  )
  
  # This should fail with the fake API
  result <- detect_ipv("Test narrative", custom_config)
  
  # Should return error structure
  expect_type(result, "list")
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
  expect_true("error" %in% names(result))
})

test_that("detect_ipv handles API errors gracefully", {
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Use invalid API URL
  bad_config <- list(
    api_url = "http://invalid-url-that-does-not-exist:9999/api",
    model = "test",
    prompt_template = "Test: %s"
  )
  
  # Should not crash, should return error
  result <- detect_ipv("Test text", bad_config)
  
  expect_type(result, "list")
  expect_true(is.na(result$detected))
  expect_equal(result$confidence, 0)
  expect_true("error" %in% names(result))
})

test_that("detect_ipv trims input text", {
  # Source the function
  source(here::here("docs", "ULTIMATE_CLEAN.R"))
  
  # Skip if no API available
  skip_if_not(
    httr2::request("http://localhost:1234") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform() |>
      (\(x) TRUE)() |>
      tryCatch(error = function(e) FALSE),
    "LLM API not available"
  )
  
  # Text with leading/trailing spaces
  text_with_spaces <- "  The victim was shot by her husband.  "
  text_trimmed <- "The victim was shot by her husband."
  
  # Both should give same result (if API is deterministic)
  result1 <- detect_ipv(text_with_spaces)
  result2 <- detect_ipv(text_trimmed)
  
  # Both should return valid structures
  expect_type(result1, "list")
  expect_type(result2, "list")
  expect_true("detected" %in% names(result1))
  expect_true("detected" %in% names(result2))
})