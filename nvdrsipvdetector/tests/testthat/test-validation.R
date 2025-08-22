test_that("calculate_metrics handles perfect predictions", {
  predictions <- data.frame(
    ipv_detected = c(TRUE, TRUE, FALSE, FALSE),
    ManualIPVFlag = c(TRUE, TRUE, FALSE, FALSE)
  )
  
  metrics <- calculate_metrics(predictions)
  expect_equal(metrics$accuracy, 1.0)
  expect_equal(metrics$precision, 1.0)
  expect_equal(metrics$recall, 1.0)
  expect_equal(metrics$f1_score, 1.0)
})

test_that("calculate_metrics handles NA values", {
  predictions <- data.frame(
    ipv_detected = c(TRUE, NA, FALSE, TRUE),
    ManualIPVFlag = c(TRUE, FALSE, NA, FALSE)
  )
  
  metrics <- calculate_metrics(predictions)
  expect_equal(metrics$n, 2)  # Only 2 valid pairs
})

test_that("confusion_matrix creates correct matrix", {
  predictions <- c(TRUE, TRUE, FALSE, FALSE, TRUE)
  actual <- c(TRUE, FALSE, FALSE, TRUE, TRUE)
  
  cm <- confusion_matrix(predictions, actual)
  expect_equal(cm[1,1], 1)  # TN
  expect_equal(cm[2,2], 2)  # TP
  expect_equal(cm[2,1], 1)  # FP
  expect_equal(cm[1,2], 1)  # FN
})