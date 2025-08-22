#!/usr/bin/env Rscript

# Install required packages for package development
packages_needed <- c(
  "usethis", "devtools", "roxygen2", "testthat", 
  "covr", "lintr", "styler", "goodpractice"
)

for (pkg in packages_needed) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Installing", pkg, "...\n")
    install.packages(pkg, repos = "http://cran.rstudio.com/")
  } else {
    cat(pkg, "is already installed\n")
  }
}

cat("All required packages installed\n")