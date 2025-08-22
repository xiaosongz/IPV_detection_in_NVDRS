#' Accuracy Metrics
#'
#' @description Validation and accuracy calculation functions
#' @keywords internal
NULL

#' Calculate Metrics
#'
#' @param predictions Data frame with ipv_detected column
#' @param actual Data frame with ManualIPVFlag column
#' @return List with metrics
#' @export
calculate_metrics <- function(predictions, actual = NULL) {
  # If actual is NULL, look for ManualIPVFlag in predictions
  if (is.null(actual)) {
    if (!"ManualIPVFlag" %in% names(predictions)) {
      stop("No manual flags provided for validation")
    }
    actual <- predictions$ManualIPVFlag
  } else if (is.data.frame(actual)) {
    actual <- actual$ManualIPVFlag
  }
  
  pred <- predictions$ipv_detected
  
  # Remove NA values
  valid_idx <- !is.na(pred) & !is.na(actual)
  pred <- pred[valid_idx]
  actual <- actual[valid_idx]
  
  if (length(pred) == 0) {
    return(list(n = 0, error = "No valid predictions"))
  }
  
  # Calculate confusion matrix
  tp <- sum(pred & actual)
  tn <- sum(!pred & !actual)
  fp <- sum(pred & !actual)
  fn <- sum(!pred & actual)
  
  # Calculate metrics
  accuracy <- (tp + tn) / length(pred)
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA
  f1 <- if (!is.na(precision) && !is.na(recall) && (precision + recall) > 0) {
    2 * (precision * recall) / (precision + recall)
  } else NA
  
  return(list(
    n = length(pred),
    accuracy = accuracy,
    precision = precision,
    recall = recall,
    f1_score = f1,
    true_positive = tp,
    true_negative = tn,
    false_positive = fp,
    false_negative = fn
  ))
}

#' Generate Confusion Matrix
#'
#' @param predictions Predictions vector
#' @param actual Actual values vector
#' @return Confusion matrix
#' @export
confusion_matrix <- function(predictions, actual) {
  # Handle data frames
  if (is.data.frame(predictions)) predictions <- predictions$ipv_detected
  if (is.data.frame(actual)) actual <- actual$ManualIPVFlag
  
  # Remove NAs
  valid <- !is.na(predictions) & !is.na(actual)
  predictions <- predictions[valid]
  actual <- actual[valid]
  
  # Create matrix
  cm <- table(Predicted = predictions, Actual = actual)
  return(cm)
}

#' Print Validation Report
#'
#' @param metrics Metrics list from calculate_metrics
#' @export
print_validation_report <- function(metrics) {
  cat("\n=== IPV Detection Validation Report ===\n")
  cat(sprintf("Total samples: %d\n", metrics$n))
  cat(sprintf("Accuracy: %.2f%%\n", metrics$accuracy * 100))
  cat(sprintf("Precision: %.2f%%\n", metrics$precision * 100))
  cat(sprintf("Recall: %.2f%%\n", metrics$recall * 100))
  cat(sprintf("F1 Score: %.3f\n", metrics$f1_score))
  cat("\nConfusion Matrix:\n")
  cat(sprintf("  TP: %d  FP: %d\n", metrics$true_positive, metrics$false_positive))
  cat(sprintf("  FN: %d  TN: %d\n", metrics$false_negative, metrics$true_negative))
}