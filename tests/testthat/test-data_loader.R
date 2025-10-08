# Tests for data_loader.R
# Data loading and narrative retrieval

test_that("load_source_data requires valid Excel file", {
  con <- create_temp_db(defer_cleanup = FALSE)
  
  expect_error(
    load_source_data(con, "/nonexistent/file.xlsx"),
    "not found"
  )
  
  safe_db_disconnect(con)
})

test_that("load_source_data loads narratives into database", {
  con <- create_temp_db(defer_cleanup = FALSE)
  fixtures <- local_excel_fixtures()
  
  # Load valid Excel data
  n_loaded <- load_source_data(con, fixtures$valid)
  
  expect_equal(n_loaded, 3)
  
  # Verify data was loaded correctly
  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM source_narratives")$n
  expect_equal(count, 3)
  
  # Verify specific content
  result <- DBI::dbGetQuery(con, "SELECT incident_id, narrative_type, manual_flag_ind FROM source_narratives ORDER BY incident_id")
  expect_equal(result$incident_id, c("INC001", "INC002", "INC003"))
  expect_equal(result$narrative_type, c("LE", "CME", "LE"))
  expect_equal(result$manual_flag_ind, c(1, 0, 1))
  
  safe_db_disconnect(con)
})

test_that("load_source_data respects force_reload=FALSE", {
  con <- create_temp_db(defer_cleanup = FALSE)
  
  # Load sample narratives
  narratives <- create_sample_narratives(5)
  DBI::dbWriteTable(con, "source_narratives", narratives, append = TRUE)
  
  # Check count
  count1 <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM source_narratives")$n
  expect_equal(count1, 5)
  
  safe_db_disconnect(con)
})

test_that("load_source_data with force_reload=TRUE deletes existing data", {
  con <- create_temp_db()
  
  # Load sample data
  narratives1 <- create_sample_narratives(3)
  DBI::dbWriteTable(con, "source_narratives", narratives1, append = TRUE)
  
  count_before <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM source_narratives")$n
  expect_equal(count_before, 3)
  
  DBI::dbDisconnect(con)
})

test_that("load_source_data coerces incident IDs to character", {
  con <- create_temp_db()
  
  # Create narratives with numeric IDs
  narratives <- create_sample_narratives(3)
  DBI::dbWriteTable(con, "source_narratives", narratives, append = TRUE)
  
  # Check type
  result <- DBI::dbGetQuery(con, "SELECT incident_id FROM source_narratives LIMIT 1")
  expect_type(result$incident_id, "character")
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives returns all narratives by default", {
  con <- create_temp_db()
  load_sample_narratives(con, create_sample_narratives(10))
  
  narratives <- get_source_narratives(con)
  
  expect_valid_narratives(narratives, min_rows = 10)
  expect_equal(nrow(narratives), 10)
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives respects max_narratives", {
  con <- create_temp_db()
  load_sample_narratives(con, create_sample_narratives(20))
  
  narratives <- get_source_narratives(con, max_narratives = 5)
  
  expect_valid_narratives(narratives, min_rows = 5)
  expect_equal(nrow(narratives), 5)
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives filters by data_source", {
  con <- create_temp_db()
  
  # Load from two sources
  narr1 <- create_sample_narratives(5)
  narr1$data_source <- "source1"
  DBI::dbWriteTable(con, "source_narratives", narr1, append = TRUE)
  
  narr2 <- create_sample_narratives(3)
  narr2$data_source <- "source2"
  narr2$incident_id <- sprintf("INC2-%05d", 1:3)
  DBI::dbWriteTable(con, "source_narratives", narr2, append = TRUE)
  
  # Get only source1
  result <- get_source_narratives(con, data_source = "source1")
  expect_equal(nrow(result), 5)
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives returns empty for missing data", {
  con <- create_temp_db()
  
  narratives <- get_source_narratives(con)
  
  expect_equal(nrow(narratives), 0)
  
  DBI::dbDisconnect(con)
})

test_that("check_data_loaded returns TRUE when data exists", {
  con <- create_temp_db()
  load_sample_narratives(con)
  
  result <- check_data_loaded(con, "test")
  
  expect_true(result)
  
  DBI::dbDisconnect(con)
})

test_that("check_data_loaded returns FALSE when no data", {
  con <- create_temp_db()
  
  result <- check_data_loaded(con, "nonexistent")
  
  expect_false(result)
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives handles narrative_type filtering", {
  con <- create_temp_db()
  
  # Create mixed narrative types
  narratives <- create_sample_narratives(10)
  narratives$narrative_type[1:5] <- "LE"
  narratives$narrative_type[6:10] <- "CME"
  DBI::dbWriteTable(con, "source_narratives", narratives, append = TRUE)
  
  # Query should return all types
  result <- get_source_narratives(con)
  expect_true(all(c("LE", "CME") %in% unique(result$narrative_type)))
  
  DBI::dbDisconnect(con)
})

test_that("get_source_narratives preserves manual flags", {
  con <- create_temp_db()
  narratives <- create_sample_narratives(10, with_ipv = 0.3)
  load_sample_narratives(con, narratives)
  
  result <- get_source_narratives(con)
  
  expect_true("manual_flag" %in% names(result))
  expect_true("manual_flag_ind" %in% names(result))
  expect_equal(sum(result$manual_flag), 3)
  
  DBI::dbDisconnect(con)
})

test_that("load_source_data handles empty Excel files", {
  con <- create_temp_db(defer_cleanup = FALSE)
  fixtures <- local_excel_fixtures()
  
  # Load empty Excel file
  n_loaded <- load_source_data(con, fixtures$empty)
  
  # Empty file should load 0 rows
  expect_equal(n_loaded, 0)
  
  # Verify no data was loaded
  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM source_narratives")$n
  expect_equal(count, 0)
  
  safe_db_disconnect(con)
})

test_that("load_source_data handles malformed Excel files", {
  con <- create_temp_db(defer_cleanup = FALSE)
  fixtures <- local_excel_fixtures()
  
  # Expect error when loading malformed Excel file
  expect_error(
    load_source_data(con, fixtures$malformed),
    class = "error"
  )
  
  # Verify no data was loaded after error
  count <- DBI::dbGetQuery(con, "SELECT COUNT(*) as n FROM source_narratives")$n
  expect_equal(count, 0)
  
  safe_db_disconnect(con)
})
