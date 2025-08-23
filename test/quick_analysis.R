# Quick IPV Detection Results Analysis
# =====================================

# Load results
results_path <- "tests/test_results/baseline_results.csv"

if (!file.exists(results_path)) {
  cat("❌ Results file not found:", results_path, "\n")
  quit()
}

cat("📂 Loading results...\n")
results <- read.csv(results_path, stringsAsFactors = FALSE)
cat("✅ Loaded", nrow(results), "cases\n\n")

# Basic Performance Metrics Function
calculate_metrics <- function(actual, predicted, confidence, label) {
  
  # Handle missing values
  valid_idx <- !is.na(actual) & !is.na(predicted)
  actual <- actual[valid_idx]
  predicted <- predicted[valid_idx]
  confidence <- confidence[valid_idx]
  
  if (length(actual) == 0) {
    cat("⚠️ No valid cases for", label, "\n")
    return(NULL)
  }
  
  # Confusion Matrix
  tp <- sum(predicted == 1 & actual == 1)  # True Positive
  tn <- sum(predicted == 0 & actual == 0)  # True Negative
  fp <- sum(predicted == 1 & actual == 0)  # False Positive
  fn <- sum(predicted == 0 & actual == 1)  # False Negative
  
  # Metrics
  accuracy <- (tp + tn) / length(actual)
  precision <- if (tp + fp > 0) tp / (tp + fp) else 0
  recall <- if (tp + fn > 0) tp / (tp + fn) else 0
  specificity <- if (tn + fp > 0) tn / (tn + fp) else 0
  f1 <- if (precision + recall > 0) 2 * (precision * recall) / (precision + recall) else 0
  
  # Error Analysis
  error_rate <- (fp + fn) / length(actual)
  
  return(list(
    label = label,
    n = length(actual),
    tp = tp, tn = tn, fp = fp, fn = fn,
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    specificity = specificity,
    f1 = f1,
    error_rate = error_rate,
    mean_confidence = mean(confidence, na.rm = TRUE),
    confidence_range = range(confidence, na.rm = TRUE)
  ))
}

# Analyze all methods
cat("📊 PERFORMANCE ANALYSIS\n")
cat("========================\n\n")

# LE Analysis
le_metrics <- calculate_metrics(
  actual = results$actual_le,
  predicted = results$predicted_le,
  confidence = results$confidence_le,
  label = "Law Enforcement"
)

# CME Analysis
cme_metrics <- calculate_metrics(
  actual = results$actual_cme,
  predicted = results$predicted_cme,
  confidence = results$confidence_cme,
  label = "Medical Examiner"
)

# Combined Analysis (actual IPV if either LE or CME is positive)
actual_ipv <- ifelse(results$actual_le == 1 | results$actual_cme == 1, 1, 0)
combined_metrics <- calculate_metrics(
  actual = actual_ipv,
  predicted = results$combined_ipv,
  confidence = results$combined_conf,
  label = "Combined Weighted"
)

# Print Results
print_metrics <- function(metrics) {
  if (is.null(metrics)) return()
  
  cat(sprintf("%-20s (n=%d)\n", metrics$label, metrics$n))
  cat(sprintf("  Accuracy:    %.3f (%.1f%%)\n", metrics$accuracy, metrics$accuracy * 100))
  cat(sprintf("  Precision:   %.3f (%.1f%%)\n", metrics$precision, metrics$precision * 100))
  cat(sprintf("  Recall:      %.3f (%.1f%%)\n", metrics$recall, metrics$recall * 100))
  cat(sprintf("  Specificity: %.3f (%.1f%%)\n", metrics$specificity, metrics$specificity * 100))
  cat(sprintf("  F1 Score:    %.3f\n", metrics$f1))
  cat(sprintf("  Error Rate:  %.3f (%.1f%%)\n", metrics$error_rate, metrics$error_rate * 100))
  cat(sprintf("  TP=%d, TN=%d, FP=%d, FN=%d\n", metrics$tp, metrics$tn, metrics$fp, metrics$fn))
  cat(sprintf("  Mean Confidence: %.3f (range: %.3f - %.3f)\n", 
              metrics$mean_confidence, metrics$confidence_range[1], metrics$confidence_range[2]))
  cat("\n")
}

print_metrics(le_metrics)
print_metrics(cme_metrics)  
print_metrics(combined_metrics)

# Error Analysis
cat("🔍 ERROR ANALYSIS\n")
cat("==================\n\n")

# Identify problematic cases
errors <- data.frame(
  incident_id = results$incident_id,
  actual_ipv = actual_ipv,
  predicted_ipv = results$combined_ipv,
  confidence = results$combined_conf,
  le_actual = results$actual_le,
  le_pred = results$predicted_le,
  cme_actual = results$actual_cme,
  cme_pred = results$predicted_cme
)

# False Positives (predicted IPV when not actual)
fp_cases <- errors[errors$predicted_ipv == 1 & errors$actual_ipv == 0, ]
if (nrow(fp_cases) > 0) {
  cat("❌ FALSE POSITIVES (", nrow(fp_cases), " cases):\n")
  for (i in 1:nrow(fp_cases)) {
    cat(sprintf("  Case %s: Confidence=%.3f\n", fp_cases$incident_id[i], fp_cases$confidence[i]))
  }
  cat("\n")
} else {
  cat("✅ No False Positives!\n\n")
}

# False Negatives (missed actual IPV)
fn_cases <- errors[errors$predicted_ipv == 0 & errors$actual_ipv == 1, ]
if (nrow(fn_cases) > 0) {
  cat("❌ FALSE NEGATIVES (", nrow(fn_cases), " cases):\n")
  for (i in 1:nrow(fn_cases)) {
    cat(sprintf("  Case %s: Confidence=%.3f, LE_actual=%d, CME_actual=%d\n", 
                fn_cases$incident_id[i], fn_cases$confidence[i], 
                fn_cases$le_actual[i], fn_cases$cme_actual[i]))
  }
  cat("\n")
} else {
  cat("✅ No False Negatives!\n\n")
}

# Method Comparison
cat("📈 METHOD COMPARISON\n")
cat("====================\n\n")

comparison <- data.frame(
  Method = c("LE Only", "CME Only", "Combined"),
  Accuracy = c(le_metrics$accuracy, cme_metrics$accuracy, combined_metrics$accuracy),
  Precision = c(le_metrics$precision, cme_metrics$precision, combined_metrics$precision),
  Recall = c(le_metrics$recall, cme_metrics$recall, combined_metrics$recall),
  F1 = c(le_metrics$f1, cme_metrics$f1, combined_metrics$f1),
  Errors = c(le_metrics$fp + le_metrics$fn, cme_metrics$fp + cme_metrics$fn, 
             combined_metrics$fp + combined_metrics$fn)
)

print(comparison)

# Statistical Significance (simplified)
cat("\n📊 STATISTICAL ANALYSIS\n")
cat("========================\n\n")

# Test if accuracy is significantly better than random (50%)
for (method_name in c("LE", "CME", "Combined")) {
  if (method_name == "LE") metrics <- le_metrics
  else if (method_name == "CME") metrics <- cme_metrics
  else metrics <- combined_metrics
  
  # Binomial test for accuracy vs random (0.5)
  correct <- metrics$tp + metrics$tn
  total <- metrics$n
  
  # Simple z-test approximation
  expected <- total * 0.5
  se <- sqrt(total * 0.5 * 0.5)
  z_score <- (correct - expected) / se
  p_value <- 2 * (1 - pnorm(abs(z_score)))  # Two-tailed test
  
  significant <- p_value < 0.05
  
  cat(sprintf("%-12s: Accuracy=%.3f, Z=%.2f, p=%.4f %s\n", 
              method_name, metrics$accuracy, z_score, p_value,
              ifelse(significant, "***", "")))
}

# Effect Size (Cohen's h)
cat("\nEffect Sizes (vs random baseline):\n")
for (method_name in c("LE", "CME", "Combined")) {
  if (method_name == "LE") metrics <- le_metrics
  else if (method_name == "CME") metrics <- cme_metrics
  else metrics <- combined_metrics
  
  # Cohen's h for proportions
  h <- 2 * (asin(sqrt(metrics$accuracy)) - asin(sqrt(0.5)))
  effect_interpretation <- if (abs(h) > 0.8) "Large"
                          else if (abs(h) > 0.5) "Medium"
                          else if (abs(h) > 0.2) "Small"
                          else "Negligible"
  
  cat(sprintf("%-12s: h=%.3f (%s effect)\n", method_name, h, effect_interpretation))
}

# Recommendations
cat("\n⚙️ OPTIMIZATION RECOMMENDATIONS\n")
cat("================================\n\n")

# Current threshold analysis
current_threshold <- 0.7
conf_scores <- results$combined_conf[!is.na(results$combined_conf)]

cat("Current Configuration:\n")
cat(sprintf("  Threshold: %.1f\n", current_threshold))
cat(sprintf("  LE Weight: 0.4, CME Weight: 0.6\n"))
cat(sprintf("  Combined F1 Score: %.3f\n", combined_metrics$f1))

# Suggest threshold optimization
above_thresh <- sum(conf_scores > current_threshold)
below_thresh <- sum(conf_scores <= current_threshold)
cat(sprintf("  Cases above threshold: %d (%.1f%%)\n", above_thresh, 100*above_thresh/length(conf_scores)))
cat(sprintf("  Cases below threshold: %d (%.1f%%)\n", below_thresh, 100*below_thresh/length(conf_scores)))

# Simple threshold analysis
thresholds <- c(0.5, 0.6, 0.7, 0.8, 0.9)
cat("\nThreshold Analysis:\n")
cat("Threshold | Predicted IPV | Accuracy Estimate\n")
cat("----------|---------------|------------------\n")

for (thresh in thresholds) {
  pred_count <- sum(conf_scores >= thresh)
  pred_rate <- pred_count / length(conf_scores)
  
  # Simple accuracy estimate (assuming current performance holds)
  est_accuracy <- combined_metrics$accuracy  # This is a simplification
  
  cat(sprintf("   %.1f     |      %2d      |      %.3f\n", 
              thresh, pred_count, est_accuracy))
}

cat("\nKey Insights:\n")
if (combined_metrics$f1 > max(le_metrics$f1, cme_metrics$f1)) {
  cat("✅ Combined method outperforms individual methods\n")
} else {
  cat("⚠️ Individual methods may be better than combined\n")
}

if (combined_metrics$precision == 1.0) {
  cat("✅ Perfect precision - no false positives\n")
} else {
  cat(sprintf("⚠️ Precision could be improved (%.3f)\n", combined_metrics$precision))
}

if (combined_metrics$recall < 1.0) {
  cat(sprintf("⚠️ Missing some IPV cases (Recall=%.3f)\n", combined_metrics$recall))
} else {
  cat("✅ Perfect recall - catching all IPV cases\n")
}

# Save summary
summary_data <- list(
  le = le_metrics,
  cme = cme_metrics,
  combined = combined_metrics,
  comparison = comparison,
  fp_cases = fp_cases,
  fn_cases = fn_cases,
  raw_data = results
)

save(summary_data, file = "tests/test_results/analysis_summary.RData")

cat("\n💾 Analysis summary saved to: tests/test_results/analysis_summary.RData\n")
cat("✅ Analysis complete!\n")