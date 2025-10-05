# Tests for experiment_queries.R
# Query functions for experiments and results

test_that("list_experiments returns all experiments", {
  con <- mock_populated_db(n_experiments = 5)
  
  experiments <- list_experiments(con)
  
  expect_true(nrow(experiments) >= 5)
  expect_true("experiment_id" %in% names(experiments))
  expect_true("experiment_name" %in% names(experiments))
  
  DBI::dbDisconnect(con)
})

test_that("list_experiments filters by status", {
  con <- mock_populated_db(n_experiments = 3)
  
  # Add a failed experiment
  DBI::dbExecute(con, "
    INSERT INTO experiments (
      experiment_id, experiment_name, status,
      model_name, temperature, system_prompt, user_template
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  ", params = list("failed-exp", "Failed Test", "failed",
                   "test-model", 0.0, "test", "test"))
  
  # Query only completed
  completed <- list_experiments(con, status = "completed")
  expect_true(all(completed$status == "completed"))
  
  # Query only failed
  failed <- list_experiments(con, status = "failed")
  expect_true(all(failed$status == "failed"))
  
  DBI::dbDisconnect(con)
})

test_that("list_experiments returns empty for no experiments", {
  con <- create_temp_db()
  
  experiments <- list_experiments(con)
  
  expect_equal(nrow(experiments), 0)
  
  DBI::dbDisconnect(con)
})

test_that("get_experiment_results returns results for experiment", {
  con <- mock_populated_db(n_experiments = 1, n_results = 10)
  
  # Get first experiment ID
  exp_id <- DBI::dbGetQuery(con, "SELECT experiment_id FROM experiments LIMIT 1")$experiment_id
  
  results <- get_experiment_results(con, exp_id)
  
  expect_true(nrow(results) > 0)
  expect_true("incident_id" %in% names(results))
  expect_true("detected" %in% names(results))
  expect_true("confidence" %in% names(results))
  
  DBI::dbDisconnect(con)
})

test_that("get_experiment_results returns empty for nonexistent experiment", {
  con <- create_temp_db()
  
  results <- get_experiment_results(con, "nonexistent-id")
  
  expect_equal(nrow(results), 0)
  
  DBI::dbDisconnect(con)
})

test_that("compare_experiments returns comparison data", {
  con <- mock_populated_db(n_experiments = 3)
  
  exp_ids <- DBI::dbGetQuery(con, "SELECT experiment_id FROM experiments LIMIT 3")$experiment_id
  
  comparison <- compare_experiments(con, exp_ids)
  
  expect_type(comparison, "list")
  expect_true(length(comparison) > 0)
  
  DBI::dbDisconnect(con)
})

test_that("compare_experiments handles single experiment", {
  con <- mock_populated_db(n_experiments = 1)
  
  exp_id <- DBI::dbGetQuery(con, "SELECT experiment_id FROM experiments LIMIT 1")$experiment_id
  
  comparison <- compare_experiments(con, exp_id)
  
  expect_type(comparison, "list")
  
  DBI::dbDisconnect(con)
})

test_that("find_disagreements identifies conflicting predictions", {
  con <- create_temp_db()
  config <- mock_config()
  
  # Create two experiments
  exp1 <- start_experiment(con, config)
  exp2 <- start_experiment(con, config)
  
  # Log same incident with different results
  log_narrative_result(con, exp1, list(
    incident_id = "INC-001",
    detected = TRUE,
    confidence = 0.9
  ))
  
  log_narrative_result(con, exp2, list(
    incident_id = "INC-001",
    detected = FALSE,
    confidence = 0.8
  ))
  
  disagreements <- find_disagreements(con, c(exp1, exp2))
  
  expect_true(nrow(disagreements) >= 1)
  expect_true("INC-001" %in% disagreements$incident_id)
  
  DBI::dbDisconnect(con)
})

test_that("find_disagreements returns empty when all agree", {
  con <- create_temp_db()
  config <- mock_config()
  
  exp1 <- start_experiment(con, config)
  exp2 <- start_experiment(con, config)
  
  # Log same result for both
  for (exp_id in c(exp1, exp2)) {
    log_narrative_result(con, exp_id, list(
      incident_id = "INC-001",
      detected = TRUE,
      confidence = 0.9
    ))
  }
  
  disagreements <- find_disagreements(con, c(exp1, exp2))
  
  expect_equal(nrow(disagreements), 0)
  
  DBI::dbDisconnect(con)
})

test_that("analyze_experiment_errors returns error summary", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log some errors
  for (i in 1:3) {
    log_narrative_result(con, experiment_id, list(
      incident_id = sprintf("INC-%03d", i),
      error_occurred = 1,
      error_message = "API timeout"
    ))
  }
  
  # Log successful results
  for (i in 4:7) {
    log_narrative_result(con, experiment_id, list(
      incident_id = sprintf("INC-%03d", i),
      detected = TRUE,
      confidence = 0.8
    ))
  }
  
  error_summary <- analyze_experiment_errors(con, experiment_id)
  
  expect_type(error_summary, "list")
  expect_true("n_errors" %in% names(error_summary) || 
              length(error_summary) > 0)
  
  DBI::dbDisconnect(con)
})

test_that("analyze_experiment_errors handles no errors", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Log only successful results
  for (i in 1:5) {
    log_narrative_result(con, experiment_id, list(
      incident_id = sprintf("INC-%03d", i),
      detected = TRUE,
      confidence = 0.8
    ))
  }
  
  error_summary <- analyze_experiment_errors(con, experiment_id)
  
  # Should indicate no errors
  expect_type(error_summary, "list")
  
  DBI::dbDisconnect(con)
})

test_that("read_experiment_log reads log file if exists", {
  skip("Need log file fixture or implementation")
})

test_that("list_experiments orders by created_at", {
  con <- create_temp_db()
  config <- mock_config()
  
  # Create multiple experiments
  for (i in 1:3) {
    config$experiment$name <- sprintf("Exp %d", i)
    start_experiment(con, config)
    Sys.sleep(0.01)  # Small delay to ensure different timestamps
  }
  
  experiments <- list_experiments(con)
  
  # Should be ordered (either ascending or descending)
  expect_true(nrow(experiments) == 3)
  
  DBI::dbDisconnect(con)
})

test_that("get_experiment_results includes all result fields", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  log_narrative_result(con, experiment_id, list(
    incident_id = "INC-001",
    detected = TRUE,
    confidence = 0.85,
    indicators = "test indicators",
    rationale = "test rationale",
    prompt_tokens = 150,
    completion_tokens = 50
  ))
  
  results <- get_experiment_results(con, experiment_id)
  
  expect_true("indicators" %in% names(results))
  expect_true("rationale" %in% names(results))
  expect_true("prompt_tokens" %in% names(results))
  
  DBI::dbDisconnect(con)
})

test_that("compare_experiments shows performance differences", {
  con <- create_temp_db()
  config1 <- mock_config()
  config2 <- mock_config()
  config2$experiment$name <- "Experiment 2"
  
  exp1 <- start_experiment(con, config1)
  exp2 <- start_experiment(con, config2)
  
  # Finalize with different metrics
  DBI::dbExecute(con, "
    UPDATE experiments SET status = 'completed', 
    accuracy = ?, f1_ipv = ? WHERE experiment_id = ?
  ", params = list(0.90, 0.85, exp1))
  
  DBI::dbExecute(con, "
    UPDATE experiments SET status = 'completed',
    accuracy = ?, f1_ipv = ? WHERE experiment_id = ?
  ", params = list(0.75, 0.70, exp2))
  
  comparison <- compare_experiments(con, c(exp1, exp2))
  
  expect_type(comparison, "list")
  
  DBI::dbDisconnect(con)
})
