#' Store LLM result in database
#' 
#' Simple storage function following Unix philosophy and tidyverse style.
#' Takes parsed result, stores it, returns success/failure.
#' Works transparently with both SQLite and PostgreSQL backends.
#' 
#' @param parsed_result List from parse_llm_result()
#' @param conn Database connection (optional, will create if NULL)
#' @param db_path Database file path for SQLite or config for unified connection (default: "llm_results.db")
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
      # Use unified connection function to support both backends
      conn <- get_unified_connection(db_path)
      created_conn <- TRUE
      ensure_schema(conn)
    }, error = function(e) {
      return(list(success = FALSE, error = paste("Connection failed:", e$message)))
    })
  }
  
  # Prepare data for insertion using tidyverse style
  insert_data <- tibble::tibble(
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
  ) |>
    dplyr::slice(1)  # Ensure single row
  
  # Build database-specific SQL
  db_type <- detect_db_type(conn)
  
  if (db_type == "postgresql") {
    # PostgreSQL: Use ON CONFLICT DO NOTHING
    sql <- "
      INSERT INTO llm_results (
        narrative_id, narrative_text, detected, confidence,
        model, prompt_tokens, completion_tokens, total_tokens,
        response_time_ms, raw_response, error_message
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
      )
      ON CONFLICT (narrative_id, narrative_text, model) DO NOTHING
    "
  } else {
    # SQLite: Use INSERT OR IGNORE (existing behavior)
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
  }
  
  # Execute insertion with database-specific parameter binding
  result <- tryCatch({
    if (db_type == "postgresql") {
      # PostgreSQL: Use positional parameters
      rows_affected <- DBI::dbExecute(conn, sql, 
        list(
          insert_data$narrative_id,
          insert_data$narrative_text,
          insert_data$detected,
          insert_data$confidence,
          insert_data$model,
          insert_data$prompt_tokens,
          insert_data$completion_tokens,
          insert_data$total_tokens,
          insert_data$response_time_ms,
          insert_data$raw_response,
          insert_data$error_message
        )
      )
    } else {
      # SQLite: Use named parameters (existing behavior)
      rows_affected <- DBI::dbExecute(conn, sql, params = insert_data)
    }
    
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
#' Optimized for both SQLite and PostgreSQL backends.
#' Performance target: >1000 inserts/second (SQLite), >5000 inserts/second (PostgreSQL).
#' 
#' @param parsed_results List of parsed results
#' @param db_path Database file path for SQLite or config for unified connection (default: "llm_results.db")
#' @param chunk_size Number of records per transaction (default: 1000 for SQLite, 5000 for PostgreSQL)
#' @param conn Existing connection (optional, improves performance)
#' @return List with summary statistics
#' @export
store_llm_results_batch <- function(parsed_results, 
                                   db_path = "llm_results.db",
                                   chunk_size = NULL,
                                   conn = NULL) {
  
  if (!is.list(parsed_results) || length(parsed_results) == 0) {
    return(list(success = FALSE, error = "Input must be non-empty list"))
  }
  
  # Get connection for batch operation
  created_conn <- is.null(conn)
  if (created_conn) {
    conn <- get_unified_connection(db_path)
    ensure_schema(conn)
  }
  
  # Detect database type for optimization
  db_type <- detect_db_type(conn)
  
  # Set optimal chunk size based on database type
  if (is.null(chunk_size)) {
    chunk_size <- if (db_type == "postgresql") 5000 else 1000
  }
  
  # Track results
  total <- length(parsed_results)
  inserted <- 0
  duplicates <- 0
  errors <- 0
  
  # Use optimized batch processing based on database type
  if (db_type == "postgresql" && length(parsed_results) > 100) {
    # PostgreSQL: Use multi-row INSERT for better performance
    result_stats <- store_batch_postgresql_optimized(parsed_results, conn, chunk_size, inserted, duplicates, errors)
    inserted <- result_stats$inserted
    duplicates <- result_stats$duplicates
    errors <- result_stats$errors
  } else {
    # SQLite or small batches: Use existing transaction-based approach
    chunks <- split(parsed_results, 
                   ceiling(seq_along(parsed_results) / chunk_size))
    
    for (chunk in chunks) {
      # Use transaction wrapper for concurrent safety
      chunk_result <- execute_with_transaction(conn, {
        chunk_stats <- list(inserted = 0, duplicates = 0, errors = 0)
        
        for (result in chunk) {
          store_result <- store_llm_result(result, conn = conn, auto_close = FALSE)
          
          if (!store_result$success) {
            chunk_stats$errors <- chunk_stats$errors + 1
          } else if (!is.null(store_result$warning)) {
            chunk_stats$duplicates <- chunk_stats$duplicates + 1
          } else {
            chunk_stats$inserted <- chunk_stats$inserted + 1
          }
        }
        chunk_stats
      })
      
      # Aggregate results
      if (inherits(chunk_result, "try-error")) {
        errors <- errors + length(chunk)
      } else {
        inserted <- inserted + chunk_result$inserted
        duplicates <- duplicates + chunk_result$duplicates
        errors <- errors + chunk_result$errors
      }
    }
  }
  
  # Close connection only if we created it
  if (created_conn) {
    close_db_connection(conn)
  }
  
  list(
    success = errors == 0,
    total = total,
    inserted = inserted,
    duplicates = duplicates,
    errors = errors,
    success_rate = (inserted + duplicates) / total
  )
}

#' PostgreSQL-optimized batch insert
#' 
#' Uses multi-row INSERT statements for maximum PostgreSQL performance.
#' Internal function, not exported.
#' 
#' @param parsed_results List of parsed results
#' @param conn Database connection
#' @param chunk_size Chunk size for batching
#' @param inserted Current inserted count
#' @param duplicates Current duplicates count 
#' @param errors Current errors count
#' @return List with updated counts
store_batch_postgresql_optimized <- function(parsed_results, conn, chunk_size, inserted, duplicates, errors) {
  
  # Process in chunks for memory efficiency
  chunks <- split(parsed_results, 
                 ceiling(seq_along(parsed_results) / chunk_size))
  
  for (chunk in chunks) {
    # Prepare data frame for batch insert
    batch_data <- do.call(rbind, lapply(chunk, function(result) {
      data.frame(
        narrative_id = result$narrative_id %||% NA_character_,
        narrative_text = trimws(result$narrative_text %||% NA_character_),
        detected = as.logical(result$detected),
        confidence = as.numeric(result$confidence %||% NA_real_),
        model = result$model %||% NA_character_,
        prompt_tokens = as.integer(result$prompt_tokens %||% NA_integer_),
        completion_tokens = as.integer(result$completion_tokens %||% NA_integer_),
        total_tokens = as.integer(result$total_tokens %||% NA_integer_),
        response_time_ms = as.integer(result$response_time_ms %||% NA_integer_),
        raw_response = result$raw_response %||% NA_character_,
        error_message = result$error_message %||% NA_character_,
        stringsAsFactors = FALSE
      )
    }))
    
    # Use multi-row INSERT with ON CONFLICT
    placeholders <- paste0("($", 1:11, ")", collapse = ", ")
    value_sets <- rep(placeholders, nrow(batch_data))
    
    # Rebuild placeholders for multiple rows
    placeholder_offset <- 0
    multi_row_placeholders <- character(nrow(batch_data))
    for (i in seq_len(nrow(batch_data))) {
      row_placeholders <- paste0("($", (placeholder_offset + 1):(placeholder_offset + 11), ")", collapse = ", ")
      multi_row_placeholders[i] <- paste0("(", paste0("$", (placeholder_offset + 1):(placeholder_offset + 11), collapse = ", "), ")")
      placeholder_offset <- placeholder_offset + 11
    }
    
    sql <- sprintf("
      INSERT INTO llm_results (
        narrative_id, narrative_text, detected, confidence,
        model, prompt_tokens, completion_tokens, total_tokens,
        response_time_ms, raw_response, error_message
      ) VALUES %s
      ON CONFLICT (narrative_id, narrative_text, model) DO NOTHING
    ", paste(multi_row_placeholders, collapse = ", "))
    
    # Flatten parameters for multi-row insert
    params <- as.list(as.vector(t(as.matrix(batch_data))))
    
    # Execute with transaction
    chunk_result <- execute_with_transaction(conn, {
      rows_affected <- DBI::dbExecute(conn, sql, params)
      list(
        inserted = rows_affected,
        duplicates = nrow(batch_data) - rows_affected,
        errors = 0
      )
    })
    
    # Aggregate results
    if (inherits(chunk_result, "try-error")) {
      errors <- errors + nrow(batch_data)
    } else {
      inserted <- inserted + chunk_result$inserted
      duplicates <- duplicates + chunk_result$duplicates
      errors <- errors + chunk_result$errors
    }
  }
  
  list(inserted = inserted, duplicates = duplicates, errors = errors)
}

# NULL coalescing operator is now defined in utils.R