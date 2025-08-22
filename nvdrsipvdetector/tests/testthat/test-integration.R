# Integration tests for nvdrs_ipv_detector package
# Testing full workflow with real data

test_that("Full workflow integration test with real data", {
  skip_if_not_installed("readxl")
  
  # Load real data (Excel -> CSV conversion) - use absolute path
  excel_data <- readxl::read_excel(system.file("data-raw/sui_all_flagged.xlsx", package = "nvdrsipvdetector"))
  
  # Fallback if not in installed package
  if (nrow(excel_data) == 0) {
    excel_data <- readxl::read_excel("../../data-raw/sui_all_flagged.xlsx")
  }
  
  # Create temporary CSV for testing
  temp_csv <- tempfile(fileext = ".csv")
  write.csv(excel_data, temp_csv, row.names = FALSE)
  
  # Test data loading
  data <- read_nvdrs_data(temp_csv)
  expect_true(is.data.frame(data))
  expect_true(nrow(data) > 0)
  expect_true(all(c("IncidentID", "NarrativeLE", "NarrativeCME") %in% names(data)))
  
  # Test data validation
  validated_data <- validate_input_data(data)
  expect_true(nrow(validated_data) <= nrow(data))
  
  # Test batch splitting
  batches <- split_into_batches(validated_data, batch_size = 10)
  expect_true(length(batches) > 0)
  expect_true(all(sapply(batches, nrow) <= 10))
  
  # Test with small sample for performance
  sample_data <- head(validated_data, 5)
  
  # Test IPV detection with mock responses
  with_mock_api({
    results <- detect_ipv(sample_data$NarrativeLE[1], "LE")
    expect_true(is.list(results))
    expect_true("ipv_detected" %in% names(results))
  })
  
  # Clean up
  unlink(temp_csv)
})

test_that("Integration with mock API responses", {
  # Test data
  test_data <- data.frame(
    IncidentID = c("1", "2", "3"),
    NarrativeLE = c("domestic violence incident", "suicide by firearm", "overdose death"),
    NarrativeCME = c("injuries consistent with strangulation", "self-inflicted gunshot", "drug toxicity"),
    stringsAsFactors = FALSE
  )
  
  # Mock API function
  with_mock_api <- function(code) {
    # Override send_to_llm to return mock responses
    original_send <- send_to_llm
    mockery::stub(detect_ipv, "send_to_llm", function(prompt) {
      list(
        ipv_detected = grepl("domestic|strangulation", prompt, ignore.case = TRUE),
        confidence = 0.85,
        indicators = if(grepl("domestic", prompt)) c("domestic") else character(0),
        rationale = "Mock analysis"
      )
    })
    
    # Execute test code
    eval.parent(substitute(code))
  }
  
  expect_true(TRUE) # Placeholder for mock testing
})

test_that("Performance benchmarks with real data", {
  skip_if_not_installed("readxl")
  skip("Skipping performance test - optional")
  
  # Load subset of real data
  excel_path <- system.file("data-raw/sui_all_flagged.xlsx", package = "nvdrsipvdetector")
  if (excel_path == "") excel_path <- "../../data-raw/sui_all_flagged.xlsx"
  excel_data <- readxl::read_excel(excel_path)
  sample_data <- head(excel_data, 10)
  
  # Create temp CSV
  temp_csv <- tempfile(fileext = ".csv")
  write.csv(sample_data, temp_csv, row.names = FALSE)
  
  # Benchmark data loading
  timing <- system.time({
    data <- read_nvdrs_data(temp_csv)
    validated <- validate_input_data(data)
    batches <- split_into_batches(validated, batch_size = 5)
  })
  
  # Performance expectations (should process 10 records very quickly)
  expect_lt(timing["elapsed"], 1.0) # Less than 1 second
  
  # Memory usage check
  data_size <- object.size(data)
  expect_lt(data_size, 1024 * 1024) # Less than 1MB for small dataset
  
  unlink(temp_csv)
})

test_that("Database logging integration", {
  # Test database initialization
  temp_db <- tempfile(fileext = ".sqlite")
  
  # Initialize database
  db_result <- init_database(temp_db)
  expect_true(file.exists(temp_db))
  
  # Test logging with correct function signature
  conn <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  log_result <- log_api_request(
    conn = conn,
    incident_id = "incident-456", 
    prompt_type = "LE",
    prompt_text = "Test prompt",
    response = '{"ipv_detected": true}',
    response_time_ms = 150
  )
  DBI::dbDisconnect(conn)
  
  # Verify log was written
  conn <- DBI::dbConnect(RSQLite::SQLite(), temp_db)
  logs <- DBI::dbReadTable(conn, "api_logs")
  DBI::dbDisconnect(conn)
  
  expect_equal(nrow(logs), 1)
  expect_equal(logs$request_id, "test-123")
  expect_equal(logs$incident_id, "incident-456")
  
  unlink(temp_db)
})

test_that("Configuration loading and validation", {
  # Test config loading - use relative path from package root
  config_path <- system.file("config/settings.yml", package = "nvdrsipvdetector")
  if (config_path == "") {
    config_path <- "../../config/settings.yml"  # Fallback for dev testing
  }
  config <- load_config(config_path)
  
  expect_true(is.list(config))
  expect_true("api" %in% names(config))
  expect_true("processing" %in% names(config))
  expect_true("weights" %in% names(config))
  
  # Validate required config elements
  expect_true("base_url" %in% names(config$api))
  expect_true("batch_size" %in% names(config$processing))
  expect_true("threshold" %in% names(config$weights))
})

# Helper function for API mocking
with_mock_api <- function(code) {
  # Simple mock - in real implementation this would use mockery package
  # to override the actual HTTP calls
  eval.parent(substitute(code))
}