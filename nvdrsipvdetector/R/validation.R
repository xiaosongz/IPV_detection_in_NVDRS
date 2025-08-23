#' Accuracy Metrics
#'
#' @description Validation and accuracy calculation functions
#' @name validation
#' @keywords internal
NULL

#' Calculate Metrics (Modernized)
#'
#' @param predictions Data frame with ipv_detected column
#' @param actual Data frame with ManualIPVFlag column or NULL
#' @return Tibble with metrics
#' @export
calculate_metrics <- function(predictions, actual = NULL) {
  # Prepare data as tibble
  data <- tibble::as_tibble(predictions)
  
  # Extract actual values
  actual_col <- if (is.null(actual)) {
    if (!"ManualIPVFlag" %in% names(data)) {
      stop("No manual flags provided for validation")
    }
    data$ManualIPVFlag
  } else if (is.data.frame(actual)) {
    actual$ManualIPVFlag
  } else {
    actual
  }
  
  # Create analysis dataset
  analysis_data <- tibble::tibble(
    predicted = data$ipv_detected,
    actual = actual_col
  ) %>%
    dplyr::filter(!is.na(predicted) & !is.na(actual))
  
  if (nrow(analysis_data) == 0) {
    return(tibble::tibble(
      n = 0L,
      error = "No valid predictions"
    ))
  }
  
  # Calculate all metrics using dplyr::summarise
  analysis_data %>%
    dplyr::summarise(
      n = dplyr::n(),
      true_positive = sum(predicted & actual),
      true_negative = sum(!predicted & !actual),
      false_positive = sum(predicted & !actual),
      false_negative = sum(!predicted & actual),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      accuracy = (true_positive + true_negative) / n,
      precision = dplyr::case_when(
        (true_positive + false_positive) > 0 ~ 
          true_positive / (true_positive + false_positive),
        TRUE ~ NA_real_
      ),
      recall = dplyr::case_when(
        (true_positive + false_negative) > 0 ~ 
          true_positive / (true_positive + false_negative),
        TRUE ~ NA_real_
      ),
      f1_score = dplyr::case_when(
        !is.na(precision) & !is.na(recall) & (precision + recall) > 0 ~
          2 * (precision * recall) / (precision + recall),
        TRUE ~ NA_real_
      )
    )
}

#' Generate Confusion Matrix (Modernized)
#'
#' @param predictions Predictions vector or data frame
#' @param actual Actual values vector or data frame
#' @return Confusion matrix as tibble
#' @export
confusion_matrix <- function(predictions, actual) {
  # Extract vectors from data frames if needed
  pred_vec <- if (is.data.frame(predictions)) {
    predictions$ipv_detected
  } else {
    predictions
  }
  
  actual_vec <- if (is.data.frame(actual)) {
    actual$ManualIPVFlag
  } else {
    actual
  }
  
  # Remove NA values
  valid_idx <- !is.na(pred_vec) & !is.na(actual_vec)
  pred_vec <- pred_vec[valid_idx]
  actual_vec <- actual_vec[valid_idx]
  
  # Create standard confusion matrix table
  table(Predicted = pred_vec, Actual = actual_vec)
}

#' Print Validation Report (Modernized)
#'
#' @param metrics Metrics tibble from calculate_metrics
#' @export
print_validation_report <- function(metrics) {
  # Handle error case
  if ("error" %in% names(metrics)) {
    cli::cli_alert_danger("Validation error: {metrics$error}")
    return(invisible(NULL))
  }
  
  # Use cli for better formatting
  cli::cli_h1("IPV Detection Validation Report")
  
  # Basic metrics
  cli::cli_alert_info("Total samples: {metrics$n}")
  
  if (!is.na(metrics$accuracy)) {
    cli::cli_alert_success(
      "Accuracy: {scales::percent(metrics$accuracy, accuracy = 0.01)}"
    )
  }
  
  if (!is.na(metrics$precision)) {
    cli::cli_alert_info(
      "Precision: {scales::percent(metrics$precision, accuracy = 0.01)}"
    )
  }
  
  if (!is.na(metrics$recall)) {
    cli::cli_alert_info(
      "Recall: {scales::percent(metrics$recall, accuracy = 0.01)}"
    )
  }
  
  if (!is.na(metrics$f1_score)) {
    cli::cli_alert_info("F1 Score: {round(metrics$f1_score, 3)}")
  }
  
  # Confusion matrix
  cli::cli_h2("Confusion Matrix")
  cli::cli_text("  TP: {metrics$true_positive}  FP: {metrics$false_positive}")
  cli::cli_text("  FN: {metrics$false_negative}  TN: {metrics$true_negative}")
  
  invisible(metrics)
}