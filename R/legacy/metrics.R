compute_model_performance <- function(
  all_results,
  detected_col = "detected",
  manual_col = "manual_flag_ind",
  verbose = TRUE
) {
  # Handle empty inputs early
  if (is.null(all_results) || nrow(all_results) == 0) {
    res <- list(
      processed = 0L,
      valid = 0L,
      accuracy = NA_real_,
      sensitivity = NA_real_,
      specificity = NA_real_
    )
    if (isTRUE(verbose)) {
      cat("\nModel Performance:\n")
      cat("  Processed:", 0, "narratives\n")
      cat("  Valid results:", 0, "\n")
      cat("  Accuracy:", "NA", "\n")
      cat("  Sensitivity:", "NA", "\n")
      cat("  Specificity:", "NA", "\n")
    }
    return(res)
  }

  # Filter to valid rows (no NAs in the two key columns)
  valid_results <- all_results %>%
    dplyr::filter(!is.na(.data[[detected_col]]) & !is.na(.data[[manual_col]]))

  processed_n <- nrow(all_results)
  valid_n <- nrow(valid_results)

  if (valid_n == 0) {
    res <- list(
      processed = processed_n,
      valid = 0L,
      accuracy = NA_real_,
      sensitivity = NA_real_,
      specificity = NA_real_
    )
    if (isTRUE(verbose)) {
      cat("\nModel Performance:\n")
      cat("  Processed:", processed_n, "narratives\n")
      cat("  Valid results:", 0, "\n")
      cat("  Accuracy:", "NA", "\n")
      cat("  Sensitivity:", "NA", "\n")
      cat("  Specificity:", "NA", "\n")
    }
    return(res)
  }

  # Compute metrics (replicates existing script logic)
  accuracy <- mean(valid_results[[detected_col]] == valid_results[[manual_col]])
  sensitivity <- mean(valid_results[[detected_col]][valid_results[[manual_col]] == TRUE])
  specificity <- mean(!valid_results[[detected_col]][valid_results[[manual_col]] == FALSE])

  res <- list(
    processed = processed_n,
    valid = valid_n,
    accuracy = accuracy,
    sensitivity = sensitivity,
    specificity = specificity
  )

  if (isTRUE(verbose)) {
    cat("\nModel Performance:\n")
    cat("  Processed:", processed_n, "narratives\n")
    cat("  Valid results:", valid_n, "\n")
    cat("  Accuracy:", sprintf("%.2f%%", accuracy * 100), "\n")
    cat("  Sensitivity:", sprintf("%.2f%%", sensitivity * 100), "\n")
    cat("  Specificity:", sprintf("%.2f%%", specificity * 100), "\n")
  }

  return(res)
}

