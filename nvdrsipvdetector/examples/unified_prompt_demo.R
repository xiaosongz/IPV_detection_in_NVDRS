# Demonstration of unified prompt template
library(nvdrsipvdetector)

# Load configuration
config <- load_config()

# Example narratives
le_narrative <- "The victim was shot by her ex-boyfriend after she refused to reconcile their relationship. Neighbors reported hearing arguments between the couple in recent weeks."

cme_narrative <- "The deceased had multiple bruises on her arms and torso in various stages of healing. Her husband stated she fell down the stairs."

# Build prompts using unified template
# Notice how both use the same template, only the narrative type differs

cat("=== LAW ENFORCEMENT PROMPT ===\n")
le_prompt <- build_prompt(le_narrative, "LE", config)
cat(substr(le_prompt, 1, 200), "...\n\n")

cat("=== MEDICAL EXAMINER PROMPT ===\n")
cme_prompt <- build_prompt(cme_narrative, "CME", config)
cat(substr(cme_prompt, 1, 200), "...\n\n")

# The key improvement:
# - Same comprehensive IPV indicators for both types
# - Only difference is "law enforcement" vs "medical examiner" label
# - Simpler to maintain - one template instead of two
# - LLM gets full context regardless of narrative source

cat("=== KEY BENEFITS ===\n")
cat("1. Single source of truth for IPV indicators\n")
cat("2. Both narrative types get same comprehensive analysis\n")
cat("3. Easier to update - modify one template instead of two\n")
cat("4. Reduces redundancy and maintenance burden\n")