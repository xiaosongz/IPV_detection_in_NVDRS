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
trimws_safe <- function(x) {
  trimws(x %||% "")
}