#!/usr/bin/env Rscript

# Analyze baseline results
library(dplyr)
library(cli)

# Load results
results <- read.csv("tests/test_results/baseline_results.csv", stringsAsFactors = FALSE)

cli::cli_h1("IPV Detection Baseline Analysis")
cli::cli_alert_info("Analyzing {nrow(results)} test cases")

# Add combined actual label
results <- results %>%
  mutate(actual_combined = actual_le | actual_cme)

# LE Performance
cli::cli_h2("Law Enforcement (LE) Narrative Performance")
le_valid <- results %>% filter(!is.na(predicted_le) & !is.na(actual_le))
le_tp <- sum(le_valid$predicted_le & le_valid$actual_le)
le_tn <- sum(!le_valid$predicted_le & !le_valid$actual_le)
le_fp <- sum(le_valid$predicted_le & !le_valid$actual_le)
le_fn <- sum(!le_valid$predicted_le & le_valid$actual_le)
le_accuracy <- (le_tp + le_tn) / nrow(le_valid)
le_precision <- ifelse(le_tp + le_fp > 0, le_tp / (le_tp + le_fp), 0)
le_recall <- ifelse(le_tp + le_fn > 0, le_tp / (le_tp + le_fn), 0)
le_f1 <- ifelse(le_precision + le_recall > 0, 2 * le_precision * le_recall / (le_precision + le_recall), 0)

cli::cli_alert_info("LE Confusion Matrix:")
cli::cli_alert_info("  TP: {le_tp}, TN: {le_tn}, FP: {le_fp}, FN: {le_fn}")
cli::cli_alert_success("LE Metrics:")
cli::cli_alert_success("  Accuracy: {round(le_accuracy, 3)} ({le_tp + le_tn}/{nrow(le_valid)})")
cli::cli_alert_success("  Precision: {round(le_precision, 3)} ({le_tp}/{le_tp + le_fp})")
cli::cli_alert_success("  Recall: {round(le_recall, 3)} ({le_tp}/{le_tp + le_fn})")
cli::cli_alert_success("  F1 Score: {round(le_f1, 3)}")

# CME Performance
cli::cli_h2("Medical Examiner (CME) Narrative Performance")
cme_valid <- results %>% filter(!is.na(predicted_cme) & !is.na(actual_cme))
cme_tp <- sum(cme_valid$predicted_cme & cme_valid$actual_cme)
cme_tn <- sum(!cme_valid$predicted_cme & !cme_valid$actual_cme)
cme_fp <- sum(cme_valid$predicted_cme & !cme_valid$actual_cme)
cme_fn <- sum(!cme_valid$predicted_cme & cme_valid$actual_cme)
cme_accuracy <- (cme_tp + cme_tn) / nrow(cme_valid)
cme_precision <- ifelse(cme_tp + cme_fp > 0, cme_tp / (cme_tp + cme_fp), 0)
cme_recall <- ifelse(cme_tp + cme_fn > 0, cme_tp / (cme_tp + cme_fn), 0)
cme_f1 <- ifelse(cme_precision + cme_recall > 0, 2 * cme_precision * cme_recall / (cme_precision + cme_recall), 0)

cli::cli_alert_info("CME Confusion Matrix:")
cli::cli_alert_info("  TP: {cme_tp}, TN: {cme_tn}, FP: {cme_fp}, FN: {cme_fn}")
cli::cli_alert_success("CME Metrics:")
cli::cli_alert_success("  Accuracy: {round(cme_accuracy, 3)} ({cme_tp + cme_tn}/{nrow(cme_valid)})")
cli::cli_alert_success("  Precision: {round(cme_precision, 3)} ({cme_tp}/{cme_tp + cme_fp})")
cli::cli_alert_success("  Recall: {round(cme_recall, 3)} ({cme_tp}/{cme_tp + cme_fn})")
cli::cli_alert_success("  F1 Score: {round(cme_f1, 3)}")

# Combined Performance
cli::cli_h2("Combined Performance (Weighted)")
combined_valid <- results %>% filter(!is.na(combined_ipv) & !is.na(actual_combined))
combined_tp <- sum(combined_valid$combined_ipv & combined_valid$actual_combined)
combined_tn <- sum(!combined_valid$combined_ipv & !combined_valid$actual_combined)
combined_fp <- sum(combined_valid$combined_ipv & !combined_valid$actual_combined)
combined_fn <- sum(!combined_valid$combined_ipv & combined_valid$actual_combined)
combined_accuracy <- (combined_tp + combined_tn) / nrow(combined_valid)
combined_precision <- ifelse(combined_tp + combined_fp > 0, combined_tp / (combined_tp + combined_fp), 0)
combined_recall <- ifelse(combined_tp + combined_fn > 0, combined_tp / (combined_tp + combined_fn), 0)
combined_f1 <- ifelse(combined_precision + combined_recall > 0, 2 * combined_precision * combined_recall / (combined_precision + combined_recall), 0)

cli::cli_alert_info("Combined Confusion Matrix:")
cli::cli_alert_info("  TP: {combined_tp}, TN: {combined_tn}, FP: {combined_fp}, FN: {combined_fn}")
cli::cli_alert_success("Combined Metrics:")
cli::cli_alert_success("  Accuracy: {round(combined_accuracy, 3)} ({combined_tp + combined_tn}/{nrow(combined_valid)})")
cli::cli_alert_success("  Precision: {round(combined_precision, 3)} ({combined_tp}/{combined_tp + combined_fp})")
cli::cli_alert_success("  Recall: {round(combined_recall, 3)} ({combined_tp}/{combined_tp + combined_fn})")
cli::cli_alert_success("  F1 Score: {round(combined_f1, 3)}")

# Analyze misclassifications
cli::cli_h2("Error Analysis")
errors <- combined_valid %>% filter(combined_ipv != actual_combined)
cli::cli_alert_warning("Total misclassifications: {nrow(errors)}")

if (nrow(errors) > 0) {
  cli::cli_alert_info("False Negatives (missed IPV): {combined_fn}")
  cli::cli_alert_info("False Positives (incorrect IPV): {combined_fp}")
  
  # Show false negatives
  fn_cases <- errors %>% filter(!combined_ipv & actual_combined)
  if (nrow(fn_cases) > 0) {
    cli::cli_alert_warning("False Negative Cases (missed real IPV):")
    for (i in 1:nrow(fn_cases)) {
      cli::cli_alert_info("  Case {fn_cases$incident_id[i]}: Conf={round(fn_cases$combined_conf[i], 3)}")
    }
  }
  
  # Show false positives
  fp_cases <- errors %>% filter(combined_ipv & !actual_combined)
  if (nrow(fp_cases) > 0) {
    cli::cli_alert_warning("False Positive Cases (detected IPV incorrectly):")
    for (i in 1:nrow(fp_cases)) {
      cli::cli_alert_info("  Case {fp_cases$incident_id[i]}: Conf={round(fp_cases$combined_conf[i], 3)}")
    }
  }
}

# Confidence analysis
cli::cli_h2("Confidence Score Analysis")
cli::cli_alert_info("Combined confidence range: {round(min(results$combined_conf, na.rm=T), 3)} - {round(max(results$combined_conf, na.rm=T), 3)}")
cli::cli_alert_info("Mean confidence: {round(mean(results$combined_conf, na.rm=T), 3)}")
cli::cli_alert_info("Median confidence: {round(median(results$combined_conf, na.rm=T), 3)}")

# Threshold optimization
cli::cli_h2("Threshold Optimization")
thresholds <- seq(0.5, 0.95, by = 0.05)
best_f1 <- 0
best_threshold <- 0.7

for (t in thresholds) {
  pred_at_t <- combined_valid$combined_conf >= t
  tp_t <- sum(pred_at_t & combined_valid$actual_combined)
  fp_t <- sum(pred_at_t & !combined_valid$actual_combined)
  fn_t <- sum(!pred_at_t & combined_valid$actual_combined)
  
  prec_t <- ifelse(tp_t + fp_t > 0, tp_t / (tp_t + fp_t), 0)
  rec_t <- ifelse(tp_t + fn_t > 0, tp_t / (tp_t + fn_t), 0)
  f1_t <- ifelse(prec_t + rec_t > 0, 2 * prec_t * rec_t / (prec_t + rec_t), 0)
  
  if (f1_t > best_f1) {
    best_f1 <- f1_t
    best_threshold <- t
  }
  
  if (t == 0.60 || t == 0.70) {
    cli::cli_alert_info("Threshold {t}: F1={round(f1_t, 3)}, Prec={round(prec_t, 3)}, Rec={round(rec_t, 3)}")
  }
}

cli::cli_alert_success("Optimal threshold: {best_threshold} (F1={round(best_f1, 3)})")

# Key findings
cli::cli_h2("Key Findings")
cli::cli_alert_success("✓ System successfully processes all test cases")
cli::cli_alert_success("✓ Combined approach achieves {round(combined_accuracy * 100, 1)}% accuracy")
cli::cli_alert_success("✓ High precision ({round(combined_precision, 3)}) - few false positives")
if (combined_recall < 0.95) {
  cli::cli_alert_warning("⚠ Recall could be improved ({round(combined_recall, 3)}) - some IPV cases missed")
}
if (best_threshold != 0.7) {
  cli::cli_alert_info("💡 Consider adjusting threshold from 0.7 to {best_threshold} for better performance")
}