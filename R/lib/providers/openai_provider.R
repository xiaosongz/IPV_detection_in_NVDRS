# OpenAI Provider Implementation
# Handles communication with OpenAI API for IPV detection

library(R6)
library(httr2)
library(jsonlite)
library(glue)
library(ratelimitr)

# Source dependencies
source("R/lib/core.R")

#' OpenAI Provider Class
#' @export
OpenAIProvider <- R6::R6Class("OpenAIProvider",
  inherit = AIProvider,
  
  public = list(
    #' @field rate_limiter Rate limiting function
    rate_limiter = NULL,
    
    #' @field cache_manager Cache manager instance
    cache_manager = NULL,
    
    #' Initialize OpenAI Provider
    #' @param config Provider configuration
    #' @param logger Logger instance
    #' @param cache_manager Cache manager instance
    initialize = function(config, logger = NULL, cache_manager = NULL) {
      super$initialize("openai", config, logger)
      self$cache_manager <- cache_manager
      
      # Validate API key
      private$validate_api_key()
      
      # Set up rate limiting
      private$setup_rate_limiting()
      
      # Set up system prompt
      private$setup_system_prompt()
      
      self$logger$info("OpenAI provider initialized", 
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
      
      # Make API call with retry
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
    }
  ),
  
  private = list(
    #' @field api_key OpenAI API key
    api_key = NULL,
    
    #' @field system_prompt System prompt for the model
    system_prompt = NULL,
    
    #' Validate API key
    validate_api_key = function() {
      key_env <- self$config$key_env %||% "OPENAI_API_KEY"
      private$api_key <- Sys.getenv(key_env)
      
      if (!nzchar(private$api_key)) {
        stop(glue("OpenAI API key not found in environment variable: {key_env}"))
      }
      
      # Validate key format (basic check)
      if (!grepl("^sk-", private$api_key)) {
        warning("OpenAI API key does not start with 'sk-'. Please verify it's correct.")
      }
    },
    
    #' Set up rate limiting
    setup_rate_limiting = function() {
      rate_config <- self$config$rate_limit
      
      if (!is.null(rate_config)) {
        rpm <- rate_config$requests_per_minute %||% 90
        self$rate_limiter <- limit_rate(
          function(req) req_perform(req),
          rate(n = rpm, period = 60)
        )
        
        self$logger$debug("Rate limiting configured", 
                         requests_per_minute = rpm)
      } else {
        # Default rate limiting
        self$rate_limiter <- limit_rate(
          function(req) req_perform(req),
          rate(n = 90, period = 60)
        )
      }
    },
    
    #' Set up system prompt
    setup_system_prompt = function() {
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
      
      list(
        model = self$config$model %||% "gpt-4o-mini",
        temperature = self$config$temperature %||% 0,
        messages = list(
          list(role = "system", content = private$system_prompt),
          list(role = "user", content = user_prompt)
        )
      )
    },
    
    #' Make API call with error handling
    make_api_call = function(request_data, batch_id) {
      endpoint <- self$config$endpoint %||% "https://api.openai.com/v1/chat/completions"
      timeout <- self$config$timeout %||% 120
      
      self$logger$debug("Making API call", batch_id = batch_id, endpoint = endpoint)
      
      response <- tryCatch({
        req <- request(endpoint) |>
          req_headers(
            "Authorization" = paste("Bearer", private$api_key),
            "Content-Type" = "application/json"
          ) |>
          req_body_json(request_data) |>
          req_timeout(timeout)
        
        # Apply rate limiting
        if (!is.null(self$rate_limiter)) {
          self$rate_limiter(req)
        } else {
          req_perform(req)
        }
      }, error = function(e) {
        self$logger$error("API call failed", 
                         batch_id = batch_id,
                         error = e$message)
        stop(e)
      })
      
      # Check response status
      if (resp_status(response) != 200) {
        error_body <- resp_body_json(response)
        self$logger$error("API error response", 
                         batch_id = batch_id,
                         status = resp_status(response),
                         error = error_body$error$message)
        stop(glue("OpenAI API error: {error_body$error$message}"))
      }
      
      resp_body_json(response)
    },
    
    #' Parse API response
    parse_response = function(response, narratives) {
      # Extract content
      content <- response$choices[[1]]$message$content
      
      # Remove markdown formatting if present
      content <- gsub("```json\\s*|```\\s*$", "", content)
      
      # Parse JSON
      parsed <- tryCatch({
        fromJSON(content, flatten = TRUE)
      }, error = function(e) {
        self$logger$error("Failed to parse response", error = e$message)
        stop(glue("Failed to parse OpenAI response: {e$message}"))
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
      # Could implement a health check here
      return(!is.null(private$api_key) && nzchar(private$api_key))
    }
  )
)