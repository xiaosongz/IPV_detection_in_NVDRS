Task: Build an R package called nvdrs_ipv_detector that processes NVDRS death investigation narratives to detect intimate partner violence indicators using local LLM APIs.
STEP 1: Create Package Structure
Create an R package with the following structure:
nvdrs_ipv_detector/
├── R/
│   ├── data_input.R
│   ├── llm_interface.R
│   ├── ipv_detection.R
│   ├── validation.R
│   ├── reconciliation.R
│   └── output.R
├── inst/
│   └── prompts/
│       └── ipv_prompts.yml
├── config/
│   └── config.yml
├── tests/
│   └── testthat/
├── DESCRIPTION
├── NAMESPACE
└── README.md
STEP 2: Implement Data Input Module (R/data_input.R)
Create functions to:

Read CSV/excel files with columns: IncidentID, NarrativeLE, NarrativeCME, ipv_flag_LE, ipv_flag_CME
Handle missing narratives (some LE narratives will be empty)
Validate that IncidentID is present and unique
Create a function that combines or separates narratives as needed
Return a tibble ready for processing

STEP 3: Build LLM Interface (R/llm_interface.R)
Implement:

setup_lm_studio() function to configure connection to LM Studio API at http://192.168.10.24:1234/v1(better to be a variable can be change)
send_to_llm() function that sends POST requests with narrative and prompt
parse_llm_json() function to extract structured JSON response
retry_with_backoff() for handling API failures
Token counting and management functions

STEP 4: Create IPV Detection Engine (R/ipv_detection.R)
Build the core detection logic:

detect_ipv() main function that processes a single narrative
Separate detection functions for LE and CME narratives
Extract these indicators:

Relationship types (boyfriend, girlfriend, husband, wife, partner, ex-)
Violence indicators (domestic, abuse, violence, hit, assault)
Protection orders (restraining order, protective order, shelter)
Temporal proximity (recent, separation, divorce, argument)


Return structured output with: ipv_detected (boolean), confidence (0-1), indicators (list), rationale (text)

STEP 5: Implement Validation Module (R/validation.R)
Create validation functions:

compare_to_manual_flags() to check predictions against ipv_flag_LE and ipv_flag_CME
calculate_accuracy() for precision, recall, F1 scores
generate_confusion_matrix() for LE and CME separately
identify_disagreements() to find cases where LE and CME results differ

STEP 6: Build Reconciliation Logic (R/reconciliation.R)
Implement reconciliation for dual narratives:

reconcile_dual_narratives() to combine LE and CME results
Weight CME results slightly higher in disagreements
Handle cases with only one narrative available
Calculate combined confidence score
Return final IPV determination with agreement status

STEP 7: Create Output Module (R/output.R)
Build output functions:

format_results() to structure all results in a consistent tibble
save_results_csv() to export to CSV format
generate_summary_report() for overview statistics
create_audit_log() for processing metadata

STEP 8: Configure Prompts (inst/prompts/ipv_prompts.yml)
the system promts should be easy to change
Create YAML configuration with:
system_prompt: "You are analyzing death investigation narratives for intimate partner violence indicators. Return only valid JSON."

le_template: "Analyze this law enforcement narrative for IPV indicators. Look for relationships, violence, protection orders, and recent conflicts. Narrative: {narrative}"

cme_template: "Analyze this medical examiner narrative for IPV indicators. Consider medical history, prior injuries, and relationship context. Narrative: {narrative}"

output_format: 
  ipv_detected: boolean
  confidence: float
  indicators: array
  rationale: string

STEP 9: Main Pipeline Function
Create process_nvdrs_batch() in R/pipeline.R:

Accept input CSV path, output path, config file
Read and validate input data
Process each case through both LE and CME analysis
Reconcile dual narratives
If validation flags present, calculate performance metrics
Save results and generate report
Include progress bar for batch processing

STEP 10: Package Configuration
Set up DESCRIPTION file with dependencies:

tidyverse
httr2 (for API calls)
jsonlite
yaml
progress
logger

Create comprehensive documentation and examples in README.md
STEP 11: Error Handling
Implement robust error handling for:

Missing narratives
API connection failures
Malformed JSON responses
Invalid input data
Token limit exceeded

STEP 12: Testing
Create unit tests for:

Input validation
API connection
JSON parsing
IPV detection logic
Reconciliation logic
Output formatting

Key Implementation Requirements:

Process LE and CME narratives independently with separate prompts
Generate separate IPV flags for each narrative type
Include confidence scores for all predictions
Handle missing narratives gracefully
Support validation mode when manual flags are present
Maintain detailed logging throughout processing
Return structured JSON from LLM for reliable parsing
Implement retry logic for API failures
Support batch processing with configurable batch size
All the prompts send to LLM and raw response should be carefully logged in to database.
You can use a sqlite dabase to save the information

1. Database Schema and Logging Architecture
The SQLite database mention needs expansion:
yaml# Add detailed schema specification
tables:
  api_logs:
    - request_id (UUID)
    - incident_id
    - timestamp
    - prompt_type (LE/CME)
    - prompt_text
    - raw_response
    - parsed_response
    - token_count
    - response_time_ms
    - error_status
  
  processing_runs:
    - run_id
    - start_time
    - end_time
    - total_cases
    - success_count
    - config_hash
    - model_version
2. Configuration Management Enhancement
Expand the config.yml structure:
yaml# config/config.yml
api:
  base_url: "http://192.168.10.24:1234/v1"
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
3. Enhanced Reconciliation Logic
Replace vague "weight CME slightly higher" with:
r# R/reconciliation.R
reconcile_dual_narratives <- function(le_result, cme_result) {
  # Weighted voting with configurable weights
  # If both agree: high confidence
  # If disagree: use weighted average
  # Include agreement_score metric
  # Handle edge cases (one missing, both low confidence)
}

4. Performance Optimization
Add these modules:

Parallel Processing: Use future and furrr for parallel narrative processing(no need to prototype on local LLM)
Caching Layer: Implement response caching with memoise to avoid duplicate API calls
Checkpoint System: Save progress every N records for recovery from failures
Memory Management: Process in chunks with explicit garbage collection

Begin by creating the package structure and implementing the data input module. Then proceed through each module in order, testing as you go.