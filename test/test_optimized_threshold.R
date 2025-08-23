# Test Optimized Threshold Configuration
# =====================================

# Load results
results <- read.csv("tests/test_results/baseline_results.csv", stringsAsFactors = FALSE)

cat("🔧 TESTING OPTIMIZED THRESHOLD\n")
cat("==============================\n\n")

# Current configuration
current_threshold <- 0.7
proposed_threshold <- 0.6

# Calculate actual IPV (either LE or CME positive)
actual_ipv <- ifelse(results$actual_le == 1 | results$actual_cme == 1, 1, 0)

# Test current configuration
current_pred <- ifelse(results$combined_conf >= current_threshold, 1, 0)
current_tp <- sum(current_pred == 1 & actual_ipv == 1)
current_tn <- sum(current_pred == 0 & actual_ipv == 0) 
current_fp <- sum(current_pred == 1 & actual_ipv == 0)
current_fn <- sum(current_pred == 0 & actual_ipv == 1)

current_accuracy <- (current_tp + current_tn) / length(actual_ipv)
current_precision <- if (current_tp + current_fp > 0) current_tp / (current_tp + current_fp) else 0
current_recall <- if (current_tp + current_fn > 0) current_tp / (current_tp + current_fn) else 0
current_f1 <- if (current_precision + current_recall > 0) 2 * (current_precision * current_recall) / (current_precision + current_recall) else 0

# Test proposed configuration  
proposed_pred <- ifelse(results$combined_conf >= proposed_threshold, 1, 0)
proposed_tp <- sum(proposed_pred == 1 & actual_ipv == 1)
proposed_tn <- sum(proposed_pred == 0 & actual_ipv == 0)
proposed_fp <- sum(proposed_pred == 1 & actual_ipv == 0)
proposed_fn <- sum(proposed_pred == 0 & actual_ipv == 1)

proposed_accuracy <- (proposed_tp + proposed_tn) / length(actual_ipv)
proposed_precision <- if (proposed_tp + proposed_fp > 0) proposed_tp / (proposed_tp + proposed_fp) else 0
proposed_recall <- if (proposed_tp + proposed_fn > 0) proposed_tp / (proposed_tp + proposed_fn) else 0
proposed_f1 <- if (proposed_precision + proposed_recall > 0) 2 * (proposed_precision * proposed_recall) / (proposed_precision + proposed_recall) else 0

# Print comparison
cat("THRESHOLD COMPARISON\n")
cat("====================\n\n")

comparison_df <- data.frame(
  Configuration = c("Current (0.7)", "Proposed (0.6)"),
  Accuracy = c(current_accuracy, proposed_accuracy),
  Precision = c(current_precision, proposed_precision),  
  Recall = c(current_recall, proposed_recall),
  F1_Score = c(current_f1, proposed_f1),
  True_Pos = c(current_tp, proposed_tp),
  False_Pos = c(current_fp, proposed_fp),
  False_Neg = c(current_fn, proposed_fn),
  Cases_Predicted = c(sum(current_pred), sum(proposed_pred))
)

print(comparison_df)

# Improvement analysis
cat("\n📈 IMPROVEMENT ANALYSIS\n")
cat("========================\n")

accuracy_improvement <- proposed_accuracy - current_accuracy
recall_improvement <- proposed_recall - current_recall
f1_improvement <- proposed_f1 - current_f1
precision_change <- proposed_precision - current_precision

cat(sprintf("Accuracy Improvement: %+.3f (%+.1f%%)\n", accuracy_improvement, accuracy_improvement * 100))
cat(sprintf("Recall Improvement:   %+.3f (%+.1f%%)\n", recall_improvement, recall_improvement * 100))
cat(sprintf("F1 Score Improvement: %+.3f (%+.1f%%)\n", f1_improvement, f1_improvement * 100))
cat(sprintf("Precision Change:     %+.3f (%+.1f%%)\n", precision_change, precision_change * 100))

# Identify cases affected by threshold change
affected_cases <- results[results$combined_conf >= proposed_threshold & results$combined_conf < current_threshold, ]

cat("\n🎯 CASES AFFECTED BY THRESHOLD CHANGE\n")
cat("=====================================\n")

if (nrow(affected_cases) > 0) {
  cat(sprintf("Cases now classified as IPV: %d\n", nrow(affected_cases)))
  for (i in 1:nrow(affected_cases)) {
    case_id <- affected_cases$incident_id[i]
    conf <- affected_cases$combined_conf[i]
    actual_le <- affected_cases$actual_le[i] 
    actual_cme <- affected_cases$actual_cme[i]
    cat(sprintf("  Case %s: Confidence=%.3f, Actual_LE=%s, Actual_CME=%s\n", 
                case_id, conf, actual_le, actual_cme))
  }
} else {
  cat("No cases affected by threshold change\n")
}

# Risk assessment
cat("\n⚠️ RISK ASSESSMENT\n")
cat("==================\n")

# Check if any new false positives would be introduced
if (proposed_fp > current_fp) {
  cat("❌ WARNING: Proposed threshold introduces false positives\n")
  
  new_fp_cases <- results[proposed_pred == 1 & actual_ipv == 0 & current_pred == 0, ]
  if (nrow(new_fp_cases) > 0) {
    cat("New false positive cases:\n")
    for (i in 1:nrow(new_fp_cases)) {
      cat(sprintf("  Case %s: Confidence=%.3f\n", new_fp_cases$incident_id[i], new_fp_cases$combined_conf[i]))
    }
  }
  
} else if (proposed_fp == current_fp) {
  cat("✅ No new false positives introduced\n")
} else {
  cat("✅ Fewer false positives with new threshold\n")
}

# Check false negatives
if (proposed_fn < current_fn) {
  eliminated_fn <- current_fn - proposed_fn
  cat(sprintf("✅ Eliminates %d false negative(s)\n", eliminated_fn))
} else if (proposed_fn == current_fn) {
  cat("⚠️ No change in false negatives\n")
} else {
  cat("❌ WARNING: Increases false negatives\n")
}

# Statistical significance of improvement
cat("\n📊 STATISTICAL VALIDATION\n")
cat("=========================\n")

# McNemar's test for paired proportions (simplified)
# This tests if the improvement is statistically significant
correct_current <- (current_pred == actual_ipv)
correct_proposed <- (proposed_pred == actual_ipv)

improved_cases <- sum(correct_proposed & !correct_current)
degraded_cases <- sum(correct_current & !correct_proposed)

cat(sprintf("Cases improved by threshold change: %d\n", improved_cases))
cat(sprintf("Cases degraded by threshold change: %d\n", degraded_cases))

if (improved_cases > degraded_cases) {
  cat("✅ Net improvement in classification accuracy\n")
} else if (improved_cases == degraded_cases) {
  cat("⚪ No net change in classification accuracy\n") 
} else {
  cat("❌ Net degradation in classification accuracy\n")
}

# Confidence interval for new accuracy
n <- length(actual_ipv)
correct_proposed_count <- sum(correct_proposed)
se_accuracy <- sqrt(proposed_accuracy * (1 - proposed_accuracy) / n)
ci_lower <- proposed_accuracy - 1.96 * se_accuracy
ci_upper <- proposed_accuracy + 1.96 * se_accuracy

cat(sprintf("Proposed accuracy: %.3f (95%% CI: %.3f - %.3f)\n", 
            proposed_accuracy, ci_lower, ci_upper))

# Final recommendation
cat("\n🏆 FINAL RECOMMENDATION\n")
cat("=======================\n")

if (proposed_f1 > current_f1 && proposed_fp <= current_fp) {
  cat("✅ RECOMMENDED: Adopt threshold of 0.6\n")
  cat("   Reasons:\n")
  cat(sprintf("   - Improves F1 score by %.3f\n", f1_improvement))
  cat(sprintf("   - Improves recall by %.3f\n", recall_improvement))
  if (proposed_fp == current_fp) {
    cat("   - Maintains precision (no new false positives)\n")
  }
  cat(sprintf("   - Affects %d additional cases\n", nrow(affected_cases)))
  
} else if (proposed_f1 > current_f1 && proposed_fp > current_fp) {
  cat("⚠️ CONDITIONAL RECOMMENDATION: Consider threshold of 0.6\n")
  cat("   Trade-offs:\n")
  cat(sprintf("   + Improves F1 score by %.3f\n", f1_improvement))
  cat(sprintf("   + Improves recall by %.3f\n", recall_improvement))
  cat(sprintf("   - Introduces %d false positive(s)\n", proposed_fp - current_fp))
  cat("   Decision depends on cost of false positives vs false negatives\n")
  
} else {
  cat("❌ NOT RECOMMENDED: Keep current threshold of 0.7\n")
  cat("   Reasons:\n")
  if (proposed_f1 <= current_f1) {
    cat(sprintf("   - F1 score does not improve (%.3f)\n", f1_improvement))
  }
  if (proposed_fp > current_fp) {
    cat(sprintf("   - Introduces %d false positive(s)\n", proposed_fp - current_fp))
  }
}

cat("\n💾 Threshold analysis saved\n")

# Save analysis
threshold_analysis <- list(
  current = list(
    threshold = current_threshold,
    accuracy = current_accuracy,
    precision = current_precision,
    recall = current_recall,
    f1 = current_f1,
    tp = current_tp, tn = current_tn, fp = current_fp, fn = current_fn
  ),
  proposed = list(
    threshold = proposed_threshold,
    accuracy = proposed_accuracy,
    precision = proposed_precision, 
    recall = proposed_recall,
    f1 = proposed_f1,
    tp = proposed_tp, tn = proposed_tn, fp = proposed_fp, fn = proposed_fn
  ),
  affected_cases = affected_cases,
  improvements = list(
    accuracy = accuracy_improvement,
    precision = precision_change,
    recall = recall_improvement,
    f1 = f1_improvement
  )
)

save(threshold_analysis, file = "tests/test_results/threshold_optimization.RData")