# nvdrsipvdetector

An R package for detecting intimate partner violence (IPV) indicators in NVDRS (National Violent Death Reporting System) narratives using Large Language Model APIs.

## Features

- 🔍 Automated IPV detection in law enforcement and medical examiner narratives
- 🤖 Compatible with any OpenAI-compatible API (LM Studio, Ollama, etc.)
- 📊 Confidence scoring and indicator extraction
- 🔄 Batch processing with automatic checkpointing
- 📈 Validation metrics and accuracy reporting
- 💾 SQLite logging for API request tracking

## Installation

```r
# Install from local directory
devtools::install_local("path/to/nvdrsipvdetector")

# Or install from GitHub (if available)
# devtools::install_github("username/nvdrsipvdetector")
```

## Quick Start

### 1. Initial Setup

```r
library(nvdrsipvdetector)

# Create a configuration file in your project
init_config()  # Creates settings.yml in current directory
```

### 2. Configure Your LLM

Edit `settings.yml` to match your LLM setup:

```yaml
api:
  base_url: "http://localhost:1234/v1"  # Your LM Studio/Ollama server
  model: "your-model-name"              # Your model
  temperature: 0.1                      # Lower = more consistent
  max_tokens: 1000                      # Adjust based on needs
```

### 3. Process Narratives

```r
# Simple detection for single narrative
result <- detect_ipv("Domestic violence incident involving ex-boyfriend")
print(result$ipv_detected)  # TRUE
print(result$confidence)    # 0.95

# Process CSV file with batch detection
results <- nvdrs_process_batch(
  data_path = "your_data.csv",  # Must have: IncidentID, NarrativeLE, NarrativeCME
  config = "settings.yml"        # Optional: uses default search if not specified
)

# Export results
export_results(results, "ipv_detection_results.csv")
```

## Core Functions

### Individual Detection

```r
# Detect IPV in a single narrative
result <- detect_ipv(
  narrative = "Text to analyze",
  type = "LE",        # "LE" for law enforcement, "CME" for medical examiner
  config = NULL       # Uses default config search
)
```

### Batch Processing

```r
# Process multiple narratives from CSV
results <- nvdrs_process_batch(
  data_path = "input.csv",
  config = NULL,              # Auto-searches for settings.yml
  validate = TRUE,            # Compare with manual flags if present
  batch_size = 50            # Process in chunks
)
```

### Validation

```r
# Calculate accuracy metrics if manual flags exist
metrics <- calculate_metrics(results)
print_validation_report(metrics)
```

## Configuration

### Configuration Search Order

The package searches for `settings.yml` in this order:
1. Path explicitly provided to function
2. Current working directory (`./settings.yml`)
3. Package installation directory (read-only defaults)

### Environment Variables

You can override settings using environment variables:

```r
# In R
Sys.setenv(LM_STUDIO_URL = "http://192.168.1.100:1234/v1")
Sys.setenv(LLM_MODEL = "my-custom-model")

# Or in .Renviron
LM_STUDIO_URL=http://192.168.1.100:1234/v1
LLM_MODEL=my-custom-model
```

## Input Data Format

Your CSV file should have these columns:
- `IncidentID`: Unique identifier for each case
- `NarrativeLE`: Law enforcement narrative (can be empty)
- `NarrativeCME`: Medical examiner narrative (can be empty)
- `ManualIPVFlag` (optional): For validation (0/1 or TRUE/FALSE)

## Output Format

The results include:
- `IncidentID`: Original incident identifier
- `ipv_detected`: Boolean indicator
- `confidence`: Confidence score (0-1)
- `indicators`: Detected IPV indicators
- `rationale`: Explanation of detection
- `le_ipv`, `cme_ipv`: Individual narrative results
- `final_ipv`: Reconciled result using weighted combination

## Logging

API requests are automatically logged to SQLite database:
- Default location: `logs/api_logs.sqlite`
- Includes prompts, responses, timing, and errors
- Useful for debugging and audit trails

## Testing

```r
# Run all tests
devtools::test()

# Run specific test file
devtools::test_active_file()

# Check package
devtools::check()
```

## Troubleshooting

### Common Issues

1. **Connection refused error**
   - Ensure your LLM server is running
   - Check the `base_url` in settings.yml
   - Verify firewall settings

2. **Malformed JSON responses**
   - Lower the temperature in settings.yml
   - Ensure your model supports JSON output
   - Check model's system prompt compliance

3. **Memory issues with large datasets**
   - Reduce `batch_size` in settings.yml
   - Process data in smaller chunks
   - Use checkpoint_every setting for recovery

4. **Token limit errors**
   - Reduce `max_tokens` in settings.yml
   - Consider splitting long narratives
   - Use a model with larger context window

## Requirements

- R >= 4.0.0
- Required packages: httr2, jsonlite, yaml, DBI, RSQLite, cli, glue
- LLM API server (LM Studio, Ollama, or OpenAI-compatible)

## License

MIT License - see LICENSE file for details

## Support

For issues or questions:
- Check the [package documentation](man/)
- Review [test examples](tests/testthat/)
- Open an issue on GitHub