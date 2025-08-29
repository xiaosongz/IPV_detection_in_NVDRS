# Tests for build_prompt function - minimal and focused

# Source the function
source(here::here("R", "build_prompt.R"))

test_that("build_prompt creates correct message structure", {
  result <- build_prompt("You are helpful.", "Hello world")
  
  expect_type(result, "list")
  expect_length(result, 2)
  
  # Check system message
  expect_equal(result[[1]]$role, "system")
  expect_equal(result[[1]]$content, "You are helpful.")
  
  # Check user message
  expect_equal(result[[2]]$role, "user")
  expect_equal(result[[2]]$content, "Hello world")
})

test_that("build_prompt handles empty strings", {
  result <- build_prompt("", "")
  expect_equal(result[[1]]$content, "")
  expect_equal(result[[2]]$content, "")
})

test_that("build_prompt rejects invalid inputs", {
  # NULL inputs
  expect_error(build_prompt(NULL, "valid"))
  expect_error(build_prompt("valid", NULL))
  
  # Non-character inputs
  expect_error(build_prompt(123, "valid"))
  expect_error(build_prompt("valid", 456))
  
  # Multiple element vectors
  expect_error(build_prompt(c("prompt1", "prompt2"), "valid"))
})

test_that("build_prompt preserves content exactly", {
  # Test with whitespace
  spaces <- "  text with spaces  "
  result <- build_prompt(spaces, spaces)
  expect_equal(result[[1]]$content, spaces)
  expect_equal(result[[2]]$content, spaces)
  
  # Test with special characters
  special <- "Line1\nLine2\t'quoted'\""
  result <- build_prompt(special, special)
  expect_equal(result[[1]]$content, special)
  expect_equal(result[[2]]$content, special)
})