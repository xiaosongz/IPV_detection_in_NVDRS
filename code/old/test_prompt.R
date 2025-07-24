library(httr2)
library(jsonlite)
library(dotenv)
library(dplyr)
library(readxl)

# Load environment variables
load_dot_env()
key <- Sys.getenv("OPENAI_API_KEY")
stopifnot(nzchar(key))

# Read the Excel file
narratives <- read_excel("data/2023_2024_NVDRS_Narratives.xlsx") |>
  select(incident_id, narrative) |>
  mutate(row_id = row_number())

# System prompt
system_prompt <- paste(
  "You are a forensic reviewer trained to classify fatality review narratives.",
  "IMPORTANT: Return a SINGLE JSON object (not an array) with these 5 fields:",
  "{",
  "  \"family_friend_mentioned\": \"yes\" or \"no\"",
  "  \"intimate_partner_mentioned\": \"yes\" or \"no\"",
  "  \"violence_mentioned\": \"yes\" or \"no\"",
  "  \"substance_abuse_mentioned\": \"yes\" or \"no\"",
  "  \"ipv_between_intimate_partners\": \"yes\" or \"no\"",
  "}",
  "Respond based on *any* relevant detail you can infer from the narrative. Do NOT default to 'unclear'.",
  "'unclear' should ONLY be used when no relevant clue is present, or when the subject of a phrase cannot be reasonably determined.",
  "CRITICAL: Return ONLY a single JSON object—NOT an array, NOT wrapped in anything, just the object itself.",
  "Example of correct response:",
  "{",
  "  \"family_friend_mentioned\": \"yes\",",
  "  \"intimate_partner_mentioned\": \"yes\",",
  "  \"violence_mentioned\": \"yes\",",
  "  \"substance_abuse_mentioned\": \"no\",",
  "  \"ipv_between_intimate_partners\": \"yes\"",
  "}"
)

# Function to test a single narrative
test_narrative <- function(narrative, model = "gpt-4o-mini") {
  # Create user prompt
  user_prompt <- paste(
    "Analyze this narrative and return a SINGLE JSON object (not an array):",
    narrative,
    "Remember: Return ONLY a single JSON object, not an array.",
    sep = "\n"
  )
  
  # Print prompts
  cat("\nSystem Prompt:\n")
  cat(system_prompt)
  cat("\n\nUser Prompt:\n")
  cat(user_prompt)
  cat("\n\n")
  
  # Make API request
  resp <- request("https://api.openai.com/v1/chat/completions") |>
    req_headers(
      "Authorization" = paste("Bearer", key),
      "Content-Type"  = "application/json"
    ) |>
    req_body_json(list(
      model       = model,
      temperature = 0,
      messages    = list(
        list(role = "system", content = system_prompt),
        list(role = "user", content = user_prompt)
      )
    )) |>
    req_perform() |>
    resp_body_json()
  
  # Get raw response
  response_text <- resp$choices[[1]]$message$content
  cat("\nRaw API Response:\n")
  cat(response_text)
  cat("\n\n")
  
  # Try to parse and validate
  tryCatch({
    # Remove any markdown code block markers
    response_text <- gsub("```json\\s*|```\\s*$", "", response_text)
    
    # Parse JSON
    result <- fromJSON(response_text)
    
    # Validate structure
    valid_keys <- c("family_friend_mentioned", "intimate_partner_mentioned", 
                   "violence_mentioned", "substance_abuse_mentioned", 
                   "ipv_between_intimate_partners")
    valid_values <- c("yes", "no", "unclear")
    
    # Check for missing keys
    missing_keys <- setdiff(valid_keys, names(result))
    if (length(missing_keys) > 0) {
      cat("Warning: Missing keys:", paste(missing_keys, collapse = ", "), "\n")
      for (key in missing_keys) {
        result[[key]] <- "unclear"
      }
    }
    
    # Check for extra keys
    extra_keys <- setdiff(names(result), valid_keys)
    if (length(extra_keys) > 0) {
      cat("Warning: Extra keys found:", paste(extra_keys, collapse = ", "), "\n")
      result <- result[valid_keys]
    }
    
    # Validate values
    invalid_values <- sapply(result, function(v) !v %in% valid_values)
    if (any(invalid_values)) {
      cat("Warning: Invalid values found for:", 
          paste(names(result)[invalid_values], collapse = ", "), "\n")
      result[invalid_values] <- "unclear"
    }
    
    # Convert to data frame and return
    as.data.frame(result)
  }, error = function(e) {
    cat("Error parsing response:", e$message, "\n")
    data.frame(
      family_friend_mentioned = "unclear",
      intimate_partner_mentioned = "unclear",
      violence_mentioned = "unclear",
      substance_abuse_mentioned = "unclear",
      ipv_between_intimate_partners = "unclear"
    )
  })
}

# Function to test by row number
test_by_row <- function(row_num, narrative_type = "CME") {
  # Get the narrative for the specified row
  row_data <- df |> filter(row_id == row_num)
  
  if (nrow(row_data) == 0) {
    cat("Error: Row", row_num, "not found in the dataset\n")
    return(NULL)
  }
  
  # Select the appropriate narrative
  narrative_col <- if(narrative_type == "CME") "NarrativeCME" else "NarrativeLE"
  narrative <- row_data[[narrative_col]]
  
  cat("\nTesting narrative for row", row_num, "\n")
  cat("Narrative type:", narrative_type, "\n")
  cat("Narrative:", narrative, "\n\n")
  
  # Test the narrative
  result <- test_narrative(narrative)
  
  # Add metadata to result
  result$row_id <- row_num
  result$narrative_type <- narrative_type
  
  return(result)
}

## ---------- run on file ---------------------------------------------
df <- read_excel("data/sui_all_flagged.xlsx") |>
  mutate(row_id = row_number()) |>          # keep original order
  select(row_id, NarrativeCME, NarrativeLE) 

# Print data structure
cat("\nData Structure:\n")
str(df)
cat("\nFirst few rows:\n")
print(head(df))

# Example usage:
# Test CME narrative for row 1
result_cme <- test_by_row(1, "CME")
View(result_cme)

# Test LE narrative for row 1
result_le <- test_by_row(1, "LE")
View(result_le) 
