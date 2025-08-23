#!/usr/bin/env Rscript

# Root Directory Cleanup Script
# Ensures no loose files are left in the root directory

library(cli)

cli::cli_h1("Root Directory Cleanup Check")

# Define allowed files in root
ALLOWED_ROOT_FILES <- c(
  "README.md",
  "CLAUDE.md", 
  "CLAUDE.local.md",
  ".gitignore",
  ".env.example",
  ".env",
  "LICENSE",
  "LICENSE.md",
  ".Rhistory",
  ".DS_Store"
)

ALLOWED_EXTENSIONS <- c(
  "\\.Rproj$",      # RStudio project files
  "\\.Rproj\\.user$" # RStudio user settings
)

# File type to directory mapping
FILE_MAPPINGS <- list(
  # R scripts
  "analyze.*\\.R$" = "scripts/analysis/",
  "monitor.*\\.R$" = "scripts/monitoring/",
  "test.*\\.R$" = "scripts/testing/",
  "run.*\\.R$" = "scripts/testing/",
  "debug.*\\.R$" = "scripts/debugging/",
  "\\.R$" = "scripts/utilities/",  # Other R scripts
  
  # Documentation
  ".*RESULTS.*\\.md$" = "docs/reports/",
  ".*SUMMARY.*\\.md$" = "docs/summaries/",
  ".*REPORT.*\\.md$" = "docs/reports/",
  "\\.md$" = "docs/notes/",  # Other markdown
  
  # Config files
  "\\.yml$" = "config/",
  "\\.yaml$" = "config/",
  "\\.json$" = "config/",
  
  # Results
  "\\.csv$" = "results/",
  "\\.RData$" = "results/",
  "\\.rds$" = "results/",
  
  # Logs
  "\\.log$" = "logs/",
  "\\.txt$" = "logs/"
)

# Get all files in root
all_files <- list.files(".", all.files = FALSE, no.. = TRUE)

# Filter out directories
files_only <- all_files[!file.info(all_files)$isdir]

# Check for loose files
loose_files <- files_only[!files_only %in% ALLOWED_ROOT_FILES]

# Filter out allowed extensions
for (pattern in ALLOWED_EXTENSIONS) {
  loose_files <- loose_files[!grepl(pattern, loose_files)]
}

if (length(loose_files) == 0) {
  cli::cli_alert_success("Root directory is clean! No loose files found.")
} else {
  cli::cli_alert_warning("Found {length(loose_files)} loose file{?s} in root directory:")
  
  for (file in loose_files) {
    cli::cli_alert_info("  {file}")
    
    # Find appropriate directory
    target_dir <- NULL
    for (pattern in names(FILE_MAPPINGS)) {
      if (grepl(pattern, file)) {
        target_dir <- FILE_MAPPINGS[[pattern]]
        break
      }
    }
    
    if (!is.null(target_dir)) {
      cli::cli_alert("    → Should be in: {target_dir}")
    }
  }
  
  # Ask if user wants to auto-organize
  if (interactive()) {
    response <- readline(prompt = "\nWould you like to automatically organize these files? (y/n): ")
    
    if (tolower(response) == "y") {
      for (file in loose_files) {
        # Find target directory
        target_dir <- NULL
        for (pattern in names(FILE_MAPPINGS)) {
          if (grepl(pattern, file)) {
            target_dir <- FILE_MAPPINGS[[pattern]]
            break
          }
        }
        
        if (!is.null(target_dir)) {
          # Create directory if it doesn't exist
          if (!dir.exists(target_dir)) {
            dir.create(target_dir, recursive = TRUE)
            cli::cli_alert_info("Created directory: {target_dir}")
          }
          
          # Move file
          new_path <- file.path(target_dir, file)
          file.rename(file, new_path)
          cli::cli_alert_success("Moved {file} → {new_path}")
        } else {
          cli::cli_alert_warning("Don't know where to put {file}, skipping...")
        }
      }
      
      cli::cli_alert_success("Cleanup complete!")
    }
  } else {
    cli::cli_h2("To clean up manually, run these commands:")
    
    for (file in loose_files) {
      target_dir <- NULL
      for (pattern in names(FILE_MAPPINGS)) {
        if (grepl(pattern, file)) {
          target_dir <- FILE_MAPPINGS[[pattern]]
          break
        }
      }
      
      if (!is.null(target_dir)) {
        cat(sprintf("mv '%s' '%s'\n", file, file.path(target_dir, file)))
      }
    }
  }
}

# Also check for common problem patterns
cli::cli_h2("Additional Checks")

# Check for tar.gz files
tar_files <- list.files(".", pattern = "\\.tar\\.gz$")
if (length(tar_files) > 0) {
  cli::cli_alert_warning("Found package tar.gz files that should be removed:")
  for (f in tar_files) {
    cli::cli_alert_info("  {f}")
  }
}

# Check for .Rcheck directories
check_dirs <- list.dirs(".", recursive = FALSE, full.names = FALSE)
check_dirs <- check_dirs[grepl("\\.Rcheck$", check_dirs)]
if (length(check_dirs) > 0) {
  cli::cli_alert_warning("Found R check directories that could be removed:")
  for (d in check_dirs) {
    cli::cli_alert_info("  {d}/")
  }
}

cli::cli_alert_success("Cleanup check complete!")