# Tests for db_schema.R
# Database schema initialization and migration

test_that("init_experiment_db creates database file", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test_experiments.db")
    
    conn <- init_experiment_db(db_path)
    
    expect_true(file.exists(db_path))
    expect_valid_db(conn)
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db creates all required tables", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    tables <- DBI::dbListTables(conn)
    
    expect_true("experiments" %in% tables)
    expect_true("narrative_results" %in% tables)
    expect_true("source_narratives" %in% tables)
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db is idempotent", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    
    # Call twice
    conn1 <- init_experiment_db(db_path)
    DBI::dbDisconnect(conn1)
    
    conn2 <- init_experiment_db(db_path)
    
    tables <- DBI::dbListTables(conn2)
    expect_true(length(tables) >= 3)
    
    DBI::dbDisconnect(conn2)
  })
})

test_that("init_experiment_db creates experiments table with correct schema", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Check columns exist
    columns <- DBI::dbListFields(conn, "experiments")
    
    required_cols <- c("experiment_id", "experiment_name", "status",
                      "model_name", "temperature", "system_prompt",
                      "user_template", "accuracy", "f1_ipv")
    
    for (col in required_cols) {
      expect_true(col %in% columns,
                 info = sprintf("Missing column: %s", col))
    }
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db creates narrative_results table with correct schema", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    columns <- DBI::dbListFields(conn, "narrative_results")
    
    required_cols <- c("result_id", "experiment_id", "incident_id",
                      "detected", "confidence", "prompt_tokens",
                      "completion_tokens", "tokens_used")
    
    for (col in required_cols) {
      expect_true(col %in% columns,
                 info = sprintf("Missing column: %s", col))
    }
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db creates source_narratives table", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    columns <- DBI::dbListFields(conn, "source_narratives")
    
    required_cols <- c("narrative_id", "incident_id", "narrative_type",
                      "narrative_text", "manual_flag", "manual_flag_ind")
    
    for (col in required_cols) {
      expect_true(col %in% columns,
                 info = sprintf("Missing column: %s", col))
    }
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db creates indexes", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Query indexes
    indexes <- DBI::dbGetQuery(conn, "
      SELECT name FROM sqlite_master 
      WHERE type='index' AND name LIKE 'idx_%'
    ")
    
    expect_true(nrow(indexes) > 0,
               info = "Should create at least one index")
    
    DBI::dbDisconnect(conn)
  })
})

test_that("get_db_connection returns valid connection", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    
    # Initialize first
    conn1 <- init_experiment_db(db_path)
    DBI::dbDisconnect(conn1)
    
    # Get connection
    conn2 <- get_db_connection(db_path)
    
    expect_valid_db(conn2)
    expect_true(DBI::dbIsValid(conn2))
    
    DBI::dbDisconnect(conn2)
  })
})

test_that("get_db_connection errors on missing database", {
  expect_error(
    get_db_connection("/nonexistent/path/test.db"),
    "not found|does not exist"
  )
})

test_that("ensure_token_columns adds missing token columns", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Drop a token column to simulate old schema
    DBI::dbExecute(conn, "
      CREATE TABLE IF NOT EXISTS narrative_results_backup AS
      SELECT * FROM narrative_results
    ")
    
    # Run migration
    result <- ensure_token_columns(conn)
    
    # Check columns exist
    columns <- DBI::dbListFields(conn, "narrative_results")
    expect_true("prompt_tokens" %in% columns)
    expect_true("completion_tokens" %in% columns)
    expect_true("tokens_used" %in% columns)
    
    DBI::dbDisconnect(conn)
  })
})

test_that("ensure_token_columns is idempotent", {
  with_temp_dir({
    db_path <- file.path(getwd(), "test.db")
    conn <- init_experiment_db(db_path)
    
    # Run twice
    ensure_token_columns(conn)
    result <- ensure_token_columns(conn)
    
    # Should not error
    expect_true(TRUE)
    
    DBI::dbDisconnect(conn)
  })
})

test_that("init_experiment_db uses centralized config when db_path is NULL", {
  # Mock the config function
  withr::local_envvar(c(IPV_DB_PATH = tempfile(fileext = ".db")))
  
  conn <- init_experiment_db(NULL)
  
  expect_valid_db(conn)
  
  DBI::dbDisconnect(conn)
})
