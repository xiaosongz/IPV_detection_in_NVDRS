# Compare Baseline vs Optimized Configuration Performance
# This script analyzes the differences between the two approaches

library(dplyr)

cat("IPV Detection Configuration Comparison\n")
cat(paste(rep("=", 50), collapse = ""), "\n", sep = "")

# Helper function to load results safely
load_results <- function(file_path, config_name) {
  if (file.exists(file_path)) {
    results <- read.csv(file_path, stringsAsFactors = FALSE)
    cat(sprintf("Loaded %s results: %d cases\n", config_name, nrow(results)))
    return(results)
  } else {
    cat(sprintf("WARNING: %s results file not found: %s\n", config_name, file_path))
    return(NULL)
  }
}

# Load both result sets
baseline_results <- load_results("results/baseline_test_results.csv", "baseline")
optimized_results <- load_results("results/optimized_test_results.csv", "optimized")

if (is.null(baseline_results) || is.null(optimized_results)) {
  cat("Cannot perform comparison - missing result files\n")
  quit(save = "no", status = 1)
}

# Helper function to calculate metrics
calculate_metrics <- function(results, config_name) {
  valid_results <- results[!is.na(results$Predicted_IPV), ]
  
  if (nrow(valid_results) == 0) {
    cat(sprintf("No valid results for %s configuration\n", config_name))
    return(NULL)
  }
  
  tp <- sum(valid_results$Manual_IPV_Flag & valid_results$Predicted_IPV, na.rm = TRUE)
  tn <- sum(!valid_results$Manual_IPV_Flag & !valid_results$Predicted_IPV, na.rm = TRUE)
  fp <- sum(!valid_results$Manual_IPV_Flag & valid_results$Predicted_IPV, na.rm = TRUE)
  fn <- sum(valid_results$Manual_IPV_Flag & !valid_results$Predicted_IPV, na.rm = TRUE)
  
  total <- tp + tn + fp + fn
  accuracy <- (tp + tn) / total
  precision <- if (tp + fp > 0) tp / (tp + fp) else 0
  recall <- if (tp + fn > 0) tp / (tp + fn) else 0  # Sensitivity
  specificity <- if (tn + fp > 0) tn / (tn + fp) else 0
  f1 <- if (precision + recall > 0) 2 * (precision * recall) / (precision + recall) else 0
  
  error_rate <- sum(is.na(results$Predicted_IPV)) / nrow(results)
  avg_confidence <- mean(valid_results$Confidence, na.rm = TRUE)
  avg_processing_time <- mean(valid_results$Processing_Time, na.rm = TRUE)
  
  return(list(
    config = config_name,
    total_cases = nrow(results),
    valid_cases = nrow(valid_results),
    error_rate = error_rate,
    tp = tp, tn = tn, fp = fp, fn = fn,
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    specificity = specificity,
    f1_score = f1,
    avg_confidence = avg_confidence,
    avg_processing_time = avg_processing_time
  ))
}

# Calculate metrics for both configurations
baseline_metrics <- calculate_metrics(baseline_results, "Baseline")
optimized_metrics <- calculate_metrics(optimized_results, "Optimized")

if (is.null(baseline_metrics) || is.null(optimized_metrics)) {
  cat("Cannot calculate metrics for comparison\n")
  quit(save = "no", status = 1)
}

# Display comparison
cat("\n", paste(rep("=", 70), collapse = ""), "\n", sep = "")
cat("CONFIGURATION COMPARISON\n")
cat(paste(rep("=", 70), collapse = ""), "\n", sep = "")

# Summary table
cat(sprintf("%-20s %12s %12s %12s\n", "Metric", "Baseline", "Optimized", "Improvement"))
cat(paste(rep("-", 70), collapse = ""), "\n", sep = "")

metrics_to_compare <- c("accuracy", "precision", "recall", "specificity", "f1_score", "error_rate")
improvements <- numeric()

for (metric in metrics_to_compare) {
  baseline_val <- baseline_metrics[[metric]]
  optimized_val <- optimized_metrics[[metric]]
  
  # Calculate improvement (handle error_rate specially - lower is better)
  if (metric == "error_rate") {
    improvement <- baseline_val - optimized_val  # Reduction in error rate
    improvement_text <- sprintf("%.3f", improvement)
    if (improvement > 0) improvement_text <- paste0("+", improvement_text)
  } else {
    improvement <- optimized_val - baseline_val
    improvement_pct <- (improvement / baseline_val) * 100
    improvement_text <- sprintf("%.3f (+%.1f%%)", improvement, improvement_pct)
    if (improvement < 0) {
      improvement_text <- sprintf("%.3f (%.1f%%)", improvement, improvement_pct)
    }
  }
  
  improvements <- c(improvements, improvement)
  
  cat(sprintf("%-20s %12.3f %12.3f %12s\n", 
              stringr::str_to_title(gsub("_", " ", metric)),
              baseline_val, optimized_val, improvement_text))
}

cat(paste(rep("-", 70), collapse = ""), "\n", sep = "")

# Additional metrics
cat(sprintf("%-20s %12.1f %12.1f %12.1f\n", "Avg Confidence", 
            baseline_metrics$avg_confidence, optimized_metrics$avg_confidence,
            optimized_metrics$avg_confidence - baseline_metrics$avg_confidence))

cat(sprintf("%-20s %12.1f %12.1f %12.1f\n", "Avg Time (sec)", 
            baseline_metrics$avg_processing_time %||% 0, 
            optimized_metrics$avg_processing_time %||% 0,
            (optimized_metrics$avg_processing_time %||% 0) - (baseline_metrics$avg_processing_time %||% 0)))

cat(sprintf("%-20s %12d %12d %12d\n", "Valid Cases", 
            baseline_metrics$valid_cases, optimized_metrics$valid_cases,
            optimized_metrics$valid_cases - baseline_metrics$valid_cases))

# Key improvements summary
cat("\n", paste(rep("=", 70), collapse = ""), "\n", sep = "")
cat("KEY FINDINGS\n")
cat(paste(rep("=", 70), collapse = ""), "\n", sep = "")

# Overall assessment
overall_improvement <- mean(improvements[1:5])  # Exclude error rate from average
cat(sprintf("Overall Performance Improvement: %.3f (%.1f%%)\n", 
            overall_improvement, overall_improvement * 100))

# Critical metrics for IPV detection
cat("\nCRITICAL IPV METRICS:\n")
cat(sprintf("  False Negative Reduction: %d → %d (-%d cases)\n", 
            baseline_metrics$fn, optimized_metrics$fn, 
            baseline_metrics$fn - optimized_metrics$fn))
cat(sprintf("  Recall Improvement: %.3f → %.3f (+%.1f%%)\n", 
            baseline_metrics$recall, optimized_metrics$recall,
            ((optimized_metrics$recall - baseline_metrics$recall) / baseline_metrics$recall) * 100))
cat(sprintf("  Error Rate Reduction: %.3f → %.3f (%.3f)\n", 
            baseline_metrics$error_rate, optimized_metrics$error_rate,
            baseline_metrics$error_rate - optimized_metrics$error_rate))

# Case-by-case analysis for changed predictions
if (nrow(baseline_results) == nrow(optimized_results)) {
  cat("\nCASE-BY-CASE CHANGES:\n")
  
  # Find cases where predictions changed
  changed_cases <- baseline_results$IncidentID[
    !is.na(baseline_results$Predicted_IPV) & 
    !is.na(optimized_results$Predicted_IPV) &
    baseline_results$Predicted_IPV != optimized_results$Predicted_IPV
  ]
  
  if (length(changed_cases) > 0) {
    cat(sprintf("  %d cases changed predictions\n", length(changed_cases)))
    
    for (case_id in changed_cases) {
      baseline_row <- baseline_results[baseline_results$IncidentID == case_id, ]
      optimized_row <- optimized_results[optimized_results$IncidentID == case_id, ]
      manual_flag <- baseline_row$Manual_IPV_Flag
      
      change_type <- if (optimized_row$Predicted_IPV && !baseline_row$Predicted_IPV) {
        "False Negative → True Positive"
      } else if (!optimized_row$Predicted_IPV && baseline_row$Predicted_IPV) {
        "False Positive → True Negative"
      } else if (optimized_row$Predicted_IPV && baseline_row$Predicted_IPV) {
        "Both Positive"
      } else {
        "Both Negative"
      }
      
      accuracy_change <- if (optimized_row$Predicted_IPV == manual_flag && 
                             baseline_row$Predicted_IPV != manual_flag) {
        " ✓ IMPROVED"
      } else if (optimized_row$Predicted_IPV != manual_flag && 
                 baseline_row$Predicted_IPV == manual_flag) {
        " ✗ WORSENED"
      } else {
        ""
      }
      
      cat(sprintf("    %s: %s%s\n", case_id, change_type, accuracy_change))
      cat(sprintf("      Confidence: %.2f → %.2f\n", 
                  baseline_row$Confidence %||% 0, optimized_row$Confidence %||% 0))
    }
  } else {
    cat("  No prediction changes between configurations\n")
  }
}

# Recommendations
cat("\n", paste(rep("=", 70), collapse = ""), "\n", sep = "")
cat("RECOMMENDATIONS\n")
cat(paste(rep("=", 70), collapse = ""), "\n", sep = "")

if (optimized_metrics$recall > baseline_metrics$recall && 
    optimized_metrics$error_rate < baseline_metrics$error_rate) {
  cat("✓ RECOMMEND OPTIMIZED CONFIGURATION\n")
  cat("  - Better recall (fewer missed IPV cases)\n")
  cat("  - Lower error rate (more stable processing)\n")
  cat("  - Improved overall accuracy\n")
} else if (optimized_metrics$f1_score > baseline_metrics$f1_score) {
  cat("✓ RECOMMEND OPTIMIZED CONFIGURATION\n") 
  cat("  - Better F1 score (balanced precision/recall)\n")
} else {
  cat("? FURTHER ANALYSIS NEEDED\n")
  cat("  - Mixed results require domain expert review\n")
}

cat(sprintf("\nAnalysis completed at: %s\n", Sys.time()))

# Save comparison results
comparison_summary <- data.frame(
  Metric = c("Accuracy", "Precision", "Recall", "Specificity", "F1_Score", "Error_Rate"),
  Baseline = c(baseline_metrics$accuracy, baseline_metrics$precision, baseline_metrics$recall, 
               baseline_metrics$specificity, baseline_metrics$f1_score, baseline_metrics$error_rate),
  Optimized = c(optimized_metrics$accuracy, optimized_metrics$precision, optimized_metrics$recall,
                optimized_metrics$specificity, optimized_metrics$f1_score, optimized_metrics$error_rate),
  Improvement = improvements[1:6],
  stringsAsFactors = FALSE
)

write.csv(comparison_summary, "results/configuration_comparison.csv", row.names = FALSE)
cat("Comparison summary saved to: results/configuration_comparison.csv\n")