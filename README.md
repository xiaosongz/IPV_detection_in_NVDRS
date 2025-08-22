# NVDRS IPV Detector

An R package for detecting intimate partner violence (IPV) indicators in National Violent Death Reporting System (NVDRS) narratives using local Large Language Model APIs.

## Overview

This package processes death investigation narratives from law enforcement (LE) and coroner/medical examiner (CME) reports to identify patterns and indicators of intimate partner violence. It leverages local LLM APIs (like LM Studio) to analyze text while maintaining data privacy.

## Features

- Dual narrative processing (LE and CME independently)
- Configurable LLM integration with local APIs
- Weighted reconciliation of conflicting results
- SQLite database logging for audit trails
- Validation against manual IPV flags
- Batch processing with checkpointing
- Comprehensive error handling and retry logic

## Installation

```r
# Install from GitHub
devtools::install_github("yourusername/nvdrs_ipv_detector")

# Or build from source
devtools::install()
```

## Quick Start

```r
library(nvdrsipvdetector)

# Configure API connection
config <- setup_lm_studio(
  base_url = "http://192.168.10.22:1234/v1",
  model = "openai/gpt-oss-120b"
)

# Process narratives
results <- nvdrs_process_batch(
  input_file = "data/narratives.csv",
  output_file = "results/ipv_detected.csv",
  config = config
)

# View summary
summary(results)
```

## Implementation Guide

### STEP 1: Create Package Structure

The package follows standard R package conventions with the following structure:

```
nvdrs_ipv_detector/
├── R/
│   ├── data_input.R      # Data reading and validation
│   ├── llm_interface.R   # LLM API communication
│   ├── ipv_detection.R   # Core detection algorithms
│   ├── validation.R      # Accuracy metrics
│   ├── reconciliation.R  # Combine LE/CME results
│   ├── output.R          # Export functions
│   └── zzz.R            # Package initialization
├── inst/
│   └── prompts/
│       └── ipv_prompts.yml
├── config/
│   └── settings.yml
├── tests/
│   └── testthat/
│       ├── fixtures/
│       └── test-*.R
├── DESCRIPTION
├── NAMESPACE
└── README.md
```

### STEP 2: Data Input Module (R/data_input.R)

Functions to handle narrative data:

- **read_nvdrs_data()**: Read CSV/Excel files with required columns
  - IncidentID (unique identifier)
  - NarrativeLE (law enforcement narrative)
  - NarrativeCME (medical examiner narrative)
  - ipv_flag_LE (optional validation flag)
  - ipv_flag_CME (optional validation flag)

- **validate_input()**: Check data integrity
  - Ensure IncidentID is unique
  - Handle missing narratives gracefully
  - Validate column presence

- **prepare_narratives()**: Format for processing
  - Combine or separate narratives as needed
  - Apply text cleaning (trimws, encoding fixes)
  - Return tibble ready for analysis

### STEP 3: LLM Interface (R/llm_interface.R)

API communication layer:

- **setup_lm_studio()**: Configure connection
  - Base URL: `http://192.168.10.22:1234/v1` (configurable)
  - Model: `openai/gpt-oss-120b` (configurable)
  - Authentication if required

- **send_to_llm()**: POST requests with narratives
  - Format prompts with templates
  - Handle request/response cycle
  - Implement timeout controls

- **parse_llm_json()**: Extract structured responses
  - Validate JSON structure
  - Handle malformed responses
  - Extract key fields

- **retry_with_backoff()**: Fault tolerance
  - Exponential backoff strategy
  - Maximum 3 retry attempts
  - Log all attempts

- **count_tokens()**: Token management
  - Estimate token usage
  - Split long narratives if needed
  - Track usage for billing

### STEP 4: IPV Detection Engine (R/ipv_detection.R)

Core detection logic:

- **detect_ipv()**: Main processing function
  - Process single narrative
  - Return structured results

- **detect_ipv_le()**: Law enforcement specific
- **detect_ipv_cme()**: Medical examiner specific

Indicators to extract:
- **Relationship types**: boyfriend, girlfriend, husband, wife, partner, ex-
- **Violence indicators**: domestic, abuse, violence, hit, assault
- **Protection orders**: restraining order, protective order, shelter
- **Temporal proximity**: recent, separation, divorce, argument

Output structure:
```r
list(
  ipv_detected = TRUE/FALSE,
  confidence = 0.0-1.0,
  indicators = c("domestic", "ex-boyfriend"),
  rationale = "Explanation text"
)
```

### STEP 5: Validation Module (R/validation.R)

Performance measurement:

- **compare_to_manual_flags()**: Check accuracy
  - Compare predictions to ipv_flag_LE/CME
  - Calculate agreement rates

- **calculate_accuracy()**: Performance metrics
  - Precision, recall, F1 scores
  - Separate metrics for LE and CME

- **generate_confusion_matrix()**: Detailed analysis
  - True/false positives and negatives
  - Separate matrices for each narrative type

- **identify_disagreements()**: Find conflicts
  - Cases where LE and CME disagree
  - Pattern analysis of disagreements

### STEP 6: Reconciliation Logic (R/reconciliation.R)

Combine dual narrative results:

- **reconcile_dual_narratives()**: Merge LE/CME
  - Weighted voting (CME weight: 0.6, LE: 0.4)
  - Handle single narrative cases
  - Calculate combined confidence

- **calculate_agreement()**: Agreement metrics
  - Perfect agreement, partial agreement, conflict
  - Weight by confidence scores

- **handle_missing()**: Missing narrative logic
  - Use available narrative
  - Adjust confidence accordingly

### STEP 7: Output Module (R/output.R)

Results formatting and export:

- **format_results()**: Structure output
  - Consistent tibble format
  - Include all metadata

- **save_results_csv()**: Export to CSV
  - Configurable output path
  - Include timestamp

- **generate_summary_report()**: Overview statistics
  - Total cases processed
  - IPV detection rates
  - Performance metrics if validation available

- **create_audit_log()**: Processing metadata
  - Timestamps, model versions
  - Error counts, retry attempts

### STEP 8: Prompt Configuration (inst/prompts/ipv_prompts.yml)

YAML configuration for prompts:

```yaml
system_prompt: |
  You are analyzing death investigation narratives for intimate partner 
  violence indicators. Return only valid JSON.

le_template: |
  Analyze this law enforcement narrative for IPV indicators. 
  Look for relationships, violence, protection orders, and recent conflicts.
  Narrative: {narrative}

cme_template: |
  Analyze this medical examiner narrative for IPV indicators. 
  Consider medical history, prior injuries, and relationship context.
  Narrative: {narrative}

output_format:
  ipv_detected: boolean
  confidence: float
  indicators: array
  rationale: string
```

### STEP 9: Main Pipeline Function (R/pipeline.R)

Orchestrate the complete workflow:

```r
nvdrs_process_batch <- function(input_path, output_path, config_file) {
  # 1. Load configuration
  # 2. Read and validate input data
  # 3. Initialize database connection
  # 4. Process each case:
  #    - Send LE narrative to LLM
  #    - Send CME narrative to LLM
  #    - Reconcile results
  #    - Log to database
  # 5. Calculate validation metrics if flags present
  # 6. Save results and generate report
  # 7. Show progress bar throughout
}
```

### STEP 10: Package Dependencies

Configure DESCRIPTION file:

```yaml
Imports:
  httr2 (>= 1.0.0),    # API calls
  jsonlite,            # JSON parsing
  yaml,                # Configuration
  DBI,                 # Database interface
  RSQLite,             # SQLite
  cli,                 # Progress bars
  glue,                # String interpolation
  digest               # Caching

Suggests:
  testthat (>= 3.0.0),
  mockery,
  lintr,
  covr
```

### STEP 11: Error Handling

Robust error management for:

1. **Missing narratives**: Skip with warning, continue batch
2. **API connection failures**: Retry with exponential backoff
3. **Malformed JSON responses**: Log raw response, use NA
4. **Invalid input data**: Validation with clear error messages
5. **Token limit exceeded**: Split narrative into chunks

### STEP 12: Testing Strategy

Comprehensive test coverage:

- **Unit tests** for each module
- **Integration tests** for pipeline
- **Mock API responses** for offline testing
- **Edge cases**: Empty narratives, special characters
- **Performance tests**: Large batch processing

## Database Schema

All API interactions are logged to SQLite:

```sql
CREATE TABLE api_logs (
  request_id TEXT PRIMARY KEY,
  incident_id TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  prompt_type TEXT CHECK(prompt_type IN ('LE', 'CME')),
  prompt_text TEXT NOT NULL,
  raw_response TEXT,
  parsed_response TEXT,
  token_count INTEGER,
  response_time_ms INTEGER,
  error_status TEXT
);

CREATE TABLE processing_runs (
  run_id TEXT PRIMARY KEY,
  start_time INTEGER,
  end_time INTEGER,
  total_cases INTEGER,
  success_count INTEGER,
  config_hash TEXT,
  model_version TEXT
);
```

## Configuration

Main configuration file (config/settings.yml):

```yaml
api:
  base_url: "http://192.168.10.22:1234/v1"
  timeout: 30
  max_retries: 3
  rate_limit: 10  # requests per second

model:
  name: "llama-3.1-8b"
  temperature: 0.1
  max_tokens: 1000

processing:
  batch_size: 50
  parallel_workers: 4
  cache_responses: true
  checkpoint_frequency: 100

weights:
  cme_weight: 0.6
  le_weight: 0.4
  confidence_threshold: 0.7

database:
  path: "logs/api_logs.sqlite"
```

## Performance Optimization

- **Parallel Processing**: Use future/furrr for concurrent narratives
- **Caching**: memoise package to avoid duplicate API calls
- **Checkpointing**: Save progress every 100 records
- **Memory Management**: Process in chunks with garbage collection
- **Response caching**: Use digest::digest for deduplication

## Key Implementation Requirements

1. Process LE and CME narratives independently with separate prompts
2. Generate separate IPV flags for each narrative type
3. Include confidence scores for all predictions
4. Handle missing narratives gracefully
5. Support validation mode when manual flags are present
6. Maintain detailed logging throughout processing
7. Return structured JSON from LLM for reliable parsing
8. Implement retry logic for API failures
9. Support batch processing with configurable batch size
10. Log all prompts and raw responses to database

## Development Workflow

```bash
# Create package
usethis::create_package("nvdrs_ipv_detector")

# Set up testing
usethis::use_testthat()
usethis::use_test("data_input")

# Add license
usethis::use_mit_license()

# Document
devtools::document()

# Check package
devtools::check()

# Run tests
devtools::test()

# Check coverage
covr::package_coverage()
```

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- NVDRS for providing the data structure specifications
- LM Studio team for local LLM capabilities
- R community for excellent package development tools