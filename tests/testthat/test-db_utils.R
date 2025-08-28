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