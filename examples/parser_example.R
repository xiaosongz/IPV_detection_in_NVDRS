#!/usr/bin/env Rscript

#' Example: Using the LLM Result Parser
#'
#' This example demonstrates how to use parse_llm_result() function
#' to extract structured data from call_llm() responses.

# Load required functions
source("R/build_prompt.R")
source("R/call_llm.R")
source("R/parse_llm_result.R")

# Example 1: Basic usage with IPV detection
cat("=== Example 1: Basic IPV Detection ===\n")

# Define prompts
system_prompt <- "You are analyzing narratives for intimate partner violence. 
Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}"
user_prompt <- "Victim was shot by ex-husband during custody dispute."

# Call LLM
cat("Calling LLM...\n")
response <- call_llm(user_prompt, system_prompt)

# Parse the response
cat("Parsing response...\n")
result <- parse_llm_result(response, narrative_id = "example_001")

# Display results
cat(sprintf("  Detected: %s\n", result$detected))
cat(sprintf("  Confidence: %.2f\n", result$confidence))
cat(sprintf("  Tokens used: %d\n", result$tokens_used))
cat(sprintf("  Model: %s\n", result$model))
cat(sprintf("  Parse error: %s\n", result$parse_error))

# Example 2: Batch processing with error handling
cat("\n=== Example 2: Batch Processing ===\n")

narratives <- list(
  list(id = "case_001", text = "Motor vehicle accident on highway"),
  list(id = "case_002", text = "Woman strangled by boyfriend"),
  list(id = "case_003", text = "Suicide by hanging in garage"),
  list(id = "case_004", text = "Shot by ex-partner at workplace")
)

# Process each narrative
results <- list()
for (narrative in narratives) {
  cat(sprintf("\nProcessing %s...\n", narrative$id))
  
  # Call LLM
  response <- tryCatch({
    call_llm(narrative$text, system_prompt)
  }, error = function(e) {
    list(error = TRUE, error_message = e$message)
  })
  
  # Parse response
  parsed <- parse_llm_result(response, narrative_id = narrative$id)
  
  # Store result
  results[[narrative$id]] <- parsed
  
  # Display summary
  if (parsed$parse_error) {
    cat(sprintf("  ❌ Error: %s\n", parsed$error_message))
  } else {
    cat(sprintf("  ✓ IPV: %s (confidence: %.2f)\n", 
                parsed$detected, parsed$confidence))
  }
  
  # Small delay to avoid rate limiting
  Sys.sleep(0.5)
}

# Example 3: Aggregating results
cat("\n=== Example 3: Results Summary ===\n")

# Count detections
total <- length(results)
detected <- sum(sapply(results, function(r) isTRUE(r$detected)))
errors <- sum(sapply(results, function(r) r$parse_error))
avg_confidence <- mean(sapply(results, function(r) {
  if (!is.na(r$confidence)) r$confidence else NA
}), na.rm = TRUE)

cat(sprintf("Total processed: %d\n", total))
cat(sprintf("IPV detected: %d (%.1f%%)\n", detected, detected/total*100))
cat(sprintf("Parse errors: %d\n", errors))
cat(sprintf("Average confidence: %.2f\n", avg_confidence))

# Example 4: Saving results for database storage
cat("\n=== Example 4: Preparing for Database ===\n")

# Convert to data frame for database insertion
df_results <- do.call(rbind, lapply(results, function(r) {
  data.frame(
    narrative_id = r$narrative_id %||% NA_character_,
    detected = r$detected %||% NA,
    confidence = r$confidence %||% NA_real_,
    model = r$model %||% NA_character_,
    tokens_used = r$tokens_used %||% NA_integer_,
    parse_error = r$parse_error %||% FALSE,
    created_at = Sys.time(),
    stringsAsFactors = FALSE
  )
}))

# Display structure ready for database
cat("Data frame ready for database:\n")
print(df_results[, c("narrative_id", "detected", "confidence", "parse_error")])

cat("\n✓ Examples complete. Ready for database storage implementation (Task #4).\n")