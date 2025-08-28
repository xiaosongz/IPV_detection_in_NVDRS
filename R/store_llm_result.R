#' Store LLM result in SQLite database
#' 
#' Simple storage function following Unix philosophy.
#' Takes parsed result, stores it, returns success/failure.
#' 
#' @param parsed_result List from parse_llm_result()
#' @param conn Database connection (optional, will create if NULL)
#' @param db_path Database file path (default: "llm_results.db")
#' @param auto_close Whether to close connection after operation (default: TRUE if conn is NULL)
#' @return List with success status and optional error message
#' @export
store_llm_result <- function(parsed_result, 
                            conn = NULL, 
                            db_path = "llm_results.db",
                            auto_close = is.null(conn)) {
  
  # Validate input
  if (!is.list(parsed_result)) {
    return(list(success = FALSE, error = "Input must be a list"))
  }
  
  # Required fields
  if (!("detected" %in% names(parsed_result))) {
    return(list(success = FALSE, error = "Missing 'detected' field"))
  }
  
  # Get connection if not provided
  created_conn <- FALSE
  if (is.null(conn)) {
    tryCatch({
      conn <- get_db_connection(db_path)
      created_conn <- TRUE
      ensure_schema(conn)
    }, error = function(e) {
      return(list(success = FALSE, error = paste("Connection failed:", e$message)))
    })
  }
  
  # Prepare data for insertion
  insert_data <- list(
    narrative_id = parsed_result$narrative_id %||% NA_character_,
    narrative_text = trimws(parsed_result$narrative_text %||% NA_character_),
    detected = as.logical(parsed_result$detected),
    confidence = as.numeric(parsed_result$confidence %||% NA_real_),
    model = parsed_result$model %||% NA_character_,
    prompt_tokens = as.integer(parsed_result$prompt_tokens %||% NA_integer_),
    completion_tokens = as.integer(parsed_result$completion_tokens %||% NA_integer_),
    total_tokens = as.integer(parsed_result$total_tokens %||% NA_integer_),
    response_time_ms = as.integer(parsed_result$response_time_ms %||% NA_integer_),
    raw_response = parsed_result$raw_response %||% NA_character_,
    error_message = parsed_result$error_message %||% NA_character_
  )
  
  # Build SQL
  sql <- "
    INSERT OR IGNORE INTO llm_results (
      narrative_id, narrative_text, detected, confidence,
      model, prompt_tokens, completion_tokens, total_tokens,
      response_time_ms, raw_response, error_message
    ) VALUES (
      :narrative_id, :narrative_text, :detected, :confidence,
      :model, :prompt_tokens, :completion_tokens, :total_tokens,
      :response_time_ms, :raw_response, :error_message
    )
  "
  
  # Execute insertion
  result <- tryCatch({
    rows_affected <- DBI::dbExecute(conn, sql, params = insert_data)
    
    if (rows_affected == 0) {
      list(success = TRUE, warning = "Record already exists (duplicate ignored)")
    } else {
      list(success = TRUE, rows_inserted = rows_affected)
    }
  }, error = function(e) {
    list(success = FALSE, error = paste("Insert failed:", e$message))
  })
  
  # Clean up if we created the connection
  if (created_conn || auto_close) {
    close_db_connection(conn)
  }
  
  result
}

#' Batch store multiple LLM results
#' 
#' Efficient batch insertion with transaction support.
#' Performance target: >1000 inserts/second.
#' 
#' @param parsed_results List of parsed results
#' @param db_path Database file path
#' @param chunk_size Number of records per transaction (default: 1000)
#' @return List with summary statistics
#' @export
store_llm_results_batch <- function(parsed_results, 
                                   db_path = "llm_results.db",
                                   chunk_size = 1000) {
  
  if (!is.list(parsed_results) || length(parsed_results) == 0) {
    return(list(success = FALSE, error = "Input must be non-empty list"))
  }
  
  # Get connection for batch operation
  conn <- get_db_connection(db_path)
  ensure_schema(conn)
  
  # Track results
  total <- length(parsed_results)
  inserted <- 0
  duplicates <- 0
  errors <- 0
  
  # Process in chunks for efficiency
  chunks <- split(parsed_results, 
                 ceiling(seq_along(parsed_results) / chunk_size))
  
  for (chunk in chunks) {
    # Begin transaction for chunk
    DBI::dbBegin(conn)
    
    chunk_success <- TRUE
    for (result in chunk) {
      store_result <- store_llm_result(result, conn = conn, auto_close = FALSE)
      
      if (!store_result$success) {
        errors <- errors + 1
        chunk_success <- FALSE
      } else if (!is.null(store_result$warning)) {
        duplicates <- duplicates + 1
      } else {
        inserted <- inserted + 1
      }
    }
    
    # Commit or rollback chunk
    if (chunk_success) {
      DBI::dbCommit(conn)
    } else {
      DBI::dbRollback(conn)
    }
  }
  
  # Close connection
  close_db_connection(conn)
  
  list(
    success = errors == 0,
    total = total,
    inserted = inserted,
    duplicates = duplicates,
    errors = errors,
    success_rate = (inserted + duplicates) / total
  )
}

# Helper for NULL coalescing
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || (is.character(x) && !nzchar(x[1]))) y else x
}