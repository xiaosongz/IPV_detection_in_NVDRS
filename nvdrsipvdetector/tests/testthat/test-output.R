test_that("export_results handles CSV format", {
  results <- data.frame(
    IncidentID = 1:3,
    ipv_detected = c(TRUE, FALSE, TRUE),
    confidence = c(0.8, 0.3, 0.9)
  )
  
  tmp_file <- tempfile(fileext = ".csv")
  export_results(results, tmp_file, "csv")
  
  expect_true(file.exists(tmp_file))
  
  # Read back and verify
  read_back <- read.csv(tmp_file)
  expect_equal(nrow(read_back), 3)
  expect_equal(read_back$ipv_detected, results$ipv_detected)
  
  unlink(tmp_file)
})

test_that("export_results handles RDS format", {
  results <- data.frame(
    IncidentID = 1:3,
    ipv_detected = c(TRUE, FALSE, TRUE)
  )
  
  tmp_file <- tempfile(fileext = ".rds")
  export_results(results, tmp_file, "rds")
  
  expect_true(file.exists(tmp_file))
  
  read_back <- readRDS(tmp_file)
  expect_equal(read_back, results)
  
  unlink(tmp_file)
})

test_that("export_results handles JSON format", {
  results <- data.frame(
    IncidentID = 1:2,
    ipv_detected = c(TRUE, FALSE)
  )
  
  tmp_file <- tempfile(fileext = ".json")
  export_results(results, tmp_file, "json")
  
  expect_true(file.exists(tmp_file))
  
  json_content <- readLines(tmp_file)
  expect_true(length(json_content) > 0)
  
  unlink(tmp_file)
})

test_that("print_summary calculates correct statistics", {
  results <- data.frame(
    ipv_detected = c(TRUE, TRUE, FALSE, NA),
    confidence = c(0.8, 0.9, 0.2, NA)
  )
  
  # Capture output
  output <- capture.output(print_summary(results))
  
  expect_true(any(grepl("Total records: 4", output)))
  expect_true(any(grepl("IPV detected: 2", output)))
  expect_true(any(grepl("Unable to determine: 1", output)))
})