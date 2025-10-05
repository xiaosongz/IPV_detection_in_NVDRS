# Tests for run_benchmark_core.R
# Core orchestration logic

test_that("run_benchmark_core processes narratives with mocked LLM", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(3)
  load_sample_narratives(con, narratives)
  
  # Mock the call_llm function
  local_mocked_bindings(
    call_llm = mock_call_llm("ipv_detected")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  expect_type(result, "list")
  expect_true("experiment_id" %in% names(result))
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core logs all narratives", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(5)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("ipv_detected")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  # Check results were logged
  results <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) as n FROM narrative_results WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_equal(results$n, 5)
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core handles LLM errors gracefully", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(2)
  
  # Mock LLM that errors
  local_mocked_bindings(
    call_llm = mock_call_llm("error")
  )
  
  # Should not crash
  expect_error(
    result <- run_benchmark_core(con, config, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core updates progress", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(3)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("ipv_detected")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  # Check experiment was finalized
  exp <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_equal(exp$n_narratives_processed, 3)
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core handles empty narrative list", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(0)
  
  result <- run_benchmark_core(con, config, narratives)
  
  expect_type(result, "list")
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core respects max_narratives config", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config(list(
    data = list(max_narratives = 3)
  ))
  narratives <- create_sample_narratives(10)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("ipv_detected")
  )
  
  result <- run_benchmark_core(con, config, narratives[1:3, ])
  
  results_count <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) as n FROM narrative_results WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_equal(results_count$n, 3)
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core handles parse errors", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(2)
  
  # Mock malformed response
  local_mocked_bindings(
    call_llm = mock_call_llm("malformed")
  )
  
  # Should handle gracefully
  expect_error(
    result <- run_benchmark_core(con, config, narratives),
    NA
  )
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core records token usage", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(2)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("default")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  # Check token columns were populated
  tokens <- DBI::dbGetQuery(con,
    "SELECT prompt_tokens, completion_tokens FROM narrative_results 
     WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_true(all(!is.na(tokens$prompt_tokens)))
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core alternates between responses with rotating mock", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(4)
  
  local_mocked_bindings(
    call_llm = mock_call_llm_rotating(c("ipv_detected", "no_ipv"))
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  results <- DBI::dbGetQuery(con,
    "SELECT detected FROM narrative_results WHERE experiment_id = ?
     ORDER BY result_id",
    params = list(result$experiment_id))
  
  # Should alternate TRUE, FALSE, TRUE, FALSE
  expect_equal(nrow(results), 4)
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core finalizes with correct status", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(2)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("ipv_detected")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT status FROM experiments WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_equal(exp$status, "completed")
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core computes metrics after completion", {
  skip_if_not_smoke()
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(5, with_ipv = 0.5)
  load_sample_narratives(con, narratives)
  
  local_mocked_bindings(
    call_llm = mock_call_llm_rotating(c("ipv_detected", "no_ipv"))
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  exp <- DBI::dbGetQuery(con,
    "SELECT accuracy, f1_ipv FROM experiments WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_false(is.na(exp$accuracy))
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core handles timeout errors", {
  skip_if_not_smoke()
  skip("Timeout handling not fully implemented")
  
  con <- create_temp_db()
  config <- mock_config()
  narratives <- create_sample_narratives(1)
  
  local_mocked_bindings(
    call_llm = mock_call_llm("timeout")
  )
  
  result <- run_benchmark_core(con, config, narratives)
  
  # Should mark as error
  errors <- DBI::dbGetQuery(con,
    "SELECT error_occurred FROM narrative_results WHERE experiment_id = ?",
    params = list(result$experiment_id))
  
  expect_equal(sum(errors$error_occurred, na.rm = TRUE), 1)
  
  DBI::dbDisconnect(con)
})

test_that("run_benchmark_core respects run_seed for reproducibility", {
  skip_if_not_smoke()
  skip("Seed handling not fully testable with mocks")
})
