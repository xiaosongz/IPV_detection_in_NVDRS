# Tests for utils.R
# Utility functions

test_that("trimws_safe trims whitespace", {
  result <- trimws_safe("  hello  ")
  expect_equal(result, "hello")
})

test_that("trimws_safe handles NULL", {
  result <- trimws_safe(NULL)
  expect_equal(result, "")
})

test_that("trimws_safe handles NA", {
  result <- trimws_safe(NA)
  expect_equal(result, "")
})

test_that("trimws_safe handles empty string", {
  result <- trimws_safe("")
  expect_equal(result, "")
})

test_that("trimws_safe handles numeric input", {
  result <- trimws_safe(123)
  expect_equal(result, "123")
})

test_that("trimws_safe handles vectors", {
  result <- trimws_safe(c("  a  ", "  b  ", "  c  "))
  expect_equal(result, c("a", "b", "c"))
})

test_that("trimws_safe handles mixed vector with NA", {
  result <- trimws_safe(c("  a  ", NA, "  b  "))
  expect_equal(result, c("a", "", "b"))
})

test_that("trimws_safe preserves character encoding", {
  result <- trimws_safe("  café  ")
  expect_equal(result, "café")
})
