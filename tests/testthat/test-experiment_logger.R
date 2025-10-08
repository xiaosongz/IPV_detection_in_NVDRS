# Tests for experiment_logger.R
# Experiment and result logging

test_that("start_experiment creates experiment record", {
  con <- create_temp_db()
  config <- mock_config()

  experiment_id <- start_experiment(con, config)

  expect_type(experiment_id, "character")
  expect_true(nchar(experiment_id) > 0)

  # Check it was logged
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  expect_equal(nrow(exp), 1)
  expect_equal(exp$status, "running")
  expect_equal(exp$experiment_name, config$experiment$name)

  DBI::dbDisconnect(con)
})

test_that("start_experiment records configuration details", {
  con <- create_temp_db()
  config <- mock_config(list(
    experiment = list(name = "test_exp"),
    model = list(name = "test-model", temperature = 0.5)
  ))

  experiment_id <- start_experiment(con, config)

  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  expect_equal(exp$model_name, "test-model")
  expect_equal(exp$temperature, 0.5)
  expect_false(is.na(exp$system_prompt))

  DBI::dbDisconnect(con)
})

test_that("log_narrative_result inserts result record", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  result <- list(
    incident_id = "INC-001",
    narrative_type = "LE",
    row_num = 1,
    narrative_text = "Test narrative",
    manual_flag_ind = 1,
    manual_flag = 1,
    detected = TRUE,
    confidence = 0.85,
    indicators = list("indicator1", "indicator2"),
    rationale = "test rationale",
    reasoning = "step1; step2",
    raw_response = "{}",
    response_sec = 1.5,
    parse_error = 0,
    prompt_tokens = 150,
    completion_tokens = 50,
    tokens_used = 200
  )

  log_narrative_result(con, experiment_id, result)

  # Check it was logged
  results <- DBI::dbGetQuery(con,
    "SELECT * FROM narrative_results WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  expect_equal(nrow(results), 1)
  expect_equal(results$incident_id, "INC-001")
  expect_equal(results$detected, 1)
  expect_equal(results$confidence, 0.85)

  DBI::dbDisconnect(con)
})

test_that("log_narrative_result handles missing token usage", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  result <- list(
    incident_id = "INC-002",
    narrative_type = "LE",
    row_num = 1,
    narrative_text = "Test narrative",
    manual_flag_ind = 0,
    manual_flag = 0,
    detected = FALSE,
    confidence = 0.90,
    rationale = "test",
    reasoning = "test",
    raw_response = "{}",
    response_sec = 1.0,
    parse_error = 0
    # No token fields
  )

  # Should not error
  expect_error(
    log_narrative_result(con, experiment_id, result),
    NA
  )

  DBI::dbDisconnect(con)
})

test_that("finalize_experiment updates experiment status", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # Log simple test results
  result <- list(
    incident_id = "INC-001",
    narrative_type = "LE",
    row_num = 1,
    narrative_text = "Test narrative",
    manual_flag_ind = 0,
    manual_flag = 0,
    detected = TRUE,
    confidence = 0.8,
    rationale = "test",
    reasoning = "test",
    raw_response = "{}",
    response_sec = 1.0,
    parse_error = 0
  )
  log_narrative_result(con, experiment_id, result)

  finalize_experiment(con, experiment_id)

  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  expect_equal(exp$status, "completed")
  expect_false(is.na(exp$end_time))
  expect_equal(exp$n_narratives_processed, 1)

  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates performance metrics", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # Log simple TP/TN results for metrics calculation
  log_narrative_result(con, experiment_id, list(
    incident_id = "TP-001", narrative_type = "LE", row_num = 1, narrative_text = "Test TP", manual_flag_ind = 1, manual_flag = 1, detected = TRUE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0
  ))
  log_narrative_result(con, experiment_id, list(
    incident_id = "TN-001", narrative_type = "LE", row_num = 2, narrative_text = "Test TN", manual_flag_ind = 0, manual_flag = 0, detected = FALSE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0
  ))

  metrics <- compute_enhanced_metrics(con, experiment_id)

  expect_equal(metrics$n_true_positive, 1)
  expect_equal(metrics$n_true_negative, 1)
  expect_equal(metrics$n_false_positive, 0)
  expect_equal(metrics$n_false_negative, 0)
  expect_equal(metrics$accuracy, 1.0) # 2 correct out of 2

  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics handles no manual flags", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # Log results without manual flags
  for (i in 1:3) {
    result <- list(
      incident_id = sprintf("INC-%03d", i),
      narrative_type = "LE",
      row_num = i,
      narrative_text = "Test narrative",
      manual_flag_ind = 1,
      manual_flag = 1,
      detected = TRUE,
      confidence = 0.8,
      rationale = "test",
      reasoning = "test",
      raw_response = "{}",
      response_sec = 1.0,
      parse_error = 0
    )
    log_narrative_result(con, experiment_id, result)
  }

  # Should handle gracefully
  expect_error(
    compute_enhanced_metrics(con, experiment_id),
    NA
  )

  DBI::dbDisconnect(con)
})

test_that("mark_experiment_failed sets status and error message", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  error_msg <- "Test error occurred"
  mark_experiment_failed(con, experiment_id, error_msg)

  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  expect_equal(exp$status, "failed")
  expect_true(grepl(error_msg, exp$notes))

  DBI::dbDisconnect(con)
})

test_that("init_experiment_logger creates log directory", {
  with_temp_dir({
    experiment_id <- "test-exp-001"

    log_info <- init_experiment_logger(experiment_id)

    expect_true(dir.exists(log_info$log_dir))
    expect_true(file.exists(log_info$log_file))
    # errors.log may be created on first error; ensure performance log is initialized
    expect_true(file.exists(log_info$paths$performance))
  })
})

test_that("log_message writes to log file", {
  with_temp_dir({
    log_file <- file.path(getwd(), "test.log")

    log_message(log_file, "INFO", "Test message")

    expect_true(file.exists(log_file))

    content <- readLines(log_file)
    expect_true(any(grepl("Test message", content)))
    expect_true(any(grepl("INFO", content)))
  })
})

test_that("log_message handles different log levels", {
  with_temp_dir({
    log_file <- file.path(getwd(), "test.log")

    log_message(log_file, "ERROR", "Error message")
    log_message(log_file, "WARN", "Warning message")
    log_message(log_file, "DEBUG", "Debug message")

    content <- readLines(log_file)
    expect_true(any(grepl("ERROR", content)))
    expect_true(any(grepl("WARN", content)))
    expect_true(any(grepl("DEBUG", content)))
  })
})

test_that("finalize_experiment saves CSV output when requested", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log some test results
  log_narrative_result(con, experiment_id, list(
    incident_id = "TEST001",
    detected = 1,
    confidence = 0.9,
    indicators = list("threat", "isolation")
  ))
  
  # Test CSV export
  withr::local_tempdir({
    files <- save_experiment_results(experiment_id, format = "csv", output_dir = getwd())
    
    expect_true(file.exists(files$csv))
    expect_true(grepl("\\.csv$", files$csv))
    
    # Verify CSV content
    csv_data <- read.csv(files$csv)
    expect_equal(nrow(csv_data), 1)
    expect_equal(csv_data$incident_id, "TEST001")
    expect_equal(csv_data$detected, 1)
    expect_true(grepl("threat; isolation", csv_data$indicators))
  })
  
  safe_db_disconnect(con)
})

test_that("finalize_experiment saves JSON output when requested", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log some test results
  log_narrative_result(con, experiment_id, list(
    incident_id = "TEST002",
    detected = 0,
    confidence = 0.1,
    indicators = list()
  ))
  
  # Test JSON export
  withr::local_tempdir({
    files <- save_experiment_results(experiment_id, format = "json", output_dir = getwd())
    
    expect_true(file.exists(files$json))
    expect_true(grepl("\\.json$", files$json))
    
    # Verify JSON content
    json_data <- jsonlite::fromJSON(files$json)
    expect_equal(nrow(json_data), 1)
    expect_equal(json_data$incident_id, "TEST002")
    expect_equal(json_data$detected, 0)
    expect_equal(json_data$indicators, list())  # Empty list should be preserved
  })
  
  safe_db_disconnect(con)
})

test_that("log_narrative_result handles error cases", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  result <- list(
    incident_id = "INC-ERR",
    error_occurred = 1,
    error_message = "API timeout"
  )

  expect_error(
    log_narrative_result(con, experiment_id, result),
    NA
  )

  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates precision correctly", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # 2 TP, 1 FP -> precision = 2/3 = 0.667
  results <- list(
    list(incident_id = "I1", narrative_type = "LE", row_num = 1, narrative_text = "Test 1", manual_flag_ind = 1, manual_flag = 1, detected = TRUE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # TP
    list(incident_id = "I2", narrative_type = "LE", row_num = 2, narrative_text = "Test 2", manual_flag_ind = 1, manual_flag = 1, detected = TRUE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # TP
    list(incident_id = "I3", narrative_type = "LE", row_num = 3, narrative_text = "Test 3", manual_flag_ind = 0, manual_flag = 0, detected = TRUE, confidence = 0.8, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0) # FP
  )

  for (r in results) log_narrative_result(con, experiment_id, r)

  metrics <- compute_enhanced_metrics(con, experiment_id)
  expect_true(abs(metrics$precision_ipv - 0.667) < 0.01)

  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates recall correctly", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # 1 TP, 2 FN -> recall = 1/3 = 0.333
  results <- list(
    list(incident_id = "I1", narrative_type = "LE", row_num = 1, narrative_text = "Test 1", manual_flag_ind = 1, manual_flag = 1, detected = TRUE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # TP
    list(incident_id = "I2", narrative_type = "LE", row_num = 2, narrative_text = "Test 2", manual_flag_ind = 1, manual_flag = 1, detected = FALSE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # FN
    list(incident_id = "I3", narrative_type = "LE", row_num = 3, narrative_text = "Test 3", manual_flag_ind = 1, manual_flag = 1, detected = FALSE, confidence = 0.7, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0) # FN
  )

  for (r in results) log_narrative_result(con, experiment_id, r)

  metrics <- compute_enhanced_metrics(con, experiment_id)
  expect_true(abs(metrics$recall_ipv - 0.333) < 0.01)

  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates F1 correctly", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)

  # Precision = Recall = 0.5 -> F1 = 0.5
  results <- list(
    list(incident_id = "I1", narrative_type = "LE", row_num = 1, narrative_text = "Test 1", manual_flag_ind = 1, manual_flag = 1, detected = TRUE, confidence = 0.9, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # TP
    list(incident_id = "I2", narrative_type = "LE", row_num = 2, narrative_text = "Test 2", manual_flag_ind = 0, manual_flag = 0, detected = TRUE, confidence = 0.8, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0), # FP
    list(incident_id = "I3", narrative_type = "LE", row_num = 3, narrative_text = "Test 3", manual_flag_ind = 1, manual_flag = 1, detected = FALSE, confidence = 0.7, rationale = "test", reasoning = "test", raw_response = "{}", response_sec = 1.0, parse_error = 0) # FN
  )

  for (r in results) log_narrative_result(con, experiment_id, r)

  metrics <- compute_enhanced_metrics(con, experiment_id)
  expect_true(abs(metrics$f1_ipv - 0.5) < 0.01)

  DBI::dbDisconnect(con)
})
