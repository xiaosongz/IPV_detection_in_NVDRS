#!/usr/bin/env Rscript

# Create the package structure
library(usethis)

# Create package
usethis::create_package("nvdrsipvdetector", open = FALSE, rstudio = FALSE)

# Set working directory to the package
setwd("nvdrsipvdetector")

# Use MIT license
usethis::use_mit_license("Your Name")

# Set up testing infrastructure
usethis::use_testthat()

# Set up roxygen
usethis::use_roxygen_md()

# Create necessary directories
dir.create("inst/prompts", recursive = TRUE, showWarnings = FALSE)
dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
dir.create("config", recursive = TRUE, showWarnings = FALSE)
dir.create("data-raw", recursive = TRUE, showWarnings = FALSE)
dir.create("vignettes", recursive = TRUE, showWarnings = FALSE)
dir.create(".github/workflows", recursive = TRUE, showWarnings = FALSE)

cat("Package structure created successfully\n")