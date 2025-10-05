# Integration Tests
# End-to-end workflow validation

test_that("complete workflow: config -> load -> run -> query", {
  skip_if_not_smoke()
  
  with_temp_dir({
    # Setup
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Load configuration
    config <- mock_config()
    
    # Load narratives
    narratives <- create_sample_narratives(5)
    load_sample_narratives(conn, narratives)
    
    # Mock LLM
    local_mocked_bindings(
      call_llm = mock_call_llm("ipv_detected")
    )
    
    # Run benchmark
    result <- run_benchmark_core(conn, config, narratives)
    
    # Query results
    experiments <- list_experiments(conn)
    exp_results <- get_experiment_results(conn, result$experiment_id)
    
    # Validate
    expect_true(nrow(experiments) > 0)
    expect_true(nrow(exp_results) == 5)
    expect_experiment_logged(conn, result$experiment_id, "completed")
    
    DBI::dbDisconnect(conn)
  })
})

test_that("workflow handles multiple experiments", {
  skip_if_not_smoke()
  
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    narratives <- create_sample_narratives(3)
    load_sample_narratives(conn, narratives)
    
    local_mocked_bindings(
      call_llm = mock_call_llm("ipv_detected")
    )
    
    # Run 3 experiments
    exp_ids <- c()
    for (i in 1:3) {
      config <- mock_config(list(
        experiment = list(name = sprintf("Exp %d", i))
      ))
      result <- run_benchmark_core(conn, config, narratives)
      exp_ids <- c(exp_ids, result$experiment_id)
    }
    
    # Compare experiments
    experiments <- list_experiments(conn)
    expect_equal(nrow(experiments), 3)
    
    comparison <- compare_experiments(conn, exp_ids)
    expect_type(comparison, "list")
    
    DBI::dbDisconnect(conn)
  })
})

test_that("workflow persists across connections", {
  skip_if_not_smoke()
  
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    
    # First connection: create experiment
    conn1 <- init_experiment_db(db_path)
    config <- mock_config()
    narratives <- create_sample_narratives(2)
    load_sample_narratives(conn1, narratives)
    
    local_mocked_bindings(
      call_llm = mock_call_llm("ipv_detected")
    )
    
    result <- run_benchmark_core(conn1, config, narratives)
    experiment_id <- result$experiment_id
    DBI::dbDisconnect(conn1)
    
    # Second connection: query results
    conn2 <- get_db_connection(db_path)
    experiments <- list_experiments(conn2)
    exp_results <- get_experiment_results(conn2, experiment_id)
    
    expect_true(nrow(experiments) > 0)
    expect_true(nrow(exp_results) == 2)
    
    DBI::dbDisconnect(conn2)
  })
})

test_that("workflow handles mixed success and failure", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(4)
  
  # Mix of success and errors
  call_count <- 0
  local_mocked_bindings(
    call_llm = function(...) {
      call_count <<- call_count + 1
      if (call_count %% 2 == 0) {
        mock_llm_response("ipv_detected")
      } else {
        mock_llm_response("no_ipv")
      }
    }
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  results <- get_experiment_results(con, result$experiment_id)
  expect_equal(nrow(results), 4)
  
  DBI::dbDisconnect(con)
})

test_that("workflow validates configuration before running", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  
  # Invalid config (missing model)
  bad_config <- mock_config()
  bad_config$experiment$model_name <- NULL
  
  expect_error(
    validate_config(bad_config),
    "model_name"
  )
  
  DBI::dbDisconnect(con)
})

test_that("workflow computes accurate metrics", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  
  # Create narratives with known labels
  narratives <- create_sample_narratives(4, with_ipv = 0.5)
  load_sample_narratives(con, narratives)
  
  # Mock perfect predictions
  call_count <- 0
  local_mocked_bindings(
    call_llm = function(...) {
      call_count <<- call_count + 1
      # Match the manual flags
      if (call_count <= 2) {
        mock_llm_response("ipv_detected")  # For IPV cases
      } else {
        mock_llm_response("no_ipv")  # For non-IPV cases
      }
    }
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT accuracy FROM experiments WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  # Should be high accuracy
  expect_true(exp$accuracy >= 0.5)
  
  DBI::dbDisconnect(con)
})

test_that("workflow handles experiment failure gracefully", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Simulate failure
  mark_experiment_failed(con, experiment_id, "Test failure")
  
  exp <- DBI::dbGetQuery(con,
    "SELECT status FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_equal(exp$status, "failed")
  
  DBI::dbDisconnect(con)
})

test_that("workflow creates proper experiment logs", {
  skip_if_not_smoke()
  
  with_temp_dir({
    experiment_id <- "test-integration-exp"
    log_info <- init_experiment_logger(experiment_id)
    
    expect_true(dir.exists(log_info$log_dir))
    expect_true(file.exists(log_info$log_file))
    
    log_message(log_info$log_file, "INFO", "Test log entry")
    
    content <- readLines(log_info$log_file)
    expect_true(any(grepl("Test log entry", content)))
  })
})

test_that("workflow query functions return consistent data", {
  skip_if_not_smoke()
  
  con <- mock_populated_db(n_experiments = 2, n_results = 10)
  
  experiments <- list_experiments(con)
  exp_id <- experiments$experiment_id[1]
  
  results1 <- get_experiment_results(con, exp_id)
  results2 <- get_experiment_results(con, exp_id)
  
  # Should be identical
  expect_equal(nrow(results1), nrow(results2))
  expect_equal(results1$incident_id, results2$incident_id)
  
  DBI::dbDisconnect(con)
})

test_that("workflow handles database schema migration", {
  skip_if_not_smoke()
  
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Run migration
    ensure_token_columns(conn)
    
    # Should still work
    columns <- DBI::dbListFields(conn, "narrative_results")
    expect_true("prompt_tokens" %in% columns)
    
    DBI::dbDisconnect(conn)
  })
})
