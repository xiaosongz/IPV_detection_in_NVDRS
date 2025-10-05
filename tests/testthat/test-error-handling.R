# Error Handling Tests
# Systematic error coverage

test_that("handles missing database file", {
  expect_error(
    get_db_connection("/nonexistent/database.db"),
    "not found|does not exist"
  )
})

test_that("handles corrupted configuration file", {
  with_temp_dir({
    # Create invalid YAML
    bad_config <- file.path(getwd(), "bad.yaml")
    writeLines(c(
      "experiment:",
      "  name: test",
      "  invalid syntax here {{{"
    ), bad_config)
    
    expect_error(
      load_experiment_config(bad_config)
    )
  })
})

test_that("handles missing required config fields", {
  config <- mock_config()
  config$experiment$model_name <- NULL
  
  expect_error(
    validate_config(config),
    "model_name"
  )
})

test_that("handles invalid temperature values", {
  config <- mock_config()
  config$experiment$temperature <- -1
  
  expect_error(
    validate_config(config),
    "temperature"
  )
  
  config$experiment$temperature <- 5
  expect_error(
    validate_config(config),
    "temperature"
  )
})

test_that("handles missing user template placeholder", {
  config <- mock_config()
  config$prompts$user_template <- "No placeholder here"
  
  expect_error(
    validate_config(config),
    "\\{text\\}"
  )
})

test_that("handles API timeout errors", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(1)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("timeout")
  )
  
  # Should handle gracefully
  expect_error(
    run_benchmark_core(con, config, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("handles API rate limit errors", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(1)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("error")
  )
  
  expect_error(
    run_benchmark_core(con, config, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("handles malformed JSON responses", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(1)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("malformed")
  )
  
  expect_error(
    run_benchmark_core(con, config, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("handles missing LLM response fields", {
  response <- mock_llm_response("missing_fields")
  
  # Should have detected field
  expect_true("detected" %in% names(response))
})

test_that("handles empty narrative text", {
  con <- create_temp_db()
  
  narratives <- tibble::tibble(
    incident_id = "INC-001",
    narrative_type = "LE",
    narrative_text = "",
    manual_flag_ind = 1,
    manual_flag = 0,
    data_source = "test"
  )
  
  load_sample_narratives(con, narratives)
  
  result <- get_source_narratives(con)
  expect_equal(nrow(result), 1)
  
  DBI::dbDisconnect(con)
})

test_that("handles NULL narrative text", {
  con <- create_temp_db()
  
  narratives <- tibble::tibble(
    incident_id = "INC-002",
    narrative_type = "LE",
    narrative_text = NA_character_,
    manual_flag_ind = 1,
    manual_flag = 0,
    data_source = "test"
  )
  
  load_sample_narratives(con, narratives)
  
  result <- get_source_narratives(con)
  expect_equal(nrow(result), 1)
  
  DBI::dbDisconnect(con)
})

test_that("handles very long narrative text", {
  con <- create_temp_db()
  
  long_text <- paste(rep("word", 10000), collapse = " ")
  
  narratives <- tibble::tibble(
    incident_id = "INC-003",
    narrative_type = "LE",
    narrative_text = long_text,
    manual_flag_ind = 1,
    manual_flag = 0,
    data_source = "test"
  )
  
  expect_error(
    load_sample_narratives(con, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("handles special characters in text", {
  con <- create_temp_db()
  
  special_text <- "Text with 'quotes' and \"double quotes\" and \n newlines"
  
  narratives <- tibble::tibble(
    incident_id = "INC-004",
    narrative_type = "LE",
    narrative_text = special_text,
    manual_flag_ind = 1,
    manual_flag = 0,
    data_source = "test"
  )
  
  load_sample_narratives(con, narratives)
  result <- get_source_narratives(con)
  
  expect_equal(result$narrative_text[1], special_text)
  
  DBI::dbDisconnect(con)
})

test_that("handles Unicode characters", {
  con <- create_temp_db()
  
  unicode_text <- "Text with émojis 😀 and ñoñó"
  
  narratives <- tibble::tibble(
    incident_id = "INC-005",
    narrative_type = "LE",
    narrative_text = unicode_text,
    manual_flag_ind = 1,
    manual_flag = 0,
    data_source = "test"
  )
  
  load_sample_narratives(con, narratives)
  result <- get_source_narratives(con)
  
  expect_true(grepl("émoji", result$narrative_text[1]))
  
  DBI::dbDisconnect(con)
})

test_that("handles database connection loss", {
  con <- create_temp_db()
  DBI::dbDisconnect(con)
  
  # Trying to use closed connection should error
  expect_error(
    list_experiments(con)
  )
})

test_that("handles concurrent write attempts", {
  skip("Concurrent access testing requires special setup")
})

test_that("handles disk full errors", {
  skip("Disk full errors require special test environment")
})

test_that("handles missing environment variables", {
  withr::local_envvar(c(TEST_VAR = NA_character_))
  
  text <- "${TEST_VAR}"
  result <- expand_env_vars(text)
  
  # Should handle gracefully
  expect_type(result, "character")
})

test_that("handles zero division in metrics", {
  # All negative cases - no positives
  results <- list(
    list(detected = FALSE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  # Should not crash
  expect_type(metrics, "list")
})

test_that("handles experiment with no results", {
  con <- create_temp_db()
  config <- mock_config()
  experiment_id <- start_experiment(con, config)
  
  # Finalize without logging any results
  finalize_experiment(con, experiment_id)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id))
  
  expect_equal(exp$n_narratives_processed, 0)
  
  DBI::dbDisconnect(con)
})

test_that("handles query for nonexistent experiment", {
  con <- create_temp_db()
  
  results <- get_experiment_results(con, "nonexistent-id")
  
  expect_equal(nrow(results), 0)
  
  DBI::dbDisconnect(con)
})

test_that("handles trimws_safe edge cases", {
  expect_equal(trimws_safe(NULL), "")
  expect_equal(trimws_safe(NA), "")
  expect_equal(trimws_safe(""), "")
  expect_equal(trimws_safe(123), "123")
})
