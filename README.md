# NVDRS IPV Detector

An R package for detecting intimate partner violence (IPV) indicators in National Violent Death Reporting System (NVDRS) narratives using Large Language Model APIs.

## 📊 Current Status

- **Package Version**: 0.1.0 (Development)
- **Test Coverage**: 0% (needs fixing - tests exist but don't call package functions)
- **API Integration**: ✅ Working with LM Studio
- **Accuracy**: 70% on test sample (289 records available for validation)
- **Performance**: ~38,000 records/second theoretical throughput

### Test Results Summary
- **R CMD Check**: ✅ 0 errors, 0 warnings, 0 notes
- **Unit Tests**: 54 tests (all pass but need fixing for coverage)
- **LLM Integration**: Successfully tested with OpenAI's gpt-oss-120b model
- **Validation Dataset**: `sui_all_flagged.xlsx` with manual IPV flags

## 🚀 Installation

```r
# Install from local directory
devtools::install("nvdrsipvdetector")

# Or install directly from the package directory
setwd("nvdrsipvdetector")
devtools::install()
```

## 🔧 Configuration

### 1. Set up LM Studio

Ensure LM Studio is running with your preferred model:
```bash
# Default endpoint: http://192.168.10.22:1234/v1
# Tested models:
# - openai/gpt-oss-120b (recommended)
# - qwen/qwen3-30b-a3b-2507
```

### 2. Configure Environment Variables

```r
# Set your LLM API endpoint
Sys.setenv(LM_STUDIO_URL = "http://192.168.10.22:1234/v1")
Sys.setenv(LLM_MODEL = "openai/gpt-oss-120b")
```

### 3. Edit Configuration File

The package uses `config/settings.yml` for configuration:
```yaml
api:
  base_url: "${LM_STUDIO_URL:-http://192.168.10.22:1234/v1}"
  model: "${LLM_MODEL:-openai/gpt-oss-120b}"
  timeout: 30
  max_retries: 3
  
processing:
  batch_size: 50
  checkpoint_every: 100
```

## 📖 Usage Examples

### Basic Usage

```r
library(nvdrsipvdetector)

# Load and process NVDRS data
data <- read_nvdrs_data("path/to/your/data.csv")

# Process narratives for IPV detection
results <- nvdrs_process_batch(
  data = data,
  config_file = "config/settings.yml"
)

# Export results
export_results(results, "output/ipv_results.csv", format = "csv")
```

### Step-by-Step Processing

```r
library(nvdrsipvdetector)
library(readxl)

# 1. Load your NVDRS data
# Can be CSV or Excel format
data <- read_excel("data/sui_all_flagged.xlsx")

# 2. Validate and clean the data
validated_data <- validate_input_data(data)
# This removes empty narratives and ensures required columns exist

# 3. Process individual narratives
# For Law Enforcement narrative
le_result <- detect_ipv(
  narrative = data$NarrativeLE[1],
  narrative_type = "LE"
)

# For Coroner/Medical Examiner narrative  
cme_result <- detect_ipv(
  narrative = data$NarrativeCME[1],
  narrative_type = "CME"
)

# 4. Reconcile LE and CME results
final_result <- reconcile_le_cme(
  le_result = le_result,
  cme_result = cme_result,
  weights = list(le = 0.4, cme = 0.6)
)

# 5. View the results
print(final_result)
```

### Batch Processing with Validation

```r
# If you have manual IPV flags for validation
data_with_flags <- read_excel("data/sui_all_flagged.xlsx")

# Process in batches
batches <- split_into_batches(data_with_flags, batch_size = 50)

all_results <- list()
for (i in seq_along(batches)) {
  batch <- batches[[i]]
  
  # Process each narrative
  batch_results <- lapply(1:nrow(batch), function(j) {
    row <- batch[j, ]
    
    le_result <- if (!is.na(row$NarrativeLE)) {
      detect_ipv(row$NarrativeLE, "LE")
    } else {
      list(ipv_detected = NA, confidence = NA)
    }
    
    cme_result <- if (!is.na(row$NarrativeCME)) {
      detect_ipv(row$NarrativeCME, "CME")
    } else {
      list(ipv_detected = NA, confidence = NA)
    }
    
    reconcile_le_cme(le_result, cme_result)
  })
  
  all_results <- c(all_results, batch_results)
  
  # Progress message
  cat(sprintf("Processed batch %d/%d\n", i, length(batches)))
}

# Validate against manual flags if available
if ("ipv_flag_LE" %in% names(data_with_flags)) {
  validation <- validate_results(
    results = all_results,
    ground_truth = data_with_flags
  )
  
  print_validation_report(validation)
}
```

### Testing the LLM Connection

```r
library(httr2)
library(jsonlite)

# Test basic connectivity
test_llm_connection <- function() {
  response <- request("http://192.168.10.22:1234/v1/chat/completions") |>
    req_headers("Content-Type" = "application/json") |>
    req_body_json(list(
      model = "openai/gpt-oss-120b",
      messages = list(
        list(role = "user", content = "Say 'Connected' if you receive this")
      ),
      temperature = 0.1,
      max_tokens = 50
    )) |>
    req_timeout(10) |>
    req_perform()
  
  result <- resp_body_json(response)
  return(result$choices[[1]]$message$content)
}

# Run the test
test_llm_connection()
# Should return: "Connected"
```

## 📁 Data Format

### Input Data Requirements

Your input data should have the following columns:
- `IncidentID`: Unique identifier for each case
- `NarrativeLE`: Law enforcement narrative text
- `NarrativeCME`: Coroner/Medical examiner narrative text

Optional validation columns:
- `ipv_flag_LE`: Manual IPV flag for LE narrative (TRUE/FALSE)
- `ipv_flag_CME`: Manual IPV flag for CME narrative (TRUE/FALSE)

### Output Format

The package returns results with:
```r
list(
  incident_id = "12345",
  ipv_detected = TRUE,
  confidence = 0.85,
  indicators = c("domestic violence", "ex-boyfriend", "restraining order"),
  le_result = list(...),  # Detailed LE analysis
  cme_result = list(...), # Detailed CME analysis
  rationale = "Evidence of domestic violence history..."
)
```

## 🧪 Testing

```r
# Run all tests
devtools::test()

# Check package
devtools::check()

# Test coverage (currently needs fixing)
covr::package_coverage()

# Run integration test with real LLM
source("test_llm_api.R")
```

## ⚠️ Known Issues

1. **Test Coverage**: Tests exist but don't properly call package functions (0% coverage)
2. **Function Interfaces**: Some functions have parameter mismatches that need fixing
3. **JSON Parsing**: LLM responses sometimes include extra tokens that need cleaning
4. **File Format**: Package assumes CSV input but test data is Excel format

## 🛠️ Development Roadmap

- [ ] Fix test coverage issue (make tests actually call package functions)
- [ ] Standardize function interfaces and parameters
- [ ] Add robust JSON parsing with error handling
- [ ] Support both CSV and Excel formats seamlessly
- [ ] Implement proper checkpointing for large datasets
- [ ] Add progress bars for batch processing
- [ ] Create vignettes with detailed examples
- [ ] Add more comprehensive error messages
- [ ] Implement caching to avoid redundant API calls
- [ ] Add support for multiple LLM providers

## 📄 License

MIT License - See LICENSE file for details

## 👥 Contributing

Please report issues or submit pull requests on GitHub.

## 📚 References

- National Violent Death Reporting System (NVDRS)
- LM Studio Documentation
- R Package Development Guide

## 🙏 Acknowledgments

This package was developed to assist researchers in identifying intimate partner violence patterns in death investigation narratives, contributing to public health surveillance and prevention efforts.