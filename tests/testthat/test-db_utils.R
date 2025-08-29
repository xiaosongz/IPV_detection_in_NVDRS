# Source required functions
library(here)
source(here::here("R", "0_setup.R"))
source(here::here("R", "db_utils.R"))
source(here::here("R", "experiment_utils.R"))
source(here::here("R", "experiment_analysis.R"))

test_that("get_db_connection creates valid SQLite connection", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  # Use temporary database
  db_file <- tempfile(fileext = ".db")
  
  conn <- get_db_connection(db_file)
  expect_true(DBI::dbIsValid(conn))
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("ensure_schema creates tables and indexes", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  
  # Create schema
  result <- ensure_schema(conn)
  expect_true(result)
  
  # Check table exists
  tables <- DBI::dbListTables(conn)
  expect_true("llm_results" %in% tables)
  
  # Check columns
  fields <- DBI::dbListFields(conn, "llm_results")
  expected_fields <- c("id", "narrative_id", "narrative_text", "detected", 
                      "confidence", "model", "prompt_tokens", 
                      "completion_tokens", "total_tokens", 
                      "response_time_ms", "raw_response", 
                      "error_message", "created_at")
  expect_true(all(expected_fields %in% fields))
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("schema versioning works", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  
  # Initial version should be 0
  version <- get_schema_version(conn)
  expect_equal(version, 0L)
  
  # Set version
  set_schema_version(conn, 42L)
  new_version <- get_schema_version(conn)
  expect_equal(new_version, 42L)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("ensure_schema is idempotent", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  
  # Call multiple times - should not error
  expect_true(ensure_schema(conn))
  expect_true(ensure_schema(conn))
  expect_true(ensure_schema(conn))
  
  # Table should still exist and be valid
  tables <- DBI::dbListTables(conn)
  expect_true("llm_results" %in% tables)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

# Connection type detection tests
test_that("detect_db_type works correctly", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  # Test SQLite detection
  db_file <- tempfile(fileext = ".db")
  sqlite_conn <- get_db_connection(db_file)
  expect_equal(detect_db_type(sqlite_conn), "sqlite")
  close_db_connection(sqlite_conn)
  unlink(db_file)
  
  # Test invalid connection
  expect_equal(detect_db_type(NULL), "unknown")
})

test_that("test_connection_health works", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  
  # Test basic health check
  health <- test_connection_health(conn)
  expect_true(health$healthy)
  expect_equal(health$db_type, "sqlite")
  expect_true(is.numeric(health$response_time_ms))
  expect_null(health$error)
  
  # Test detailed health check
  detailed <- test_connection_health(conn, detailed = TRUE)
  expect_true(detailed$healthy)
  expect_true(is.list(detailed$query_result))
  expect_true(is.list(detailed$connection_info))
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
  
  # Test invalid connection
  invalid_health <- test_connection_health(NULL)
  expect_false(invalid_health$healthy)
  expect_equal(invalid_health$db_type, "unknown")
})

test_that("get_unified_connection auto-detection works", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  # Test SQLite auto-detection with string path
  db_file <- tempfile(fileext = ".db")
  conn <- get_unified_connection(db_file, type = "auto")
  expect_equal(detect_db_type(conn), "sqlite")
  close_db_connection(conn)
  unlink(db_file)
  
  # Test explicit SQLite type
  db_file2 <- tempfile(fileext = ".db")
  conn2 <- get_unified_connection(db_file2, type = "sqlite")
  expect_equal(detect_db_type(conn2), "sqlite")
  close_db_connection(conn2)
  unlink(db_file2)
})

test_that("validate_db_config works for SQLite", {
  # Valid SQLite config
  temp_dir <- tempdir()
  db_path <- file.path(temp_dir, "test.db")
  
  validation <- validate_db_config(db_path, type = "sqlite")
  expect_true(validation$valid)
  expect_equal(validation$type, "sqlite")
  expect_length(validation$errors, 0)
  
  # Invalid SQLite config - non-existent directory
  invalid_path <- file.path("/non/existent/dir", "test.db")
  invalid_validation <- validate_db_config(invalid_path, type = "sqlite")
  expect_false(invalid_validation$valid)
  expect_length(invalid_validation$errors, 1)
  expect_match(invalid_validation$errors[1], "Database directory does not exist")
})

test_that("cleanup_connections works", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  # Create multiple connections
  db_file1 <- tempfile(fileext = ".db")
  db_file2 <- tempfile(fileext = ".db")
  
  conn1 <- get_db_connection(db_file1)
  conn2 <- get_db_connection(db_file2)
  
  # Test single connection cleanup
  count <- cleanup_connections(conn1)
  expect_equal(count, 1L)
  
  # Test multiple connections cleanup
  count <- cleanup_connections(list(conn2, NULL))
  expect_equal(count, 1L)
  
  # Clean up files
  unlink(c(db_file1, db_file2))
  
  # Test with NULL
  count <- cleanup_connections(NULL)
  expect_equal(count, 0L)
})

test_that("execute_with_transaction works", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  ensure_schema(conn)
  
  # Test successful transaction
  result <- execute_with_transaction(conn, {
    DBI::dbExecute(conn, "INSERT INTO llm_results (narrative_text, detected) VALUES ('test', 1)")
    DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")
  })
  expect_equal(result$count, 1)
  
  # Test transaction rollback on error
  expect_error(
    execute_with_transaction(conn, {
      DBI::dbExecute(conn, "INSERT INTO llm_results (narrative_text, detected) VALUES ('test2', 1)")
      stop("Simulated error")
    }),
    "Transaction failed"
  )
  
  # Check that second insert was rolled back
  count_after <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as count FROM llm_results")
  expect_equal(count_after$count, 1)  # Only first insert should remain
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

# PostgreSQL-specific tests (will be skipped if PostgreSQL not available)
test_that("connect_postgres with retry and timeout", {
  skip_if_not_installed("DBI")
  skip("PostgreSQL tests require server connection - skipping in automated tests")
  
  # These tests would run if PostgreSQL server is available
  # They test the enhanced connect_postgres function with retries and timeouts
  
  # Test with invalid credentials should fail after retries
  # Sys.setenv(POSTGRES_PASSWORD = "wrong_password")
  # expect_error(connect_postgres(retry_attempts = 2), "Failed to connect")
  
  # Test with valid credentials should succeed
  # conn <- connect_postgres()
  # expect_true(DBI::dbIsValid(conn))
  # expect_equal(detect_db_type(conn), "postgresql")
  # close_db_connection(conn)
})

test_that("PostgreSQL schema version handling", {
  skip_if_not_installed("DBI")
  skip("PostgreSQL tests require server connection - skipping in automated tests")
  
  # These would test the PostgreSQL-specific schema version functions
  # conn <- connect_postgres()
  
  # # Test initial version
  # version <- get_schema_version(conn)
  # expect_equal(version, 0L)
  
  # # Set and get version
  # set_schema_version(conn, 42L)
  # new_version <- get_schema_version(conn)
  # expect_equal(new_version, 42L)
  
  # # Test metadata table creation
  # tables <- DBI::dbListTables(conn)
  # expect_true("_schema_metadata" %in% tables)
  
  # close_db_connection(conn)
})

test_that("PostgreSQL schema creation with constraints", {
  skip_if_not_installed("DBI")
  skip("PostgreSQL tests require server connection - skipping in automated tests")
  
  # These would test PostgreSQL-specific schema features
  # conn <- connect_postgres()
  # ensure_schema(conn)
  
  # # Test that PostgreSQL constraints are applied
  # expect_error(
  #   DBI::dbExecute(conn, "INSERT INTO llm_results (detected, confidence) VALUES (1, 1.5)"),
  #   "violates check constraint"
  # )
  
  # close_db_connection(conn)
})