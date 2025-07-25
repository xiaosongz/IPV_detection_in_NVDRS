# Ollama Provider Implementation
# Handles communication with local Ollama instance for IPV detection

library(R6)
library(httr2)
library(jsonlite)
library(glue)

# Source dependencies
source("R/lib/core.R")

#' Ollama Provider Class
#' @export
OllamaProvider <- R6::R6Class("OllamaProvider",
  inherit = AIProvider,
  
  public = list(
    #' @field cache_manager Cache manager instance
    cache_manager = NULL,
    
    #' Initialize Ollama Provider
    #' @param config Provider configuration
    #' @param logger Logger instance
    #' @param cache_manager Cache manager instance
    initialize = function(config, logger = NULL, cache_manager = NULL) {
      super$initialize("ollama", config, logger)
      self$cache_manager <- cache_manager
      
      # Validate endpoint
      private$validate_endpoint()
      
      # Set up system prompt
      private$setup_system_prompt()
      
      # Check connection
      if (!private$check_connection()) {
        warning("Ollama server is not accessible. Provider may not work correctly.")
      }
      
      self$logger$info("Ollama provider initialized", 
                      model = config$model,
                      endpoint = config$endpoint)
    },
    
    #' Process batch of narratives
    #' @param narratives Vector of narrative texts
    #' @param batch_id Batch identifier
    #' @return Data frame with results
    process_batch = function(narratives, batch_id) {
      self$logger$debug("Processing batch", 
                       batch_id = batch_id,
                       size = length(narratives))
      
      # Handle invalid narratives
      validation <- private$validate_batch_input(narratives)
      if (validation$all_invalid) {
        return(private$create_skipped_results(narratives, batch_id))
      }
      
      # Check cache
      if (!is.null(self$cache_manager)) {
        cached_result <- private$check_cache(validation$valid_narratives, batch_id)
        if (!is.null(cached_result)) {
          return(private$merge_results(cached_result, validation, batch_id))
        }
      }
      
      # Prepare request
      request_data <- private$prepare_request(validation$valid_narratives)
      
      # Make API call
      response <- private$make_api_call(request_data, batch_id)
      
      # Parse response
      parsed_result <- private$parse_response(response, validation$valid_narratives)
      
      # Cache result
      if (!is.null(self$cache_manager)) {
        private$save_to_cache(validation$valid_narratives, parsed_result, batch_id)
      }
      
      # Merge with invalid narrative placeholders
      final_result <- private$merge_results(parsed_result, validation, batch_id)
      
      return(final_result)
    },
    
    #' Check if Ollama server is available
    #' @return TRUE if available
    is_available = function() {
      private$check_connection()
    }
  ),
  
  private = list(
    #' @field system_prompt System prompt for the model
    system_prompt = NULL,
    
    #' @field base_url Base URL for Ollama API
    base_url = NULL,
    
    #' Validate endpoint configuration
    validate_endpoint = function() {
      endpoint <- self$config$endpoint
      
      if (is.null(endpoint) || !nzchar(endpoint)) {
        stop("Ollama endpoint is required in configuration")
      }
      
      # Extract base URL
      private$base_url <- sub("/api/.*$", "", endpoint)
      
      # Validate URL format
      if (!grepl("^https?://", endpoint)) {
        stop("Ollama endpoint must be a valid HTTP(S) URL")
      }
    },
    
    #' Set up system prompt
    setup_system_prompt = function() {
      # Same prompt as OpenAI for consistency
      private$system_prompt <- paste(
        "You are a meticulous forensic pathologist and data analyst.",
        "Your task is to review fatality review narratives and extract specific, objective information.",
        "Your classifications will be audited against evaluations by human experts, so every answer must be based *only* on explicit evidence within the provided text.",
        "First, think step-by-step to form a rationale for your classifications, then provide the final JSON object.",
        "",
        "For each narrative provided, you MUST return a single JSON object with the following 8 fields:",
        "{",
        "  \"sequence\": <integer>,",
        "  \"rationale\": \"A brief explanation of why you made each yes/no/unclear choice, citing evidence from the text.\",",
        "  \"key_facts_summary\": \"A 1-2 sentence objective summary of the key events and circumstances described.\",",
        "  \"family_friend_mentioned\": \"yes\", \"no\", or \"unclear\",",
        "  \"intimate_partner_mentioned\": \"yes\", \"no\", or \"unclear\",",
        "  \"violence_mentioned\": \"yes\", \"no\", or \"unclear\",",
        "  \"substance_abuse_mentioned\": \"yes\", \"no\", or \"unclear\",",
        "  \"ipv_between_intimate_partners\": \"yes\", \"no\", or \"unclear\"",
        "}",
        "",
        "Respond with a single, valid JSON array containing one object for each narrative.",
        "Do not include markdown formatting (like ```json), commentary, or any other text outside of the JSON array."
      )
    },
    
    #' Check connection to Ollama server
    check_connection = function() {
      # Try to get model list as a health check
      health_url <- paste0(private$base_url, "/api/tags")
      
      result <- tryCatch({
        response <- request(health_url) |>
          req_timeout(5) |>
          req_perform()
        
        resp_status(response) == 200
      }, error = function(e) {
        self$logger$warning("Failed to connect to Ollama", 
                           url = health_url,
                           error = e$message)
        FALSE
      })
      
      return(result)
    },
    
    #' Validate batch input
    validate_batch_input = function(narratives) {
      is_invalid <- is.na(narratives) | narratives == ""
      valid_narratives <- narratives[!is_invalid]
      
      list(
        all_invalid = length(valid_narratives) == 0,
        is_invalid = is_invalid,
        valid_narratives = valid_narratives,
        valid_indices = which(!is_invalid)
      )
    },
    
    #' Create skipped results for invalid narratives
    create_skipped_results = function(narratives, batch_id) {
      self$logger$info("Skipping empty batch", batch_id = batch_id)
      
      data.frame(
        sequence = seq_along(narratives),
        rationale = "Narrative was NA or empty.",
        key_facts_summary = "skipped_na",
        family_friend_mentioned = "skipped_na",
        intimate_partner_mentioned = "skipped_na",
        violence_mentioned = "skipped_na",
        substance_abuse_mentioned = "skipped_na",
        ipv_between_intimate_partners = "skipped_na",
        stringsAsFactors = FALSE
      )
    },
    
    #' Check cache for results
    check_cache = function(narratives, batch_id) {
      if (is.null(self$cache_manager)) return(NULL)
      
      cache_key <- create_cache_key(paste(narratives, collapse = "|"))
      cached <- self$cache_manager$get(cache_key)
      
      if (!is.null(cached)) {
        self$logger$info("Using cached results", batch_id = batch_id)
        return(cached)
      }
      
      return(NULL)
    },
    
    #' Prepare API request
    prepare_request = function(narratives) {
      user_prompt <- paste(
        "Analyze the following narratives and return a JSON array of results:",
        paste0(sprintf("Narrative %03d: %s", seq_along(narratives), narratives), 
               collapse = "\n\n")
      )
      
      # Combine system prompt and user prompt for Ollama
      full_prompt <- paste(private$system_prompt, "\n\n", user_prompt)
      
      list(
        model = self$config$model %||% "llama3.1:8b",
        prompt = full_prompt,
        stream = FALSE,
        options = list(
          temperature = self$config$temperature %||% 0,
          num_predict = 4096  # Ensure enough tokens for response
        )
      )
    },
    
    #' Make API call with error handling
    make_api_call = function(request_data, batch_id) {
      endpoint <- self$config$endpoint %||% "http://localhost:11434/api/generate"
      timeout <- self$config$timeout %||% 300  # Longer timeout for local models
      
      self$logger$debug("Making API call", batch_id = batch_id, endpoint = endpoint)
      
      response <- tryCatch({
        req <- request(endpoint) |>
          req_headers("Content-Type" = "application/json") |>
          req_body_json(request_data) |>
          req_timeout(timeout)
        
        req_perform(req)
      }, error = function(e) {
        self$logger$error("API call failed", 
                         batch_id = batch_id,
                         error = e$message)
        
        # Check if it's a connection error
        if (grepl("Failed to connect", e$message)) {
          stop(glue("Cannot connect to Ollama at {endpoint}. ",
                   "Please ensure Ollama is running."))
        }
        
        stop(e)
      })
      
      # Check response status
      if (resp_status(response) != 200) {
        error_body <- tryCatch(
          resp_body_json(response),
          error = function(e) list(error = "Unknown error")
        )
        
        self$logger$error("API error response", 
                         batch_id = batch_id,
                         status = resp_status(response),
                         error = error_body$error)
        stop(glue("Ollama API error: {error_body$error}"))
      }
      
      resp_body_json(response)
    },
    
    #' Parse API response
    parse_response = function(response, narratives) {
      # Extract content from Ollama response
      content <- response$response
      
      if (is.null(content) || !nzchar(content)) {
        stop("Empty response from Ollama")
      }
      
      # Remove markdown formatting if present
      content <- gsub("```json\\s*|```\\s*$", "", content)
      
      # Try to extract JSON array if there's extra text
      json_match <- regexpr("\\[\\s*\\{[^\\[\\]]*\\}\\s*\\]", content)
      if (json_match > 0) {
        content <- regmatches(content, json_match)
      }
      
      # Parse JSON
      parsed <- tryCatch({
        fromJSON(content, flatten = TRUE)
      }, error = function(e) {
        self$logger$error("Failed to parse response", 
                         error = e$message,
                         content_preview = substr(content, 1, 200))
        stop(glue("Failed to parse Ollama response: {e$message}"))
      })
      
      # Convert to data frame if needed
      if (!is.data.frame(parsed)) {
        parsed <- as.data.frame(parsed)
      }
      
      # Validate response count
      if (nrow(parsed) != length(narratives)) {
        self$logger$warning("Response count mismatch", 
                           expected = length(narratives),
                           received = nrow(parsed))
        
        # Pad or truncate as needed
        if (nrow(parsed) < length(narratives)) {
          # Pad with error results
          missing <- length(narratives) - nrow(parsed)
          padding <- data.frame(
            sequence = (nrow(parsed) + 1):length(narratives),
            rationale = rep("Response truncated", missing),
            key_facts_summary = rep("api_or_parse_error", missing),
            family_friend_mentioned = rep("api_or_parse_error", missing),
            intimate_partner_mentioned = rep("api_or_parse_error", missing),
            violence_mentioned = rep("api_or_parse_error", missing),
            substance_abuse_mentioned = rep("api_or_parse_error", missing),
            ipv_between_intimate_partners = rep("api_or_parse_error", missing),
            stringsAsFactors = FALSE
          )
          parsed <- rbind(parsed, padding)
        } else {
          # Truncate
          parsed <- parsed[1:length(narratives), ]
        }
      }
      
      return(parsed)
    },
    
    #' Save results to cache
    save_to_cache = function(narratives, result, batch_id) {
      if (is.null(self$cache_manager)) return()
      
      cache_key <- create_cache_key(paste(narratives, collapse = "|"))
      self$cache_manager$set(cache_key, result)
      
      self$logger$debug("Saved to cache", batch_id = batch_id)
    },
    
    #' Merge results with invalid placeholders
    merge_results = function(api_result, validation, batch_id) {
      # Create full result template
      full_result <- data.frame(
        sequence = seq_along(validation$is_invalid),
        rationale = "Narrative was NA or empty.",
        key_facts_summary = "skipped_na",
        family_friend_mentioned = "skipped_na",
        intimate_partner_mentioned = "skipped_na",
        violence_mentioned = "skipped_na",
        substance_abuse_mentioned = "skipped_na",
        ipv_between_intimate_partners = "skipped_na",
        stringsAsFactors = FALSE
      )
      
      # Place API results in correct positions
      if (!validation$all_invalid && nrow(api_result) > 0) {
        # Ensure we don't exceed bounds
        n_results <- min(nrow(api_result), length(validation$valid_indices))
        
        for (i in seq_len(n_results)) {
          idx <- validation$valid_indices[i]
          if (idx <= nrow(full_result)) {
            full_result[idx, names(api_result)] <- api_result[i, ]
          }
        }
      }
      
      return(full_result)
    },
    
    #' Check provider availability
    check_availability = function() {
      private$check_connection()
    }
  )
)