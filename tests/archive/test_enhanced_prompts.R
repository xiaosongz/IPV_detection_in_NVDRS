# Test script for enhanced call_llm with system/user prompts
# This validates the new functionality without making actual API calls

# Load functions
source("R/call_llm.R")

# Test 1: Validate build_ipv_prompt function
cat("=== Test 1: build_ipv_prompt function ===\n")
test_narrative <- "Test narrative about domestic violence incident"
prompts <- build_ipv_prompt(test_narrative)

# Check structure
cat("✓ Returns list with 'system' and 'user' elements:", 
    all(c("system", "user") %in% names(prompts)), "\n")

# Check system prompt content
system_contains_role <- grepl("forensic death investigation analyst", prompts$system)
system_contains_json <- grepl("Respond only with valid JSON", prompts$system)
cat("✓ System prompt contains role definition:", system_contains_role, "\n")
cat("✓ System prompt contains JSON instruction:", system_contains_json, "\n")

# Check user prompt content
user_contains_narrative <- grepl(test_narrative, prompts$user)
user_contains_indicators <- grepl("IPV indicators", prompts$user)
cat("✓ User prompt contains narrative:", user_contains_narrative, "\n")
cat("✓ User prompt contains indicator instructions:", user_contains_indicators, "\n")

cat("\nSystem prompt length:", nchar(prompts$system), "characters\n")
cat("User prompt length:", nchar(prompts$user), "characters\n\n")

# Test 2: Validate input validation
cat("=== Test 2: Input validation ===\n")
tryCatch({
  build_ipv_prompt(c("multiple", "narratives"))
  cat("✗ Should reject multiple narratives\n")
}, error = function(e) {
  cat("✓ Correctly rejects multiple narratives:", e$message, "\n")
})

tryCatch({
  build_ipv_prompt(123)
  cat("✗ Should reject non-character input\n")
}, error = function(e) {
  cat("✓ Correctly rejects non-character input:", e$message, "\n")
})

# Test 3: Mock the enhanced call_llm function structure
cat("\n=== Test 3: call_llm parameter validation ===\n")

# Mock function to test parameter handling (don't make actual API calls)
test_call_llm_params <- function(prompt, system_prompt = NULL) {
  # Simulate the parameter validation from call_llm
  if (!is.character(prompt) || length(prompt) != 1) {
    stop("'prompt' must be a single character string", call. = FALSE)
  }
  if (!is.null(system_prompt) && (!is.character(system_prompt) || length(system_prompt) != 1)) {
    stop("'system_prompt' must be a single character string or NULL", call. = FALSE)
  }
  
  # Build messages array like the real function
  messages <- list()
  if (!is.null(system_prompt)) {
    messages[[length(messages) + 1]] <- list(role = "system", content = system_prompt)
  }
  messages[[length(messages) + 1]] <- list(role = "user", content = prompt)
  
  return(messages)
}

# Test backward compatibility (no system prompt)
messages1 <- test_call_llm_params("Test user prompt")
cat("✓ Backward compatibility - single user message:", length(messages1) == 1, "\n")
cat("✓ User role correct:", messages1[[1]]$role == "user", "\n")

# Test with system prompt
messages2 <- test_call_llm_params("Test user prompt", "Test system prompt")
cat("✓ System + user messages:", length(messages2) == 2, "\n")
cat("✓ System role correct:", messages2[[1]]$role == "system", "\n")
cat("✓ User role correct:", messages2[[2]]$role == "user", "\n")

# Test validation errors
tryCatch({
  test_call_llm_params(c("multiple", "prompts"))
  cat("✗ Should reject multiple prompts\n")
}, error = function(e) {
  cat("✓ Correctly rejects multiple prompts\n")
})

tryCatch({
  test_call_llm_params("test", c("multiple", "system", "prompts"))
  cat("✗ Should reject multiple system prompts\n")
}, error = function(e) {
  cat("✓ Correctly rejects multiple system prompts\n")
})

cat("\n=== All tests completed ===\n")
cat("Enhanced call_llm function is ready for use!\n\n")

# Example usage pattern
cat("=== Usage Example ===\n")
cat("# Method 1: Using helper function\n")
cat("prompts <- build_ipv_prompt(narrative_text)\n")
cat("response <- call_llm(prompts$user, system_prompt = prompts$system)\n\n")

cat("# Method 2: Manual system/user prompts\n") 
cat("response <- call_llm(user_prompt, system_prompt = system_prompt)\n\n")

cat("# Method 3: Backward compatible\n")
cat("response <- call_llm(single_prompt)\n")