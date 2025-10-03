#' @file experiment_utils.R
#' @section DEPRECATED - DO NOT USE FOR NEW CODE:
#' **This file contains legacy functions from the R&D phase (August 2025).**
#'
#' These functions were used during initial development before the YAML-based
#' experiment tracking system was implemented (October 2025).
#'
#' ## ⚠️ WARNING: Function Name Collisions
#' Several functions in this file have the SAME NAMES as functions in the new system:
#' - `start_experiment()` - Conflicts with experiment_logger::start_experiment()
#' - `list_experiments()` - Conflicts with experiment_queries::list_experiments()
#'
#' Depending on which file R loads last, you'll get different behavior!
#'
#' ## For New Code, Use Instead:
#' - **experiment_logger.R** - For experiment tracking (start/log/finalize)
#' - **experiment_queries.R** - For querying results
#' - **run_experiment.R** - For running complete experiments
#'
#' ## Migration Timeline:
#' - Oct 2025: Marked deprecated (this notice added)
#' - Nov 2025: Will be moved to R/legacy/
#' - Dec 2025: May be removed entirely
#'
#' ## If You Need This Code:
#' Contact the maintainer before the Nov 2025 cleanup. We can extract any
#' useful functions and add them to the new system.
#'
#' @keywords internal deprecated
NULL

#' Experiment utilities for R&D phase
#' 
#' Optional functions for tracking prompt experiments.
#' These functions supplement the basic IPV detection with experiment tracking.
#' Only use these if you need to compare different prompt versions.

#' Register a new prompt version
#' 
#' Stores a prompt version in the database for experiment tracking.
#' Automatically generates a hash to detect duplicates.
#' 
#' @param system_prompt The system prompt text
#' @param user_prompt_template The user prompt template (use {text} as placeholder)
#' @param version_tag Optional human-readable version tag (e.g., "v1.0_baseline")
#' @param notes Optional description of this prompt version
#' @param conn Database connection (optional, will create if NULL)
#' @param db_path Path to database file (default: "llm_results.db")
#' @return Prompt version ID or NULL if failed
#' @export
#' @examples
#' \dontrun{
#' # Register a baseline prompt version
#' sys_prompt <- "You are an expert at identifying intimate partner violence."
#' user_template <- "Analyze this narrative for IPV indicators: {text}"
#' 
#' prompt_id <- register_prompt(
#'   system_prompt = sys_prompt,
#'   user_prompt_template = user_template,
#'   version_tag = "v1.0_baseline",
#'   notes = "Initial baseline prompt"
#' )
#' 
#' # Register improved version
#' enhanced_prompt_id <- register_prompt(
#'   system_prompt = "You are an expert forensic analyst...",
#'   user_prompt_template = "Analyze for IPV with confidence: {text}",
#'   version_tag = "v2.0_enhanced"
#' )
#' 
#' # List all registered prompts
#' versions <- list_prompt_versions()
#' print(versions)
#' }
register_prompt <- function(system_prompt, 
                          user_prompt_template,
                          version_tag = NULL,
                          notes = NULL,
                          conn = NULL,
                          db_path = "llm_results.db") {
  
  # Validate inputs
  if (missing(system_prompt) || missing(user_prompt_template)) {
    stop("Both system_prompt and user_prompt_template are required")
  }
  
  # Generate hash for deduplication
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' required. Install with: install.packages('digest')")
  }
  
  prompt_content <- paste(system_prompt, user_prompt_template, sep = "\n---\n")
  prompt_hash <- digest::digest(prompt_content, algo = "sha256")
  
  # Get connection if not provided
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    ensure_experiment_schema(conn)
    created_conn <- TRUE
  }
  
  # Check if this prompt already exists
  existing <- DBI::dbGetQuery(
    conn, 
    "SELECT id, version_tag FROM prompt_versions WHERE prompt_hash = ?",
    params = list(prompt_hash)
  )
  
  if (nrow(existing) > 0) {
    message(sprintf("Prompt already registered as ID %d (version: %s)", 
                   existing$id[1], existing$version_tag[1]))
    if (created_conn) close_db_connection(conn)
    return(existing$id[1])
  }
  
  # Insert new prompt version
  result <- tryCatch({
    DBI::dbExecute(
      conn,
      "INSERT INTO prompt_versions (system_prompt, user_prompt_template, prompt_hash, version_tag, notes) 
       VALUES (?, ?, ?, ?, ?)",
      params = list(
        system_prompt, 
        user_prompt_template, 
        prompt_hash, 
        version_tag %||% NA_character_, 
        notes %||% NA_character_
      )
    )
    
    # Get the inserted ID
    prompt_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id
    message(sprintf("Registered prompt version ID: %d", prompt_id))
    prompt_id
    
  }, error = function(e) {
    warning(sprintf("Failed to register prompt: %s", e$message))
    NULL
  })
  
  if (created_conn) close_db_connection(conn)
  result
}

#' Get prompt by version ID
#' 
#' Retrieves a prompt version from the database.
#' 
#' @param prompt_id The prompt version ID
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return List with system_prompt and user_prompt_template, or NULL if not found
#' @export
get_prompt <- function(prompt_id, conn = NULL, db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  result <- DBI::dbGetQuery(
    conn,
    "SELECT system_prompt, user_prompt_template, version_tag, notes 
     FROM prompt_versions WHERE id = ?",
    params = list(prompt_id)
  )
  
  if (created_conn) close_db_connection(conn)
  
  if (nrow(result) == 0) {
    warning(sprintf("Prompt version ID %d not found", prompt_id))
    return(NULL)
  }
  
  list(
    system_prompt = result$system_prompt[1],
    user_prompt_template = result$user_prompt_template[1],
    version_tag = result$version_tag[1],
    notes = result$notes[1]
  )
}

#' List all prompt versions
#' 
#' Returns a summary of all registered prompt versions.
#' 
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return Data frame with prompt version information
#' @export
list_prompt_versions <- function(conn = NULL, db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  result <- DBI::dbGetQuery(
    conn,
    "SELECT id, version_tag, created_at, notes,
            SUBSTR(system_prompt, 1, 50) as system_preview,
            SUBSTR(user_prompt_template, 1, 50) as user_preview
     FROM prompt_versions 
     ORDER BY created_at DESC"
  )
  
  if (created_conn) close_db_connection(conn)
  result
}

#' Compare two prompt versions
#' 
#' Shows differences between two prompt versions.
#' 
#' @param prompt_id1 First prompt version ID
#' @param prompt_id2 Second prompt version ID
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return List showing the differences
#' @export
compare_prompts <- function(prompt_id1, prompt_id2, 
                          conn = NULL, db_path = "llm_results.db") {
  
  prompt1 <- get_prompt(prompt_id1, conn, db_path)
  prompt2 <- get_prompt(prompt_id2, conn, db_path)
  
  if (is.null(prompt1) || is.null(prompt2)) {
    stop("One or both prompt versions not found")
  }
  
  list(
    version1 = list(
      id = prompt_id1,
      version_tag = prompt1$version_tag,
      system_prompt = prompt1$system_prompt,
      user_prompt = prompt1$user_prompt_template
    ),
    version2 = list(
      id = prompt_id2,
      version_tag = prompt2$version_tag,
      system_prompt = prompt2$system_prompt,
      user_prompt = prompt2$user_prompt_template
    ),
    system_changed = prompt1$system_prompt != prompt2$system_prompt,
    user_changed = prompt1$user_prompt_template != prompt2$user_prompt_template
  )
}

# ============================================================================
# Experiment Management Functions
# ============================================================================

#' Start a new experiment
#' 
#' Creates a new experiment record for tracking a batch of tests.
#' 
#' @param name Experiment name (e.g., "baseline_test", "keyword_enhanced_v2")
#' @param prompt_version_id ID of the prompt version to use
#' @param model Model identifier (e.g., "gpt-4", "claude-3")
#' @param dataset_name Optional dataset identifier
#' @param notes Optional notes about this experiment
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return Experiment ID or NULL if failed
#' @export
#' @examples
#' \dontrun{
#' # Start a baseline experiment
#' prompt_id <- register_prompt("System prompt", "User template")
#' 
#' exp_id <- start_experiment(
#'   name = "baseline_test_jan2025",
#'   prompt_version_id = prompt_id,
#'   model = "gpt-4o-mini",
#'   dataset_name = "NVDRS_sample_100",
#'   notes = "Testing baseline prompt on 100 random cases"
#' )
#' 
#' # Run your tests and store results
#' # ... process narratives ...
#' # store_experiment_result(exp_id, narrative_id, parsed_result)
#' 
#' # Complete the experiment
#' complete_experiment(exp_id)
#' 
#' # View experiment summary
#' experiments <- list_experiments()
#' print(experiments[experiments$id == exp_id, ])
#' }
start_experiment <- function(name,
                           prompt_version_id,
                           model,
                           dataset_name = NULL,
                           notes = NULL,
                           conn = NULL,
                           db_path = "llm_results.db") {
  
  if (missing(name) || missing(prompt_version_id) || missing(model)) {
    stop("name, prompt_version_id, and model are required")
  }
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    ensure_experiment_schema(conn)
    created_conn <- TRUE
  }
  
  # Verify prompt version exists
  prompt_check <- DBI::dbGetQuery(
    conn,
    "SELECT id FROM prompt_versions WHERE id = ?",
    params = list(prompt_version_id)
  )
  
  if (nrow(prompt_check) == 0) {
    warning(sprintf("Prompt version ID %d not found", prompt_version_id))
    if (created_conn) close_db_connection(conn)
    return(NULL)
  }
  
  # Insert experiment record
  result <- tryCatch({
    DBI::dbExecute(
      conn,
      "INSERT INTO experiments (name, prompt_version_id, model, dataset_name, notes, status) 
       VALUES (?, ?, ?, ?, ?, 'running')",
      params = list(
        name, 
        prompt_version_id, 
        model, 
        dataset_name %||% NA_character_, 
        notes %||% NA_character_
      )
    )
    
    exp_id <- DBI::dbGetQuery(conn, "SELECT last_insert_rowid() as id")$id
    message(sprintf("Started experiment ID: %d (%s)", exp_id, name))
    exp_id
    
  }, error = function(e) {
    warning(sprintf("Failed to start experiment: %s", e$message))
    NULL
  })
  
  if (created_conn) close_db_connection(conn)
  result
}

#' Complete an experiment
#' 
#' Marks an experiment as completed and updates statistics.
#' 
#' @param experiment_id The experiment ID to complete
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return TRUE if successful, FALSE otherwise
#' @export
complete_experiment <- function(experiment_id,
                              conn = NULL,
                              db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  # Get count of results
  result_count <- DBI::dbGetQuery(
    conn,
    "SELECT COUNT(*) as cnt FROM experiment_results WHERE experiment_id = ?",
    params = list(experiment_id)
  )$cnt
  
  # Update experiment record
  success <- tryCatch({
    DBI::dbExecute(
      conn,
      "UPDATE experiments 
       SET status = 'completed', 
           completed_at = CURRENT_TIMESTAMP,
           total_narratives = ?
       WHERE id = ?",
      params = list(result_count, experiment_id)
    )
    
    message(sprintf("Completed experiment ID: %d (%d results)", 
                   experiment_id, result_count))
    TRUE
    
  }, error = function(e) {
    warning(sprintf("Failed to complete experiment: %s", e$message))
    FALSE
  })
  
  if (created_conn) close_db_connection(conn)
  success
}

#' Store result with experiment tracking
#' 
#' Stores a result linked to an experiment.
#' Similar to store_llm_result but links to experiment.
#' 
#' @param experiment_id The experiment this result belongs to
#' @param narrative_id Identifier for the narrative
#' @param parsed_result Parsed result from parse_llm_result()
#' @param narrative_text The actual narrative text (optional if in parsed_result)
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return TRUE if successful, FALSE otherwise
#' @export
store_experiment_result <- function(experiment_id,
                                  narrative_id,
                                  parsed_result,
                                  narrative_text = NULL,
                                  conn = NULL,
                                  db_path = "llm_results.db") {
  
  if (!is.list(parsed_result)) {
    stop("parsed_result must be a list")
  }
  
  if (!("detected" %in% names(parsed_result))) {
    stop("parsed_result must contain 'detected' field")
  }
  
  # Get narrative text from parsed result if not provided
  if (is.null(narrative_text) && "narrative_text" %in% names(parsed_result)) {
    narrative_text <- parsed_result$narrative_text
  }
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  # Prepare data
  insert_data <- list(
    experiment_id = experiment_id,
    narrative_id = narrative_id,
    narrative_text = trimws(narrative_text %||% ""),
    detected = as.logical(parsed_result$detected),
    confidence = as.numeric(parsed_result$confidence %||% NA_real_),
    response_time_ms = as.integer(parsed_result$response_time_ms %||% NA_integer_),
    prompt_tokens = as.integer(parsed_result$prompt_tokens %||% NA_integer_),
    completion_tokens = as.integer(parsed_result$completion_tokens %||% NA_integer_),
    total_tokens = as.integer(parsed_result$total_tokens %||% NA_integer_),
    raw_response = parsed_result$raw_response %||% NA_character_,
    error_message = parsed_result$error_message %||% NA_character_
  )
  
  # Insert result
  success <- tryCatch({
    DBI::dbExecute(
      conn,
      "INSERT OR IGNORE INTO experiment_results 
       (experiment_id, narrative_id, narrative_text, detected, confidence,
        response_time_ms, prompt_tokens, completion_tokens, total_tokens,
        raw_response, error_message)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      params = unname(insert_data)
    )
    TRUE
    
  }, error = function(e) {
    warning(sprintf("Failed to store experiment result: %s", e$message))
    FALSE
  })
  
  if (created_conn) close_db_connection(conn)
  success
}

#' List all experiments
#' 
#' Returns a summary of all experiments.
#' 
#' @param status Filter by status ("running", "completed", "failed", or NULL for all)
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return Data frame with experiment information
#' @export
list_experiments <- function(status = NULL,
                           conn = NULL,
                           db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  query <- "
    SELECT 
      e.id,
      e.name,
      pv.version_tag as prompt_version,
      e.model,
      e.dataset_name,
      e.status,
      e.started_at,
      e.completed_at,
      e.total_narratives,
      COUNT(er.id) as actual_results
    FROM experiments e
    LEFT JOIN prompt_versions pv ON e.prompt_version_id = pv.id
    LEFT JOIN experiment_results er ON e.id = er.experiment_id"
  
  if (!is.null(status)) {
    query <- paste(query, "WHERE e.status = ?")
    result <- DBI::dbGetQuery(conn, paste(query, "GROUP BY e.id ORDER BY e.started_at DESC"),
                             params = list(status))
  } else {
    result <- DBI::dbGetQuery(conn, paste(query, "GROUP BY e.id ORDER BY e.started_at DESC"))
  }
  
  if (created_conn) close_db_connection(conn)
  result
}

# Helper for NULL coalescing (same as in store_llm_result.R)
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && !nzchar(x[1]))) y else x
}