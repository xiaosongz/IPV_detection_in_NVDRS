# Tests for store_llm_result function

# Source required functions
source(here::here("R", "db_utils.R"))
source(here::here("R", "store_llm_result.R"))

test_that("store_llm_result stores valid parsed result", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  # Setup
  db_file <- tempfile(fileext = ".db")
  
  # Create sample parsed result
  parsed_result <- list(
    narrative_id = "TEST001",
    narrative_text = "Test narrative",
    detected = TRUE,
    confidence = 0.95,
    model = "gpt-4",
    prompt_tokens = 100,
    completion_tokens = 50,
    total_tokens = 150,
    response_time_ms = 1234,
    raw_response = '{"detected": true, "confidence": 0.95}'
  )
  
  # Store result
  result <- store_llm_result(parsed_result, db_path = db_file)
  expect_true(result$success)
  expect_equal(result$rows_inserted, 1)
  
  # Verify stored data
  conn <- get_db_connection(db_file)
  stored <- DBI::dbGetQuery(conn, "SELECT * FROM llm_results WHERE narrative_id = 'TEST001'")
  
  expect_equal(nrow(stored), 1)
  expect_equal(stored$narrative_id, "TEST001")
  expect_equal(stored$detected, 1)  # SQLite stores as integer
  expect_equal(stored$confidence, 0.95)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("store_llm_result handles duplicates", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  parsed_result <- list(
    narrative_id = "DUP001",
    narrative_text = "Duplicate test",
    detected = FALSE,
    confidence = 0.3,
    model = "gpt-4"
  )
  
  # First insertion
  result1 <- store_llm_result(parsed_result, db_path = db_file)
  expect_true(result1$success)
  
  # Duplicate insertion - should be ignored
  result2 <- store_llm_result(parsed_result, db_path = db_file)
  expect_true(result2$success)
  expect_true(!is.null(result2$warning))
  expect_match(result2$warning, "already exists", ignore.case = TRUE)
  
  # Verify only one record
  conn <- get_db_connection(db_file)
  count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM llm_results WHERE narrative_id = 'DUP001'")
  expect_equal(count$n, 1)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("store_llm_result handles missing fields gracefully", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Minimal valid result
  minimal_result <- list(
    detected = TRUE
  )
  
  result <- store_llm_result(minimal_result, db_path = db_file)
  expect_true(result$success)
  
  # Verify stored with NAs
  conn <- get_db_connection(db_file)
  stored <- DBI::dbGetQuery(conn, "SELECT * FROM llm_results")
  expect_equal(nrow(stored), 1)
  expect_true(is.na(stored$narrative_id))
  expect_true(is.na(stored$confidence))
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("store_llm_result validates required fields", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Missing required field
  invalid_result <- list(
    narrative_id = "INVALID001",
    confidence = 0.5
    # Missing 'detected' field
  )
  
  result <- store_llm_result(invalid_result, db_path = db_file)
  expect_false(result$success)
  expect_match(result$error, "detected", ignore.case = TRUE)
  
  # Clean up
  unlink(db_file)
})

test_that("store_llm_results_batch handles multiple records efficiently", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create batch of results
  batch_results <- lapply(1:100, function(i) {
    list(
      narrative_id = sprintf("BATCH%03d", i),
      narrative_text = sprintf("Narrative %d", i),
      detected = i %% 2 == 0,
      confidence = runif(1),
      model = "gpt-4"
    )
  })
  
  # Store batch
  start_time <- Sys.time()
  result <- store_llm_results_batch(batch_results, db_path = db_file)
  elapsed <- as.numeric(Sys.time() - start_time, units = "secs")
  
  expect_true(result$success)
  expect_equal(result$inserted, 100)
  expect_equal(result$duplicates, 0)
  expect_equal(result$errors, 0)
  
  # Performance check (should be reasonably fast)
  expect_lt(elapsed, 0.2)
  
  # Verify all stored
  conn <- get_db_connection(db_file)
  count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM llm_results")
  expect_equal(count$n, 100)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("store_llm_results_batch handles duplicates in batch", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create batch with duplicates
  batch_results <- list(
    list(narrative_id = "SAME", narrative_text = "Same text", 
         detected = TRUE, model = "gpt-4"),
    list(narrative_id = "SAME", narrative_text = "Same text", 
         detected = FALSE, model = "gpt-4"),  # Duplicate
    list(narrative_id = "DIFF", narrative_text = "Different", 
         detected = TRUE, model = "gpt-4")
  )
  
  result <- store_llm_results_batch(batch_results, db_path = db_file)
  
  expect_true(result$success)
  expect_equal(result$inserted, 2)
  expect_equal(result$duplicates, 1)
  
  # Clean up
  unlink(db_file)
})

test_that("trimws is applied to narrative_text", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Text with trailing spaces
  parsed_result <- list(
    narrative_id = "TRIM001",
    narrative_text = "  Text with spaces  \n\t",
    detected = TRUE
  )
  
  result <- store_llm_result(parsed_result, db_path = db_file)
  expect_true(result$success)
  
  # Verify trimmed
  conn <- get_db_connection(db_file)
  stored <- DBI::dbGetQuery(conn, "SELECT narrative_text FROM llm_results WHERE narrative_id = 'TRIM001'")
  expect_equal(stored$narrative_text, "Text with spaces")
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("store_llm_result works with unified connection (auto-detection)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create sample parsed result
  parsed_result <- list(
    narrative_id = "UNIFIED001",
    narrative_text = "Test unified connection",
    detected = TRUE,
    confidence = 0.85,
    model = "gpt-4"
  )
  
  # Should auto-detect SQLite from string path
  result <- store_llm_result(parsed_result, db_path = db_file)
  expect_true(result$success)
  expect_equal(result$rows_inserted, 1)
  
  # Verify connection type detection
  conn <- get_unified_connection(db_file)
  db_type <- detect_db_type(conn)
  expect_equal(db_type, "sqlite")
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("batch operations work with database type detection", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create batch of results
  batch_results <- lapply(1:50, function(i) {
    list(
      narrative_id = sprintf("DETECT%03d", i),
      narrative_text = sprintf("Narrative %d", i),
      detected = i %% 2 == 0,
      confidence = runif(1),
      model = "gpt-4"
    )
  })
  
  # Store batch with auto chunk sizing
  result <- store_llm_results_batch(batch_results, db_path = db_file)
  expect_true(result$success)
  expect_equal(result$inserted, 50)
  
  # Verify stored data
  conn <- get_db_connection(db_file)
  count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM llm_results")
  expect_equal(count$n, 50)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

# PostgreSQL tests - only run if PostgreSQL is available
test_that("store_llm_result works with PostgreSQL backend", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RPostgres")
  skip("PostgreSQL tests require server connection - skipping in automated tests")
})

test_that("concurrent writes work with transaction support", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create test data
  parsed_result1 <- list(
    narrative_id = "CONCURRENT001",
    narrative_text = "Concurrent test 1",
    detected = TRUE,
    model = "gpt-4"
  )
  
  parsed_result2 <- list(
    narrative_id = "CONCURRENT002", 
    narrative_text = "Concurrent test 2",
    detected = FALSE,
    model = "gpt-4"
  )
  
  # Use shared connection with transaction support
  conn <- get_db_connection(db_file)
  ensure_schema(conn)
  
  # Test transaction wrapper
  result <- execute_with_transaction(conn, {
    store_llm_result(parsed_result1, conn = conn, auto_close = FALSE)
    store_llm_result(parsed_result2, conn = conn, auto_close = FALSE)
    list(success = TRUE, message = "Both stored")
  })
  
  expect_true(result$success)
  
  # Verify both records stored
  count <- DBI::dbGetQuery(conn, "SELECT COUNT(*) as n FROM llm_results WHERE narrative_id LIKE 'CONCURRENT%'")
  expect_equal(count$n, 2)
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})