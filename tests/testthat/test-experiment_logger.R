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
    params = list(experiment_id))
  
  expect_equal(nrow(exp), 1)
  expect_equal(exp$status, "running")
  expect_equal(exp$experiment_name, config$experiment$name)
  
  DBI::dbDisconnect(con)
})

test_that("start_experiment records configuration details", {
  con <- create_temp_db()
  config <- mock_config(list(
    experiment = list(name = "test_exp", model_name = "test-model", temperature = 0.5)
  ))
  
  experiment_id <- start_experiment(con, config)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
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
    indicators = "test indicators",
    rationale = "test rationale",
    reasoning_steps = c("step1", "step2"),
    raw_response = "{}",
    response_sec = 1.5,
    prompt_tokens = 150,
    completion_tokens = 50,
    tokens_used = 200
  )
  
  log_narrative_result(con, experiment_id, result)
  
  # Check it was logged
  results <- DBI::dbGetQuery(con,
    "SELECT * FROM narrative_results WHERE experiment_id = ?",
    params = list(experiment_id))
  
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
    detected = FALSE,
    confidence = 0.90
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
  
  # Log some results
  for (i in 1:3) {
    result <- list(
      incident_id = sprintf("INC-%03d", i),
      detected = i %% 2 == 0,
      confidence = 0.8
    )
    log_narrative_result(con, experiment_id, result)
  }
  
  finalize_experiment(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_equal(exp$status, "completed")
  expect_false(is.na(exp$end_time))
  expect_equal(exp$n_narratives_processed, 3)
  
  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates performance metrics", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log results with known outcomes
  results_data <- list(
    list(incident_id = "I1", detected = TRUE, confidence = 0.9, manual_flag = 1),  # TP
    list(incident_id = "I2", detected = FALSE, confidence = 0.9, manual_flag = 0), # TN
    list(incident_id = "I3", detected = TRUE, confidence = 0.8, manual_flag = 0),  # FP
    list(incident_id = "I4", detected = FALSE, confidence = 0.7, manual_flag = 1)  # FN
  )
  
  for (result in results_data) {
    log_narrative_result(con, experiment_id, result)
  }
  
  compute_enhanced_metrics(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_equal(exp$n_true_positive, 1)
  expect_equal(exp$n_true_negative, 1)
  expect_equal(exp$n_false_positive, 1)
  expect_equal(exp$n_false_negative, 1)
  expect_equal(exp$accuracy, 0.5)  # 2 correct out of 4
  
  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics handles no manual flags", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log results without manual flags
  for (i in 1:3) {
    result <- list(
      incident_id = sprintf("I%d", i),
      detected = TRUE,
      confidence = 0.8
      # No manual_flag
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
    params = list(experiment_id))
  
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
    expect_true(file.exists(log_info$error_file))
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
  skip("Need file output implementation")
})

test_that("finalize_experiment saves JSON output when requested", {
  skip("Need file output implementation")
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
    list(incident_id = "I1", detected = TRUE, manual_flag = 1),  # TP
    list(incident_id = "I2", detected = TRUE, manual_flag = 1),  # TP
    list(incident_id = "I3", detected = TRUE, manual_flag = 0)   # FP
  )
  
  for (r in results) log_narrative_result(con, experiment_id, r)
  
  compute_enhanced_metrics(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT precision_ipv FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_true(abs(exp$precision_ipv - 0.667) < 0.01)
  
  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates recall correctly", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # 1 TP, 2 FN -> recall = 1/3 = 0.333
  results <- list(
    list(incident_id = "I1", detected = TRUE, manual_flag = 1),   # TP
    list(incident_id = "I2", detected = FALSE, manual_flag = 1),  # FN
    list(incident_id = "I3", detected = FALSE, manual_flag = 1)   # FN
  )
  
  for (r in results) log_narrative_result(con, experiment_id, r)
  
  compute_enhanced_metrics(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT recall_ipv FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_true(abs(exp$recall_ipv - 0.333) < 0.01)
  
  DBI::dbDisconnect(con)
})

test_that("compute_enhanced_metrics calculates F1 correctly", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Precision = Recall = 0.5 -> F1 = 0.5
  results <- list(
    list(incident_id = "I1", detected = TRUE, manual_flag = 1),   # TP
    list(incident_id = "I2", detected = TRUE, manual_flag = 0),   # FP
    list(incident_id = "I3", detected = FALSE, manual_flag = 1)   # FN
  )
  
  for (r in results) log_narrative_result(con, experiment_id, r)
  
  compute_enhanced_metrics(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT f1_ipv FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_true(abs(exp$f1_ipv - 0.5) < 0.01)
  
  DBI::dbDisconnect(con)
})
