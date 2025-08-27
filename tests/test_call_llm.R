# Test script for call_llm function
# Tests should only live in tests/ directory

# Load the function
source("R/call_llm.R")

# Read the test prompt
prompt <- readLines("tests/test_promt.txt", warn = FALSE) |> 
  paste(collapse = "\n")

# Call the LLM
cat("Testing call_llm() with forensic prompt...\n\n")
result <- call_llm(prompt)

# Show response structure
cat("Response received. Structure:\n")
cat("- ID:", result$id, "\n")
cat("- Model:", result$model, "\n")
cat("- Tokens used:", result$usage$total_tokens, "\n")

# Extract and display content
content <- result$choices[[1]]$message$content
cat("\nLLM Response Content:\n")
cat(content, "\n")

# Validate it's JSON
if (grepl("^\\{", trimws(content))) {
  tryCatch({
    parsed <- jsonlite::fromJSON(content)
    cat("\n✓ Valid JSON response\n")
    cat("- IPV Detected:", parsed$ipv_detected, "\n")
    cat("- Confidence:", parsed$confidence, "\n")
    cat("- Indicators found:", length(parsed$indicators), "\n")
  }, error = function(e) {
    cat("\n✗ JSON parsing failed:", e$message, "\n")
  })
} else {
  cat("\n✗ Response is not JSON format\n")
}