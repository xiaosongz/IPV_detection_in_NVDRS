#' Statistical Testing Utilities for IPV Detection Performance
#' 
#' This module provides statistical tests for comparing model performance
#' across different configurations, including significance tests, effect sizes,
#' and A/B testing frameworks.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr) 
  library(broom)
  library(effectsize)
  library(pwr)
})

#' Perform McNemar's Test for Comparing Two Models
#' 
#' McNemar's test is appropriate for comparing two models on the same dataset
#' where we want to test if the difference in accuracy is significant.
#' 
#' @param conn Database connection
#' @param run_id_a First model run ID
#' @param run_id_b Second model run ID  
#' @param narrative_type "LE", "CME", or "combined"
#' @return List with test results
#' @export
mcnemar_test_comparison <- function(conn, run_id_a, run_id_b, narrative_type = "combined") {
  
  # Get results for both runs
  results_a <- get_test_results(conn, run_id_a, narrative_type)
  results_b <- get_test_results(conn, run_id_b, narrative_type) 
  
  # Match incidents
  matched_results <- inner_join(
    results_a, results_b, 
    by = c("incident_id", "narrative_type"),
    suffix = c("_a", "_b")
  )
  
  if (nrow(matched_results) == 0) {
    stop("No matching incidents found between the two runs")
  }
  
  # Create contingency table for McNemar's test
  # Rows: Model A correct/incorrect, Cols: Model B correct/incorrect
  correct_a <- matched_results$predicted_ipv_a == matched_results$actual_ipv_a
  correct_b <- matched_results$predicted_ipv_b == matched_results$actual_ipv_b
  
  # McNemar's test focuses on discordant pairs
  both_correct <- sum(correct_a & correct_b)
  both_incorrect <- sum(!correct_a & !correct_b)
  a_correct_b_wrong <- sum(correct_a & !correct_b)
  a_wrong_b_correct <- sum(!correct_a & correct_b)
  
  # Perform McNemar's test
  mcnemar_table <- matrix(
    c(both_correct, a_wrong_b_correct, a_correct_b_wrong, both_incorrect),
    nrow = 2,
    dimnames = list(
      "Model_A" = c("Correct", "Incorrect"),
      "Model_B" = c("Correct", "Incorrect")
    )
  )
  
  # Only test discordant pairs
  if (a_correct_b_wrong + a_wrong_b_correct == 0) {
    return(list(
      test_type = "McNemar's Test",
      p_value = 1.0,
      statistic = 0,
      interpretation = "Models perform identically",
      effect_size = 0,
      sample_size = nrow(matched_results),
      discordant_pairs = 0
    ))
  }
  
  # McNemar's chi-square test
  chi_sq <- (abs(a_correct_b_wrong - a_wrong_b_correct) - 1)^2 / (a_correct_b_wrong + a_wrong_b_correct)
  p_value <- 1 - pchisq(chi_sq, df = 1)
  
  # Effect size (odds ratio for discordant pairs)
  odds_ratio <- a_correct_b_wrong / max(a_wrong_b_correct, 1)
  
  # Interpretation
  interpretation <- if (p_value < 0.01) {
    "Highly significant difference"
  } else if (p_value < 0.05) {
    "Significant difference" 
  } else if (p_value < 0.10) {
    "Marginally significant difference"
  } else {
    "No significant difference"
  }
  
  return(list(
    test_type = "McNemar's Test",
    p_value = p_value,
    statistic = chi_sq,
    interpretation = interpretation,
    odds_ratio = odds_ratio,
    sample_size = nrow(matched_results),
    discordant_pairs = a_correct_b_wrong + a_wrong_b_correct,
    contingency_table = mcnemar_table,
    model_a_better = a_correct_b_wrong > a_wrong_b_correct
  ))
}

#' Perform Paired t-test on Confidence Scores
#' 
#' @param conn Database connection
#' @param run_id_a First model run ID
#' @param run_id_b Second model run ID
#' @param narrative_type "LE", "CME", or "combined"
#' @return List with test results
#' @export
paired_confidence_test <- function(conn, run_id_a, run_id_b, narrative_type = "combined") {
  
  # Get confidence scores for both runs
  results_a <- get_test_results(conn, run_id_a, narrative_type) %>%
    select(incident_id, narrative_type, predicted_confidence) %>%
    rename(confidence_a = predicted_confidence)
  
  results_b <- get_test_results(conn, run_id_b, narrative_type) %>%
    select(incident_id, narrative_type, predicted_confidence) %>%
    rename(confidence_b = predicted_confidence)
  
  # Match and filter complete cases
  matched_confidence <- inner_join(results_a, results_b, by = c("incident_id", "narrative_type")) %>%
    filter(!is.na(confidence_a), !is.na(confidence_b))
  
  if (nrow(matched_confidence) < 10) {
    stop("Insufficient matched confidence scores for comparison (need ≥10)")
  }
  
  # Perform paired t-test
  t_test <- t.test(matched_confidence$confidence_a, matched_confidence$confidence_b, paired = TRUE)
  
  # Effect size (Cohen's d for paired data)
  diff_scores <- matched_confidence$confidence_a - matched_confidence$confidence_b
  cohens_d <- mean(diff_scores, na.rm = TRUE) / sd(diff_scores, na.rm = TRUE)
  
  # Interpretation
  interpretation <- if (t_test$p.value < 0.01) {
    "Highly significant difference in confidence"
  } else if (t_test$p.value < 0.05) {
    "Significant difference in confidence"
  } else if (t_test$p.value < 0.10) {
    "Marginally significant difference in confidence"
  } else {
    "No significant difference in confidence"
  }
  
  effect_interpretation <- if (abs(cohens_d) < 0.2) {
    "Negligible effect size"
  } else if (abs(cohens_d) < 0.5) {
    "Small effect size"
  } else if (abs(cohens_d) < 0.8) {
    "Medium effect size"
  } else {
    "Large effect size"
  }
  
  return(list(
    test_type = "Paired t-test (Confidence Scores)",
    p_value = t_test$p.value,
    statistic = t_test$statistic,
    degrees_freedom = t_test$parameter,
    mean_difference = t_test$estimate,
    confidence_interval = t_test$conf.int,
    cohens_d = cohens_d,
    interpretation = interpretation,
    effect_interpretation = effect_interpretation,
    sample_size = nrow(matched_confidence)
  ))
}

#' Perform Bootstrap Confidence Interval for Performance Metrics
#' 
#' @param conn Database connection
#' @param run_id Test run ID
#' @param metric Metric to bootstrap ("accuracy", "f1_score", etc.)
#' @param narrative_type "LE", "CME", or "combined"
#' @param n_bootstrap Number of bootstrap samples (default: 1000)
#' @param confidence_level Confidence level (default: 0.95)
#' @return List with bootstrap results
#' @export
bootstrap_performance_ci <- function(conn, run_id, metric = "f1_score", narrative_type = "combined",
                                    n_bootstrap = 1000, confidence_level = 0.95) {
  
  # Get test results
  results <- get_test_results(conn, run_id, narrative_type)
  
  if (nrow(results) < 20) {
    stop("Insufficient data for bootstrap (need ≥20 cases)")
  }
  
  # Bootstrap function
  bootstrap_metric <- function(data) {
    n <- nrow(data)
    bootstrap_indices <- sample(n, n, replace = TRUE)
    bootstrap_data <- data[bootstrap_indices, ]
    
    # Calculate metric on bootstrap sample
    if (metric == "accuracy") {
      sum(bootstrap_data$predicted_ipv == bootstrap_data$actual_ipv) / nrow(bootstrap_data)
    } else if (metric == "precision") {
      tp <- sum(bootstrap_data$predicted_ipv & bootstrap_data$actual_ipv)
      fp <- sum(bootstrap_data$predicted_ipv & !bootstrap_data$actual_ipv)
      tp / max(tp + fp, 1)
    } else if (metric == "recall") {
      tp <- sum(bootstrap_data$predicted_ipv & bootstrap_data$actual_ipv)
      fn <- sum(!bootstrap_data$predicted_ipv & bootstrap_data$actual_ipv)
      tp / max(tp + fn, 1)
    } else if (metric == "f1_score") {
      tp <- sum(bootstrap_data$predicted_ipv & bootstrap_data$actual_ipv)
      fp <- sum(bootstrap_data$predicted_ipv & !bootstrap_data$actual_ipv)
      fn <- sum(!bootstrap_data$predicted_ipv & bootstrap_data$actual_ipv)
      precision <- tp / max(tp + fp, 1)
      recall <- tp / max(tp + fn, 1)
      2 * (precision * recall) / max(precision + recall, 1e-10)
    } else {
      stop("Unsupported metric: ", metric)
    }
  }
  
  # Perform bootstrap
  set.seed(42)  # For reproducibility
  bootstrap_values <- replicate(n_bootstrap, bootstrap_metric(results))
  
  # Calculate confidence interval
  alpha <- 1 - confidence_level
  lower_percentile <- 100 * (alpha / 2)
  upper_percentile <- 100 * (1 - alpha / 2)
  
  ci_lower <- quantile(bootstrap_values, lower_percentile / 100)
  ci_upper <- quantile(bootstrap_values, upper_percentile / 100)
  
  # Original metric value
  original_value <- bootstrap_metric(results)
  
  return(list(
    metric = metric,
    original_value = original_value,
    bootstrap_mean = mean(bootstrap_values),
    bootstrap_sd = sd(bootstrap_values),
    confidence_interval = c(ci_lower, ci_upper),
    confidence_level = confidence_level,
    n_bootstrap = n_bootstrap,
    sample_size = nrow(results),
    narrative_type = narrative_type
  ))
}

#' Create A/B Test Record
#' 
#' @param conn Database connection
#' @param test_name Descriptive name for the A/B test
#' @param variant_a_run_id Run ID for variant A
#' @param variant_b_run_id Run ID for variant B
#' @param test_metric Primary metric for comparison
#' @param narrative_type "LE", "CME", or "combined"
#' @return A/B test ID
#' @export
create_ab_test <- function(conn, test_name, variant_a_run_id, variant_b_run_id, 
                          test_metric = "f1_score", narrative_type = "combined") {
  
  # Get performance metrics for both variants
  metrics_a <- DBI::dbGetQuery(conn, paste0("
    SELECT ", test_metric, " FROM performance_metrics 
    WHERE run_id = ? AND narrative_type = ?
  "), params = list(variant_a_run_id, narrative_type))
  
  metrics_b <- DBI::dbGetQuery(conn, paste0("
    SELECT ", test_metric, " FROM performance_metrics 
    WHERE run_id = ? AND narrative_type = ?  
  "), params = list(variant_b_run_id, narrative_type))
  
  if (nrow(metrics_a) == 0 || nrow(metrics_b) == 0) {
    stop("Performance metrics not found for one or both runs")
  }
  
  variant_a_score <- metrics_a[[test_metric]][1]
  variant_b_score <- metrics_b[[test_metric]][1]
  
  # Perform statistical test (McNemar's for accuracy-based metrics)
  if (test_metric %in% c("accuracy", "f1_score", "precision", "recall")) {
    stat_test <- mcnemar_test_comparison(conn, variant_a_run_id, variant_b_run_id, narrative_type)
    p_value <- stat_test$p_value
    effect_size <- abs(variant_b_score - variant_a_score) / max(variant_a_score, 0.01)
  } else {
    p_value <- NA_real_
    effect_size <- NA_real_
  }
  
  # Determine winner
  winner <- if (is.na(p_value) || p_value > 0.05) {
    "tie"
  } else if (variant_b_score > variant_a_score) {
    "B"
  } else {
    "A"
  }
  
  # Get sample sizes
  sample_size_a <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) as n FROM test_results WHERE run_id = ?
  ", params = list(variant_a_run_id))$n[1]
  
  sample_size_b <- DBI::dbGetQuery(conn, "
    SELECT COUNT(*) as n FROM test_results WHERE run_id = ?
  ", params = list(variant_b_run_id))$n[1]
  
  sample_size <- min(sample_size_a, sample_size_b)
  
  # Calculate statistical power (approximate)
  test_power <- if (!is.na(effect_size)) {
    tryCatch({
      pwr::pwr.chisq.test(w = effect_size, N = sample_size, df = 1, sig.level = 0.05)$power
    }, error = function(e) NA_real_)
  } else {
    NA_real_
  }
  
  # Generate test ID
  test_id <- paste0("ab_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_", 
                   digest::digest(test_name, algo = "md5", serialize = FALSE)[1:6])
  
  # Insert A/B test record
  DBI::dbExecute(conn, "
    INSERT INTO ab_tests (
      test_id, test_name, variant_a_run_id, variant_b_run_id, test_metric,
      variant_a_score, variant_b_score, statistical_significance, effect_size,
      winner, test_power, sample_size, created_timestamp
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(
    test_id, test_name, variant_a_run_id, variant_b_run_id, test_metric,
    variant_a_score, variant_b_score, p_value, effect_size,
    winner, test_power, sample_size, as.integer(Sys.time())
  ))
  
  cli::cli_alert_success("Created A/B test: {test_id}")
  
  # Print summary
  cli::cli_h2("A/B Test Summary")
  cli::cli_alert_info("Test: {test_name}")
  cli::cli_alert_info("Metric: {test_metric}")
  cli::cli_alert_info("Variant A: {round(variant_a_score, 4)}")
  cli::cli_alert_info("Variant B: {round(variant_b_score, 4)}")
  cli::cli_alert_info("Improvement: {round((variant_b_score - variant_a_score) / variant_a_score * 100, 2)}%")
  cli::cli_alert_info("P-value: {round(p_value, 6)}")
  cli::cli_alert_info("Winner: {winner}")
  
  return(test_id)
}

#' Power Analysis for Sample Size Planning
#' 
#' @param effect_size Expected effect size (Cohen's d)
#' @param alpha Significance level (default: 0.05)
#' @param power Desired statistical power (default: 0.80)
#' @param test_type Type of test ("two_sample", "paired", "proportion")
#' @return Required sample size
#' @export
calculate_required_sample_size <- function(effect_size, alpha = 0.05, power = 0.80, 
                                         test_type = "two_sample") {
  
  if (test_type == "two_sample") {
    result <- pwr::pwr.t.test(d = effect_size, sig.level = alpha, power = power, type = "two.sample")
  } else if (test_type == "paired") {
    result <- pwr::pwr.t.test(d = effect_size, sig.level = alpha, power = power, type = "paired") 
  } else if (test_type == "proportion") {
    # Assuming equal proportions and effect_size is the difference in proportions
    p1 <- 0.5  # baseline proportion
    p2 <- p1 + effect_size
    result <- pwr::pwr.2p.test(h = effect_size, sig.level = alpha, power = power)
  } else {
    stop("Unsupported test type: ", test_type)
  }
  
  sample_size <- ceiling(result$n)
  
  cli::cli_h2("Power Analysis Results")
  cli::cli_alert_info("Test type: {test_type}")
  cli::cli_alert_info("Effect size: {effect_size}")
  cli::cli_alert_info("Significance level: {alpha}")
  cli::cli_alert_info("Desired power: {power}")
  cli::cli_alert_info("Required sample size per group: {sample_size}")
  
  return(sample_size)
}

#' Helper function to get test results
#' 
#' @param conn Database connection
#' @param run_id Run identifier
#' @param narrative_type Narrative type filter
#' @return Test results tibble
get_test_results <- function(conn, run_id, narrative_type) {
  
  query <- if (narrative_type == "combined") {
    "SELECT * FROM test_results WHERE run_id = ? AND predicted_ipv IS NOT NULL AND actual_ipv IS NOT NULL"
  } else {
    "SELECT * FROM test_results WHERE run_id = ? AND narrative_type = ? AND predicted_ipv IS NOT NULL AND actual_ipv IS NOT NULL"
  }
  
  params <- if (narrative_type == "combined") {
    list(run_id)
  } else {
    list(run_id, narrative_type)
  }
  
  DBI::dbGetQuery(conn, query, params = params) %>%
    as_tibble()
}

#' Comprehensive Statistical Summary
#' 
#' @param conn Database connection
#' @param run_id Test run identifier
#' @return List with comprehensive statistics
#' @export
comprehensive_statistical_summary <- function(conn, run_id) {
  
  results <- list()
  
  # Performance metrics with confidence intervals
  for (metric in c("accuracy", "precision", "recall", "f1_score")) {
    for (nt in c("LE", "CME", "combined")) {
      tryCatch({
        bootstrap_result <- bootstrap_performance_ci(conn, run_id, metric, nt, n_bootstrap = 500)
        results[[paste0(metric, "_", nt, "_bootstrap")]] <- bootstrap_result
      }, error = function(e) {
        # Skip if insufficient data
      })
    }
  }
  
  # Get run information
  run_info <- DBI::dbGetQuery(conn, "
    SELECT run_name, test_set_size, model_name FROM test_runs WHERE run_id = ?
  ", params = list(run_id))
  
  results$run_info <- run_info
  results$run_id <- run_id
  results$timestamp <- Sys.time()
  
  return(results)
}