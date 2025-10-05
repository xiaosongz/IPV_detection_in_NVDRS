# Test Mocking Utilities
#
# Mock functions for LLM calls, API responses, and external dependencies

#' Mock LLM responses with various patterns
#'
#' @param pattern Response pattern: "default", "ipv_detected", "no_ipv",
#'   "high_confidence", "low_confidence", "error", "timeout", "malformed",
#'   "missing_fields", "empty"
#' @return Mocked LLM response list or error
#' @export
mock_llm_response <- function(pattern = "default") {
  switch(pattern,
    "default" = ,
    "ipv_detected" = list(
      detected = TRUE,
      confidence = 0.85,
      indicators = "controlling behavior, isolation, threats",
      rationale = "Clear evidence of intimate partner violence including controlling behavior and threats of harm.",
      reasoning_steps = c(
        "Identified controlling behaviors in narrative",
        "Found threats of violence",
        "Confirmed relationship context"
      ),
      usage = list(
        prompt_tokens = 150,
        completion_tokens = 50,
        total_tokens = 200
      )
    ),
    "no_ipv" = list(
      detected = FALSE,
      confidence = 0.92,
      indicators = "none identified",
      rationale = "No indicators of intimate partner violence found in the narrative.",
      reasoning_steps = c(
        "Reviewed narrative for IPV indicators",
        "No relationship violence patterns found",
        "Incident appears unrelated to IPV"
      ),
      usage = list(
        prompt_tokens = 145,
        completion_tokens = 45,
        total_tokens = 190
      )
    ),
    "high_confidence" = list(
      detected = TRUE,
      confidence = 0.98,
      indicators = "physical violence, coercion, isolation",
      rationale = "Multiple clear indicators of severe intimate partner violence.",
      reasoning_steps = c("Step 1", "Step 2", "Step 3"),
      usage = list(prompt_tokens = 150, completion_tokens = 60, total_tokens = 210)
    ),
    "low_confidence" = list(
      detected = TRUE,
      confidence = 0.35,
      indicators = "possible argument",
      rationale = "Some indicators present but context unclear.",
      reasoning_steps = c("Uncertain evidence", "Limited information"),
      usage = list(prompt_tokens = 140, completion_tokens = 40, total_tokens = 180)
    ),
    "malformed" = '{"detected": true, "confidence": }', # Invalid JSON
    "missing_fields" = list(
      detected = TRUE
      # Missing required fields
    ),
    "empty" = list(),
    "missing_usage" = list(
      detected = TRUE,
      confidence = 0.80,
      indicators = "test",
      rationale = "test rationale",
      reasoning_steps = c("step 1")
      # No usage field
    ),
    "error" = stop("API rate limit exceeded (429)"),
    "timeout" = {
      Sys.sleep(0.1) # Small delay for testing
      stop("Request timeout")
    },
    "auth_error" = stop("Authentication failed (401)"),
    "server_error" = stop("Internal server error (500)"),
    stop("Unknown mock pattern: ", pattern)
  )
}

#' Mock call_llm function
#'
#' @param response_pattern Pattern to use (passed to mock_llm_response)
#' @param delay Simulated API delay in seconds
#' @return Function that mocks call_llm
#' @export
mock_call_llm <- function(response_pattern = "default", delay = 0) {
  function(user_prompt, system_prompt = NULL, model = NULL,
           temperature = NULL, max_tokens = NULL, ...) {
    # Simulate API delay
    if (delay > 0) Sys.sleep(delay)

    # Return mocked response
    mock_llm_response(response_pattern)
  }
}

#' Mock call_llm with rotating responses
#'
#' @param patterns Vector of patterns to cycle through
#' @return Function that mocks call_llm with rotating responses
#' @export
mock_call_llm_rotating <- function(patterns = c("ipv_detected", "no_ipv")) {
  counter <- 0

  function(user_prompt, system_prompt = NULL, model = NULL,
           temperature = NULL, max_tokens = NULL, ...) {
    counter <<- counter + 1
    pattern <- patterns[(counter - 1) %% length(patterns) + 1]
    mock_llm_response(pattern)
  }
}

#' Mock Sys.info for consistent testing
#'
#' @return Mocked system info
#' @export
mock_sys_info <- function() {
  c(
    sysname = "TestOS",
    release = "1.0",
    version = "Test Version",
    nodename = "test-host",
    machine = "x86_64",
    login = "testuser",
    user = "testuser"
  )
}

#' Mock Sys.time for consistent timestamps
#'
#' @param time POSIXct time to return (default: 2025-01-01 12:00:00)
#' @return Function that returns fixed time
#' @export
mock_sys_time <- function(time = as.POSIXct("2025-01-01 12:00:00")) {
  function() time
}

#' Mock uuid::UUIDgenerate for predictable IDs
#'
#' @param ids Vector of IDs to return in sequence
#' @return Function that returns predictable UUIDs
#' @export
mock_uuid_generate <- function(ids = NULL) {
  if (is.null(ids)) {
    ids <- sprintf("test-uuid-%04d", 1:1000)
  }
  counter <- 0

  function() {
    counter <<- counter + 1
    ids[counter]
  }
}

#' Create a mock experiment configuration
#'
#' @param overrides List of values to override defaults
#' @return Configuration list
#' @export
mock_config <- function(overrides = list()) {
  default_config <- list(
    experiment = list(
      name = "test_experiment"
    ),
    model = list(
      name = "test-model",
      provider = "test",
      temperature = 0.0,
      api_url = "http://localhost:1234/v1/chat/completions"
    ),
    prompt = list(
      version = "test-v1",
      system_prompt = "You are an IPV detection system.",
      user_template = "Analyze: <<TEXT>>"
    ),
    data = list(
      file = "tests/fixtures/data/test_data.csv",
      max_narratives = 10
    ),
    run = list(
      seed = 42,
      save_incremental = TRUE,
      save_csv_json = FALSE
    )
  )

  # Apply overrides
  modifyList(default_config, overrides)
}

#' Mock database connection with pre-populated data
#'
#' @param n_experiments Number of experiments to create
#' @param n_results Number of results to create
#' @return Database connection
#' @export
mock_populated_db <- function(n_experiments = 3, n_results = 30) {
  con <- create_temp_db(initialize = TRUE)

  # Add sample narratives
  load_sample_narratives(con)

  # Add experiments
  for (i in 1:n_experiments) {
    exp_id <- sprintf("test-exp-%03d", i)

    DBI::dbExecute(con, "
      INSERT INTO experiments (
        experiment_id, experiment_name, status,
        model_name, temperature, system_prompt, user_template,
        n_narratives_total, n_narratives_processed,
        accuracy, precision_ipv, recall_ipv, f1_ipv
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(
      exp_id,
      sprintf("Test Experiment %d", i),
      "completed",
      "test-model",
      0.0 + i * 0.1,
      "Test system prompt",
      "Test template",
      10L,
      10L,
      0.9,
      0.85,
      0.80,
      0.825
    ))

    # Add results for this experiment
    n_per_exp <- n_results %/% n_experiments
    for (j in 1:n_per_exp) {
      DBI::dbExecute(con, "
        INSERT INTO narrative_results (
          experiment_id, incident_id, detected, confidence,
          indicators, rationale, prompt_tokens, completion_tokens, tokens_used
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", params = list(
        exp_id,
        sprintf("INC-%05d", j),
        j %% 2, # Alternate detected
        0.7 + runif(1) * 0.3,
        "test indicators",
        "test rationale",
        150L,
        50L,
        200L
      ))
    }
  }

  return(con)
}

#' Mock httr2 response for API testing
#'
#' @param status_code HTTP status code
#' @param body Response body
#' @return Mocked httr2 response
#' @export
mock_httr2_response <- function(status_code = 200, body = NULL) {
  if (is.null(body)) {
    body <- list(
      choices = list(
        list(
          message = list(
            content = jsonlite::toJSON(mock_llm_response("default"), auto_unbox = TRUE)
          )
        )
      ),
      usage = list(
        prompt_tokens = 150,
        completion_tokens = 50,
        total_tokens = 200
      )
    )
  }

  # Create a simple response object
  structure(
    list(
      status_code = status_code,
      body = body
    ),
    class = "httr2_response"
  )
}
