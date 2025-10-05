# Tests for metrics.R
# Performance metric calculations

test_that("compute_model_performance calculates accuracy", {
  # Perfect accuracy
  results <- list(
    list(detected = TRUE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 0),
    list(detected = TRUE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$accuracy, 1.0)
})

test_that("compute_model_performance calculates precision", {
  # 2 TP, 1 FP -> precision = 2/3
  results <- list(
    list(detected = TRUE, manual_flag = 1),   # TP
    list(detected = TRUE, manual_flag = 1),   # TP
    list(detected = TRUE, manual_flag = 0)    # FP
  )
  
  metrics <- compute_model_performance(results)
  
  expect_true(abs(metrics$precision_ipv - 0.667) < 0.01)
})

test_that("compute_model_performance calculates recall", {
  # 1 TP, 2 FN -> recall = 1/3
  results <- list(
    list(detected = TRUE, manual_flag = 1),    # TP
    list(detected = FALSE, manual_flag = 1),   # FN
    list(detected = FALSE, manual_flag = 1)    # FN
  )
  
  metrics <- compute_model_performance(results)
  
  expect_true(abs(metrics$recall_ipv - 0.333) < 0.01)
})

test_that("compute_model_performance calculates F1 score", {
  # Balanced: P=R=0.5 -> F1=0.5
  results <- list(
    list(detected = TRUE, manual_flag = 1),    # TP
    list(detected = FALSE, manual_flag = 1),   # FN
    list(detected = TRUE, manual_flag = 0)     # FP
  )
  
  metrics <- compute_model_performance(results)
  
  expect_true(abs(metrics$f1_ipv - 0.5) < 0.01)
})

test_that("compute_model_performance counts true positives", {
  results <- list(
    list(detected = TRUE, manual_flag = 1),
    list(detected = TRUE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 1)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$n_true_positive, 2)
})

test_that("compute_model_performance counts true negatives", {
  results <- list(
    list(detected = FALSE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0),
    list(detected = TRUE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$n_true_negative, 2)
})

test_that("compute_model_performance counts false positives", {
  results <- list(
    list(detected = TRUE, manual_flag = 0),
    list(detected = TRUE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$n_false_positive, 2)
})

test_that("compute_model_performance counts false negatives", {
  results <- list(
    list(detected = FALSE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 1),
    list(detected = TRUE, manual_flag = 1)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$n_false_negative, 2)
})

test_that("compute_model_performance handles empty results", {
  results <- list()
  
  metrics <- compute_model_performance(results)
  
  # Should return NA or 0 for all metrics
  expect_true(is.na(metrics$accuracy) || metrics$accuracy == 0)
})

test_that("compute_model_performance handles all negative cases", {
  results <- list(
    list(detected = FALSE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_equal(metrics$accuracy, 1.0)
  expect_equal(metrics$n_true_negative, 3)
})

test_that("compute_model_performance handles zero division in precision", {
  # No positive predictions
  results <- list(
    list(detected = FALSE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  # Precision undefined, should be NA or 0
  expect_true(is.na(metrics$precision_ipv) || metrics$precision_ipv == 0)
})

test_that("compute_model_performance handles zero division in recall", {
  # No actual positives
  results <- list(
    list(detected = TRUE, manual_flag = 0),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  # Recall undefined, should be NA or 0
  expect_true(is.na(metrics$recall_ipv) || metrics$recall_ipv == 0)
})

test_that("compute_model_performance returns all required metrics", {
  results <- list(
    list(detected = TRUE, manual_flag = 1)
  )
  
  metrics <- compute_model_performance(results)
  
  required_metrics <- c("accuracy", "precision_ipv", "recall_ipv", "f1_ipv",
                       "n_true_positive", "n_true_negative",
                       "n_false_positive", "n_false_negative")
  
  for (metric in required_metrics) {
    expect_true(metric %in% names(metrics),
               info = sprintf("Missing metric: %s", metric))
  }
})

test_that("compute_model_performance validates with expect_valid_metrics", {
  results <- list(
    list(detected = TRUE, manual_flag = 1),
    list(detected = FALSE, manual_flag = 0)
  )
  
  metrics <- compute_model_performance(results)
  
  expect_valid_metrics(metrics)
})
