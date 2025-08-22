source("fixtures/mock_responses.R")

test_that("detect_ipv handles empty narratives", {
  config <- list(api = list())
  
  result <- detect_ipv(NA, "LE", config)
  expect_true(is.na(result$ipv_detected))
  expect_equal(result$rationale, "No narrative available")
  
  result <- detect_ipv("", "LE", config)
  expect_true(is.na(result$ipv_detected))
})

test_that("init_database creates SQLite database", {
  tmp_db <- tempfile(fileext = ".sqlite")
  conn <- init_database(tmp_db)
  
  # Check table exists
  tables <- DBI::dbListTables(conn)
  expect_true("api_logs" %in% tables)
  
  DBI::dbDisconnect(conn)
  unlink(tmp_db)
})

test_that("load_config handles environment variables", {
  # Create temp config
  tmp_config <- tempfile(fileext = ".yml")
  writeLines(c(
    "api:",
    '  base_url: "${TEST_URL:-http://default}"',
    "  timeout: 30"
  ), tmp_config)
  
  # Test with env var
  Sys.setenv(TEST_URL = "http://custom")
  config <- load_config(tmp_config)
  expect_equal(config$api$base_url, "http://custom")
  
  # Test with default
  Sys.unsetenv("TEST_URL")
  config <- load_config(tmp_config)
  expect_equal(config$api$base_url, "http://default")
  
  unlink(tmp_config)
})

test_that("reconcile_results handles missing narratives", {
  results <- data.frame(
    le_ipv = c(TRUE, NA, FALSE),
    le_confidence = c(0.8, NA, 0.3),
    cme_ipv = c(FALSE, TRUE, NA),
    cme_confidence = c(0.2, 0.9, NA)
  )
  
  config <- list(weights = list(le = 0.4, cme = 0.6, threshold = 0.5))
  
  reconciled <- reconcile_results(results, config)
  
  # First row: weighted average
  expect_equal(reconciled$confidence[1], 0.8 * 0.4 + 0.2 * 0.6)
  
  # Second row: only CME
  expect_equal(reconciled$ipv_detected[2], TRUE)
  expect_equal(reconciled$confidence[2], 0.9)
  
  # Third row: only LE
  expect_equal(reconciled$ipv_detected[3], FALSE)
  expect_equal(reconciled$confidence[3], 0.3)
})