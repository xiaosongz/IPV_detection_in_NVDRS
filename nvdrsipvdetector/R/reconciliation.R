#' Combine LE/CME Results
#'
#' @description Functions for reconciling LE and CME detection results
#' @keywords internal
NULL

#' Reconcile LE and CME
#'
#' @param le_result LE detection result
#' @param cme_result CME detection result
#' @param weights List with le, cme, and threshold values
#' @return Reconciled result
#' @export
reconcile_le_cme <- function(le_result, cme_result, weights) {
  # Handle missing results
  if (is.na(le_result$ipv_detected) && is.na(cme_result$ipv_detected)) {
    return(list(
      ipv_detected = NA,
      confidence = NA,
      rationale = "No narratives available"
    ))
  }
  
  if (is.na(le_result$ipv_detected)) {
    return(cme_result)
  }
  
  if (is.na(cme_result$ipv_detected)) {
    return(le_result)
  }
  
  # Both available - weighted average
  combined_confidence <- le_result$confidence * weights$le + 
                        cme_result$confidence * weights$cme
  
  ipv_detected <- combined_confidence >= weights$threshold
  
  return(list(
    ipv_detected = ipv_detected,
    confidence = combined_confidence,
    le_ipv = le_result$ipv_detected,
    le_confidence = le_result$confidence,
    cme_ipv = cme_result$ipv_detected,
    cme_confidence = cme_result$confidence,
    rationale = sprintf("LE: %.0f%%, CME: %.0f%%, Combined: %.0f%%",
                       le_result$confidence * 100,
                       cme_result$confidence * 100,
                       combined_confidence * 100)
  ))
}

#' Calculate Agreement
#'
#' @param results Data frame with le_ipv and cme_ipv columns
#' @return Agreement statistics
#' @export
calculate_agreement <- function(results) {
  valid <- !is.na(results$le_ipv) & !is.na(results$cme_ipv)
  n_valid <- sum(valid)
  
  if (n_valid == 0) {
    return(list(n = 0, agreement_rate = NA))
  }
  
  n_agree <- sum(results$le_ipv[valid] == results$cme_ipv[valid])
  
  return(list(
    n = n_valid,
    agreement_rate = n_agree / n_valid,
    both_positive = sum(results$le_ipv[valid] & results$cme_ipv[valid]),
    both_negative = sum(!results$le_ipv[valid] & !results$cme_ipv[valid]),
    le_only = sum(results$le_ipv[valid] & !results$cme_ipv[valid]),
    cme_only = sum(!results$le_ipv[valid] & results$cme_ipv[valid])
  ))
}