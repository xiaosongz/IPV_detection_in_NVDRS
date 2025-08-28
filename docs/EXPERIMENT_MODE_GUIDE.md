# Experiment Mode Guide

## Overview

The IPVdetection package now includes an optional **Experiment Mode** for R&D purposes. This allows you to:

- Track different prompt versions
- Compare performance across prompts
- Perform statistical A/B testing
- Avoid redundant API calls
- Maintain full experiment history

**Important**: Experiment mode is completely optional. The basic `call_llm()` and `store_llm_result()` functions work exactly as before.

## Quick Start

### 1. Setup Database for Experiments

```r
library(IPVdetection)

# Create or connect to database
conn <- get_db_connection("experiments.db")

# Initialize experiment schema (one-time setup)
ensure_experiment_schema(conn)

close_db_connection(conn)
```

### 2. Register Prompt Versions

```r
# Register your baseline prompt
baseline_id <- register_prompt(
  system_prompt = "You are an expert at detecting intimate partner violence (IPV) in narratives.",
  user_prompt_template = "Analyze this narrative for IPV indicators: {text}",
  version_tag = "v1.0_baseline",
  notes = "Initial baseline prompt"
)

# Register an improved version
enhanced_id <- register_prompt(
  system_prompt = "You are an expert at detecting intimate partner violence (IPV). 
                   Look for patterns of control, threats, and violence.",
  user_prompt_template = "Analyze this narrative for IPV indicators. 
                         Consider physical, emotional, and financial abuse: {text}",
  version_tag = "v2.0_enhanced",
  notes = "Added specific IPV types to prompt"
)
```

### 3. Run Experiments

```r
# Load test narratives (example)
test_data <- readxl::read_excel("data-raw/suicide_IPV_manuallyflagged.xlsx")

# Start experiment with baseline prompt
exp1 <- start_experiment(
  name = "baseline_test_jan2025",
  prompt_version_id = baseline_id,
  model = "gpt-4",
  dataset_name = "suicide_IPV_flagged"
)

# Get the prompt for this experiment
prompts <- get_prompt(baseline_id)

# Process narratives
for (i in 1:nrow(test_data)) {
  # Call LLM with the prompt
  response <- call_llm(
    user_prompt = gsub("{text}", test_data$narrative[i], prompts$user_prompt_template),
    system_prompt = prompts$system_prompt,
    model = "gpt-4"
  )
  
  # Parse the response
  parsed <- parse_llm_result(response, narrative_id = test_data$id[i])
  
  # Store with experiment tracking
  store_experiment_result(
    experiment_id = exp1,
    narrative_id = test_data$id[i],
    parsed_result = parsed,
    narrative_text = test_data$narrative[i]
  )
}

# Mark experiment as complete
complete_experiment(exp1)
```

### 4. Analyze Results

```r
# Get experiment metrics
metrics <- experiment_metrics(exp1)
print(metrics$detection_rate)  # What percentage detected IPV?
print(metrics$avg_confidence)  # How confident was the model?

# Generate detailed report
cat(experiment_report(exp1))
```

### 5. Compare Experiments

```r
# Run second experiment with enhanced prompt
exp2 <- start_experiment(
  name = "enhanced_test_jan2025",
  prompt_version_id = enhanced_id,
  model = "gpt-4",
  dataset_name = "suicide_IPV_flagged"
)

# ... process same narratives with new prompt ...

# Compare results
comparison <- compare_experiments(exp1, exp2)
print(comparison$differences$confidence_diff)  # Did confidence improve?
print(comparison$statistical_tests)  # Is the difference significant?
```

## Common Workflows

### A/B Testing Prompts

Test two prompt versions on the same narratives:

```r
# Perform paired A/B test
ab_results <- ab_test_prompts(
  prompt_v1_id = baseline_id,
  prompt_v2_id = enhanced_id,
  model = "gpt-4"
)

# Check if improvement is significant
if (ab_results$confidence_paired_t_test$significant) {
  print("New prompt significantly better!")
  print(paste("Confidence improved by:", ab_results$confidence_improvement))
}
```

### Track Prompt Evolution

See how your prompts improve over time:

```r
# View all prompt versions
all_prompts <- list_prompt_versions()
print(all_prompts[, c("version_tag", "created_at", "notes")])

# Analyze performance trajectory
evolution <- analyze_prompt_evolution()
plot(evolution$avg_confidence, type = "b", 
     xlab = "Prompt Version", ylab = "Average Confidence")
```

### Avoid Redundant API Calls

Check if narrative already tested with this prompt:

```r
# Before calling API, check if already tested
conn <- get_db_connection("experiments.db")
existing <- DBI::dbGetQuery(
  conn,
  "SELECT er.* FROM experiment_results er
   JOIN experiments e ON er.experiment_id = e.id
   WHERE e.prompt_version_id = ? AND er.narrative_id = ?",
  params = list(prompt_id, narrative_id)
)

if (nrow(existing) > 0) {
  print("Already tested - using cached result")
  result <- existing[1, ]
} else {
  # Call API and store result
  result <- call_llm(...)
}
close_db_connection(conn)
```

## Ground Truth Evaluation

Add human-annotated labels for accuracy testing:

```r
# Add ground truth labels
conn <- get_db_connection("experiments.db")
DBI::dbExecute(
  conn,
  "INSERT OR REPLACE INTO ground_truth (narrative_id, true_ipv, confidence_level, annotator)
   VALUES (?, ?, ?, ?)",
  params = list("NARR001", TRUE, 3, "expert_reviewer")
)
close_db_connection(conn)

# Metrics will now include accuracy
metrics <- experiment_metrics(exp_id)
print(metrics$accuracy_metrics$precision)
print(metrics$accuracy_metrics$recall)
print(metrics$accuracy_metrics$f1_score)
```

## Database Schema

The experiment mode uses 4 additional tables:

1. **prompt_versions** - Stores unique prompt combinations
2. **experiments** - Tracks test batches
3. **experiment_results** - Links results to experiments
4. **ground_truth** - Human-annotated correct answers

These tables supplement the original `llm_results` table without affecting it.

## Tips and Best Practices

### 1. Version Tag Convention

Use semantic versioning for prompts:
- `v1.0_baseline` - Initial version
- `v1.1_typo_fix` - Minor correction
- `v2.0_keywords` - Major change
- `v2.1_keywords_refined` - Refinement

### 2. Experiment Naming

Include date and purpose:
- `baseline_test_jan2025`
- `keyword_ablation_2025-01-15`
- `production_candidate_v3`

### 3. Batch Processing

Process in batches to track progress:

```r
batch_size <- 50
for (batch_start in seq(1, nrow(data), batch_size)) {
  batch_end <- min(batch_start + batch_size - 1, nrow(data))
  
  # Process batch
  for (i in batch_start:batch_end) {
    # ... process narrative ...
  }
  
  message(sprintf("Processed %d/%d", batch_end, nrow(data)))
}
```

### 4. Statistical Power

For reliable A/B testing:
- Test on at least 100 narratives
- Use paired testing (same narratives for both prompts)
- Consider multiple testing correction for many comparisons

## Migration from Simple Mode

If you have existing results in the simple `llm_results` table:

```r
# Your existing code still works!
result <- call_llm(user_prompt, system_prompt)
store_llm_result(result)  # Goes to original table

# Add experiment tracking when ready
exp_id <- start_experiment("migration_test", prompt_id, model)
store_experiment_result(exp_id, narrative_id, result)  # Goes to experiment table
```

## Troubleshooting

### Issue: Prompt already registered
```r
# Register prompt returns existing ID if duplicate
id1 <- register_prompt(...)  # Creates new
id2 <- register_prompt(...)  # Returns same ID
```

### Issue: Can't find experiment_schema.sql
```r
# Ensure package is loaded
library(IPVdetection)

# Or manually source if developing
source("R/db_utils.R")
source("R/experiment_utils.R")
```

### Issue: Database locked
```r
# Always close connections
conn <- get_db_connection()
# ... do work ...
close_db_connection(conn)

# Or use auto-closing pattern
result <- local({
  conn <- get_db_connection()
  on.exit(close_db_connection(conn))
  # ... do work ...
})
```

## Summary

Experiment mode provides a structured way to optimize prompts while maintaining the simplicity of the original design:

- **Optional**: Only use if you need it
- **Non-breaking**: Original functions unchanged
- **Scientific**: Proper A/B testing and statistics
- **Efficient**: Avoid redundant API calls
- **Traceable**: Full history of what was tested

The Unix philosophy remains: each function does one thing well, and you compose them as needed.