# Demonstration of Enhanced call_llm with System and User Prompts
# This script shows how to use the enhanced prompt structure for IPV detection

# Load the functions (in a real package, you'd use library(IPVdetection))
source("R/call_llm.R")

# Example narrative from test file
narrative_text <- "The V is a 19 year old white female. The V had a history of suicidal ideations and had recently been talking about killing herself. The V got into an argument with her boyfriend over her methamphetamine abuse and she told him something to the effect of 'I guess I should just go kill myself,' to which he responded 'Fine, go ahead.' The went into her room, posted a suicide note on social media, and was found 10 minutes later, unresponsive and hanging by the neck. 911 was called and when EMS arrived the V was transported to the hospital where she was pronounced dead. No toxicology results are given. The manner of death is suicide."

# Method 1: Using the prompt builder helper (RECOMMENDED)
cat("=== Method 1: Using build_ipv_prompt helper ===\n")
prompts <- build_ipv_prompt(narrative_text)

cat("System prompt:\n")
cat(prompts$system, "\n\n")

cat("User prompt (first 200 chars):\n")
cat(substr(prompts$user, 1, 200), "...\n\n")

# Use with call_llm
response <- call_llm(prompts$user, system_prompt = prompts$system)
result <- response$choices[[1]]$message$content
cat("Response:\n", result, "\n\n")

# Method 2: Manual system and user prompts
cat("=== Method 2: Manual system/user prompts ===\n")
system_prompt <- "You are a forensic death investigation analyst specializing in intimate partner violence cases. Respond only with valid JSON."
user_prompt <- paste("Analyze this narrative for IPV indicators:", narrative_text, 
                    "Return JSON with: ipv_detected, confidence, indicators, rationale")

response <- call_llm(user_prompt, system_prompt = system_prompt)
result <- response$choices[[1]]$message$content
cat("Response:\n", result, "\n\n")

# Method 3: Backward compatible - single prompt (LEGACY)
cat("=== Method 3: Backward compatible single prompt ===\n")
combined_prompt <- paste("You are a forensic analyst. Respond with JSON only.",
                        "Analyze this narrative for IPV:", narrative_text)

response <- call_llm(combined_prompt)
result <- response$choices[[1]]$message$content
cat("Response:\n", result, "\n\n")

# Batch processing example with the new structure
cat("=== Batch Processing Example ===\n")
narratives <- c(
  "Domestic violence incident with strangulation marks found...",
  "Victim found with defensive wounds and history of restraining orders...",
  "Single gunshot wound, no relationship factors identified..."
)

# Process batch with proper system/user separation
results <- lapply(narratives, function(narrative) {
  prompts <- build_ipv_prompt(narrative)
  response <- call_llm(prompts$user, system_prompt = prompts$system)
  response$choices[[1]]$message$content
})

cat("Processed", length(results), "narratives\n")
cat("First result:", substr(results[[1]], 1, 100), "...\n")