# Simplified IPV Detection with mall + LM Studio
# Direct connection approach without ellmer dependency

library(tidyverse)
library(mall)
library(httr2)
library(jsonlite)
library(readxl)
library(glue)

# ============================================================================
# LM Studio Connection Setup (Alternative Approach)
# ============================================================================

# Since mall expects Ollama-style API, we'll create a wrapper
# LM Studio uses OpenAI-compatible endpoints at port 1234

# First, try using mall with Ollama backend pointing to LM Studio
# LM Studio can emulate Ollama API format

# Set mall to use custom Ollama endpoint
Sys.setenv(OLLAMA_HOST = "http://192.168.10.22:1234")

# Configure mall to use the model
# Using the exact model name: qwen3-30b-2507
llm_use(
  backend = "ollama",
  model = "qwen3-30b-2507",
  seed = 100,
  temperature = 0.1,
  .silent = TRUE
)

# ============================================================================
# IPV Detection Setup
# ============================================================================

# Comprehensive IPV detection prompt
create_ipv_prompt <- function() {
  paste(
    "You are analyzing a death investigation narrative for intimate partner violence indicators.",
    "Provide a structured analysis in JSON format.",
    "",
    "Return ONLY a valid JSON object with these fields:",
    "{",
    '  "ipv_detected": "yes/no/unclear",',
    '  "confidence": "high/medium/low",',
    '  "intimate_partner": "yes/no/unclear",',
    '  "violence_indicators": "yes/no/unclear",',
    '  "substance_abuse": "yes/no/unclear",',
    '  "key_evidence": "Brief quote or description from text",',
    '  "risk_factors": "List any IPV risk factors found"',
    "}",
    "",
    "Base all answers on explicit text evidence only.",
    "Return ONLY the JSON, no other text.",
    "",
    "Narrative:"
  )
}

# ============================================================================
# Processing Functions
# ============================================================================

# Process a single narrative and return structured results
process_single_narrative <- function(narrative_text, case_id = NA) {
  
  # Skip empty narratives
  if (is.na(narrative_text) || nchar(trimws(narrative_text)) == 0) {
    return(tibble(
      case_id = case_id,
      ipv_detected = "skipped",
      confidence = "NA",
      intimate_partner = "skipped",
      violence_indicators = "skipped",
      substance_abuse = "skipped",
      key_evidence = "Empty narrative",
      risk_factors = "None",
      processing_status = "skipped_empty"
    ))
  }
  
  # Create temporary dataframe for mall
  temp_df <- tibble(narrative = narrative_text)
  
  # Process with mall's llm_custom function
  result <- tryCatch({
    temp_df |>
      llm_custom(
        col = narrative,
        prompt = create_ipv_prompt()
      )
  }, error = function(e) {
    tibble(.llm = paste("Error:", e$message))
  })
  
  # Parse the JSON response
  parsed <- tryCatch({
    # Clean the response
    response <- result$.llm[1]
    response <- gsub("```json\\s*|```\\s*", "", response)
    response <- trimws(response)
    
    # Parse JSON
    json_data <- fromJSON(response, flatten = TRUE)
    
    # Create structured output
    tibble(
      case_id = case_id,
      ipv_detected = json_data$ipv_detected %||% "parse_error",
      confidence = json_data$confidence %||% "parse_error",
      intimate_partner = json_data$intimate_partner %||% "parse_error",
      violence_indicators = json_data$violence_indicators %||% "parse_error",
      substance_abuse = json_data$substance_abuse %||% "parse_error",
      key_evidence = json_data$key_evidence %||% "parse_error",
      risk_factors = json_data$risk_factors %||% "parse_error",
      processing_status = "success"
    )
  }, error = function(e) {
    # Return error record if parsing fails
    tibble(
      case_id = case_id,
      ipv_detected = "error",
      confidence = "error",
      intimate_partner = "error",
      violence_indicators = "error",
      substance_abuse = "error",
      key_evidence = paste("Parse error:", e$message),
      risk_factors = "error",
      processing_status = "parse_error"
    )
  })
  
  return(parsed)
}

# ============================================================================
# Batch Processing with Progress
# ============================================================================

analyze_narratives <- function(data, text_column, id_column = NULL) {
  
  # Create ID column if not provided
  if (is.null(id_column)) {
    data <- data |> mutate(.temp_id = row_number())
    id_column <- ".temp_id"
  }
  
  n_total <- nrow(data)
  cat(glue("Processing {n_total} narratives individually for maximum accuracy\n"))
  cat("Using LM Studio at http://192.168.10.22:1234\n\n")
  
  # Process each narrative
  results <- map2_dfr(
    data[[text_column]], 
    data[[id_column]],
    function(text, id) {
      cat(glue("\rProcessing case: {id}    "))
      result <- process_single_narrative(text, id)
      Sys.sleep(0.2)  # Small delay to not overwhelm server
      return(result)
    }
  )
  
  cat("\n\nProcessing complete!\n")
  
  # Join results back to original data
  final_data <- data |>
    left_join(results, by = setNames("case_id", id_column))
  
  # Summary statistics
  cat("\n=== Summary ===\n")
  results |>
    count(ipv_detected) |>
    print()
  
  return(final_data)
}

# ============================================================================
# Demo with Sample Data
# ============================================================================

# Create realistic sample narratives
demo_data <- tibble(
  case_number = c("2024-IPV-001", "2024-ACC-002", "2024-IPV-003", "2024-SUI-004"),
  narrative_text = c(
    # Clear IPV case
    "The victim, a 34-year-old woman, was found deceased in her bedroom by police conducting a welfare check. Her estranged husband was arrested at the scene. Neighbors reported hearing arguing and sounds of a struggle earlier that evening. The victim had an active restraining order against her husband, who had a history of domestic violence arrests. Multiple defensive wounds were observed.",
    
    # Non-IPV case (accident)
    "A 45-year-old male driver lost control of his vehicle on Interstate 95 during heavy rain conditions. The vehicle hydroplaned and struck the median barrier. Speed was estimated at 75 mph in a 65 mph zone. No other vehicles were involved. The driver was not wearing a seatbelt at the time of impact.",
    
    # Possible IPV case
    "The decedent, a 28-year-old woman, was discovered unresponsive by her boyfriend who called 911. He stated they had been drinking together the previous night. Empty prescription bottles were found near the body. Friends later told investigators that the couple had a tumultuous relationship and she had recently tried to leave him. No suicide note was found.",
    
    # Non-IPV case (suicide)
    "A 52-year-old man was found deceased in his garage with the car engine running. A suicide note was left for his family expressing remorse over financial troubles and recent job loss. His wife was out of town visiting relatives. No signs of struggle or foul play were observed."
  )
)

# Run the analysis
cat("=== IPV Detection Demo ===\n\n")
analyzed_data <- analyze_narratives(
  demo_data,
  text_column = "narrative_text",
  id_column = "case_number"
)

# Display detailed results
cat("\n=== Detailed Results ===\n")
analyzed_data |>
  select(case_number, ipv_detected, confidence, key_evidence) |>
  print(width = Inf)

# Save results
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
output_path <- glue("output/ipv_analysis_mall_{timestamp}.csv")
write_csv(analyzed_data, output_path)
cat(glue("\nResults saved to: {output_path}\n"))

# ============================================================================
# Function to Process Your Actual Data
# ============================================================================

process_nvdrs_data <- function(file_path, narrative_col = "narrative") {
  
  cat("Loading NVDRS data...\n")
  data <- read_excel(file_path)
  
  cat(glue("Found {nrow(data)} records\n\n"))
  
  # Process the narratives
  results <- analyze_narratives(
    data,
    text_column = narrative_col,
    id_column = "row_number"  # Adjust based on your actual ID column
  )
  
  # Generate output filename
  output_file <- glue("output/nvdrs_ipv_analysis_{Sys.Date()}.csv")
  write_csv(results, output_file)
  
  cat(glue("\nAnalysis complete. Results saved to: {output_file}\n"))
  
  # Print summary
  cat("\n=== IPV Detection Summary ===\n")
  results |>
    count(ipv_detected, confidence) |>
    arrange(ipv_detected, confidence) |>
    print()
  
  return(results)
}

# ============================================================================
# Instructions for Use
# ============================================================================

cat("\n")
cat("=====================================\n")
cat("Setup Instructions:\n")
cat("=====================================\n")
cat("1. Ensure LM Studio is running at http://192.168.10.22:1234\n")
cat("2. Load the qwen3-30b-2507 model in LM Studio\n")
cat("3. Start the server in LM Studio\n")
cat("\n")
cat("To process your actual data:\n")
cat("  results <- process_nvdrs_data('path/to/your/data.xlsx', 'narrative_column_name')\n")
cat("\n")