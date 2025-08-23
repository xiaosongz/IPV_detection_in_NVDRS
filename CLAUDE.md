# nvdrs_ipv_detector Package Specification

## Critical Rules
- **NO LOOSE FILES IN ROOT** - Every file must be in its designated directory
- Use trimws() on ALL text inputs to remove trailing spaces
- NEVER store API keys in code - use environment variables
- ALL functions must use explicit namespaces (httr2::request, not library())
- Process narratives in chunks of 50 to prevent memory issues
- Test with empty/NA narratives first - they WILL occur

## FILE ORGANIZATION RULES - NEVER VIOLATE

### ROOT DIRECTORY - ONLY THESE FILES ALLOWED:
```
/                          # Root should ONLY contain:
├── README.md             # Main project documentation
├── CLAUDE.md             # This file - AI instructions
├── CLAUDE.local.md       # Local AI instructions (gitignored)
├── .gitignore            # Git ignore rules
├── .env.example          # Environment variable template
├── *.Rproj               # RStudio project file
└── LICENSE               # License file
```

### MANDATORY FILE PLACEMENT:
```
scripts/                   # ALL R scripts go here
├── analysis/             # Analysis scripts (analyze_*.R)
├── monitoring/           # Monitoring scripts (monitor_*.R)
├── testing/              # Test scripts (test_*.R, run_*.R)
├── debugging/            # Debug scripts (debug_*.R)
└── utilities/            # Helper scripts

docs/                      # ALL documentation
├── reports/              # Analysis reports (*.md)
├── summaries/            # Summary documents
├── specifications/       # Technical specs
└── notes/                # Meeting notes, observations

config/                    # ALL configuration files
├── *.yml                 # YAML configs
├── *.yaml                # YAML configs
└── *.json                # JSON configs

tests/                     # Formal test suite
├── testthat/             # Unit tests
├── test_data/            # Test datasets
└── test_results/         # Test output files

results/                   # ALL output files
├── *.csv                 # Result CSVs
├── *.RData               # R data files
└── *.rds                 # R serialized objects

logs/                      # ALL log files
├── *.log                 # Text logs
├── *.sqlite              # Database logs
└── *.txt                 # Debug output
```

### BEFORE CREATING ANY FILE:
1. **STOP** - Ask: "Where does this file belong?"
2. **CHECK** - Does the directory exist? If not, create it
3. **PLACE** - Put the file in the correct location
4. **NEVER** - Save to root unless it's in the allowed list above

### EXAMPLES:
```r
# ❌ WRONG - Never do this:
write.csv(results, "analysis_results.csv")
source("test_script.R")

# ✅ CORRECT - Always do this:
write.csv(results, "results/analysis_results.csv")
source("scripts/testing/test_script.R")
```

### WHEN CREATING NEW FILES:
- Analysis script? → `scripts/analysis/`
- Test script? → `scripts/testing/`
- Report/summary? → `docs/reports/`
- Configuration? → `config/`
- Data output? → `results/`
- Log file? → `logs/`

### CLEANUP CHECK:
After any work session, run:
```r
# Check for loose files in root
root_files <- list.files(".", pattern = "\\.(R|r|csv|txt|log|yml|yaml)$")
if(length(root_files) > 0) {
  warning("LOOSE FILES IN ROOT: ", paste(root_files, collapse = ", "))
}

## Package Structure
```
nvdrs_ipv_detector/
├── R/
│   ├── data_input.R      # Read/validate CSV
│   ├── llm_interface.R   # LLM API wrapper
│   ├── ipv_detection.R   # Core detection logic
│   ├── validation.R      # Accuracy metrics
│   ├── reconciliation.R  # Combine LE/CME results
│   ├── output.R          # Export functions
│   └── zzz.R            # Package startup/namespace
├── inst/
│   └── prompts/
│       └── ipv_prompts.yml
├── config/
│   └── settings.yml
├── tests/
│   └── testthat/
│       ├── fixtures/     # Mock API responses
│       └── test-*.R      # One file per module
├── DESCRIPTION
├── NAMESPACE
└── README.md
```

## DESCRIPTION Requirements
```yaml
Package: nvdrsipvdetector  # No underscores in package names
Title: Detect IPV in NVDRS Narratives Using LLM APIs
Version: 0.1.0
Authors@R: person("First", "Last", email = "email@example.com", 
                  role = c("aut", "cre"))
Description: Processes NVDRS death investigation narratives to detect
    intimate partner violence indicators using local LLM APIs.
License: MIT + file LICENSE
Encoding: UTF-8
Roxygen: list(markdown = TRUE)
Imports:
    httr2 (>= 1.0.0),
    jsonlite,
    yaml,
    DBI,
    RSQLite,
    cli,
    glue
Suggests:
    testthat (>= 3.0.0),
    mockery,
    lintr,
    covr
Config/testthat/edition: 3
```

## Documentation Standards
```r
#' Process NVDRS Narratives for IPV Detection
#'
#' @param data Tibble with columns: IncidentID, NarrativeLE, NarrativeCME
#' @param config Path to config.yml file
#' @param validate Logical; compare against manual flags if present
#'
#' @return Tibble with IPV detection results
#' @export
#'
#' @examples
#' \dontrun{
#' results <- nvdrs_process_batch("data.csv", "config.yml")
#' }
```

## Namespace Management
```r
# R/zzz.R - Package initialization
#' @import DBI
#' @importFrom httr2 request req_body_json req_perform resp_body_json
#' @importFrom jsonlite parse_json toJSON
#' @importFrom cli cli_progress_bar cli_alert_warning
NULL

# NEVER use library() calls
# ALWAYS use pkg::function() or @importFrom
```

## Core Implementation

### Configuration (config/settings.yml)
```yaml
api:
  base_url: "${LM_STUDIO_URL:-http://192.168.10.22:1234/v1}"
  model: "${LLM_MODEL:-openai/gpt-oss-120b}"
  timeout: 30
  max_retries: 3
  
processing:
  batch_size: 50
  checkpoint_every: 100
  
weights:
  cme: 0.6
  le: 0.4
  threshold: 0.7

database:
  path: "logs/api_logs.sqlite"
```

### Database Schema (SQLite)
```sql
CREATE TABLE api_logs (
  request_id TEXT PRIMARY KEY,
  incident_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  prompt_type TEXT CHECK(prompt_type IN ('LE', 'CME')),
  prompt_text TEXT NOT NULL,
  raw_response TEXT,
  parsed_response TEXT,
  response_time_ms INTEGER,
  error TEXT
);

CREATE INDEX idx_incident ON api_logs(incident_id);
CREATE INDEX idx_timestamp ON api_logs(timestamp);
```

### Error Handling Priority
1. **Connection failures**: Exponential backoff with max 3 retries
2. **Malformed JSON**: Log raw response, return NA with warning
3. **Token limit**: Split narrative, process in chunks
4. **Missing narratives**: Skip with warning, continue processing
5. **Database locks**: Use immediate transactions with timeout

### Testing Requirements
```r
# tests/testthat/fixtures/mock_responses.R
mock_llm_response <- function(ipv_detected = TRUE) {
  list(
    ipv_detected = ipv_detected,
    confidence = 0.85,
    indicators = c("domestic", "ex-boyfriend"),
    rationale = "Mock response"
  )
}

# Test with:
# - Empty narratives
# - Malformed JSON responses  
# - API timeouts
# - Conflicting LE/CME results
# - Database write failures
```

### Performance Requirements
- Process 1000 narratives in < 10 minutes
- Memory usage < 1GB for 10,000 records
- Checkpoint every 100 records for recovery
- Log response time for each API call
- Cache duplicate narratives (use digest::digest)

### CI/CD (.github/workflows/R-CMD-check.yaml)
```yaml
on: [push, pull_request]
jobs:
  R-CMD-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: r-lib/actions/setup-r@v2
      - uses: r-lib/actions/setup-r-dependencies@v2
      - run: |
          R CMD build .
          R CMD check --as-cran *.tar.gz
      - run: Rscript -e 'covr::package_coverage()'
```

## Commands to Run
```bash
# Initial setup
usethis::create_package("nvdrs_ipv_detector")
usethis::use_testthat()
usethis::use_mit_license()

# Before each commit
devtools::check()
lintr::lint_package()
covr::package_coverage()  # Aim for >80%

# Testing
devtools::test()  # Run all tests
devtools::test_active_file()  # Test current file
```

## Known Issues to Handle
- LM Studio API sometimes returns incomplete JSON (use tryCatch)
- Some narratives exceed token limits (implement chunking)
- LE narratives often missing (handle gracefully, don't fail)
- API rate limiting can occur (implement backoff)
- SQLite locks under concurrent writes (use WAL mode)