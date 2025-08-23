# Quick Analysis Runner
# ====================

# Load comprehensive analysis framework
source("test/comprehensive_analysis.R")

# Install and load required packages
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
    cat("Installing", pkg, "...\n")
    install.packages(pkg, dependencies = TRUE, repos = "https://cran.rstudio.com/")
    require(pkg, character.only = TRUE, quietly = TRUE)
  }
}

required_packages <- c("dplyr", "ggplot2", "pROC", "caret", "corrplot", 
                      "gridExtra", "knitr", "binom", "tidyr")

cat("📦 Installing required packages...\n")
for (pkg in required_packages) {
  install_if_missing(pkg)
}

# Run comprehensive analysis
results_path <- "tests/test_results/baseline_results.csv"

if (file.exists(results_path)) {
  cat("🚀 Running comprehensive analysis...\n\n")
  
  # Generate full report
  report <- generate_comprehensive_report(results_path)
  
  # Save plots
  save_analysis_plots(report, "docs/analysis_plots")
  
  # Save detailed results
  save(report, file = "tests/test_results/comprehensive_analysis_report.RData")
  
  cat("\n✅ Analysis complete!\n")
  cat("📊 Plots saved to: docs/analysis_plots/\n") 
  cat("💾 Full report saved to: tests/test_results/comprehensive_analysis_report.RData\n")
  
} else {
  cat("❌ Results file not found:", results_path, "\n")
  cat("   Please run the IPV detection test first.\n")
}