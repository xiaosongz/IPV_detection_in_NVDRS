# IPV Detection using mall package with LM Studio
# This script demonstrates row-by-row processing for maximum accuracy
# Using local LLM via LM Studio API

library(tidyverse)
library(mall)
library(httr2)
library(jsonlite)
library(readxl)
library(glue)

# ============================================================================
# Configuration for LM Studio
# ============================================================================

# LM Studio runs an OpenAI-compatible API, so we'll use custom setup
# Note: mall doesn't directly support LM Studio, but we can use ellmer with custom endpoint

library(ellmer)

# Create custom chat function for LM Studio
lm_studio_chat <- function() {
  # Create a custom provider for LM Studio
  chat_openai(
    base_url = "http://192.168.10.22:1234/v1",
    api_key = "not-needed",  # LM Studio doesn't require API key
    model = "qwen3-30b-2507"  # Using the exact model name you specified
  )
}

# ============================================================================
# Set up mall with LM Studio
# ============================================================================

# Initialize mall with LM Studio connection
chat_connection <- lm_studio_chat()
llm_use(chat_connection)

# ============================================================================
# Define IPV Detection Prompt
# ============================================================================

ipv_detection_prompt <- function() {
  paste(
    "You are a forensic data analyst reviewing death investigation narratives.",
    "Analyze the provided narrative for indicators of intimate partner violence (IPV).",
    "",
    "Return ONLY a valid JSON object with these exact fields:",
    "{",
    '  "rationale": "Brief explanation citing specific evidence from the text",',
    '  "key_facts_summary": "1-2 sentence objective summary of events",',
    '  "family_friend_mentioned": "yes/no/unclear",',
    '  "intimate_partner_mentioned": "yes/no/unclear",',
    '  "violence_mentioned": "yes/no/unclear",',
    '  "substance_abuse_mentioned": "yes/no/unclear",',
    '  "ipv_between_intimate_partners": "yes/no/unclear"',
    "}",
    "",
    "Rules:",
    "- Base all answers ONLY on explicit evidence in the text",
    "- Use 'unclear' when information is ambiguous or missing",
    "- Do not include markdown formatting or any text outside the JSON",
    "",
    "Narrative to analyze:"
  )
}

# ============================================================================
# Helper Functions
# ============================================================================

# Safe JSON parsing function
parse_llm_json <- function(response) {
  tryCatch({
    # Remove any markdown formatting if present
    clean_response <- gsub("```json\\s*|```\\s*", "", response)
    clean_response <- trimws(clean_response)
    
    # Parse JSON
    result <- fromJSON(clean_response, flatten = TRUE)
    
    # Ensure all expected fields exist
    expected_fields <- c(
      "rationale", "key_facts_summary", 
      "family_friend_mentioned", "intimate_partner_mentioned",
      "violence_mentioned", "substance_abuse_mentioned", 
      "ipv_between_intimate_partners"
    )
    
    for (field in expected_fields) {
      if (!field %in% names(result)) {
        result[[field]] <- "parse_error"
      }
    }
    
    return(result)
  }, error = function(e) {
    # Return error structure if parsing fails
    list(
      rationale = paste("JSON parse error:", e$message),
      key_facts_summary = "parse_error",
      family_friend_mentioned = "parse_error",
      intimate_partner_mentioned = "parse_error",
      violence_mentioned = "parse_error",
      substance_abuse_mentioned = "parse_error",
      ipv_between_intimate_partners = "parse_error"
    )
  })
}

# ============================================================================
# Process Single Narrative Function
# ============================================================================

analyze_narrative <- function(narrative_text, narrative_id = NA) {
  if (is.na(narrative_text) || narrative_text == "") {
    return(list(
      narrative_id = narrative_id,
      rationale = "Empty or NA narrative",
      key_facts_summary = "skipped_empty",
      family_friend_mentioned = "skipped_empty",
      intimate_partner_mentioned = "skipped_empty",
      violence_mentioned = "skipped_empty",
      substance_abuse_mentioned = "skipped_empty",
      ipv_between_intimate_partners = "skipped_empty"
    ))
  }
  
  # Create a temporary dataframe for mall
  temp_df <- tibble(
    narrative_id = narrative_id,
    text = narrative_text
  )
  
  # Process with mall
  result <- temp_df |>
    llm_custom(
      col = text,
      prompt = ipv_detection_prompt()
    )
  
  # Parse the LLM response
  parsed <- parse_llm_json(result$.llm[1])
  
  # Combine with narrative ID
  parsed$narrative_id <- narrative_id
  
  return(parsed)
}

# ============================================================================
# Main Processing Function
# ============================================================================

process_narratives_with_mall <- function(df, narrative_column = "narrative", id_column = NULL) {
  
  # Add ID column if not provided
  if (is.null(id_column)) {
    df <- df |> mutate(temp_id = row_number())
    id_column <- "temp_id"
  }
  
  # Initialize results list
  results <- list()
  total <- nrow(df)
  
  cat("Starting IPV detection analysis using mall + LM Studio\n")
  cat(glue("Processing {total} narratives one by one for maximum accuracy\n\n"))
  
  # Process each narrative individually
  for (i in 1:total) {
    cat(glue("\rProcessing narrative {i}/{total} ({round(i/total*100, 1)}%)"))
    
    narrative_text <- df[[narrative_column]][i]
    narrative_id <- df[[id_column]][i]
    
    # Analyze single narrative
    result <- analyze_narrative(narrative_text, narrative_id)
    
    # Store result
    results[[i]] <- result
    
    # Optional: Add small delay to prevent overwhelming the server
    Sys.sleep(0.5)
  }
  
  cat("\n\nProcessing complete!\n")
  
  # Combine all results into a dataframe
  results_df <- bind_rows(results)
  
  # Join back with original data
  final_df <- df |>
    left_join(results_df, by = setNames(id_column, "narrative_id"))
  
  return(final_df)
}

# ============================================================================
# Example Usage with Sample Data
# ============================================================================

# Create sample data for testing
sample_data <- tibble(
  case_id = c("2024-001", "2024-002", "2024-003"),
  narrative = c(
    "The victim was found deceased in her home. Her husband reported finding her after returning from work. There were signs of struggle and multiple injuries. The couple had a history of domestic disputes according to neighbors.",
    
    "Single vehicle accident on highway. Driver lost control due to icy conditions and struck a tree. No other vehicles involved. Toxicology pending.",
    
    "The decedent was discovered by her ex-boyfriend who had come to check on her. Friends reported she had recently ended the relationship due to controlling behavior. Empty medication bottles were found at the scene."
  )
)

# Test connection first
cat("Testing LM Studio connection...\n")
test_narrative <- tibble(text = "Test narrative")
test_result <- tryCatch({
  test_narrative |> 
    llm_custom(text, "Reply with 'Connection successful'")
}, error = function(e) {
  cat("Error connecting to LM Studio:", e$message, "\n")
  cat("Please ensure:\n")
  cat("1. LM Studio is running at http://192.168.10.22:1234\n")
  cat("2. The qwen3-30b-2507 model is loaded\n")
  cat("3. The server is started in LM Studio\n")
  NULL
})

if (!is.null(test_result)) {
  cat("Connection successful!\n\n")
  
  # Process the sample data
  results <- process_narratives_with_mall(
    sample_data, 
    narrative_column = "narrative",
    id_column = "case_id"
  )
  
  # Display results
  cat("\n=== RESULTS ===\n")
  results |>
    select(case_id, ipv_between_intimate_partners, intimate_partner_mentioned, 
           violence_mentioned, key_facts_summary) |>
    print()
  
  # Save results
  output_file <- glue("output/ipv_mall_demo_{format(Sys.time(), '%Y%m%d_%H%M%S')}.csv")
  write_csv(results, output_file)
  cat(glue("\nResults saved to: {output_file}\n"))
}

# ============================================================================
# Process Actual Data (if available)
# ============================================================================

# Uncomment to process your actual Excel file:
# actual_data <- read_excel("data-raw/your_file.xlsx")
# 
# # Process CME narratives
# cme_results <- process_narratives_with_mall(
#   actual_data,
#   narrative_column = "CME_narrative",  # Adjust column name
#   id_column = "case_id"  # Adjust ID column name
# )
# 
# # Process LE narratives
# le_results <- process_narratives_with_mall(
#   actual_data,
#   narrative_column = "LE_narrative",  # Adjust column name
#   id_column = "case_id"
# )
# 
# # Save results
# write_csv(cme_results, glue("output/cme_ipv_analysis_{Sys.Date()}.csv"))
# write_csv(le_results, glue("output/le_ipv_analysis_{Sys.Date()}.csv"))