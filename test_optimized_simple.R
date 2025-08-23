# Simple Optimized Configuration Test
# Test the optimized settings against the existing package

library(nvdrsipvdetector)

cat("Testing Optimized Configuration\n")
cat(paste(rep("=", 50), collapse = ""), "\n")

# Load test data
test_data <- read.csv("tests/test_data/test_sample.csv", stringsAsFactors = FALSE)
test_data$Manual_IPV_Flag <- test_data$ipv_flag_LE | test_data$ipv_flag_CME

cat(sprintf("Test cases: %d\n", nrow(test_data)))
cat(sprintf("True IPV cases: %d\n", sum(test_data$Manual_IPV_Flag)))

# Test a few cases with optimized configuration
cat("\nTesting first 5 cases with optimized config...\n")

results <- data.frame(
  IncidentID = character(),
  Manual_Flag = logical(),
  Predicted_IPV = logical(),
  Confidence = numeric(),
  stringsAsFactors = FALSE
)

# Create results directory
if (!dir.exists("results")) dir.create("results", recursive = TRUE)

# Test first 5 cases as proof of concept
for (i in 1:min(5, nrow(test_data))) {
  cat(sprintf("\nCase %d (ID: %s):\n", i, test_data$IncidentID[i]))
  cat(sprintf("Manual flag: %s\n", test_data$Manual_IPV_Flag[i]))
  
  # Combine LE and CME narratives
  combined_narrative <- paste(
    ifelse(is.na(test_data$NarrativeLE[i]) | test_data$NarrativeLE[i] == "", "", 
           paste("LE:", test_data$NarrativeLE[i])),
    ifelse(is.na(test_data$NarrativeCME[i]) | test_data$NarrativeCME[i] == "", "", 
           paste("CME:", test_data$NarrativeCME[i])),
    sep = " "
  )
  
  tryCatch({
    # Test with optimized config (use LE type for combined narrative)
    result <- detect_ipv(
      narrative = combined_narrative,
      type = "LE", 
      config = "config/optimized_settings.yml",
      log_to_db = TRUE
    )
    
    cat(sprintf("Result: IPV=%s, Confidence=%.3f\n", 
                result$ipv_detected %||% "ERROR", 
                result$confidence %||% 0))
    
    if (!is.null(result$indicators) && length(result$indicators) > 0) {
      cat(sprintf("Indicators: %s\n", paste(result$indicators, collapse = ", ")))
    }
    
    results <- rbind(results, data.frame(
      IncidentID = test_data$IncidentID[i],
      Manual_Flag = test_data$Manual_IPV_Flag[i],
      Predicted_IPV = result$ipv_detected %||% NA,
      Confidence = result$confidence %||% NA,
      stringsAsFactors = FALSE
    ))
    
  }, error = function(e) {
    cat(sprintf("ERROR: %s\n", e$message))
    
    results <<- rbind(results, data.frame(
      IncidentID = test_data$IncidentID[i],
      Manual_Flag = test_data$Manual_IPV_Flag[i],
      Predicted_IPV = NA,
      Confidence = NA,
      stringsAsFactors = FALSE
    ))
  })
}

cat("\n", paste(rep("=", 50), collapse = ""), "\n")
cat("PRELIMINARY RESULTS\n")
cat(paste(rep("=", 50), collapse = ""), "\n")

valid_results <- results[!is.na(results$Predicted_IPV), ]
if (nrow(valid_results) > 0) {
  accuracy <- mean(valid_results$Manual_Flag == valid_results$Predicted_IPV)
  avg_confidence <- mean(valid_results$Confidence, na.rm = TRUE)
  
  cat(sprintf("Valid cases: %d/%d\n", nrow(valid_results), nrow(results)))
  cat(sprintf("Accuracy: %.3f (%.1f%%)\n", accuracy, accuracy * 100))
  cat(sprintf("Average confidence: %.3f\n", avg_confidence))
  
  # Show individual results
  cat("\nIndividual Results:\n")
  for (i in 1:nrow(valid_results)) {
    correct <- valid_results$Manual_Flag[i] == valid_results$Predicted_IPV[i]
    cat(sprintf("  Case %s: %s (%.3f) %s\n", 
                valid_results$IncidentID[i],
                ifelse(valid_results$Predicted_IPV[i], "IPV", "No IPV"),
                valid_results$Confidence[i],
                ifelse(correct, "✓", "✗")))
  }
} else {
  cat("No valid results - all cases had errors\n")
}

# Save results
write.csv(results, "results/optimized_simple_test.csv", row.names = FALSE)
cat(sprintf("\nResults saved to: results/optimized_simple_test.csv\n"))

cat("\nOptimized configuration test completed!\n")