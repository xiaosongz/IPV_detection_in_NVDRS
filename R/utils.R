#' Utility functions for IPV detection package
#' 
#' Common utility functions used across the package.
#' Following tidyverse style guide and Unix philosophy.

#' NULL coalescing operator
#' 
#' Returns the first non-NULL value. Similar to rlang's %||% but
#' also handles empty strings and zero-length vectors.
#' 
#' @param x First value to check
#' @param y Default value if x is NULL/empty
#' @return x if not NULL/empty, otherwise y
#' @export
#' @examples
#' # Basic NULL coalescing
#' NULL %||% "default"        # "default"
#' "value" %||% "default"     # "value"
#' 
#' # Handles empty strings and vectors
#' "" %||% "default"          # "default"
#' character(0) %||% "default"  # "default"
#' 
#' # Useful for function parameters
#' process_narrative <- function(text, model = NULL) {
#'   model <- model %||% "default-model"
#'   # ... use model ...
#' }
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || 
      (is.character(x) && !nzchar(x[1]))) {
    y
  } else {
    x
  }
}

#' Safe trimws wrapper
#' 
#' Trims whitespace with NULL handling
#' 
#' @param x Character string or NULL
#' @return Trimmed string or empty string if NULL
#' @export
#' @examples
#' # Safe trimming with NULL handling
#' trimws_safe("  text  ")     # "text"
#' trimws_safe(NULL)           # ""
#' trimws_safe("")             # ""
#' 
#' # Useful for cleaning data
#' narratives <- c("  text with spaces  ", NULL, "", "  another  ")
#' cleaned <- sapply(narratives, trimws_safe)
#' # Result: "text with spaces", "", "", "another"
trimws_safe <- function(x) {
  trimws(x %||% "")
}