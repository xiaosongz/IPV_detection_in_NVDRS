# Core Classes and Utilities
# Base classes for AI providers, batch processing, and shared utilities

library(R6)
library(httr2)
library(jsonlite)
library(glue)
library(digest)

#' Base class for AI providers
#' @export
AIProvider <- R6::R6Class("AIProvider",
  public = list(
    #' @field name Provider name
    name = NULL,
    
    #' @field config Provider configuration
    config = NULL,
    
    #' @field logger Logger instance
    logger = NULL,
    
    #' Initialize AI Provider
    #' @param name Provider name
    #' @param config Provider configuration
    #' @param logger Logger instance
    initialize = function(name, config, logger = NULL) {
      self$name <- name
      self$config <- config
      self$logger <- logger
      
      if (is.null(self$logger)) {
        self$logger <- Logger$new()
      }
      
      self$logger$info("Initializing AI provider", provider = name)
      private$validate_config()
    },
    
    #' Process a batch of narratives
    #' @param narratives Vector of narrative texts
    #' @param batch_id Batch identifier
    #' @return Data frame with results
    process_batch = function(narratives, batch_id) {
      stop("process_batch must be implemented by subclass")
    },
    
    #' Validate response from AI
    #' @param response Response object
    #' @return Validated response or error
    validate_response = function(response) {
      required_fields <- c(
        "sequence", "rationale", "key_facts_summary",
        "family_friend_mentioned", "intimate_partner_mentioned",
        "violence_mentioned", "substance_abuse_mentioned",
        "ipv_between_intimate_partners"
      )
      
      # Check if response is a data frame
      if (!is.data.frame(response)) {
        stop("Response must be a data frame")
      }
      
      # Check for required fields
      missing_fields <- setdiff(required_fields, names(response))
      if (length(missing_fields) > 0) {
        stop(glue("Response missing required fields: {paste(missing_fields, collapse = ', ')}"))
      }
      
      # Validate field values
      valid_values <- c("yes", "no", "unclear", "skipped_na", "api_or_parse_error")
      check_fields <- c(
        "family_friend_mentioned", "intimate_partner_mentioned",
        "violence_mentioned", "substance_abuse_mentioned",
        "ipv_between_intimate_partners"
      )
      
      for (field in check_fields) {
        invalid <- !(response[[field]] %in% valid_values)
        if (any(invalid)) {
          warning(glue("Invalid values in {field}: {paste(unique(response[[field]][invalid]), collapse = ', ')}"))
        }
      }
      
      return(response)
    },
    
    #' Get provider status
    #' @return List with status information
    get_status = function() {
      list(
        name = self$name,
        configured = !is.null(self$config),
        available = private$check_availability()
      )
    }
  ),
  
  private = list(
    #' Validate provider configuration
    validate_config = function() {
      if (is.null(self$config)) {
        stop("Provider configuration is required")
      }
    },
    
    #' Check if provider is available
    check_availability = function() {
      TRUE  # Override in subclasses
    }
  )
)

#' Batch processor for parallel execution
#' @export
BatchProcessor <- R6::R6Class("BatchProcessor",
  public = list(
    #' @field provider AI provider instance
    provider = NULL,
    
    #' @field config Processing configuration
    config = NULL,
    
    #' @field logger Logger instance
    logger = NULL,
    
    #' @field progress_tracker Progress tracker instance
    progress_tracker = NULL,
    
    #' Initialize Batch Processor
    #' @param provider AI provider instance
    #' @param config Processing configuration
    #' @param logger Logger instance
    initialize = function(provider, config, logger = NULL) {
      self$provider <- provider
      self$config <- config
      self$logger <- logger %||% Logger$new()
      
      # Initialize progress tracker
      checkpoint_dir <- config$checkpoint_dir %||% "checkpoints"
      self$progress_tracker <- ProgressTracker$new(checkpoint_dir, self$logger)
      
      self$logger$info("Batch processor initialized", 
                      provider = provider$name,
                      batch_size = config$batch_size)
    },
    
    #' Process all narratives
    #' @param data Data frame with narratives
    #' @return Data frame with results
    process_all = function(data) {
      self$logger$info("Starting batch processing", total_rows = nrow(data))
      
      # Process both narrative types
      results_list <- list()
      
      for (narrative_type in c("CME", "LE")) {
        col_name <- glue("Narrative{narrative_type}")
        if (col_name %in% names(data)) {
          self$logger$info("Processing narrative type", type = narrative_type)
          results <- self$process_narrative_column(data, col_name, narrative_type)
          results_list[[narrative_type]] <- results
        }
      }
      
      # Combine results
      combined <- private$combine_results(results_list, data)
      self$logger$info("Batch processing completed", 
                      total_processed = nrow(combined))
      
      return(combined)
    },
    
    #' Process a single narrative column
    #' @param data Data frame
    #' @param col_name Column name containing narratives
    #' @param narrative_type Type identifier (CME or LE)
    #' @return Data frame with results
    process_narrative_column = function(data, col_name, narrative_type) {
      batch_size <- self$config$batch_size %||% 20
      chunks <- split(data, (seq_len(nrow(data)) - 1) %/% batch_size)
      
      results <- list()
      
      for (i in seq_along(chunks)) {
        chunk <- chunks[[i]]
        batch_id <- glue("{narrative_type}_{i}")
        
        # Check if already processed
        if (self$progress_tracker$is_completed(batch_id)) {
          self$logger$info("Batch already completed", batch_id = batch_id)
          results[[i]] <- self$progress_tracker$get_result(batch_id)
          next
        }
        
        # Process batch
        self$logger$info("Processing batch", 
                        batch_id = batch_id, 
                        size = nrow(chunk))
        
        result <- private$process_batch_with_retry(
          chunk[[col_name]], 
          batch_id,
          chunk
        )
        
        # Save progress
        self$progress_tracker$update(batch_id, "completed", result)
        results[[i]] <- result
      }
      
      return(do.call(rbind, results))
    }
  ),
  
  private = list(
    #' Process batch with retry logic
    process_batch_with_retry = function(narratives, batch_id, chunk_data) {
      max_retries <- self$config$max_retries %||% 3
      retry_delay <- self$config$retry_delay %||% 60
      
      for (attempt in 1:max_retries) {
        tryCatch({
          # Mark as in progress
          self$progress_tracker$update(batch_id, "in_progress")
          
          # Process batch
          result <- self$provider$process_batch(narratives, batch_id)
          
          # Validate result
          result <- self$provider$validate_response(result)
          
          # Add metadata
          result$row_id <- chunk_data$row_id
          result$IncidentID <- chunk_data$IncidentID
          result$narrative_type <- gsub("_\\d+$", "", batch_id)
          result$batch_id <- batch_id
          
          return(result)
          
        }, error = function(e) {
          self$logger$error("Batch processing failed", 
                           batch_id = batch_id,
                           attempt = attempt,
                           error = e$message)
          
          if (attempt < max_retries) {
            self$logger$info("Retrying after delay", 
                           batch_id = batch_id,
                           delay_seconds = retry_delay)
            Sys.sleep(retry_delay)
          } else {
            # Mark as failed
            self$progress_tracker$update(batch_id, "failed", error = e$message)
            
            # Return error result if continue_on_error is set
            if (self$config$continue_on_error %||% TRUE) {
              return(private$create_error_result(chunk_data, e$message))
            } else {
              stop(e)
            }
          }
        })
      }
    },
    
    #' Create error result for failed batches
    create_error_result = function(chunk_data, error_message) {
      data.frame(
        row_id = chunk_data$row_id,
        IncidentID = chunk_data$IncidentID,
        sequence = seq_len(nrow(chunk_data)),
        rationale = glue("Processing failed: {error_message}"),
        key_facts_summary = "error",
        family_friend_mentioned = "api_or_parse_error",
        intimate_partner_mentioned = "api_or_parse_error",
        violence_mentioned = "api_or_parse_error",
        substance_abuse_mentioned = "api_or_parse_error",
        ipv_between_intimate_partners = "api_or_parse_error",
        narrative_type = NA,
        batch_id = NA
      )
    },
    
    #' Combine results from multiple narrative types
    combine_results = function(results_list, original_data) {
      # Start with original data
      combined <- original_data
      
      # Add results for each narrative type
      for (narrative_type in names(results_list)) {
        results <- results_list[[narrative_type]]
        
        # Create column names with narrative type suffix
        result_cols <- c(
          "family_friend_mentioned", "intimate_partner_mentioned",
          "violence_mentioned", "substance_abuse_mentioned",
          "ipv_between_intimate_partners", "key_facts_summary",
          "rationale"
        )
        
        for (col in result_cols) {
          new_col <- glue("{col}_{narrative_type}")
          combined <- merge(
            combined,
            results[, c("row_id", "IncidentID", col)],
            by = c("row_id", "IncidentID"),
            all.x = TRUE,
            suffixes = c("", glue("_{narrative_type}"))
          )
          names(combined)[names(combined) == col] <- new_col
        }
      }
      
      return(combined)
    }
  )
)

#' Progress Tracker for checkpoint management
#' @export
ProgressTracker <- R6::R6Class("ProgressTracker",
  public = list(
    #' @field checkpoint_dir Directory for checkpoints
    checkpoint_dir = NULL,
    
    #' @field state Current state
    state = NULL,
    
    #' @field logger Logger instance
    logger = NULL,
    
    #' Initialize Progress Tracker
    #' @param checkpoint_dir Directory for checkpoints
    #' @param logger Logger instance
    initialize = function(checkpoint_dir = "checkpoints", logger = NULL) {
      self$checkpoint_dir <- checkpoint_dir
      self$logger <- logger %||% Logger$new()
      
      # Create checkpoint directory
      if (!dir.exists(self$checkpoint_dir)) {
        dir.create(self$checkpoint_dir, recursive = TRUE)
      }
      
      # Load existing state
      self$load_state()
    },
    
    #' Update batch status
    #' @param batch_id Batch identifier
    #' @param status Status (pending, in_progress, completed, failed)
    #' @param result Result data (optional)
    #' @param error Error message (optional)
    update = function(batch_id, status, result = NULL, error = NULL) {
      self$state[[batch_id]] <- list(
        status = status,
        timestamp = Sys.time(),
        result = result,
        error = error
      )
      self$save_state()
      
      self$logger$debug("Progress updated", 
                       batch_id = batch_id, 
                       status = status)
    },
    
    #' Check if batch is completed
    #' @param batch_id Batch identifier
    #' @return TRUE if completed
    is_completed = function(batch_id) {
      !is.null(self$state[[batch_id]]) && 
        self$state[[batch_id]]$status == "completed"
    },
    
    #' Get result for completed batch
    #' @param batch_id Batch identifier
    #' @return Result data or NULL
    get_result = function(batch_id) {
      if (self$is_completed(batch_id)) {
        return(self$state[[batch_id]]$result)
      }
      return(NULL)
    },
    
    #' Get all pending batches
    #' @return Vector of batch IDs
    get_pending_batches = function() {
      pending <- character()
      for (batch_id in names(self$state)) {
        if (self$state[[batch_id]]$status %in% c("pending", "in_progress")) {
          pending <- c(pending, batch_id)
        }
      }
      return(pending)
    },
    
    #' Load state from checkpoint
    load_state = function() {
      checkpoint_file <- file.path(self$checkpoint_dir, "progress.rds")
      if (file.exists(checkpoint_file)) {
        self$state <- readRDS(checkpoint_file)
        self$logger$info("Loaded checkpoint", 
                        batches = length(self$state))
      } else {
        self$state <- list()
      }
    },
    
    #' Save state to checkpoint
    save_state = function() {
      checkpoint_file <- file.path(self$checkpoint_dir, "progress.rds")
      saveRDS(self$state, checkpoint_file)
    },
    
    #' Get progress summary
    #' @return List with counts by status
    get_summary = function() {
      summary <- list(
        total = length(self$state),
        completed = 0,
        failed = 0,
        in_progress = 0,
        pending = 0
      )
      
      for (batch in self$state) {
        status <- batch$status
        if (status %in% names(summary)) {
          summary[[status]] <- summary[[status]] + 1
        }
      }
      
      return(summary)
    },
    
    #' Clear all checkpoints
    clear = function() {
      self$state <- list()
      self$save_state()
      self$logger$info("Cleared all checkpoints")
    }
  )
)

# Utility functions

#' Null coalescing operator
#' @param x Value to check
#' @param y Default value if x is NULL
#' @return x if not NULL, otherwise y
#' @export
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

#' Create cache key from content
#' @param content Content to hash
#' @return Hash string
#' @export
create_cache_key <- function(content) {
  digest::digest(content, algo = "md5")
}

#' Validate narrative data
#' @param data Data frame to validate
#' @param required_cols Required column names
#' @return TRUE if valid, error otherwise
#' @export
validate_narrative_data <- function(data, required_cols = c("IncidentID")) {
  if (!is.data.frame(data)) {
    stop("Data must be a data frame")
  }
  
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop(glue("Missing required columns: {paste(missing_cols, collapse = ', ')}"))
  }
  
  # Check for narrative columns
  narrative_cols <- grep("^Narrative", names(data), value = TRUE)
  if (length(narrative_cols) == 0) {
    stop("No narrative columns found (expected NarrativeCME, NarrativeLE, etc.)")
  }
  
  return(TRUE)
}