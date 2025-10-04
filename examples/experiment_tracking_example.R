#!/usr/bin/env Rscript

#' Experiment Tracking Example
#'
#' Demonstrates how to use the experiment tracking system to compare different
#' prompt versions, models, and configurations. This is optional functionality
#' for R&D phase - the basic IPV detection works without experiment tracking.

# Load required functions
source("R/build_prompt.R")
source("R/call_llm.R")
source("R/repair_json.R")
source("R/parse_llm_result.R")
source("R/store_llm_result.R")
source("R/db_utils.R")
source("R/experiment_utils.R")
source("R/experiment_analysis.R")

cat("=== Experiment Tracking Example ===\n")

# Setup experiment database
db_path <- "experiment_example.db"
conn <- get_db_connection(db_path)
ensure_schema(conn)
ensure_experiment_schema(conn)

cat(sprintf("✓ Experiment database setup complete: %s\n", db_path))

# Example 1: Register Different Prompt Versions
cat("\n=== Example 1: Prompt Version Management ===\n")

# Baseline prompt (v1.0)
baseline_system <- "You are analyzing death narratives for intimate partner violence. 
Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}"

baseline_user <- "Analyze this death narrative for intimate partner violence: {text}"

prompt_v1 <- register_prompt(
  system_prompt = baseline_system,
  user_prompt_template = baseline_user,
  version_tag = "v1.0_baseline",
  notes = "Basic IPV detection prompt",
  conn = conn
)

cat(sprintf("✓ Registered baseline prompt: ID %d\n", prompt_v1))

# Enhanced prompt (v1.1) with more specific instructions
enhanced_system <- "You are a forensic analyst specializing in intimate partner violence detection.
Analyze death narratives for signs of IPV including:
- Current or former intimate relationships
- History of domestic violence
- Physical violence patterns
- Control or jealousy behaviors

Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0, \"reasoning\": \"brief explanation\"}"

enhanced_user <- "Analyze this death narrative for intimate partner violence indicators: {text}

Consider relationship context, violence patterns, and behavioral indicators."

prompt_v11 <- register_prompt(
  system_prompt = enhanced_system,
  user_prompt_template = enhanced_user,
  version_tag = "v1.1_enhanced",
  notes = "Enhanced prompt with specific IPV indicators and reasoning",
  conn = conn
)

cat(sprintf("✓ Registered enhanced prompt: ID %d\n", prompt_v11))

# Structured prompt (v2.0) with step-by-step analysis
structured_system <- "You are an expert in intimate partner violence detection. Follow these steps:

1. Identify relationship context (current/former intimate partner)
2. Look for violence patterns (physical, emotional, control)
3. Consider escalation indicators (threats, separation, custody)
4. Assess overall IPV likelihood

Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0, \"reasoning\": \"step-by-step analysis\"}"

structured_user <- "Death narrative: {text}

Step-by-step IPV analysis:
1. Relationship context: 
2. Violence patterns:
3. Escalation indicators:
4. IPV assessment:"

prompt_v20 <- register_prompt(
  system_prompt = structured_system,
  user_prompt_template = structured_user,
  version_tag = "v2.0_structured",
  notes = "Structured step-by-step analysis approach",
  conn = conn
)

cat(sprintf("✓ Registered structured prompt: ID %d\n", prompt_v20))

# Example 2: Create Test Dataset
cat("\n=== Example 2: Test Dataset Creation ===\n")

# Create test narratives with known ground truth
test_cases <- list(
  # Clear IPV cases
  list(
    id = "ipv_001", 
    text = "Woman shot by ex-boyfriend during custody exchange",
    ground_truth = TRUE,
    category = "clear_ipv"
  ),
  list(
    id = "ipv_002",
    text = "Victim strangled by current partner after argument about finances",
    ground_truth = TRUE,
    category = "clear_ipv"
  ),
  list(
    id = "ipv_003", 
    text = "Stabbed multiple times by ex-husband who had restraining order",
    ground_truth = TRUE,
    category = "clear_ipv"
  ),
  
  # Clear non-IPV cases  
  list(
    id = "non_ipv_001",
    text = "Single vehicle accident on rural highway during storm",
    ground_truth = FALSE,
    category = "clear_non_ipv"
  ),
  list(
    id = "non_ipv_002", 
    text = "Suicide by hanging, left detailed note about depression",
    ground_truth = FALSE,
    category = "clear_non_ipv"
  ),
  list(
    id = "non_ipv_003",
    text = "Accidental overdose of prescribed medication",
    ground_truth = FALSE,
    category = "clear_non_ipv"
  ),
  
  # Ambiguous cases
  list(
    id = "ambig_001",
    text = "Found dead at home, recent separation from spouse, no obvious trauma",
    ground_truth = NA,
    category = "ambiguous"
  ),
  list(
    id = "ambig_002", 
    text = "Gunshot wound, domestic disturbance call earlier that day",
    ground_truth = NA,
    category = "ambiguous"
  )
)

cat(sprintf("Created test dataset with %d cases:\n", length(test_cases)))
cat(sprintf("  Clear IPV: %d\n", sum(sapply(test_cases, function(x) x$category == "clear_ipv"))))
cat(sprintf("  Clear non-IPV: %d\n", sum(sapply(test_cases, function(x) x$category == "clear_non_ipv"))))
cat(sprintf("  Ambiguous: %d\n", sum(sapply(test_cases, function(x) x$category == "ambiguous"))))

# Example 3: Run Experiments
cat("\n=== Example 3: Running Experiments ===\n")

# Function to run experiment with a prompt version
run_experiment <- function(prompt_id, test_cases, experiment_name) {
  cat(sprintf("Running experiment '%s' with prompt ID %d...\n", experiment_name, prompt_id))
  
  # Get prompt details
  prompt_info <- get_prompt(prompt_id, conn = conn)
  if (is.null(prompt_info)) {
    cat(sprintf("❌ Failed to get prompt %d\n", prompt_id))
    return(NULL)
  }
  
  results <- list()
  for (i in seq_along(test_cases)) {
    test_case <- test_cases[[i]]
    cat(sprintf("  [%d/%d] %s... ", i, length(test_cases), test_case$id))
    
    # Build user prompt by substituting {text}
    user_prompt <- gsub("\\{text\\}", test_case$text, prompt_info$user_prompt_template)
    
    # Simulate LLM call (using mock data for consistent results)
    mock_response <- list(
      choices = list(list(message = list(content = sprintf(
        '{"detected": %s, "confidence": %.2f, "reasoning": "Mock analysis for %s"}',
        ifelse(test_case$ground_truth %||% (runif(1) > 0.5), "true", "false"),
        runif(1, 0.6, 0.95),
        test_case$category
      )))),
      usage = list(
        prompt_tokens = nchar(paste(prompt_info$system_prompt, user_prompt))/4,
        completion_tokens = 25,
        total_tokens = nchar(paste(prompt_info$system_prompt, user_prompt))/4 + 25
      ),
      model = "gpt-4o-mini"
    )
    
    # Parse result
    parsed <- parse_llm_result(
      mock_response, 
      narrative_id = test_case$id
    )
    
    # Add narrative text to parsed result for storage
    parsed$narrative_text <- test_case$text
    
    # Store result using standard storage function
    store_result <- store_llm_result(parsed, conn = conn, auto_close = FALSE)
    
    if (store_result$success) {
      cat(sprintf("✓ %s (%.2f)\n", parsed$detected, parsed$confidence))
    } else {
      cat(sprintf("❌ Storage failed\n"))
    }
    
    results[[test_case$id]] <- list(
      test_case = test_case,
      parsed = parsed,
      stored = store_result$success
    )
    
    # Small delay for demonstration
    Sys.sleep(0.1)
  }
  
  return(results)
}

# Run experiments with different prompt versions
exp1_results <- run_experiment(prompt_v1, test_cases, "baseline_experiment")
exp2_results <- run_experiment(prompt_v11, test_cases, "enhanced_experiment")  
exp3_results <- run_experiment(prompt_v20, test_cases, "structured_experiment")

# Example 4: Experiment Analysis
cat("\n=== Example 4: Experiment Analysis ===\n")

# Simple analysis using basic queries
cat("Experiment results summary:\n")

# Count results by model
model_summary <- DBI::dbGetQuery(conn, "
  SELECT model, 
         COUNT(*) as total_cases,
         SUM(CASE WHEN detected = 1 THEN 1 ELSE 0 END) as ipv_detected,
         AVG(confidence) as avg_confidence
  FROM llm_results 
  WHERE model IS NOT NULL
  GROUP BY model
  ORDER BY total_cases DESC
")

if (nrow(model_summary) > 0) {
  for (i in 1:nrow(model_summary)) {
    row <- model_summary[i, ]
    ipv_rate <- (row$ipv_detected / row$total_cases) * 100
    cat(sprintf("  %s: %d cases, %.1f%% IPV detected, %.2f avg confidence\n",
               row$model, row$total_cases, ipv_rate, row$avg_confidence))
  }
}

# Example 5: Custom Analysis
cat("\n=== Example 5: Custom Analysis ===\n")

# Simple custom analysis on main results table
confidence_analysis <- DBI::dbGetQuery(conn, "
  SELECT 
    CASE 
      WHEN confidence >= 0.9 THEN 'High (0.9+)'
      WHEN confidence >= 0.7 THEN 'Medium (0.7-0.9)'
      WHEN confidence >= 0.5 THEN 'Low (0.5-0.7)'
      ELSE 'Very Low (<0.5)'
    END as confidence_range,
    COUNT(*) as case_count,
    SUM(CASE WHEN detected = 1 THEN 1 ELSE 0 END) as ipv_detected
  FROM llm_results
  WHERE confidence IS NOT NULL
  GROUP BY 1
  ORDER BY MIN(confidence) DESC
")

if (nrow(confidence_analysis) > 0) {
  cat("Confidence distribution:\n")
  for (i in 1:nrow(confidence_analysis)) {
    row <- confidence_analysis[i, ]
    ipv_rate <- (row$ipv_detected / row$case_count) * 100
    cat(sprintf("  %s: %d cases (%.1f%% IPV)\n", 
               row$confidence_range, row$case_count, ipv_rate))
  }
}

# Example 6: Export Results for External Analysis
cat("\n=== Example 6: Export for External Analysis ===\n")

# Export comprehensive results from main table
export_query <- "
  SELECT 
    narrative_id,
    narrative_text,
    detected,
    confidence,
    model,
    response_time_ms,
    total_tokens,
    created_at
  FROM llm_results
  ORDER BY created_at DESC
"

export_data <- DBI::dbGetQuery(conn, export_query)

if (nrow(export_data) > 0) {
  # Save to CSV for external analysis
  export_file <- "experiment_results_export.csv"
  write.csv(export_data, export_file, row.names = FALSE)
  cat(sprintf("✓ Exported %d experiment results to %s\n", nrow(export_data), export_file))
  
  # Summary statistics
  cat("\nExport summary:\n")
  cat(sprintf("  Total experiments: %d\n", nrow(export_data)))
  cat(sprintf("  Unique narratives: %d\n", length(unique(export_data$narrative_id))))
  cat(sprintf("  Prompt versions: %d\n", length(unique(export_data$version_tag))))
  cat(sprintf("  Date range: %s to %s\n", 
             min(export_data$created_at), max(export_data$created_at)))
}

# Example 7: Model Comparison Experiment
cat("\n=== Example 7: Model Comparison ===\n")

# Compare different models with same prompt
models_to_test <- c("gpt-4o-mini", "gpt-4o", "claude-3-haiku-20240307")
model_results <- list()

for (model in models_to_test) {
  cat(sprintf("Testing model: %s\n", model))
  
  # Run subset of test cases with different model
  model_cases <- test_cases[1:3]  # Use first 3 cases for demo
  
  for (test_case in model_cases) {
    # Simulate different model responses
    confidence_factor <- switch(model,
      "gpt-4o-mini" = runif(1, 0.7, 0.85),
      "gpt-4o" = runif(1, 0.8, 0.95),  
      "claude-3-haiku-20240307" = runif(1, 0.75, 0.90)
    )
    
    mock_response <- list(
      choices = list(list(message = list(content = sprintf(
        '{"detected": %s, "confidence": %.2f, "reasoning": "Analysis by %s"}',
        ifelse(test_case$ground_truth %||% (runif(1) > 0.5), "true", "false"),
        confidence_factor,
        model
      )))),
      usage = list(prompt_tokens = 60, completion_tokens = 30, total_tokens = 90),
      model = model
    )
    
    parsed <- parse_llm_result(
      mock_response, 
      narrative_id = paste0(test_case$id, "_", gsub("[^a-zA-Z0-9]", "_", model))
    )
    
    # Add narrative text and store with model-specific data
    parsed$narrative_text <- test_case$text
    store_llm_result(parsed, conn = conn, auto_close = FALSE)
  }
  
  cat(sprintf("  ✓ Completed %s testing\n", model))
}

# Clean up
close_db_connection(conn)

# Clean up files (keep export for reference)
if (file.exists(db_path)) {
  file.remove(db_path)
  cat(sprintf("Cleaned up: %s\n", db_path))
}

cat("\n✓ Experiment tracking examples completed!\n")
cat("\nKey experiment workflows:\n")
cat("1. Register prompt versions with semantic versioning\n")
cat("2. Create curated test datasets with ground truth\n")
cat("3. Run systematic experiments across prompts/models\n")
cat("4. Analyze results with built-in performance metrics\n") 
cat("5. Export data for external analysis and visualization\n")
cat("6. Compare models objectively with same test cases\n")
cat("\nUse experiment tracking to improve prompt engineering and model selection.\n")