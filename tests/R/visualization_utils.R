#' Visualization Utilities for IPV Detection Test Results
#' 
#' This module provides comprehensive visualization functions for analyzing
#' test results, including confusion matrices, ROC curves, calibration plots,
#' and performance comparisons.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(pROC)
  library(DBI)
  library(scales)
  library(viridis)
  library(patchwork)
})

#' Create Confusion Matrix Heatmap
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param narrative_type "LE", "CME", or "combined"
#' @return ggplot object
#' @export
plot_confusion_matrix <- function(conn, run_id, narrative_type = "combined") {
  
  # Get performance metrics
  metrics <- DBI::dbGetQuery(conn, "
    SELECT true_positives, false_positives, true_negatives, false_negatives,
           accuracy, precision, recall, f1_score
    FROM performance_metrics 
    WHERE run_id = ? AND narrative_type = ?
  ", params = list(run_id, narrative_type))
  
  if (nrow(metrics) == 0) {
    stop("No metrics found for run_id: ", run_id, " and narrative_type: ", narrative_type)
  }
  
  # Create confusion matrix data
  cm_data <- tibble(
    Predicted = c("IPV", "IPV", "No IPV", "No IPV"),
    Actual = c("IPV", "No IPV", "IPV", "No IPV"),
    Count = c(
      metrics$true_positives[1],
      metrics$false_positives[1],
      metrics$false_negatives[1], 
      metrics$true_negatives[1]
    ),
    Type = c("TP", "FP", "FN", "TN"),
    Correct = c(TRUE, FALSE, FALSE, TRUE)
  )
  
  # Calculate percentages
  total_cases <- sum(cm_data$Count)
  cm_data$Percentage <- cm_data$Count / total_cases * 100
  
  # Create plot
  p <- ggplot(cm_data, aes(x = Predicted, y = Actual)) +
    geom_tile(aes(fill = Correct, alpha = Count), color = "white", size = 1) +
    geom_text(aes(label = paste0(Count, "\n(", round(Percentage, 1), "%)")), 
              size = 4, fontface = "bold") +
    scale_fill_manual(values = c("TRUE" = "#2ecc71", "FALSE" = "#e74c3c"),
                      labels = c("Correct", "Incorrect")) +
    scale_alpha_continuous(range = c(0.3, 1.0), guide = "none") +
    labs(
      title = paste("Confusion Matrix -", narrative_type, "Narratives"),
      subtitle = paste0("Accuracy: ", round(metrics$accuracy[1], 3), 
                       " | Precision: ", round(metrics$precision[1], 3),
                       " | Recall: ", round(metrics$recall[1], 3),
                       " | F1: ", round(metrics$f1_score[1], 3)),
      x = "Predicted",
      y = "Actual",
      fill = "Prediction"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text = element_text(size = 11),
      axis.title = element_text(size = 12, face = "bold"),
      legend.position = "bottom"
    )
  
  return(p)
}

#' Create ROC Curve
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param narrative_type "LE", "CME", or "combined"
#' @return ggplot object
#' @export
plot_roc_curve <- function(conn, run_id, narrative_type = "combined") {
  
  # Get test results with confidence scores
  results <- DBI::dbGetQuery(conn, "
    SELECT predicted_confidence, actual_ipv
    FROM test_results 
    WHERE run_id = ? AND predicted_confidence IS NOT NULL 
      AND actual_ipv IS NOT NULL
  ", params = list(run_id))
  
  if (narrative_type != "combined") {
    results <- DBI::dbGetQuery(conn, "
      SELECT predicted_confidence, actual_ipv
      FROM test_results 
      WHERE run_id = ? AND narrative_type = ? 
        AND predicted_confidence IS NOT NULL 
        AND actual_ipv IS NOT NULL
    ", params = list(run_id, narrative_type))
  }
  
  if (nrow(results) == 0) {
    stop("No results with confidence scores found")
  }
  
  # Calculate ROC curve
  roc_obj <- pROC::roc(results$actual_ipv, results$predicted_confidence, quiet = TRUE)
  auc_value <- as.numeric(roc_obj$auc)
  
  # Extract coordinates
  roc_data <- tibble(
    fpr = 1 - roc_obj$specificities,
    tpr = roc_obj$sensitivities,
    thresholds = roc_obj$thresholds
  )
  
  # Create plot
  p <- ggplot(roc_data, aes(x = fpr, y = tpr)) +
    geom_line(color = "#3498db", size = 1.2) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "gray60") +
    geom_point(data = roc_data[seq(1, nrow(roc_data), by = max(1, nrow(roc_data) %/% 20)), ],
               color = "#2980b9", size = 1.5, alpha = 0.7) +
    scale_x_continuous(labels = scales::percent_format(accuracy = 1)) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    labs(
      title = paste("ROC Curve -", narrative_type, "Narratives"),
      subtitle = paste0("AUC = ", round(auc_value, 3), 
                       " (", nrow(results), " cases)"),
      x = "False Positive Rate (1 - Specificity)",
      y = "True Positive Rate (Sensitivity)"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text = element_text(size = 11),
      axis.title = element_text(size = 12, face = "bold"),
      panel.grid.minor = element_blank()
    ) +
    coord_equal()
  
  return(p)
}

#' Create Confidence Calibration Plot
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param narrative_type "LE", "CME", or "combined"
#' @return ggplot object
#' @export
plot_confidence_calibration <- function(conn, run_id, narrative_type = "combined") {
  
  # Get calibration data
  calibration <- DBI::dbGetQuery(conn, "
    SELECT bin_center, accuracy_in_bin, prediction_count, calibration_error
    FROM confidence_calibration 
    WHERE run_id = ? AND narrative_type = ?
    ORDER BY bin_center
  ", params = list(run_id, narrative_type))
  
  if (nrow(calibration) == 0) {
    stop("No calibration data found")
  }
  
  # Calculate overall calibration metrics
  expected_calibration_error <- weighted.mean(calibration$calibration_error, 
                                            calibration$prediction_count, na.rm = TRUE)
  max_calibration_error <- max(calibration$calibration_error, na.rm = TRUE)
  
  # Create plot
  p <- ggplot(calibration, aes(x = bin_center, y = accuracy_in_bin)) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "gray60", size = 1) +
    geom_point(aes(size = prediction_count), color = "#e74c3c", alpha = 0.7) +
    geom_line(color = "#c0392b", size = 1) +
    geom_segment(aes(xend = bin_center, yend = bin_center), 
                 color = "#95a5a6", linetype = "dotted", alpha = 0.7) +
    scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                      limits = c(0, 1)) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                      limits = c(0, 1)) +
    scale_size_continuous(name = "# Predictions", range = c(2, 8)) +
    labs(
      title = paste("Confidence Calibration -", narrative_type, "Narratives"),
      subtitle = paste0("ECE = ", round(expected_calibration_error, 3),
                       " | MCE = ", round(max_calibration_error, 3)),
      x = "Mean Predicted Confidence",
      y = "Observed Accuracy",
      caption = "Perfect calibration shown as diagonal line"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text = element_text(size = 11),
      axis.title = element_text(size = 12, face = "bold"),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    ) +
    coord_equal()
  
  return(p)
}

#' Create Performance Comparison Plot
#' 
#' @param conn Database connection
#' @param run_ids Vector of test run IDs to compare
#' @param metrics Vector of metrics to compare
#' @return ggplot object
#' @export
plot_performance_comparison <- function(conn, run_ids, 
                                      metrics = c("accuracy", "precision", "recall", "f1_score")) {
  
  # Get performance data
  perf_data <- DBI::dbGetQuery(conn, "
    SELECT tr.run_name, pm.narrative_type, pm.accuracy, pm.precision, pm.recall, pm.f1_score,
           pm.specificity, pm.auc_roc, tr.run_timestamp
    FROM performance_metrics pm
    JOIN test_runs tr ON pm.run_id = tr.run_id
    WHERE pm.run_id IN ({paste(rep('?', length(run_ids)), collapse=',')})
      AND tr.status = 'completed'
  ", params = as.list(run_ids))
  
  if (nrow(perf_data) == 0) {
    stop("No performance data found for the specified run IDs")
  }
  
  # Reshape data for plotting
  plot_data <- perf_data %>%
    select(run_name, narrative_type, all_of(metrics)) %>%
    pivot_longer(cols = all_of(metrics), names_to = "metric", values_to = "value") %>%
    mutate(
      metric = factor(metric, levels = metrics),
      narrative_type = factor(narrative_type, levels = c("LE", "CME", "combined"))
    )
  
  # Create plot
  p <- ggplot(plot_data, aes(x = run_name, y = value, fill = narrative_type)) +
    geom_bar(stat = "identity", position = "dodge", alpha = 0.8) +
    geom_text(aes(label = round(value, 3)), 
              position = position_dodge(width = 0.9), 
              vjust = -0.3, size = 3) +
    facet_wrap(~metric, scales = "free_y", ncol = 2) +
    scale_fill_manual(values = c("#3498db", "#e74c3c", "#2ecc71"),
                     name = "Narrative Type") +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    labs(
      title = "Performance Comparison Across Test Runs",
      subtitle = paste("Comparing", length(run_ids), "test runs"),
      x = "Test Run",
      y = "Performance Score"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text.x = element_text(angle = 45, hjust = 1),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 12, face = "bold"),
      legend.position = "bottom",
      strip.text = element_text(size = 11, face = "bold"),
      panel.grid.minor = element_blank()
    )
  
  return(p)
}

#' Create Error Pattern Heatmap
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @return ggplot object
#' @export
plot_error_patterns <- function(conn, run_id) {
  
  # Get error analysis data
  errors <- DBI::dbGetQuery(conn, "
    SELECT error_type, narrative_type, misclassification_reason,
           COUNT(*) as count, AVG(predicted_confidence) as avg_confidence
    FROM error_analysis 
    WHERE run_id = ?
    GROUP BY error_type, narrative_type, misclassification_reason
    HAVING COUNT(*) >= 2
    ORDER BY count DESC
  ", params = list(run_id))
  
  if (nrow(errors) == 0) {
    return(ggplot() + 
           labs(title = "No Error Patterns Found", 
                subtitle = "Either no errors occurred or insufficient data for pattern analysis") +
           theme_void())
  }
  
  # Truncate long reasons for better display
  errors$reason_short <- ifelse(nchar(errors$misclassification_reason) > 30,
                               paste0(substr(errors$misclassification_reason, 1, 30), "..."),
                               errors$misclassification_reason)
  
  # Create plot
  p <- ggplot(errors, aes(x = error_type, y = reorder(reason_short, count))) +
    geom_tile(aes(fill = count, alpha = avg_confidence), color = "white", size = 0.5) +
    geom_text(aes(label = count), color = "white", size = 3, fontface = "bold") +
    facet_wrap(~narrative_type, scales = "free_y") +
    scale_fill_viridis_c(name = "Error\nCount", option = "plasma") +
    scale_alpha_continuous(name = "Avg\nConfidence", range = c(0.4, 1.0)) +
    labs(
      title = "Error Pattern Analysis",
      subtitle = paste("Most Common Misclassification Patterns for Run:", run_id),
      x = "Error Type",
      y = "Misclassification Reason"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text.x = element_text(angle = 45, hjust = 1),
      axis.text.y = element_text(size = 9),
      axis.title = element_text(size = 12, face = "bold"),
      legend.position = "right",
      strip.text = element_text(size = 11, face = "bold"),
      panel.grid = element_blank()
    )
  
  return(p)
}

#' Create Performance Trend Plot
#' 
#' @param conn Database connection
#' @param metric_name Metric to track ("accuracy", "f1_score", etc.)
#' @param narrative_type "LE", "CME", or "combined"
#' @param last_n_runs Number of recent runs to include (default: 10)
#' @return ggplot object
#' @export
plot_performance_trends <- function(conn, metric_name = "f1_score", 
                                   narrative_type = "combined", last_n_runs = 10) {
  
  # Get performance trend data
  trend_data <- DBI::dbGetQuery(conn, paste0("
    SELECT tr.run_name, tr.run_timestamp, pm.", metric_name, " as metric_value,
           pv.version_name
    FROM test_runs tr
    JOIN performance_metrics pm ON tr.run_id = pm.run_id
    JOIN prompt_versions pv ON tr.prompt_version_id = pv.version_id
    WHERE tr.status = 'completed' AND pm.narrative_type = ?
    ORDER BY tr.run_timestamp DESC
    LIMIT ?
  "), params = list(narrative_type, last_n_runs))
  
  if (nrow(trend_data) == 0) {
    stop("No trend data found")
  }
  
  # Convert timestamp and reverse for chronological order
  trend_data <- trend_data %>%
    mutate(
      run_date = as.POSIXct(run_timestamp, origin = "1970-01-01"),
      run_order = rev(seq_len(n()))
    ) %>%
    arrange(run_timestamp)
  
  # Calculate moving average
  trend_data$moving_avg <- stats::filter(trend_data$metric_value, rep(1/3, 3), sides = 2)
  
  # Create plot
  p <- ggplot(trend_data, aes(x = run_order)) +
    geom_line(aes(y = metric_value), color = "#3498db", size = 1, alpha = 0.7) +
    geom_point(aes(y = metric_value, color = version_name), size = 3) +
    geom_line(aes(y = moving_avg), color = "#e74c3c", size = 1.2, linetype = "dashed") +
    scale_x_continuous(breaks = trend_data$run_order,
                      labels = trend_data$run_name) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 0.1)) +
    scale_color_viridis_d(name = "Prompt\nVersion") +
    labs(
      title = paste("Performance Trends -", str_to_title(metric_name)),
      subtitle = paste0(narrative_type, " narratives | Last ", nrow(trend_data), " runs"),
      x = "Test Run (Chronological Order)",
      y = str_to_title(gsub("_", " ", metric_name)),
      caption = "Dashed line shows 3-point moving average"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12),
      axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
      axis.text = element_text(size = 10),
      axis.title = element_text(size = 12, face = "bold"),
      legend.position = "bottom",
      panel.grid.minor = element_blank()
    )
  
  return(p)
}

#' Generate Comprehensive Test Report
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @param output_dir Directory to save plots
#' @return List of plot objects
#' @export
generate_test_report <- function(conn, run_id, output_dir = "tests/reports") {
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  plots <- list()
  
  # Get run information
  run_info <- DBI::dbGetQuery(conn, "
    SELECT run_name, model_name, test_set_size, run_timestamp
    FROM test_runs WHERE run_id = ?
  ", params = list(run_id))
  
  if (nrow(run_info) == 0) {
    stop("Run ID not found: ", run_id)
  }
  
  cli::cli_alert_info("Generating test report for: {run_info$run_name[1]}")
  
  # Generate plots for each narrative type
  for (nt in c("LE", "CME", "combined")) {
    
    tryCatch({
      # Confusion Matrix
      p_cm <- plot_confusion_matrix(conn, run_id, nt)
      plots[[paste0("confusion_matrix_", nt)]] <- p_cm
      
      # ROC Curve
      p_roc <- plot_roc_curve(conn, run_id, nt)
      plots[[paste0("roc_curve_", nt)]] <- p_roc
      
      # Confidence Calibration
      p_cal <- plot_confidence_calibration(conn, run_id, nt)
      plots[[paste0("calibration_", nt)]] <- p_cal
      
    }, error = function(e) {
      cli::cli_alert_warning("Could not generate plots for {nt}: {e$message}")
    })
  }
  
  # Error patterns (combined only)
  tryCatch({
    p_errors <- plot_error_patterns(conn, run_id)
    plots[["error_patterns"]] <- p_errors
  }, error = function(e) {
    cli::cli_alert_warning("Could not generate error patterns: {e$message}")
  })
  
  # Save plots
  report_timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  
  for (plot_name in names(plots)) {
    filename <- file.path(output_dir, paste0(run_id, "_", plot_name, "_", report_timestamp, ".png"))
    
    tryCatch({
      ggsave(filename, plots[[plot_name]], width = 10, height = 8, dpi = 300)
      cli::cli_alert_success("Saved: {basename(filename)}")
    }, error = function(e) {
      cli::cli_alert_warning("Could not save {plot_name}: {e$message}")
    })
  }
  
  cli::cli_alert_success("Test report generated in: {output_dir}")
  return(plots)
}