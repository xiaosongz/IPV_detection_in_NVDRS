# Final IPV Detection Optimization Test
# ======================================

results <- read.csv("tests/test_results/baseline_results.csv", stringsAsFactors = FALSE)

cat("🎯 FINAL OPTIMIZATION ANALYSIS\n")
cat("===============================\n\n")

# Calculate actual IPV
actual_ipv <- ifelse(results$actual_le == 1 | results$actual_cme == 1, 1, 0)

# Identify false negative cases
fn_cases <- results[results$combined_ipv == 0 & actual_ipv == 1, ]
cat("❌ FALSE NEGATIVE CASES:\n")
print(fn_cases[, c("incident_id", "combined_conf", "actual_le", "actual_cme")])

cat(sprintf("\nBoth FN cases have confidence = %.3f\n", fn_cases$combined_conf[1]))
cat("This explains why threshold 0.6 doesn't help - need ≤0.595\n\n")

# Test multiple threshold options
thresholds <- c(0.7, 0.65, 0.6, 0.595, 0.59, 0.55, 0.5)

cat("COMPREHENSIVE THRESHOLD ANALYSIS\n")
cat("=================================\n")
cat("Threshold | TP | TN | FP | FN | Accuracy | Precision | Recall | F1     | Cases+\n")
cat("----------|----|----|----|----|----------|-----------|--------|--------|---------\n")

results_table <- data.frame()

for (thresh in thresholds) {
  pred <- ifelse(results$combined_conf >= thresh, 1, 0)
  
  tp <- sum(pred == 1 & actual_ipv == 1)
  tn <- sum(pred == 0 & actual_ipv == 0)
  fp <- sum(pred == 1 & actual_ipv == 0)
  fn <- sum(pred == 0 & actual_ipv == 1)
  
  accuracy <- (tp + tn) / length(actual_ipv)
  precision <- if (tp + fp > 0) tp / (tp + fp) else 0
  recall <- if (tp + fn > 0) tp / (tp + fn) else 0
  f1 <- if (precision + recall > 0) 2 * (precision * recall) / (precision + recall) else 0
  
  cases_predicted <- sum(pred == 1)
  
  cat(sprintf("   %.3f  | %2d | %2d | %2d | %2d |   %.3f  |   %.3f   |  %.3f  | %.3f  |   %2d\n",
              thresh, tp, tn, fp, fn, accuracy, precision, recall, f1, cases_predicted))
  
  results_table <- rbind(results_table, data.frame(
    threshold = thresh, tp = tp, tn = tn, fp = fp, fn = fn,
    accuracy = accuracy, precision = precision, recall = recall, f1 = f1,
    cases_predicted = cases_predicted
  ))
}

# Find optimal threshold
optimal_idx <- which.max(results_table$f1)
optimal_threshold <- results_table$threshold[optimal_idx]
optimal_f1 <- results_table$f1[optimal_idx]

cat(sprintf("\n🏆 OPTIMAL THRESHOLD: %.3f (F1 = %.3f)\n", optimal_threshold, optimal_f1))

# Analyze the optimal threshold impact
optimal_pred <- ifelse(results$combined_conf >= optimal_threshold, 1, 0)
current_pred <- ifelse(results$combined_conf >= 0.7, 1, 0)

newly_detected <- results[optimal_pred == 1 & current_pred == 0, ]
if (nrow(newly_detected) > 0) {
  cat(sprintf("\n📈 CASES NEWLY DETECTED WITH THRESHOLD %.3f:\n", optimal_threshold))
  for (i in 1:nrow(newly_detected)) {
    case_id <- newly_detected$incident_id[i]
    conf <- newly_detected$combined_conf[i]
    actual_le <- newly_detected$actual_le[i]
    actual_cme <- newly_detected$actual_cme[i]
    is_correct <- ifelse(newly_detected$actual_le[i] == 1 | newly_detected$actual_cme[i] == 1, "✅ Correct", "❌ False Positive")
    
    cat(sprintf("  Case %s: Conf=%.3f, LE=%s, CME=%s - %s\n", 
                case_id, conf, actual_le, actual_cme, is_correct))
  }
} else {
  cat("\nNo additional cases detected with optimal threshold.\n")
}

# Risk-benefit analysis
cat("\n⚖️ RISK-BENEFIT ANALYSIS\n")
cat("=========================\n")

current_metrics <- results_table[results_table$threshold == 0.7, ]
optimal_metrics <- results_table[optimal_idx, ]

cat("Current (0.7) vs Optimal (", optimal_threshold, "):\n", sep="")
cat(sprintf("Accuracy:  %.3f → %.3f (%+.3f)\n", current_metrics$accuracy, optimal_metrics$accuracy, optimal_metrics$accuracy - current_metrics$accuracy))
cat(sprintf("Precision: %.3f → %.3f (%+.3f)\n", current_metrics$precision, optimal_metrics$precision, optimal_metrics$precision - current_metrics$precision))
cat(sprintf("Recall:    %.3f → %.3f (%+.3f)\n", current_metrics$recall, optimal_metrics$recall, optimal_metrics$recall - current_metrics$recall))
cat(sprintf("F1 Score:  %.3f → %.3f (%+.3f)\n", current_metrics$f1, optimal_metrics$f1, optimal_metrics$f1 - current_metrics$f1))

# Check for any degradation
precision_loss <- current_metrics$precision - optimal_metrics$precision
if (precision_loss > 0) {
  cat(sprintf("\n❌ WARNING: Precision decreases by %.3f (introduces %d false positives)\n", 
              precision_loss, optimal_metrics$fp - current_metrics$fp))
} else {
  cat("\n✅ No precision loss\n")
}

# Statistical significance of improvement
if (optimal_metrics$f1 > current_metrics$f1) {
  improvement = optimal_metrics$f1 - current_metrics$f1
  cat(sprintf("✅ F1 improvement: %.3f (%.1f%% relative improvement)\n", 
              improvement, 100 * improvement / current_metrics$f1))
}

# Final recommendation with context
cat("\n📋 FINAL RECOMMENDATIONS\n")
cat("=========================\n")

if (optimal_threshold != 0.7) {
  if (optimal_metrics$fp == current_metrics$fp) {
    cat(sprintf("🟢 STRONG RECOMMENDATION: Change threshold to %.3f\n", optimal_threshold))
    cat("   Benefits:\n")
    cat(sprintf("   • Improves recall by %.3f (catches %d more IPV cases)\n", 
                optimal_metrics$recall - current_metrics$recall, 
                current_metrics$fn - optimal_metrics$fn))
    cat(sprintf("   • Improves F1 score by %.3f\n", optimal_metrics$f1 - current_metrics$f1))
    cat("   • No additional false positives\n")
    
  } else if (optimal_metrics$fp > current_metrics$fp) {
    new_fp <- optimal_metrics$fp - current_metrics$fp
    cat(sprintf("🟡 CONDITIONAL RECOMMENDATION: Consider threshold %.3f\n", optimal_threshold))
    cat("   Trade-offs:\n")
    cat(sprintf("   + Catches %d more true IPV cases\n", current_metrics$fn - optimal_metrics$fn))
    cat(sprintf("   + Improves F1 score by %.3f\n", optimal_metrics$f1 - current_metrics$f1))
    cat(sprintf("   - Introduces %d false positive(s)\n", new_fp))
    cat("   Decision depends on relative cost of missed IPV vs false alarms\n")
  }
} else {
  cat("🔵 RECOMMENDATION: Keep current threshold (0.7)\n")
  cat("   Current configuration is already optimal for this dataset\n")
}

# Confidence analysis for edge cases
cat("\n🔍 CONFIDENCE SCORE ANALYSIS\n")
cat("=============================\n")

edge_cases <- results[results$combined_conf >= 0.59 & results$combined_conf <= 0.75, ]
if (nrow(edge_cases) > 0) {
  cat("Cases near threshold boundary:\n")
  for (i in 1:nrow(edge_cases)) {
    case_id <- edge_cases$incident_id[i]
    conf <- edge_cases$combined_conf[i]
    le_conf <- edge_cases$confidence_le[i]
    cme_conf <- edge_cases$confidence_cme[i]
    actual_ipv_case <- ifelse(edge_cases$actual_le[i] == 1 | edge_cases$actual_cme[i] == 1, "IPV", "No IPV")
    
    cat(sprintf("  %s: Combined=%.3f (LE=%.3f, CME=%.3f) - Actual: %s\n",
                case_id, conf, le_conf, cme_conf, actual_ipv_case))
  }
  
  cat("\nPattern: Both false negatives have very low LE confidence (0.05) but high CME confidence (0.96)\n")
  cat("Weighted average: 0.4 × 0.05 + 0.6 × 0.96 = 0.596\n")
  cat("Suggests: CME narratives more reliable for these edge cases\n")
}

# Weight optimization suggestion
cat("\n⚙️ WEIGHT OPTIMIZATION SUGGESTION\n")
cat("==================================\n")
cat("Current weights: LE=0.4, CME=0.6\n")
cat("False negative pattern: Low LE confidence + High CME confidence\n")
cat("Consideration: Increase CME weight to 0.7-0.8 for cases where LE < 0.2?\n")
cat("Alternative: Implement confidence-adaptive weighting\n")

# Save comprehensive results
optimization_results <- list(
  threshold_analysis = results_table,
  optimal_threshold = optimal_threshold,
  current_threshold = 0.7,
  false_negative_cases = fn_cases,
  improvement_summary = list(
    f1_improvement = optimal_metrics$f1 - current_metrics$f1,
    recall_improvement = optimal_metrics$recall - current_metrics$recall,
    precision_change = optimal_metrics$precision - current_metrics$precision,
    additional_cases_detected = current_metrics$fn - optimal_metrics$fn,
    additional_false_positives = optimal_metrics$fp - current_metrics$fp
  ),
  edge_cases = edge_cases
)

save(optimization_results, file = "tests/test_results/final_optimization_results.RData")

cat("\n💾 Complete optimization analysis saved to: final_optimization_results.RData\n")
cat("✅ Analysis complete!\n")