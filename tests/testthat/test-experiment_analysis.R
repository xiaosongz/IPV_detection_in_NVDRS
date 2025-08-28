test_that("experiment_metrics calculates basic metrics", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Setup experiment with results
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  exp_id <- start_experiment(
    name = "Metrics Test",
    prompt_version_id = prompt_id,
    model = "test-model",
    db_path = db_file
  )
  
  # Add varied results
  results <- list(
    list(detected = TRUE, confidence = 0.9, response_time_ms = 100, total_tokens = 50),
    list(detected = TRUE, confidence = 0.8, response_time_ms = 120, total_tokens = 60),
    list(detected = FALSE, confidence = 0.3, response_time_ms = 110, total_tokens = 55),
    list(detected = TRUE, confidence = 0.95, response_time_ms = 105, total_tokens = 52)
  )
  
  for (i in seq_along(results)) {
    store_experiment_result(
      experiment_id = exp_id,
      narrative_id = paste0("TEST", i),
      parsed_result = results[[i]],
      db_path = db_file
    )
  }
  
  # Get metrics
  metrics <- experiment_metrics(exp_id, db_path = db_file)
  
  expect_equal(metrics$experiment_name, "Metrics Test")
  expect_equal(metrics$model, "test-model")
  expect_equal(metrics$total_results, 4)
  expect_equal(metrics$detection_rate, 0.75)  # 3 out of 4 detected
  expect_equal(metrics$avg_confidence, mean(c(0.9, 0.8, 0.3, 0.95)))
  expect_equal(metrics$confidence_range, c(0.3, 0.95))
  
  # Clean up
  unlink(db_file)
})

test_that("experiment_metrics includes accuracy when ground truth available", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  ensure_experiment_schema(conn)
  
  # Setup experiment
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    conn = conn
  )
  
  exp_id <- start_experiment(
    name = "Accuracy Test",
    prompt_version_id = prompt_id,
    model = "test",
    conn = conn
  )
  
  # Add ground truth
  DBI::dbExecute(
    conn,
    "INSERT INTO ground_truth (narrative_id, true_ipv) VALUES 
     ('N1', 1), ('N2', 1), ('N3', 0), ('N4', 0)"
  )
  
  # Add results (2 correct, 2 incorrect)
  test_cases <- list(
    list(id = "N1", result = list(detected = TRUE, confidence = 0.9)),   # TP
    list(id = "N2", result = list(detected = FALSE, confidence = 0.3)),  # FN
    list(id = "N3", result = list(detected = FALSE, confidence = 0.2)),  # TN
    list(id = "N4", result = list(detected = TRUE, confidence = 0.7))    # FP
  )
  
  for (tc in test_cases) {
    store_experiment_result(
      experiment_id = exp_id,
      narrative_id = tc$id,
      parsed_result = tc$result,
      conn = conn
    )
  }
  
  # Get metrics with accuracy
  metrics <- experiment_metrics(exp_id, conn = conn)
  
  expect_true(!is.null(metrics$accuracy_metrics))
  expect_equal(metrics$accuracy_metrics$evaluated_count, 4)
  expect_equal(metrics$accuracy_metrics$accuracy, 0.5)  # 2 correct out of 4
  expect_equal(metrics$accuracy_metrics$precision, 0.5)  # TP/(TP+FP) = 1/(1+1)
  expect_equal(metrics$accuracy_metrics$recall, 0.5)     # TP/(TP+FN) = 1/(1+1)
  expect_equal(metrics$accuracy_metrics$specificity, 0.5) # TN/(TN+FP) = 1/(1+1)
  
  close_db_connection(conn)
  unlink(db_file)
})

test_that("compare_experiments performs statistical tests", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Setup two experiments
  prompt1 <- register_prompt(
    system_prompt = "Prompt 1",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  prompt2 <- register_prompt(
    system_prompt = "Prompt 2",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  exp1 <- start_experiment("Exp 1", prompt1, "model", db_path = db_file)
  exp2 <- start_experiment("Exp 2", prompt2, "model", db_path = db_file)
  
  # Add results with different confidence distributions
  set.seed(123)
  for (i in 1:20) {
    store_experiment_result(
      exp1, 
      paste0("N", i),
      list(detected = TRUE, confidence = runif(1, 0.3, 0.6)),
      db_path = db_file
    )
    
    store_experiment_result(
      exp2,
      paste0("N", i),
      list(detected = TRUE, confidence = runif(1, 0.7, 0.95)),
      db_path = db_file
    )
  }
  
  # Compare
  comparison <- compare_experiments(exp1, exp2, db_path = db_file)
  
  expect_equal(comparison$experiment1$name, "Exp 1")
  expect_equal(comparison$experiment2$name, "Exp 2")
  expect_true(comparison$differences$confidence_diff > 0)  # Exp2 should have higher confidence
  
  # Statistical tests should be present
  expect_true(!is.null(comparison$statistical_tests))
  expect_true(!is.null(comparison$statistical_tests$confidence_t_test))
  expect_true(comparison$statistical_tests$confidence_t_test$p_value < 0.05)  # Should be significant
  
  # Clean up
  unlink(db_file)
})

test_that("analyze_prompt_evolution tracks performance over versions", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create multiple prompt versions
  prompts <- list()
  for (v in 1:3) {
    prompts[[v]] <- register_prompt(
      system_prompt = paste("System v", v),
      user_prompt_template = "Test",
      version_tag = paste0("v", v),
      db_path = db_file
    )
    
    # Create experiment for each
    exp_id <- start_experiment(
      paste("Test v", v),
      prompts[[v]],
      "model",
      db_path = db_file
    )
    
    # Add results with improving confidence
    for (i in 1:5) {
      store_experiment_result(
        exp_id,
        paste0("N", i),
        list(detected = TRUE, confidence = 0.3 + v * 0.2),  # Increasing confidence
        db_path = db_file
      )
    }
  }
  
  # Analyze evolution
  evolution <- analyze_prompt_evolution(db_path = db_file)
  
  expect_equal(nrow(evolution), 3)
  expect_true(all(evolution$experiment_count == 1))
  expect_true(all(evolution$total_tests == 5))
  
  # Confidence should increase with version
  expect_true(evolution$avg_confidence[1] < evolution$avg_confidence[2])
  expect_true(evolution$avg_confidence[2] < evolution$avg_confidence[3])
  
  # Clean up
  unlink(db_file)
})

test_that("ab_test_prompts performs paired comparison", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  ensure_experiment_schema(conn)
  
  # Setup two prompts
  prompt_v1 <- register_prompt(
    system_prompt = "V1",
    user_prompt_template = "Test",
    conn = conn
  )
  
  prompt_v2 <- register_prompt(
    system_prompt = "V2",
    user_prompt_template = "Test",
    conn = conn
  )
  
  # Run experiments on same narratives
  exp1 <- start_experiment("AB Test V1", prompt_v1, "model", conn = conn)
  exp2 <- start_experiment("AB Test V2", prompt_v2, "model", conn = conn)
  
  # Same narratives, different results
  narratives <- paste0("N", 1:15)
  set.seed(42)
  
  for (n in narratives) {
    store_experiment_result(
      exp1, n,
      list(detected = runif(1) > 0.6, confidence = runif(1, 0.3, 0.6)),
      conn = conn
    )
    
    store_experiment_result(
      exp2, n,
      list(detected = runif(1) > 0.4, confidence = runif(1, 0.5, 0.8)),
      conn = conn
    )
  }
  
  # Add ground truth for some
  for (i in 1:10) {
    DBI::dbExecute(
      conn,
      "INSERT INTO ground_truth (narrative_id, true_ipv) VALUES (?, ?)",
      params = list(paste0("N", i), i %% 2)
    )
  }
  
  # Perform A/B test
  ab_result <- ab_test_prompts(prompt_v1, prompt_v2, "model", conn = conn)
  
  expect_equal(ab_result$n_paired, 15)
  expect_true(ab_result$avg_confidence_v2 > ab_result$avg_confidence_v1)
  
  # Paired t-test should be present
  expect_true(!is.null(ab_result$confidence_paired_t_test))
  
  # Accuracy comparison should be present (10 with ground truth)
  expect_true(!is.null(ab_result$accuracy_comparison))
  expect_equal(ab_result$accuracy_comparison$n_with_ground_truth, 10)
  
  close_db_connection(conn)
  unlink(db_file)
})

test_that("experiment_report generates formatted output", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Setup simple experiment
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    version_tag = "report_test",
    db_path = db_file
  )
  
  exp_id <- start_experiment(
    "Report Test Experiment",
    prompt_id,
    "gpt-test",
    db_path = db_file
  )
  
  # Add some results
  for (i in 1:3) {
    store_experiment_result(
      exp_id,
      paste0("N", i),
      list(detected = TRUE, confidence = 0.7 + i * 0.05),
      db_path = db_file
    )
  }
  
  complete_experiment(exp_id, db_path = db_file)
  
  # Generate report
  report <- experiment_report(exp_id, db_path = db_file)
  
  expect_true(is.character(report))
  expect_true(grepl("Report Test Experiment", report))
  expect_true(grepl("gpt-test", report))
  expect_true(grepl("Detection Rate:", report))
  expect_true(grepl("completed", report))
  
  # Clean up
  unlink(db_file)
})