#' Experiment analysis utilities
#' 
#' Functions for analyzing and comparing experiment results.
#' These help identify which prompts work best for IPV detection.

#' Get experiment metrics
#' 
#' Calculates performance metrics for an experiment.
#' 
#' @param experiment_id The experiment ID to analyze
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return List with metrics including detection rate, confidence, etc.
#' @export
#' @examples
#' \dontrun{
#' # Analyze experiment performance
#' metrics <- experiment_metrics(experiment_id = 1)
#' 
#' # Basic performance stats
#' cat("Detection rate:", round(metrics$detection_rate * 100, 1), "%\n")
#' cat("Average confidence:", round(metrics$avg_confidence, 3), "\n")
#' cat("Total results:", metrics$total_results, "\n")
#' cat("Error rate:", round(metrics$error_rate * 100, 1), "%\n")
#' 
#' # Accuracy metrics (if ground truth available)
#' if (!is.null(metrics$accuracy_metrics)) {
#'   acc <- metrics$accuracy_metrics
#'   cat("Accuracy:", round(acc$accuracy * 100, 1), "%\n")
#'   cat("Precision:", round(acc$precision, 3), "\n")
#'   cat("Recall:", round(acc$recall, 3), "\n")
#'   cat("F1 Score:", round(acc$f1_score, 3), "\n")
#' }
#' }
experiment_metrics <- function(experiment_id,
                             conn = NULL,
                             db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  # Get basic experiment info
  exp_info <- DBI::dbGetQuery(
    conn,
    "SELECT e.*, pv.version_tag 
     FROM experiments e
     LEFT JOIN prompt_versions pv ON e.prompt_version_id = pv.id
     WHERE e.id = ?",
    params = list(experiment_id)
  )
  
  if (nrow(exp_info) == 0) {
    warning(sprintf("Experiment ID %d not found", experiment_id))
    if (created_conn) close_db_connection(conn)
    return(NULL)
  }
  
  # Get results statistics using dplyr if data is available
  # Note: Still using SQL for database efficiency, but structure follows tidyverse
  results <- DBI::dbGetQuery(
    conn,
    "SELECT 
      COUNT(*) as total_results,
      SUM(CASE WHEN detected THEN 1 ELSE 0 END) as detected_count,
      AVG(confidence) as avg_confidence,
      MIN(confidence) as min_confidence,
      MAX(confidence) as max_confidence,
      AVG(response_time_ms) as avg_response_time,
      SUM(total_tokens) as total_tokens_used,
      SUM(CASE WHEN error_message IS NOT NULL THEN 1 ELSE 0 END) as error_count
     FROM experiment_results
     WHERE experiment_id = ?",
    params = list(experiment_id)
  ) |>
    tibble::as_tibble()
  
  # Calculate with ground truth if available
  accuracy_metrics <- DBI::dbGetQuery(
    conn,
    "SELECT 
      COUNT(*) as evaluated_count,
      SUM(CASE WHEN er.detected = gt.true_ipv THEN 1 ELSE 0 END) as correct_predictions,
      SUM(CASE WHEN er.detected AND gt.true_ipv THEN 1 ELSE 0 END) as true_positives,
      SUM(CASE WHEN er.detected AND NOT gt.true_ipv THEN 1 ELSE 0 END) as false_positives,
      SUM(CASE WHEN NOT er.detected AND gt.true_ipv THEN 1 ELSE 0 END) as false_negatives,
      SUM(CASE WHEN NOT er.detected AND NOT gt.true_ipv THEN 1 ELSE 0 END) as true_negatives
     FROM experiment_results er
     JOIN ground_truth gt ON er.narrative_id = gt.narrative_id
     WHERE er.experiment_id = ?",
    params = list(experiment_id)
  )
  
  # Calculate derived metrics
  metrics <- list(
    experiment_id = experiment_id,
    experiment_name = exp_info$name[1],
    prompt_version = exp_info$version_tag[1],
    model = exp_info$model[1],
    status = exp_info$status[1],
    
    # Basic metrics
    total_results = results$total_results[1],
    detection_rate = results$detected_count[1] / results$total_results[1],
    avg_confidence = results$avg_confidence[1],
    confidence_range = c(results$min_confidence[1], results$max_confidence[1]),
    avg_response_time_ms = results$avg_response_time[1],
    total_tokens = results$total_tokens_used[1],
    error_rate = results$error_count[1] / results$total_results[1]
  )
  
  # Add accuracy metrics if ground truth available
  if (accuracy_metrics$evaluated_count[1] > 0) {
    tp <- accuracy_metrics$true_positives[1]
    fp <- accuracy_metrics$false_positives[1]
    fn <- accuracy_metrics$false_negatives[1]
    tn <- accuracy_metrics$true_negatives[1]
    
    metrics$accuracy_metrics <- list(
      evaluated_count = accuracy_metrics$evaluated_count[1],
      accuracy = accuracy_metrics$correct_predictions[1] / accuracy_metrics$evaluated_count[1],
      precision = if (tp + fp > 0) tp / (tp + fp) else NA,
      recall = if (tp + fn > 0) tp / (tp + fn) else NA,
      specificity = if (tn + fp > 0) tn / (tn + fp) else NA,
      f1_score = if (tp > 0) 2 * tp / (2 * tp + fp + fn) else NA
    )
  }
  
  if (created_conn) close_db_connection(conn)
  metrics
}

#' Compare two experiments
#' 
#' Statistical comparison of two experiments.
#' 
#' @param exp_id1 First experiment ID
#' @param exp_id2 Second experiment ID
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return List with comparison results and statistical tests
#' @export
#' @examples
#' \dontrun{
#' # Compare baseline vs enhanced prompt
#' comparison <- compare_experiments(exp_id1 = 1, exp_id2 = 2)
#' 
#' # Basic comparison
#' cat("Experiment 1:", comparison$experiment1$name, "\n")
#' cat("Detection rate:", round(comparison$experiment1$detection_rate * 100, 1), "%\n")
#' cat("Experiment 2:", comparison$experiment2$name, "\n") 
#' cat("Detection rate:", round(comparison$experiment2$detection_rate * 100, 1), "%\n")
#' 
#' # Statistical significance
#' if (!is.null(comparison$statistical_tests)) {
#'   t_test <- comparison$statistical_tests$confidence_t_test
#'   cat("Confidence difference significant:", t_test$significant, "\n")
#'   cat("P-value:", round(t_test$p_value, 4), "\n")
#' }
#' 
#' # Accuracy improvements
#' if (!is.null(comparison$accuracy_comparison)) {
#'   acc_diff <- comparison$accuracy_comparison$accuracy_diff
#'   cat("Accuracy improvement:", round(acc_diff * 100, 1), "pp\n")
#' }
#' }
compare_experiments <- function(exp_id1, exp_id2,
                              conn = NULL,
                              db_path = "llm_results.db") {
  
  # Get metrics for both experiments
  metrics1 <- experiment_metrics(exp_id1, conn, db_path)
  metrics2 <- experiment_metrics(exp_id2, conn, db_path)
  
  if (is.null(metrics1) || is.null(metrics2)) {
    stop("One or both experiments not found")
  }
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  # Get confidence scores for statistical testing
  conf1 <- DBI::dbGetQuery(
    conn,
    "SELECT confidence FROM experiment_results WHERE experiment_id = ? AND confidence IS NOT NULL",
    params = list(exp_id1)
  )$confidence
  
  conf2 <- DBI::dbGetQuery(
    conn,
    "SELECT confidence FROM experiment_results WHERE experiment_id = ? AND confidence IS NOT NULL",
    params = list(exp_id2)
  )$confidence
  
  comparison <- list(
    experiment1 = list(
      id = exp_id1,
      name = metrics1$experiment_name,
      detection_rate = metrics1$detection_rate,
      avg_confidence = metrics1$avg_confidence,
      total_results = metrics1$total_results
    ),
    experiment2 = list(
      id = exp_id2,
      name = metrics2$experiment_name,
      detection_rate = metrics2$detection_rate,
      avg_confidence = metrics2$avg_confidence,
      total_results = metrics2$total_results
    ),
    differences = list(
      detection_rate_diff = metrics2$detection_rate - metrics1$detection_rate,
      confidence_diff = metrics2$avg_confidence - metrics1$avg_confidence,
      response_time_diff = metrics2$avg_response_time_ms - metrics1$avg_response_time_ms
    )
  )
  
  # Statistical tests if sufficient data
  if (length(conf1) > 1 && length(conf2) > 1) {
    # T-test for confidence scores
    t_test <- t.test(conf2, conf1)
    comparison$statistical_tests <- list(
      confidence_t_test = list(
        p_value = t_test$p.value,
        confidence_interval = t_test$conf.int,
        mean_difference = t_test$estimate[1] - t_test$estimate[2],
        significant = t_test$p.value < 0.05
      )
    )
    
    # Add Wilcoxon test as non-parametric alternative
    w_test <- wilcox.test(conf2, conf1)
    comparison$statistical_tests$confidence_wilcox_test <- list(
      p_value = w_test$p.value,
      significant = w_test$p.value < 0.05
    )
  }
  
  # Compare accuracy metrics if available
  if (!is.null(metrics1$accuracy_metrics) && !is.null(metrics2$accuracy_metrics)) {
    comparison$accuracy_comparison <- list(
      accuracy_diff = metrics2$accuracy_metrics$accuracy - metrics1$accuracy_metrics$accuracy,
      precision_diff = metrics2$accuracy_metrics$precision - metrics1$accuracy_metrics$precision,
      recall_diff = metrics2$accuracy_metrics$recall - metrics1$accuracy_metrics$recall,
      f1_diff = metrics2$accuracy_metrics$f1_score - metrics1$accuracy_metrics$f1_score
    )
  }
  
  if (created_conn) close_db_connection(conn)
  comparison
}

#' Analyze prompt performance across versions
#' 
#' Tracks how performance changes across prompt versions.
#' 
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return Data frame with performance by prompt version
#' @export
analyze_prompt_evolution <- function(conn = NULL,
                                    db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  result <- DBI::dbGetQuery(
    conn,
    "SELECT 
      pv.id as prompt_id,
      pv.version_tag,
      pv.created_at as prompt_created,
      COUNT(DISTINCT e.id) as experiment_count,
      COUNT(er.id) as total_tests,
      AVG(er.confidence) as avg_confidence,
      MIN(er.confidence) as min_confidence,
      MAX(er.confidence) as max_confidence,
      SUM(CASE WHEN er.detected THEN 1 ELSE 0 END) * 100.0 / COUNT(er.id) as detection_rate,
      AVG(er.response_time_ms) as avg_response_time
     FROM prompt_versions pv
     LEFT JOIN experiments e ON pv.id = e.prompt_version_id
     LEFT JOIN experiment_results er ON e.id = er.experiment_id
     GROUP BY pv.id
     ORDER BY pv.created_at"
  )
  
  if (created_conn) close_db_connection(conn)
  result
}

#' A/B test between prompt versions
#' 
#' Performs statistical A/B test between two prompt versions.
#' Tests on the same narratives for fair comparison.
#' 
#' @param prompt_v1_id First prompt version ID
#' @param prompt_v2_id Second prompt version ID
#' @param model Model to use for comparison (filters experiments)
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return List with A/B test results
#' @export
ab_test_prompts <- function(prompt_v1_id, prompt_v2_id,
                          model = NULL,
                          conn = NULL,
                          db_path = "llm_results.db") {
  
  created_conn <- FALSE
  if (is.null(conn)) {
    conn <- get_db_connection(db_path)
    created_conn <- TRUE
  }
  
  # Build query for paired comparison
  query <- "
    SELECT 
      r1.narrative_id,
      r1.detected as detected_v1,
      r1.confidence as confidence_v1,
      r2.detected as detected_v2,
      r2.confidence as confidence_v2,
      gt.true_ipv as ground_truth
    FROM experiment_results r1
    JOIN experiments e1 ON r1.experiment_id = e1.id
    JOIN experiment_results r2 ON r1.narrative_id = r2.narrative_id
    JOIN experiments e2 ON r2.experiment_id = e2.id
    LEFT JOIN ground_truth gt ON r1.narrative_id = gt.narrative_id
    WHERE e1.prompt_version_id = ? 
      AND e2.prompt_version_id = ?"
  
  params <- list(prompt_v1_id, prompt_v2_id)
  
  if (!is.null(model)) {
    query <- paste(query, "AND e1.model = ? AND e2.model = ?")
    params <- c(params, list(model, model))
  }
  
  paired_results <- DBI::dbGetQuery(conn, query, params = params)
  
  if (nrow(paired_results) == 0) {
    warning("No paired results found for these prompt versions")
    if (created_conn) close_db_connection(conn)
    return(NULL)
  }
  
  # Calculate paired statistics
  ab_results <- list(
    prompt_v1_id = prompt_v1_id,
    prompt_v2_id = prompt_v2_id,
    model = model,
    n_paired = nrow(paired_results),
    
    # Detection agreement
    detection_agreement = mean(paired_results$detected_v1 == paired_results$detected_v2),
    
    # Average differences
    avg_confidence_v1 = mean(paired_results$confidence_v1, na.rm = TRUE),
    avg_confidence_v2 = mean(paired_results$confidence_v2, na.rm = TRUE),
    confidence_improvement = mean(paired_results$confidence_v2 - paired_results$confidence_v1, na.rm = TRUE),
    
    # Detection rates
    detection_rate_v1 = mean(paired_results$detected_v1),
    detection_rate_v2 = mean(paired_results$detected_v2)
  )
  
  # Paired t-test for confidence
  if (sum(!is.na(paired_results$confidence_v1) & !is.na(paired_results$confidence_v2)) > 1) {
    paired_t <- t.test(paired_results$confidence_v2, paired_results$confidence_v1, paired = TRUE)
    ab_results$confidence_paired_t_test <- list(
      p_value = paired_t$p.value,
      mean_difference = paired_t$estimate,
      confidence_interval = paired_t$conf.int,
      significant = paired_t$p.value < 0.05
    )
  }
  
  # McNemar's test for detection changes
  if (nrow(paired_results) > 10) {
    # Create contingency table
    cont_table <- table(
      v1 = paired_results$detected_v1,
      v2 = paired_results$detected_v2
    )
    
    if (all(dim(cont_table) == c(2, 2))) {
      mcnemar_result <- mcnemar.test(cont_table)
      ab_results$detection_mcnemar_test <- list(
        p_value = mcnemar_result$p.value,
        significant = mcnemar_result$p.value < 0.05
      )
    }
  }
  
  # Accuracy comparison if ground truth available
  gt_available <- sum(!is.na(paired_results$ground_truth))
  if (gt_available > 0) {
    with_gt <- paired_results[!is.na(paired_results$ground_truth), ]
    ab_results$accuracy_comparison <- list(
      n_with_ground_truth = nrow(with_gt),
      accuracy_v1 = mean(with_gt$detected_v1 == with_gt$ground_truth),
      accuracy_v2 = mean(with_gt$detected_v2 == with_gt$ground_truth),
      improvement = mean(with_gt$detected_v2 == with_gt$ground_truth) - 
                   mean(with_gt$detected_v1 == with_gt$ground_truth)
    )
  }
  
  if (created_conn) close_db_connection(conn)
  ab_results
}

#' Generate experiment report
#' 
#' Creates a comprehensive report for an experiment.
#' 
#' @param experiment_id The experiment ID to report on
#' @param conn Database connection (optional)
#' @param db_path Path to database file
#' @return Character string with formatted report
#' @export
experiment_report <- function(experiment_id,
                            conn = NULL,
                            db_path = "llm_results.db") {
  
  metrics <- experiment_metrics(experiment_id, conn, db_path)
  
  if (is.null(metrics)) {
    return("Experiment not found")
  }
  
  report <- paste0(
    "=================================================\n",
    "EXPERIMENT REPORT\n",
    "=================================================\n\n",
    
    "Experiment: ", metrics$experiment_name, " (ID: ", metrics$experiment_id, ")\n",
    "Prompt Version: ", metrics$prompt_version, "\n",
    "Model: ", metrics$model, "\n",
    "Status: ", metrics$status, "\n\n",
    
    "RESULTS SUMMARY\n",
    "---------------\n",
    "Total Tests: ", metrics$total_results, "\n",
    "Detection Rate: ", sprintf("%.1f%%", metrics$detection_rate * 100), "\n",
    "Average Confidence: ", sprintf("%.3f", metrics$avg_confidence), "\n",
    "Confidence Range: [", sprintf("%.3f", metrics$confidence_range[1]), 
    ", ", sprintf("%.3f", metrics$confidence_range[2]), "]\n",
    "Avg Response Time: ", sprintf("%.0f ms", metrics$avg_response_time_ms), "\n",
    "Total Tokens Used: ", metrics$total_tokens, "\n",
    "Error Rate: ", sprintf("%.1f%%", metrics$error_rate * 100), "\n"
  )
  
  if (!is.null(metrics$accuracy_metrics)) {
    report <- paste0(
      report,
      "\nACCURACY METRICS (vs Ground Truth)\n",
      "-----------------------------------\n",
      "Evaluated: ", metrics$accuracy_metrics$evaluated_count, " narratives\n",
      "Accuracy: ", sprintf("%.1f%%", metrics$accuracy_metrics$accuracy * 100), "\n",
      "Precision: ", sprintf("%.3f", metrics$accuracy_metrics$precision), "\n",
      "Recall: ", sprintf("%.3f", metrics$accuracy_metrics$recall), "\n",
      "Specificity: ", sprintf("%.3f", metrics$accuracy_metrics$specificity), "\n",
      "F1 Score: ", sprintf("%.3f", metrics$accuracy_metrics$f1_score), "\n"
    )
  }
  
  report <- paste0(report, "\n=================================================\n")
  report
}