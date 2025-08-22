#!/usr/bin/env Rscript

# Install usethis and devtools now that libgit2 is installed
packages_needed <- c("usethis", "devtools")

for (pkg in packages_needed) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("Installing", pkg, "...\n")
    install.packages(pkg, repos = "http://cran.rstudio.com/")
  } else {
    cat(pkg, "is already installed\n")
  }
}

cat("Packages installed successfully\n")