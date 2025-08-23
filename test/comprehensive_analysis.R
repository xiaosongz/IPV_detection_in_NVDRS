# Comprehensive IPV Detection Analysis Framework
# ==============================================

library(dplyr)
library(ggplot2)
library(pROC)
library(caret)
library(corrplot)
library(gridExtra)
library(knitr)
library(binom)

# 1. PERFORMANCE METRICS CALCULATION
# ==================================

#' Calculate comprehensive performance metrics
#'
#' @param actual Binary vector of actual labels (0/1)
#' @param predicted Binary vector of predicted labels (0/1) 
#' @param confidence Numeric vector of confidence scores (0-1)
#' @param label Character label for the method
#' @return List with all performance metrics
calculate_performance_metrics <- function(actual, predicted, confidence, label) {
  
  # Handle missing values
  valid_idx <- !is.na(actual) & !is.na(predicted) & !is.na(confidence)
  actual <- actual[valid_idx]
  predicted <- predicted[valid_idx]
  confidence <- confidence[valid_idx]
  
  if (length(actual) == 0) {
    warning(paste("No valid cases for", label))
    return(NULL)
  }
  
  # Confusion matrix
  cm <- confusionMatrix(factor(predicted, levels = c(0, 1)), 
                       factor(actual, levels = c(0, 1)), 
                       positive = "1")
  
  # Basic metrics
  tp <- cm$table[2, 2]  # True Positive
  tn <- cm$table[1, 1]  # True Negative  
  fp <- cm$table[2, 1]  # False Positive
  fn <- cm$table[1, 2]  # False Negative
  
  accuracy <- (tp + tn) / (tp + tn + fp + fn)
  precision <- if (tp + fp > 0) tp / (tp + fp) else 0
  recall <- if (tp + fn > 0) tp / (tp + fn) else 0
  specificity <- if (tn + fp > 0) tn / (tn + fp) else 0
  f1 <- if (precision + recall > 0) 2 * (precision * recall) / (precision + recall) else 0
  
  # ROC Analysis
  roc_obj <- NULL
  auc <- NA
  if (length(unique(actual)) > 1) {  # Need both classes for ROC
    tryCatch({
      roc_obj <- roc(actual, confidence, quiet = TRUE)
      auc <- as.numeric(auc(roc_obj))
    }, error = function(e) {
      warning(paste("ROC calculation failed for", label, ":", e$message))
    })
  }
  
  # Confidence intervals using Wilson method
  n <- length(actual)
  ci_accuracy <- binom.confint(sum(predicted == actual), n, method = "wilson")
  ci_precision <- if (tp + fp > 0) binom.confint(tp, tp + fp, method = "wilson") else data.frame(lower = 0, upper = 0)
  ci_recall <- if (tp + fn > 0) binom.confint(tp, tp + fn, method = "wilson") else data.frame(lower = 0, upper = 0)
  
  return(list(
    label = label,
    n = n,
    confusion_matrix = cm$table,
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    specificity = specificity,
    f1 = f1,
    auc = auc,
    roc_obj = roc_obj,
    tp = tp, tn = tn, fp = fp, fn = fn,
    ci_accuracy = ci_accuracy,
    ci_precision = ci_precision,
    ci_recall = ci_recall,
    mean_confidence = mean(confidence),
    confidence_dist = list(
      min = min(confidence),
      q25 = quantile(confidence, 0.25),
      median = median(confidence),
      q75 = quantile(confidence, 0.75),
      max = max(confidence)
    )
  ))
}

#' Analyze results for all three methods (LE, CME, Combined)
analyze_all_methods <- function(results_df) {
  
  cat("📊 Calculating Performance Metrics...\n")
  
  # LE Analysis
  le_metrics <- calculate_performance_metrics(
    actual = results_df$actual_le,
    predicted = results_df$predicted_le, 
    confidence = results_df$confidence_le,
    label = "Law Enforcement"
  )
  
  # CME Analysis  
  cme_metrics <- calculate_performance_metrics(
    actual = results_df$actual_cme,
    predicted = results_df$predicted_cme,
    confidence = results_df$confidence_cme, 
    label = "Medical Examiner"
  )
  
  # Combined Analysis
  combined_metrics <- calculate_performance_metrics(
    actual = ifelse(results_df$actual_le == 1 | results_df$actual_cme == 1, 1, 0),
    predicted = results_df$combined_ipv,
    confidence = results_df$combined_conf,
    label = "Combined Weighted"
  )
  
  return(list(
    le = le_metrics,
    cme = cme_metrics, 
    combined = combined_metrics,
    raw_data = results_df
  ))
}

# 2. VISUALIZATION FUNCTIONS
# ==========================

#' Create comprehensive performance visualization dashboard
create_performance_dashboard <- function(analysis_results) {
  
  # Extract metrics for plotting
  metrics_df <- data.frame(
    Method = c("Law Enforcement", "Medical Examiner", "Combined Weighted"),
    Accuracy = c(analysis_results$le$accuracy, analysis_results$cme$accuracy, analysis_results$combined$accuracy),
    Precision = c(analysis_results$le$precision, analysis_results$cme$precision, analysis_results$combined$precision),
    Recall = c(analysis_results$le$recall, analysis_results$cme$recall, analysis_results$combined$recall),
    F1 = c(analysis_results$le$f1, analysis_results$cme$f1, analysis_results$combined$f1),
    AUC = c(analysis_results$le$auc, analysis_results$cme$auc, analysis_results$combined$auc)
  ) %>%
    tidyr::pivot_longer(cols = -Method, names_to = "Metric", values_to = "Value")
  
  # 1. Performance Metrics Comparison
  p1 <- ggplot(metrics_df, aes(x = Method, y = Value, fill = Metric)) +
    geom_bar(stat = "identity", position = "dodge") +
    facet_wrap(~Metric, scales = "free_y") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    labs(title = "Performance Metrics Comparison", 
         subtitle = "Across LE, CME, and Combined Methods") +
    scale_fill_brewer(type = "qual", palette = "Set2")
  
  # 2. Confusion Matrices Heatmap
  plot_confusion_heatmaps <- function(results) {
    plots <- list()
    
    for (method in c("le", "cme", "combined")) {
      cm <- results[[method]]$confusion_matrix
      cm_df <- as.data.frame(as.table(cm))
      colnames(cm_df) <- c("Predicted", "Actual", "Count")
      
      plots[[method]] <- ggplot(cm_df, aes(x = Predicted, y = Actual, fill = Count)) +
        geom_tile() +
        geom_text(aes(label = Count), color = "white", size = 5) +
        scale_fill_gradient(low = "lightblue", high = "darkblue") +
        labs(title = paste("Confusion Matrix:", results[[method]]$label)) +
        theme_minimal()
    }
    
    return(plots)
  }
  
  cm_plots <- plot_confusion_heatmaps(analysis_results)
  
  # 3. ROC Curves
  p_roc <- ggplot() +
    labs(title = "ROC Curves Comparison", x = "False Positive Rate", y = "True Positive Rate") +
    theme_minimal()
  
  colors <- c("red", "blue", "green")
  methods <- c("le", "cme", "combined")
  
  for (i in seq_along(methods)) {
    method <- methods[i]
    if (!is.null(analysis_results[[method]]$roc_obj)) {
      roc_data <- data.frame(
        fpr = 1 - analysis_results[[method]]$roc_obj$specificities,
        tpr = analysis_results[[method]]$roc_obj$sensitivities
      )
      p_roc <- p_roc + 
        geom_line(data = roc_data, aes(x = fpr, y = tpr), 
                 color = colors[i], size = 1) +
        annotate("text", x = 0.6, y = 0.2 + i * 0.1, 
                label = paste(analysis_results[[method]]$label, 
                            "AUC =", round(analysis_results[[method]]$auc, 3)),
                color = colors[i])
    }
  }
  
  p_roc <- p_roc + geom_abline(intercept = 0, slope = 1, linetype = "dashed", alpha = 0.5)
  
  # 4. Confidence Score Distributions
  conf_data <- data.frame(
    Method = rep(c("LE", "CME", "Combined"), each = nrow(analysis_results$raw_data)),
    Confidence = c(analysis_results$raw_data$confidence_le,
                  analysis_results$raw_data$confidence_cme, 
                  analysis_results$raw_data$combined_conf),
    Actual = rep(ifelse(analysis_results$raw_data$actual_le == 1 | 
                       analysis_results$raw_data$actual_cme == 1, "IPV", "No IPV"), 3)
  )
  
  p4 <- ggplot(conf_data, aes(x = Confidence, fill = Actual)) +
    geom_histogram(alpha = 0.7, bins = 10) +
    facet_wrap(~Method, scales = "free_y") +
    theme_minimal() +
    labs(title = "Confidence Score Distributions by Method",
         x = "Confidence Score", y = "Count") +
    scale_fill_manual(values = c("IPV" = "red", "No IPV" = "blue"))
  
  return(list(
    metrics = p1,
    confusion_le = cm_plots$le,
    confusion_cme = cm_plots$cme, 
    confusion_combined = cm_plots$combined,
    roc = p_roc,
    confidence_dist = p4
  ))
}

# 3. ERROR ANALYSIS FUNCTIONS  
# ===========================

#' Analyze error patterns and common indicators
analyze_error_patterns <- function(results_df) {
  
  cat("🔍 Analyzing Error Patterns...\n")
  
  # Create actual combined IPV flag
  actual_ipv <- ifelse(results_df$actual_le == 1 | results_df$actual_cme == 1, 1, 0)
  
  # Identify error cases
  errors <- results_df %>%
    mutate(
      actual_ipv = actual_ipv,
      le_error = (predicted_le != actual_le),
      cme_error = (predicted_cme != actual_cme), 
      combined_error = (combined_ipv != actual_ipv),
      
      # Error types
      le_fp = (predicted_le == 1 & actual_le == 0),
      le_fn = (predicted_le == 0 & actual_le == 1),
      cme_fp = (predicted_cme == 1 & actual_cme == 0),
      cme_fn = (predicted_cme == 0 & actual_cme == 1),
      combined_fp = (combined_ipv == 1 & actual_ipv == 0),
      combined_fn = (combined_ipv == 0 & actual_ipv == 1)
    )
  
  # Error summary
  error_summary <- list(
    le = list(
      total_errors = sum(errors$le_error, na.rm = TRUE),
      false_positives = sum(errors$le_fp, na.rm = TRUE),
      false_negatives = sum(errors$le_fn, na.rm = TRUE)
    ),
    cme = list(
      total_errors = sum(errors$cme_error, na.rm = TRUE), 
      false_positives = sum(errors$cme_fp, na.rm = TRUE),
      false_negatives = sum(errors$cme_fn, na.rm = TRUE)
    ),
    combined = list(
      total_errors = sum(errors$combined_error, na.rm = TRUE),
      false_positives = sum(errors$combined_fp, na.rm = TRUE),
      false_negatives = sum(errors$combined_fn, na.rm = TRUE)
    )
  )
  
  # Indicator analysis (if available)
  indicator_analysis <- NULL
  if ("le_indicators" %in% colnames(results_df) && "cme_indicators" %in% colnames(results_df)) {
    
    # Extract and analyze common indicators in FP/FN cases
    fp_cases <- errors[errors$combined_fp, ]
    fn_cases <- errors[errors$combined_fn, ]
    tp_cases <- errors[errors$combined_ipv == 1 & errors$actual_ipv == 1, ]
    tn_cases <- errors[errors$combined_ipv == 0 & errors$actual_ipv == 0, ]
    
    # Function to extract indicators from text
    extract_indicators <- function(indicator_text) {
      if (is.na(indicator_text) || indicator_text == "") return(character(0))
      # Assume indicators are comma-separated
      trimws(strsplit(as.character(indicator_text), ",")[[1]])
    }
    
    # Most common indicators by case type
    indicator_analysis <- list(
      false_positives = {
        if (nrow(fp_cases) > 0) {
          all_indicators <- unlist(lapply(c(fp_cases$le_indicators, fp_cases$cme_indicators), extract_indicators))
          table(all_indicators)
        } else NULL
      },
      false_negatives = {
        if (nrow(fn_cases) > 0) {
          all_indicators <- unlist(lapply(c(fn_cases$le_indicators, fn_cases$cme_indicators), extract_indicators))
          table(all_indicators)
        } else NULL
      },
      true_positives = {
        if (nrow(tp_cases) > 0) {
          all_indicators <- unlist(lapply(c(tp_cases$le_indicators, tp_cases$cme_indicators), extract_indicators))
          table(all_indicators)
        } else NULL
      }
    )
  }
  
  return(list(
    error_cases = errors,
    error_summary = error_summary,
    indicator_analysis = indicator_analysis
  ))
}

# 4. STATISTICAL SIGNIFICANCE TESTS
# =================================

#' Test statistical significance of performance
test_statistical_significance <- function(analysis_results, alpha = 0.05) {
  
  cat("📈 Testing Statistical Significance...\n")
  
  results <- list()
  
  for (method in c("le", "cme", "combined")) {
    metrics <- analysis_results[[method]]
    n <- metrics$n
    
    # Test if accuracy is significantly better than random (0.5)
    accuracy_test <- binom.test(sum(metrics$tp + metrics$tn), n, p = 0.5, alternative = "greater")
    
    # Test if precision is significantly better than baseline
    if (metrics$tp + metrics$fp > 0) {
      precision_test <- binom.test(metrics$tp, metrics$tp + metrics$fp, p = 0.5, alternative = "greater")
    } else {
      precision_test <- NULL
    }
    
    # Test if recall is significantly better than baseline  
    if (metrics$tp + metrics$fn > 0) {
      recall_test <- binom.test(metrics$tp, metrics$tp + metrics$fn, p = 0.5, alternative = "greater")
    } else {
      recall_test <- NULL
    }
    
    # Power analysis - detect minimum effect size
    power_analysis <- tryCatch({
      # Simple effect size calculation
      effect_size <- abs(metrics$accuracy - 0.5) / sqrt(0.5 * 0.5 / n)
      list(effect_size = effect_size, adequate = effect_size > 0.5)
    }, error = function(e) NULL)
    
    results[[method]] <- list(
      sample_size = n,
      accuracy_test = accuracy_test,
      precision_test = precision_test, 
      recall_test = recall_test,
      power_analysis = power_analysis,
      significant_accuracy = if (!is.null(accuracy_test)) accuracy_test$p.value < alpha else FALSE,
      significant_precision = if (!is.null(precision_test)) precision_test$p.value < alpha else FALSE,
      significant_recall = if (!is.null(recall_test)) recall_test$p.value < alpha else FALSE
    )
  }
  
  return(results)
}

# 5. OPTIMIZATION RECOMMENDATIONS
# ===============================

#' Find optimal threshold and weights
find_optimal_configuration <- function(results_df) {
  
  cat("⚙️ Finding Optimal Configuration...\n")
  
  actual_ipv <- ifelse(results_df$actual_le == 1 | results_df$actual_cme == 1, 1, 0)
  
  # Grid search for optimal threshold
  thresholds <- seq(0.1, 0.9, 0.05)
  threshold_results <- data.frame()
  
  for (thresh in thresholds) {
    pred <- ifelse(results_df$combined_conf >= thresh, 1, 0)
    
    if (length(unique(pred)) > 1 && length(unique(actual_ipv)) > 1) {
      cm <- confusionMatrix(factor(pred, levels = c(0,1)), factor(actual_ipv, levels = c(0,1)), positive = "1")
      
      threshold_results <- rbind(threshold_results, data.frame(
        threshold = thresh,
        accuracy = cm$overall["Accuracy"],
        precision = cm$byClass["Precision"],
        recall = cm$byClass["Recall"],
        f1 = cm$byClass["F1"],
        specificity = cm$byClass["Specificity"]
      ))
    }
  }
  
  # Find optimal threshold (maximize F1)
  if (nrow(threshold_results) > 0) {
    optimal_threshold <- threshold_results[which.max(threshold_results$f1), ]
  } else {
    optimal_threshold <- NULL
  }
  
  # Grid search for optimal LE/CME weights
  weight_results <- data.frame()
  le_weights <- seq(0.1, 0.9, 0.1)
  
  for (le_weight in le_weights) {
    cme_weight <- 1 - le_weight
    
    # Calculate weighted confidence
    weighted_conf <- le_weight * results_df$confidence_le + cme_weight * results_df$confidence_cme
    pred <- ifelse(weighted_conf >= 0.7, 1, 0)  # Use current threshold
    
    if (length(unique(pred)) > 1 && length(unique(actual_ipv)) > 1) {
      cm <- confusionMatrix(factor(pred, levels = c(0,1)), factor(actual_ipv, levels = c(0,1)), positive = "1")
      
      weight_results <- rbind(weight_results, data.frame(
        le_weight = le_weight,
        cme_weight = cme_weight,
        accuracy = cm$overall["Accuracy"],
        precision = cm$byClass["Precision"], 
        recall = cm$byClass["Recall"],
        f1 = cm$byClass["F1"]
      ))
    }
  }
  
  # Find optimal weights (maximize F1)
  if (nrow(weight_results) > 0) {
    optimal_weights <- weight_results[which.max(weight_results$f1), ]
  } else {
    optimal_weights <- NULL
  }
  
  return(list(
    threshold_analysis = threshold_results,
    optimal_threshold = optimal_threshold,
    weight_analysis = weight_results, 
    optimal_weights = optimal_weights
  ))
}

# 6. COMPREHENSIVE REPORT GENERATOR
# =================================

#' Generate comprehensive analysis report
generate_comprehensive_report <- function(results_csv_path) {
  
  cat("🚀 Starting Comprehensive IPV Detection Analysis\n")
  cat("================================================\n\n")
  
  # Load results
  cat("📂 Loading results from:", results_csv_path, "\n")
  results_df <- read.csv(results_csv_path, stringsAsFactors = FALSE)
  cat("✅ Loaded", nrow(results_df), "cases\n\n")
  
  # 1. Performance Analysis
  analysis_results <- analyze_all_methods(results_df)
  
  # 2. Error Analysis
  error_analysis <- analyze_error_patterns(results_df)
  
  # 3. Statistical Tests
  significance_tests <- test_statistical_significance(analysis_results)
  
  # 4. Optimization
  optimization <- find_optimal_configuration(results_df)
  
  # 5. Visualizations
  plots <- create_performance_dashboard(analysis_results)
  
  # Print Summary Report
  cat("\n" , "="*60, "\n")
  cat("COMPREHENSIVE IPV DETECTION ANALYSIS REPORT\n")
  cat("="*60, "\n\n")
  
  cat("📊 PERFORMANCE SUMMARY\n")
  cat("---------------------\n")
  for (method in c("le", "cme", "combined")) {
    metrics <- analysis_results[[method]]
    cat(sprintf("%-20s: Acc=%.3f, Prec=%.3f, Rec=%.3f, F1=%.3f, AUC=%.3f\n",
                metrics$label, metrics$accuracy, metrics$precision, 
                metrics$recall, metrics$f1, ifelse(is.na(metrics$auc), 0, metrics$auc)))
  }
  
  cat("\n🔍 ERROR ANALYSIS\n")
  cat("----------------\n")
  for (method in c("le", "cme", "combined")) {
    errors <- error_analysis$error_summary[[method]]
    cat(sprintf("%-20s: Total Errors=%d, FP=%d, FN=%d\n",
                analysis_results[[method]]$label, errors$total_errors, 
                errors$false_positives, errors$false_negatives))
  }
  
  cat("\n📈 STATISTICAL SIGNIFICANCE\n")
  cat("---------------------------\n")
  for (method in c("le", "cme", "combined")) {
    sig <- significance_tests[[method]]
    cat(sprintf("%-20s: Acc sig=%s, n=%d\n", 
                analysis_results[[method]]$label, 
                ifelse(sig$significant_accuracy, "YES", "NO"), sig$sample_size))
  }
  
  cat("\n⚙️ OPTIMIZATION RECOMMENDATIONS\n")
  cat("-------------------------------\n")
  if (!is.null(optimization$optimal_threshold)) {
    cat(sprintf("Optimal Threshold: %.2f (F1=%.3f)\n", 
                optimization$optimal_threshold$threshold, optimization$optimal_threshold$f1))
  }
  if (!is.null(optimization$optimal_weights)) {
    cat(sprintf("Optimal Weights: LE=%.1f, CME=%.1f (F1=%.3f)\n",
                optimization$optimal_weights$le_weight, optimization$optimal_weights$cme_weight,
                optimization$optimal_weights$f1))
  }
  
  cat("\n📈 VISUALIZATIONS GENERATED\n")
  cat("---------------------------\n")
  cat("- Performance metrics comparison\n")
  cat("- Confusion matrices for all methods\n") 
  cat("- ROC curves\n")
  cat("- Confidence score distributions\n")
  
  # Return all results for further analysis
  return(list(
    performance = analysis_results,
    errors = error_analysis,
    significance = significance_tests,
    optimization = optimization,
    plots = plots,
    raw_data = results_df
  ))
}

# 7. SAVE PLOTS FUNCTION
# ======================

#' Save all visualization plots
save_analysis_plots <- function(analysis_report, output_dir = "docs/analysis_plots") {
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  plots <- analysis_report$plots
  
  # Save individual plots
  ggsave(file.path(output_dir, "performance_metrics.png"), plots$metrics, width = 12, height = 8)
  ggsave(file.path(output_dir, "confusion_le.png"), plots$confusion_le, width = 6, height = 6)
  ggsave(file.path(output_dir, "confusion_cme.png"), plots$confusion_cme, width = 6, height = 6)
  ggsave(file.path(output_dir, "confusion_combined.png"), plots$confusion_combined, width = 6, height = 6)
  ggsave(file.path(output_dir, "roc_curves.png"), plots$roc, width = 8, height = 6)
  ggsave(file.path(output_dir, "confidence_distributions.png"), plots$confidence_dist, width = 12, height = 6)
  
  cat("📊 All plots saved to:", output_dir, "\n")
}

cat("✅ Comprehensive IPV Detection Analysis Framework Loaded\n")
cat("   Run: report <- generate_comprehensive_report('path/to/results.csv')\n")
cat("   Save plots: save_analysis_plots(report)\n")