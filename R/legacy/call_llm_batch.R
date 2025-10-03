#' Batch LLM API calls for efficient processing
#'
#' Optimized function for processing multiple narratives with the same system prompt.
#' Reduces token usage and improves throughput by batching requests.
#'
#' @param user_prompts Character vector of user prompts/narratives to process
#' @param system_prompt Character string. System-level instructions (shared across all prompts)
#' @param api_url Character string. The API endpoint URL
#' @param model Character string. The model identifier to use
#' @param temperature Numeric. Controls randomness (0-1)
#' @param batch_size Integer. Number of narratives to process in each batch (default 5)
#' @param max_retries Integer. Maximum retry attempts for failed requests (default 3)
#' @param progress Logical. Show progress bar (default TRUE)
#'
#' @return A list of responses, one for each input prompt
#'
#' @export
#'
#' @examples
#' \dontrun{
#' narratives <- c("First narrative...", "Second narrative...", "Third narrative...")
#' sys_prompt <- "You are an IPV detection expert. Analyze each narrative."
#' 
#' # Process in batches of 5
#' results <- call_llm_batch(narratives, sys_prompt, batch_size = 5)
#' 
#' # Extract detected flags
#' detected <- sapply(results, function(r) r$detected)
#' }
#'
call_llm_batch <- function(user_prompts,
                          system_prompt,
                          api_url = Sys.getenv("LLM_API_URL", "http://192.168.10.22:1234/v1/chat/completions"),
                          model = Sys.getenv("LLM_MODEL", "openai/gpt-oss-120b"),
                          temperature = 0.1,
                          batch_size = 5,
                          max_retries = 3,
                          progress = TRUE) {
  
  # Validate inputs
  if (!is.character(user_prompts) || length(user_prompts) == 0) {
    stop("'user_prompts' must be a non-empty character vector", call. = FALSE)
  }
  if (!is.character(system_prompt) || length(system_prompt) != 1) {
    stop("'system_prompt' must be a single character string", call. = FALSE)
  }
  if (batch_size < 1 || batch_size > 20) {
    stop("'batch_size' must be between 1 and 20", call. = FALSE)
  }
  
  # Initialize progress tracking
  n_prompts <- length(user_prompts)
  if (progress) {
    pb <- txtProgressBar(min = 0, max = n_prompts, style = 3)
  }
  
  # Split into batches
  batch_indices <- split(seq_along(user_prompts), 
                        ceiling(seq_along(user_prompts) / batch_size))
  
  all_results <- list()
  processed_count <- 0
  
  for (batch_idx in seq_along(batch_indices)) {
    indices <- batch_indices[[batch_idx]]
    batch_prompts <- user_prompts[indices]
    
    # Create batched prompt
    if (length(batch_prompts) == 1) {
      # Single item - use regular format
      combined_prompt <- batch_prompts[1]
    } else {
      # Multiple items - create structured batch prompt
      combined_prompt <- paste0(
        "Process these ", length(batch_prompts), " narratives independently.\n",
        "Return a JSON array with one result object for each narrative.\n\n",
        paste(
          sprintf("=== NARRATIVE %d ===\n%s", seq_along(batch_prompts), batch_prompts),
          collapse = "\n\n"
        ),
        "\n\n",
        "IMPORTANT: Return ONLY a JSON array like: ",
        '[{"detected": true/false, "confidence": 0.0-1.0}, ...]'
      )
    }
    
    # Make API call with retries
    attempt <- 1
    success <- FALSE
    
    while (attempt <= max_retries && !success) {
      tryCatch({
        # Build messages
        messages <- build_prompt(system_prompt, combined_prompt)
        
        # Build request body
        request_body <- list(
          model = model,
          messages = messages,
          temperature = temperature
        )
        
        # Make API call
        response <- httr2::request(api_url) |>
          httr2::req_body_json(request_body) |>
          httr2::req_timeout(60 * length(batch_prompts)) |>  # Scale timeout with batch size
          httr2::req_perform() |>
          httr2::resp_body_json()
        
        # Parse batch response
        content <- response$choices[[1]]$message$content
        
        if (length(batch_prompts) == 1) {
          # Single response - parse directly
          batch_results <- list(jsonlite::fromJSON(content, simplifyVector = FALSE))
        } else {
          # Multiple responses - parse array
          batch_results <- jsonlite::fromJSON(content, simplifyVector = FALSE)
          
          # Validate we got the right number of results
          if (length(batch_results) != length(batch_prompts)) {
            warning(sprintf("Batch %d: Expected %d results, got %d", 
                          batch_idx, length(batch_prompts), length(batch_results)))
            # Pad with error results if needed
            while (length(batch_results) < length(batch_prompts)) {
              batch_results <- append(batch_results, list(list(
                detected = NA,
                confidence = NA,
                error = "Missing result from batch"
              )))
            }
          }
        }
        
        # Store results
        for (i in seq_along(batch_results)) {
          result_idx <- indices[i]
          all_results[[result_idx]] <- batch_results[[i]]
          all_results[[result_idx]]$tokens_used <- response$usage$total_tokens / length(batch_prompts)
          all_results[[result_idx]]$batch_id <- batch_idx
        }
        
        success <- TRUE
        
      }, error = function(e) {
        if (attempt == max_retries) {
          # Final attempt failed - store error results
          for (idx in indices) {
            all_results[[idx]] <- list(
              detected = NA,
              confidence = NA, 
              error = paste("API error after", max_retries, "attempts:", e$message),
              batch_id = batch_idx
            )
          }
          warning(sprintf("Batch %d failed after %d attempts: %s", 
                        batch_idx, max_retries, e$message))
        } else {
          # Retry with exponential backoff
          Sys.sleep(2^(attempt - 1))
        }
        attempt <<- attempt + 1
      })
    }
    
    # Update progress
    processed_count <- processed_count + length(batch_prompts)
    if (progress) {
      setTxtProgressBar(pb, processed_count)
    }
  }
  
  if (progress) {
    close(pb)
    cat("\n")
  }
  
  return(all_results)
}


#' Parallel batch processing with multiple workers
#'
#' Process narratives in parallel using multiple R sessions for maximum throughput.
#'
#' @param user_prompts Character vector of prompts to process
#' @param system_prompt Character string. System instructions
#' @param n_workers Integer. Number of parallel workers (default 4)
#' @param batch_size Integer. Narratives per batch (default 5)
#' @param ... Additional arguments passed to call_llm_batch
#'
#' @return A list of responses
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Process 1000 narratives with 4 parallel workers
#' results <- call_llm_parallel(
#'   narratives_vector,
#'   system_prompt,
#'   n_workers = 4,
#'   batch_size = 10
#' )
#' }
#'
call_llm_parallel <- function(user_prompts,
                             system_prompt,
                             n_workers = 4,
                             batch_size = 5,
                             ...) {
  
  # Check if future is available
  if (!requireNamespace("future", quietly = TRUE)) {
    message("Package 'future' not available. Falling back to sequential processing.")
    return(call_llm_batch(user_prompts, system_prompt, batch_size = batch_size, ...))
  }
  
  if (!requireNamespace("future.apply", quietly = TRUE)) {
    message("Package 'future.apply' not available. Falling back to sequential processing.")
    return(call_llm_batch(user_prompts, system_prompt, batch_size = batch_size, ...))
  }
  
  # Set up parallel backend
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  future::plan(future::multisession, workers = n_workers)
  
  # Split prompts into chunks for each worker
  n_prompts <- length(user_prompts)
  chunk_size <- ceiling(n_prompts / n_workers)
  chunks <- split(user_prompts, ceiling(seq_along(user_prompts) / chunk_size))
  
  cat(sprintf("Processing %d narratives with %d workers (chunks of ~%d)\n", 
             n_prompts, min(n_workers, length(chunks)), chunk_size))
  
  # Process chunks in parallel
  chunk_results <- future.apply::future_lapply(chunks, function(chunk) {
    call_llm_batch(
      chunk, 
      system_prompt,
      batch_size = batch_size,
      progress = FALSE,  # Disable progress in workers
      ...
    )
  })
  
  # Flatten results
  all_results <- unlist(chunk_results, recursive = FALSE)
  
  return(all_results)
}


#' Calculate token savings from batching
#'
#' Utility function to estimate token and cost savings from batch processing.
#'
#' @param n_narratives Number of narratives to process
#' @param system_prompt_tokens Estimated tokens in system prompt
#' @param avg_narrative_tokens Average tokens per narrative
#' @param batch_size Batch size for processing
#' @param cost_per_million_tokens Cost per million tokens (default $1)
#'
#' @return A list with efficiency metrics
#'
#' @export
#'
calculate_batch_savings <- function(n_narratives,
                                   system_prompt_tokens = 400,
                                   avg_narrative_tokens = 250,
                                   batch_size = 5,
                                   cost_per_million_tokens = 1) {
  
  # Sequential processing
  sequential_tokens <- n_narratives * (system_prompt_tokens + avg_narrative_tokens)
  sequential_cost <- (sequential_tokens / 1000000) * cost_per_million_tokens
  
  # Batch processing
  n_batches <- ceiling(n_narratives / batch_size)
  batch_tokens <- n_batches * system_prompt_tokens + n_narratives * avg_narrative_tokens
  batch_cost <- (batch_tokens / 1000000) * cost_per_million_tokens
  
  # Calculate savings
  tokens_saved <- sequential_tokens - batch_tokens
  cost_saved <- sequential_cost - batch_cost
  reduction_pct <- (tokens_saved / sequential_tokens) * 100
  
  list(
    sequential_tokens = sequential_tokens,
    batch_tokens = batch_tokens,
    tokens_saved = tokens_saved,
    reduction_percent = round(reduction_pct, 1),
    sequential_cost = round(sequential_cost, 4),
    batch_cost = round(batch_cost, 4),
    cost_saved = round(cost_saved, 4),
    efficiency_multiplier = round(sequential_tokens / batch_tokens, 2)
  )
}