# nvdrsipvdetector

Detect IPV in NVDRS Narratives Using LLM APIs

## Installation

```r
devtools::install_local(".")
```

## Usage

```r
library(nvdrsipvdetector)

# Load configuration
config <- load_config("config/settings.yml")

# Process narratives
results <- nvdrs_process_batch("data.csv", config)

# Export results
export_results(results, "output.csv")
```

## Testing

```r
devtools::test()
```