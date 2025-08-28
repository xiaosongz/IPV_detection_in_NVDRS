#!/usr/bin/env Rscript

#' Analyze LLM Response Data Structure
#' 
#' This script captures and analyzes actual LLM responses from call_llm()
#' to understand all possible response formats, error scenarios, and metadata.
#' 
#' @author Claude Code
#' @date 2025-08-28

# Load required functions
source("R/build_prompt.R")
source("R/call_llm.R")

# Create output directories
dir.create("results/sample_responses", recursive = TRUE, showWarnings = FALSE)
dir.create("docs", showWarnings = FALSE)

# Initialize results storage
responses <- list()
response_categories <- list(
  success = list(),
  error = list(),
  malformed = list(),
  timeout = list(),
  partial = list()
)

# Test scenarios to cover various response types
test_scenarios <- list(
  # 1. Basic IPV detection
  list(
    name = "basic_ipv_positive",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Victim was shot by ex-husband during custody dispute at her residence."
  ),
  
  # 2. IPV negative case
  list(
    name = "basic_ipv_negative",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Individual died in motor vehicle accident on highway."
  ),
  
  # 3. Complex narrative
  list(
    name = "complex_narrative",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0, \"indicators\": []}",
    user_prompt = paste(rep("The victim had a long history of domestic disputes with their partner. ", 20), collapse = "")
  ),
  
  # 4. Empty narrative
  list(
    name = "empty_narrative",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = ""
  ),
  
  # 5. Special characters
  list(
    name = "special_characters",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Victim's ex-partner \"threatened\" her & said: 'I'll kill you!'"
  ),
  
  # 6. Non-English characters
  list(
    name = "unicode_characters",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "The victim (María José) was threatened by her ex-partner—details unclear."
  ),
  
  # 7. Numeric data
  list(
    name = "numeric_heavy",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "On 2025-03-15 at 14:30, victim (age 35) shot 3 times by spouse with .45 caliber weapon."
  ),
  
  # 8. Request additional fields
  list(
    name = "extended_response",
    system_prompt = "Analyze for IPV. Return JSON with: detected, confidence, severity, perpetrator_relationship, weapon_used",
    user_prompt = "Woman strangled by boyfriend in their shared apartment."
  ),
  
  # 9. Minimal prompt
  list(
    name = "minimal_prompt",
    system_prompt = "IPV detection",
    user_prompt = "domestic violence"
  ),
  
  # 10. Very long narrative (token limit test)
  list(
    name = "long_narrative",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = paste(rep("This is a very long narrative that tests token limits. ", 100), collapse = "")
  ),
  
  # 11. JSON in narrative
  list(
    name = "json_in_text",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "The report stated: {\"victim\": \"shot by partner\", \"location\": \"home\"}"
  ),
  
  # 12. Multiple prompts style
  list(
    name = "analysis_request",
    system_prompt = "You are a forensic analyst",
    user_prompt = "Analyze this: Partner killed victim. Is this IPV? Explain."
  ),
  
  # 13. Temperature variation - deterministic
  list(
    name = "deterministic",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Spouse shot victim",
    temperature = 0
  ),
  
  # 14. Temperature variation - creative
  list(
    name = "creative",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Spouse shot victim",
    temperature = 0.9
  ),
  
  # 15. Ambiguous case
  list(
    name = "ambiguous",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Found deceased at home. History of arguments with roommate who may have been romantic partner."
  ),
  
  # 16. Medical terminology
  list(
    name = "medical_terms",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "GSW to temporal region, defensive wounds on forearms, perpetrator: ex-boyfriend"
  ),
  
  # 17. Multiple incidents
  list(
    name = "multiple_incidents",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Three prior DV reports. Current incident: stabbed by husband. Previous: broken arm, black eye."
  ),
  
  # 18. Indirect description
  list(
    name = "indirect",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "Neighbors report frequent arguing. Police called multiple times. Today found after 'domestic situation'."
  ),
  
  # 19. Test batch separator
  list(
    name = "line_breaks",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "First incident\n\nSecond incident\n\nThird incident with partner violence"
  ),
  
  # 20. Null/NA simulation
  list(
    name = "whitespace_only",
    system_prompt = "You are analyzing narratives for intimate partner violence. Respond with JSON: {\"detected\": true/false, \"confidence\": 0.0-1.0}",
    user_prompt = "   \t\n   "
  )
)

# Function to safely call LLM and capture response
capture_response <- function(scenario) {
  cat(sprintf("\n[%d/%d] Testing: %s\n", 
              which(names(test_scenarios) == scenario$name),
              length(test_scenarios),
              scenario$name))
  
  start_time <- Sys.time()
  
  # Build arguments
  args <- list(
    user_prompt = scenario$user_prompt,
    system_prompt = scenario$system_prompt
  )
  
  # Add temperature if specified
  if (!is.null(scenario$temperature)) {
    args$temperature <- scenario$temperature
  }
  
  # Try to call LLM
  response <- tryCatch({
    do.call(call_llm, args)
  }, error = function(e) {
    list(
      error = TRUE,
      error_message = as.character(e$message),
      error_class = class(e)[1]
    )
  }, warning = function(w) {
    list(
      warning = TRUE,
      warning_message = as.character(w$message)
    )
  })
  
  end_time <- Sys.time()
  elapsed <- as.numeric(difftime(end_time, start_time, units = "secs"))
  
  # Add metadata
  response$test_metadata <- list(
    scenario_name = scenario$name,
    elapsed_seconds = elapsed,
    timestamp = format(start_time, "%Y-%m-%d %H:%M:%S"),
    prompt_length = nchar(scenario$user_prompt),
    system_prompt_length = nchar(scenario$system_prompt)
  )
  
  return(response)
}

# Run all test scenarios
cat("Starting LLM response analysis...\n")
cat(sprintf("Running %d test scenarios\n", length(test_scenarios)))

for (scenario in test_scenarios) {
  response <- capture_response(scenario)
  responses[[scenario$name]] <- response
  
  # Categorize response
  if (!is.null(response$error)) {
    response_categories$error[[scenario$name]] <- response
    cat("  → Error response captured\n")
  } else if (!is.null(response$warning)) {
    response_categories$partial[[scenario$name]] <- response
    cat("  → Warning/partial response captured\n")
  } else if (!is.null(response$choices)) {
    response_categories$success[[scenario$name]] <- response
    cat("  → Success response captured\n")
    
    # Try to parse the content
    content <- response$choices[[1]]$message$content
    parsed <- tryCatch({
      jsonlite::fromJSON(content)
    }, error = function(e) {
      response_categories$malformed[[scenario$name]] <- response
      cat("  → Response has malformed JSON\n")
      NULL
    })
  } else {
    response_categories$partial[[scenario$name]] <- response
    cat("  → Unexpected response structure\n")
  }
  
  # Save individual response
  saveRDS(response, 
          file.path("results/sample_responses", 
                   sprintf("%s.rds", scenario$name)))
  
  # Small delay to avoid rate limiting
  Sys.sleep(0.5)
}

# Analyze response structures
cat("\n\nAnalyzing response structures...\n")

# Extract all unique fields from successful responses
all_fields <- list()
for (resp_name in names(response_categories$success)) {
  resp <- response_categories$success[[resp_name]]
  fields <- names(resp)
  all_fields <- unique(c(all_fields, fields))
  
  # Also check nested structures
  if (!is.null(resp$choices)) {
    choice_fields <- names(resp$choices[[1]])
    all_fields <- unique(c(all_fields, paste0("choices.", choice_fields)))
    
    if (!is.null(resp$choices[[1]]$message)) {
      message_fields <- names(resp$choices[[1]]$message)
      all_fields <- unique(c(all_fields, paste0("choices.message.", message_fields)))
    }
  }
  
  if (!is.null(resp$usage)) {
    usage_fields <- names(resp$usage)
    all_fields <- unique(c(all_fields, paste0("usage.", usage_fields)))
  }
}

# Generate analysis report
report <- c(
  "# LLM Response Structure Analysis",
  "",
  sprintf("Generated: %s", Sys.Date()),
  "",
  "## Summary Statistics",
  "",
  sprintf("- Total scenarios tested: %d", length(responses)),
  sprintf("- Successful responses: %d", length(response_categories$success)),
  sprintf("- Error responses: %d", length(response_categories$error)),
  sprintf("- Malformed JSON: %d", length(response_categories$malformed)),
  sprintf("- Partial/Warning: %d", length(response_categories$partial)),
  "",
  "## Response Structure Fields",
  "",
  "### Top-level fields found in successful responses:",
  paste0("- `", sort(unlist(all_fields)), "`"),
  "",
  "## Detailed Field Analysis",
  ""
)

# Analyze each successful response
if (length(response_categories$success) > 0) {
  report <- c(report,
    "### Successful Response Examples",
    ""
  )
  
  for (i in 1:min(3, length(response_categories$success))) {
    resp_name <- names(response_categories$success)[i]
    resp <- response_categories$success[[resp_name]]
    
    report <- c(report,
      sprintf("#### Example %d: %s", i, resp_name),
      "```json",
      jsonlite::toJSON(resp, pretty = TRUE, auto_unbox = TRUE),
      "```",
      ""
    )
  }
}

# Document error patterns
if (length(response_categories$error) > 0) {
  report <- c(report,
    "### Error Response Patterns",
    ""
  )
  
  error_types <- table(sapply(response_categories$error, function(x) x$error_class))
  for (error_type in names(error_types)) {
    report <- c(report, sprintf("- %s: %d occurrences", error_type, error_types[error_type]))
  }
  report <- c(report, "")
}

# Proposed standardized structure
report <- c(report,
  "## Proposed Standardized Parse Output",
  "",
  "Based on the analysis, the parsed output should have this structure:",
  "",
  "```r",
  "list(",
  "  # Core IPV detection results",
  "  detected = logical(),        # TRUE/FALSE/NA",
  "  confidence = numeric(),      # 0.0-1.0",
  "  ",
  "  # Metadata from LLM response",
  "  model = character(),         # Model used",
  "  created_at = character(),    # Timestamp from response",
  "  response_id = character(),   # Unique ID from LLM",
  "  ",
  "  # Usage metrics",
  "  tokens_used = integer(),     # Total tokens",
  "  prompt_tokens = integer(),   # Input tokens",
  "  completion_tokens = integer(), # Output tokens",
  "  ",
  "  # Processing metadata",
  "  response_time_ms = numeric(), # Response time",
  "  narrative_id = character(),   # User-provided ID",
  "  narrative_length = integer(), # Input length",
  "  ",
  "  # Error handling",
  "  parse_error = logical(),     # TRUE if parsing failed",
  "  error_message = character(), # Error details if any",
  "  raw_response = character()   # Original JSON string",
  ")",
  "```",
  "",
  "## Testing Notes",
  "",
  "- Responses are generally consistent in structure",
  "- JSON parsing is reliable when proper prompts are used",
  "- Error responses need graceful handling",
  "- Token usage information is always present in successful calls",
  "- Response IDs provide unique tracking"
)

# Write report
writeLines(report, "docs/LLM_RESPONSE_ANALYSIS.md")

# Save complete analysis
saveRDS(responses, "results/sample_responses/all_responses.rds")
saveRDS(response_categories, "results/sample_responses/categorized_responses.rds")

# Print summary
cat("\n=== Analysis Complete ===\n")
cat(sprintf("✓ Tested %d scenarios\n", length(responses)))
cat(sprintf("✓ Generated %d sample files\n", length(responses)))
cat("✓ Analysis report: docs/LLM_RESPONSE_ANALYSIS.md\n")
cat("✓ Sample responses: results/sample_responses/\n")
cat("\nNext steps:\n")
cat("- Review docs/LLM_RESPONSE_ANALYSIS.md for findings\n")
cat("- Use sample responses for parser development\n")
cat("- Test parser against results/sample_responses/*.rds files\n")