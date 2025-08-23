#' Example Usage of Enhanced IPV Detection Test Framework
#' 
#' This script demonstrates how to use the comprehensive testing framework
#' for evaluating IPV detection performance, including batch testing,
#' statistical analysis, and visualization.

# Load required libraries and test framework
library(nvdrsipvdetector)
source("tests/R/test_framework.R")
source("tests/R/visualization_utils.R")
source("tests/R/statistical_tests.R")

# Set up paths
config_path <- "tests/test_data/test_config.yml"
test_data_path <- "tests/test_data/test_sample.csv"
db_path <- "tests/test_logs.sqlite"

#' Example 1: Basic Test Run
#' Run IPV detection on test data and calculate basic metrics
run_basic_test_example <- function() {
  
  cli::cli_h1("Example 1: Basic Test Run")
  
  # Initialize test database
  conn <- init_test_database(db_path)
  on.exit(DBI::dbDisconnect(conn))
  
  # Load test data
  test_data <- readr::read_csv(test_data_path)
  cli::cli_alert_info("Loaded {nrow(test_data)} test cases")
  
  # Load configuration
  config <- nvdrsipvdetector::load_config(config_path)
  
  # Run the test
  test_results <- run_ipv_detection_test(
    test_data = test_data,
    config = config,
    run_name = "Basic Test Run - Example",
    conn = conn
  )
  
  # Display summary
  cli::cli_h2("Test Results Summary")
  print(test_results$summary)
  
  return(test_results$run_id)
}

#' Example 2: Compare Two Different Configurations
#' Test statistical significance between different prompt versions
run_ab_test_example <- function() {
  
  cli::cli_h1("Example 2: A/B Testing Different Configurations")
  
  conn <- init_test_database(db_path)
  on.exit(DBI::dbDisconnect(conn))
  
  test_data <- readr::read_csv(test_data_path)
  
  # Configuration A: Default settings
  config_a <- nvdrsipvdetector::load_config(config_path)
  
  # Configuration B: Modified weights and threshold
  config_b <- config_a
  config_b$weights$le <- 0.5
  config_b$weights$cme <- 0.5
  config_b$weights$threshold <- 0.6  # Lower threshold
  
  # Run both tests
  cli::cli_alert_info("Running Variant A (default settings)...")
  results_a <- run_ipv_detection_test(
    test_data = test_data,
    config = config_a,
    run_name = "A/B Test - Variant A (Default)",
    conn = conn
  )
  
  cli::cli_alert_info("Running Variant B (modified settings)...")
  results_b <- run_ipv_detection_test(
    test_data = test_data,
    config = config_b,
    run_name = "A/B Test - Variant B (Modified)",
    conn = conn
  )
  
  # Create A/B test comparison
  ab_test_id <- create_ab_test(
    conn = conn,
    test_name = "Default vs Modified Weights",
    variant_a_run_id = results_a$run_id,
    variant_b_run_id = results_b$run_id,
    test_metric = "f1_score"
  )
  
  # Statistical comparison
  cli::cli_h2("Statistical Analysis")
  
  # McNemar's test for accuracy comparison
  mcnemar_result <- mcnemar_test_comparison(
    conn, results_a$run_id, results_b$run_id, "combined"
  )
  
  cli::cli_alert_info("McNemar's Test P-value: {round(mcnemar_result$p_value, 6)}")
  cli::cli_alert_info("Interpretation: {mcnemar_result$interpretation}")
  
  # Confidence test
  confidence_result <- paired_confidence_test(
    conn, results_a$run_id, results_b$run_id, "combined"
  )
  
  cli::cli_alert_info("Confidence Score T-test P-value: {round(confidence_result$p_value, 6)}")
  cli::cli_alert_info("Cohen's d: {round(confidence_result$cohens_d, 3)}")
  
  return(list(run_a = results_a$run_id, run_b = results_b$run_id, ab_test = ab_test_id))
}

#' Example 3: Comprehensive Performance Analysis
#' Generate detailed performance metrics with confidence intervals
run_comprehensive_analysis <- function(run_id) {
  
  cli::cli_h1("Example 3: Comprehensive Performance Analysis")
  
  conn <- init_test_database(db_path)
  on.exit(DBI::dbDisconnect(conn))
  
  # Bootstrap confidence intervals for key metrics
  cli::cli_h2("Bootstrap Confidence Intervals")
  
  metrics_to_analyze <- c("accuracy", "precision", "recall", "f1_score")
  narrative_types <- c("LE", "CME", "combined")
  
  bootstrap_results <- list()
  
  for (metric in metrics_to_analyze) {
    for (nt in narrative_types) {
      tryCatch({
        result <- bootstrap_performance_ci(
          conn, run_id, metric, nt, n_bootstrap = 1000, confidence_level = 0.95
        )
        bootstrap_results[[paste0(metric, "_", nt)]] <- result
        
        cli::cli_alert_info(
          "{toupper(nt)} {metric}: {round(result$original_value, 3)} " +
          "(95% CI: {round(result$confidence_interval[1], 3)}-{round(result$confidence_interval[2], 3)})"
        )
        
      }, error = function(e) {
        cli::cli_alert_warning("Could not calculate {metric} for {nt}: {e$message}")
      })
    }
  }
  
  # Comprehensive statistical summary
  stats_summary <- comprehensive_statistical_summary(conn, run_id)
  
  return(list(bootstrap_results = bootstrap_results, stats_summary = stats_summary))
}

#' Example 4: Visualization Dashboard
#' Generate comprehensive visualizations for test results
run_visualization_example <- function(run_id) {
  
  cli::cli_h1("Example 4: Visualization Dashboard")
  
  conn <- init_test_database(db_path)
  on.exit(DBI::dbDisconnect(conn))
  
  # Generate comprehensive test report
  plots <- generate_test_report(conn, run_id, "tests/reports")
  
  # Create additional custom plots
  cli::cli_h2("Creating Custom Visualizations")
  
  # Performance comparison (if multiple runs exist)
  all_runs <- DBI::dbGetQuery(conn, "
    SELECT run_id FROM test_runs WHERE status = 'completed' ORDER BY run_timestamp DESC LIMIT 5
  ")
  
  if (nrow(all_runs) > 1) {
    p_comparison <- plot_performance_comparison(
      conn, all_runs$run_id, c("accuracy", "f1_score", "precision", "recall")
    )
    
    ggsave("tests/reports/performance_comparison.png", p_comparison, 
           width = 12, height = 8, dpi = 300)
    cli::cli_alert_success("Saved performance comparison plot")
  }
  
  # Performance trends (if enough historical data)
  if (nrow(all_runs) >= 3) {
    p_trends <- plot_performance_trends(conn, "f1_score", "combined", last_n_runs = 10)
    
    ggsave("tests/reports/performance_trends.png", p_trends, 
           width = 12, height = 8, dpi = 300)
    cli::cli_alert_success("Saved performance trends plot")
  }
  
  return(plots)
}

#' Example 5: Power Analysis for Future Tests
#' Calculate required sample sizes for detecting meaningful differences
run_power_analysis_example <- function() {
  
  cli::cli_h1("Example 5: Power Analysis for Future Tests")
  
  # Calculate sample sizes for different effect sizes
  effect_sizes <- c(0.1, 0.2, 0.3, 0.5)  # Small to medium effect sizes
  
  cli::cli_h2("Sample Size Requirements")
  
  power_results <- list()
  
  for (effect_size in effect_sizes) {
    sample_size <- calculate_required_sample_size(
      effect_size = effect_size,
      alpha = 0.05,
      power = 0.80,
      test_type = "two_sample"
    )
    
    power_results[[as.character(effect_size)]] <- sample_size
    
    cli::cli_alert_info(
      "Effect size {effect_size}: Need {sample_size} cases per group"
    )
  }
  
  # Practical recommendations
  cli::cli_h2("Practical Recommendations")
  cli::cli_alert_info("For small improvements (2-5%): Need {power_results[['0.2']]} cases per group")
  cli::cli_alert_info("For medium improvements (5-10%): Need {power_results[['0.3']]} cases per group")
  cli::cli_alert_info("For large improvements (>10%): Need {power_results[['0.5']]} cases per group")
  
  return(power_results)
}

#' Example 6: Batch Size Optimization
#' Test different batch sizes for optimal processing
run_batch_optimization_example <- function() {
  
  cli::cli_h1("Example 6: Batch Size Optimization")
  
  test_data <- readr::read_csv(test_data_path)
  config <- nvdrsipvdetector::load_config(config_path)
  
  # Test different batch sizes
  batch_sizes <- c(10, 25, 50, 100)
  timing_results <- list()
  
  for (batch_size in batch_sizes) {
    cli::cli_alert_info("Testing batch size: {batch_size}")
    
    # Modify config for this batch size
    config$processing$batch_size <- batch_size
    
    # Time the processing (subset of data for speed)
    subset_data <- test_data[1:min(100, nrow(test_data)), ]
    
    start_time <- Sys.time()
    
    # Simulate batch processing (without full LLM calls for speed)
    n_batches <- ceiling(nrow(subset_data) / batch_size)
    processing_time <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
    
    timing_results[[as.character(batch_size)]] <- list(
      batch_size = batch_size,
      n_batches = n_batches,
      processing_time = processing_time,
      time_per_case = processing_time / nrow(subset_data)
    )
    
    cli::cli_alert_info(
      "Batch size {batch_size}: {round(processing_time, 2)}s total, " +
      "{round(processing_time / nrow(subset_data), 3)}s per case"
    )
  }
  
  # Recommendations
  cli::cli_h2("Batch Size Recommendations")
  best_batch <- names(which.min(sapply(timing_results, function(x) x$time_per_case)))
  cli::cli_alert_success("Optimal batch size: {best_batch}")
  
  return(timing_results)
}

#' Main Execution Function
#' Run all examples in sequence
run_all_examples <- function() {
  
  cli::cli_h1("IPV Detection Test Framework - Complete Example")
  cli::cli_alert_info("This example demonstrates all testing capabilities")
  
  # Create output directories
  dir.create("tests/reports", recursive = TRUE, showWarnings = FALSE)
  dir.create("tests/results", recursive = TRUE, showWarnings = FALSE)
  
  # Example 1: Basic test
  run_id_basic <- run_basic_test_example()
  
  # Example 2: A/B testing
  ab_results <- run_ab_test_example()
  
  # Example 3: Comprehensive analysis (using first run)
  comprehensive_analysis <- run_comprehensive_analysis(run_id_basic)
  
  # Example 4: Visualizations
  visualizations <- run_visualization_example(run_id_basic)
  
  # Example 5: Power analysis
  power_analysis <- run_power_analysis_example()
  
  # Example 6: Batch optimization
  batch_optimization <- run_batch_optimization_example()
  
  # Summary report
  cli::cli_h1("Complete Example Summary")
  cli::cli_alert_success("All examples completed successfully!")
  cli::cli_alert_info("Basic test run ID: {run_id_basic}")
  cli::cli_alert_info("A/B test runs: {ab_results$run_a} vs {ab_results$run_b}")
  cli::cli_alert_info("Generated {length(visualizations)} visualization plots")
  cli::cli_alert_info("Reports saved in: tests/reports/")
  
  return(list(
    basic_run_id = run_id_basic,
    ab_test_results = ab_results,
    comprehensive_analysis = comprehensive_analysis,
    visualizations = visualizations,
    power_analysis = power_analysis,
    batch_optimization = batch_optimization
  ))
}

# Uncomment to run examples:
# results <- run_all_examples()

#' Quick Start Function
#' For users who want to run a basic test quickly
quick_start_test <- function(test_data_path = "tests/test_data/test_sample.csv",
                           config_path = "tests/test_data/test_config.yml") {
  
  cli::cli_h1("Quick Start - IPV Detection Test")
  
  # Check if files exist
  if (!file.exists(test_data_path)) {
    stop("Test data file not found: ", test_data_path)
  }
  
  if (!file.exists(config_path)) {
    stop("Config file not found: ", config_path)
  }
  
  # Initialize and run test
  conn <- init_test_database("tests/quick_test.sqlite")
  on.exit(DBI::dbDisconnect(conn))
  
  test_data <- readr::read_csv(test_data_path)
  config <- nvdrsipvdetector::load_config(config_path)
  
  results <- run_ipv_detection_test(
    test_data = test_data,
    config = config,
    run_name = "Quick Start Test",
    conn = conn
  )
  
  # Generate basic visualizations
  plots <- generate_test_report(conn, results$run_id, "tests/quick_reports")
  
  cli::cli_alert_success("Quick test completed!")
  cli::cli_alert_info("Run ID: {results$run_id}")
  cli::cli_alert_info("Check tests/quick_reports/ for visualizations")
  
  return(results)
}

# Example usage:
# quick_results <- quick_start_test()