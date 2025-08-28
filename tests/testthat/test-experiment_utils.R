test_that("register_prompt creates new prompt version", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  # Setup
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  ensure_experiment_schema(conn)
  
  # Register a prompt
  system_prompt <- "You are an IPV detector"
  user_prompt <- "Analyze this narrative: {text}"
  
  prompt_id <- register_prompt(
    system_prompt = system_prompt,
    user_prompt_template = user_prompt,
    version_tag = "test_v1",
    notes = "Test prompt",
    conn = conn
  )
  
  expect_true(is.numeric(prompt_id))
  expect_true(prompt_id > 0)
  
  # Verify in database
  stored <- DBI::dbGetQuery(
    conn,
    "SELECT * FROM prompt_versions WHERE id = ?",
    params = list(prompt_id)
  )
  
  expect_equal(nrow(stored), 1)
  expect_equal(stored$system_prompt, system_prompt)
  expect_equal(stored$user_prompt_template, user_prompt)
  expect_equal(stored$version_tag, "test_v1")
  
  # Clean up
  close_db_connection(conn)
  unlink(db_file)
})

test_that("register_prompt prevents duplicates", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Register same prompt twice
  id1 <- register_prompt(
    system_prompt = "Test system",
    user_prompt_template = "Test user",
    version_tag = "v1",
    db_path = db_file
  )
  
  id2 <- register_prompt(
    system_prompt = "Test system",
    user_prompt_template = "Test user",
    version_tag = "v2",  # Different tag, same content
    db_path = db_file
  )
  
  # Should return same ID
  expect_equal(id1, id2)
  
  # Clean up
  unlink(db_file)
})

test_that("get_prompt retrieves correct prompt", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Register and retrieve
  prompt_id <- register_prompt(
    system_prompt = "System prompt text",
    user_prompt_template = "User {text}",
    version_tag = "retrieve_test",
    db_path = db_file
  )
  
  retrieved <- get_prompt(prompt_id, db_path = db_file)
  
  expect_equal(retrieved$system_prompt, "System prompt text")
  expect_equal(retrieved$user_prompt_template, "User {text}")
  expect_equal(retrieved$version_tag, "retrieve_test")
  
  # Test non-existent prompt
  missing <- get_prompt(99999, db_path = db_file)
  expect_null(missing)
  
  # Clean up
  unlink(db_file)
})

test_that("start_experiment creates experiment record", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # First register a prompt
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  # Start experiment
  exp_id <- start_experiment(
    name = "Test Experiment",
    prompt_version_id = prompt_id,
    model = "test-model",
    dataset_name = "test_data",
    notes = "Testing",
    db_path = db_file
  )
  
  expect_true(is.numeric(exp_id))
  expect_true(exp_id > 0)
  
  # Verify in database
  conn <- get_db_connection(db_file)
  exp <- DBI::dbGetQuery(
    conn,
    "SELECT * FROM experiments WHERE id = ?",
    params = list(exp_id)
  )
  
  expect_equal(nrow(exp), 1)
  expect_equal(exp$name, "Test Experiment")
  expect_equal(exp$model, "test-model")
  expect_equal(exp$status, "running")
  
  close_db_connection(conn)
  unlink(db_file)
})

test_that("start_experiment validates prompt version exists", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  
  db_file <- tempfile(fileext = ".db")
  conn <- get_db_connection(db_file)
  ensure_experiment_schema(conn)
  close_db_connection(conn)
  
  # Try to start experiment with non-existent prompt
  expect_warning(
    exp_id <- start_experiment(
      name = "Invalid Test",
      prompt_version_id = 99999,
      model = "test",
      db_path = db_file
    )
  )
  
  expect_null(exp_id)
  
  # Clean up
  unlink(db_file)
})

test_that("store_experiment_result saves results correctly", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Setup experiment
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  exp_id <- start_experiment(
    name = "Result Test",
    prompt_version_id = prompt_id,
    model = "test",
    db_path = db_file
  )
  
  # Store result
  parsed_result <- list(
    detected = TRUE,
    confidence = 0.95,
    response_time_ms = 123,
    total_tokens = 50
  )
  
  success <- store_experiment_result(
    experiment_id = exp_id,
    narrative_id = "TEST001",
    parsed_result = parsed_result,
    narrative_text = "Test narrative",
    db_path = db_file
  )
  
  expect_true(success)
  
  # Verify stored
  conn <- get_db_connection(db_file)
  result <- DBI::dbGetQuery(
    conn,
    "SELECT * FROM experiment_results WHERE experiment_id = ?",
    params = list(exp_id)
  )
  
  expect_equal(nrow(result), 1)
  expect_equal(result$narrative_id, "TEST001")
  expect_equal(result$detected, 1)  # SQLite stores as integer
  expect_equal(result$confidence, 0.95)
  
  close_db_connection(conn)
  unlink(db_file)
})

test_that("complete_experiment updates status", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Setup
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  exp_id <- start_experiment(
    name = "Complete Test",
    prompt_version_id = prompt_id,
    model = "test",
    db_path = db_file
  )
  
  # Add some results
  for (i in 1:3) {
    store_experiment_result(
      experiment_id = exp_id,
      narrative_id = paste0("TEST", i),
      parsed_result = list(detected = TRUE, confidence = 0.5),
      db_path = db_file
    )
  }
  
  # Complete experiment
  success <- complete_experiment(exp_id, db_path = db_file)
  expect_true(success)
  
  # Verify status
  conn <- get_db_connection(db_file)
  exp <- DBI::dbGetQuery(
    conn,
    "SELECT status, total_narratives FROM experiments WHERE id = ?",
    params = list(exp_id)
  )
  
  expect_equal(exp$status, "completed")
  expect_equal(exp$total_narratives, 3)
  
  close_db_connection(conn)
  unlink(db_file)
})

test_that("list_experiments returns correct summaries", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Create multiple experiments
  prompt_id <- register_prompt(
    system_prompt = "Test",
    user_prompt_template = "Test",
    db_path = db_file
  )
  
  exp1 <- start_experiment("Exp 1", prompt_id, "model1", db_path = db_file)
  exp2 <- start_experiment("Exp 2", prompt_id, "model2", db_path = db_file)
  
  complete_experiment(exp1, db_path = db_file)
  
  # List all
  all_exps <- list_experiments(db_path = db_file)
  expect_equal(nrow(all_exps), 2)
  
  # List by status
  running <- list_experiments(status = "running", db_path = db_file)
  expect_equal(nrow(running), 1)
  expect_equal(running$name, "Exp 2")
  
  completed <- list_experiments(status = "completed", db_path = db_file)
  expect_equal(nrow(completed), 1)
  expect_equal(completed$name, "Exp 1")
  
  # Clean up
  unlink(db_file)
})

test_that("compare_prompts shows differences", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("digest")
  
  db_file <- tempfile(fileext = ".db")
  
  # Register two different prompts
  id1 <- register_prompt(
    system_prompt = "System 1",
    user_prompt_template = "User 1",
    version_tag = "v1",
    db_path = db_file
  )
  
  id2 <- register_prompt(
    system_prompt = "System 2",
    user_prompt_template = "User 1",  # Same user, different system
    version_tag = "v2",
    db_path = db_file
  )
  
  comparison <- compare_prompts(id1, id2, db_path = db_file)
  
  expect_true(comparison$system_changed)
  expect_false(comparison$user_changed)
  expect_equal(comparison$version1$version_tag, "v1")
  expect_equal(comparison$version2$version_tag, "v2")
  
  # Clean up
  unlink(db_file)
})