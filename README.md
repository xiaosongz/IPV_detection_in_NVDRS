# IPV Detection in NVDRS

An automated system for detecting Intimate Partner Violence (IPV) indicators in National Violent Death Reporting System (NVDRS) narratives using AI/LLM models.

## Overview

This project analyzes death investigation narratives from medical examiners (CME) and law enforcement (LE) to identify potential IPV-related factors in suicide cases. It uses either OpenAI's GPT models or local Ollama models to process narratives and extract structured information about:

- Family/friend mentions
- Intimate partner mentions
- Violence indicators
- Substance abuse mentions
- IPV between intimate partners

## Features

- **Batch Processing**: Efficiently processes multiple narratives in batches
- **Intelligent Caching**: Avoids redundant API calls by caching results
- **Dual Model Support**: Choose between cloud-based (OpenAI) or local (Ollama) processing
- **Structured Output**: Provides detailed rationales and key facts for each classification
- **Resume Capability**: Automatically resumes from interruptions using checkpoints

## Installation

### Prerequisites

- R (version 4.0 or higher)
- RStudio (recommended)
- For OpenAI version: OpenAI API key
- For Ollama version: Access to Ollama server

### Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/IPV_detection_in_NVDRS.git
cd IPV_detection_in_NVDRS
```

2. Install required R packages:
```bash
Rscript R/requirements.R
```

3. Set up environment variables (for OpenAI version):
```bash
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
```

## Usage

### OpenAI Version

```bash
Rscript R/01_detect_ipv_openai.R
```

### Ollama Version (Local LLM)

```bash
Rscript R/02_detect_ipv_ollama.R
```

### Input Data Format

Place your Excel file with narratives in the `data-raw/` directory. The expected format includes:
- `incident_id`: Unique identifier for each case
- `narrativecme`: Medical examiner narrative
- `narrativele`: Law enforcement narrative

### Output

Results are saved to the `output/` directory as timestamped CSV files containing:
- Original narrative data
- IPV detection flags for each category
- Detailed rationales for classifications
- Key facts summary

## Project Structure

```
├── R/                      # R scripts
│   ├── 01_detect_ipv_openai.R
│   ├── 02_detect_ipv_ollama.R
│   └── requirements.R
├── data-raw/              # Input data files
├── data/                  # Processed data
├── output/                # Analysis results
├── cache/                 # API response cache
├── logs/                  # Processing logs
├── config/                # Configuration files
└── docs/                  # Additional documentation
```

## Configuration

### Batch Size
Adjust the `batch_size` variable in the scripts (default: 10-20 narratives per batch).

### API Settings
- **OpenAI**: Configure rate limits in the script if needed
- **Ollama**: Update the server URL in the script (default: `http://192.168.10.21:11434`)

## Caching System

The project implements an intelligent caching system that:
- Stores API responses to avoid redundant calls
- Organizes cache by timestamp and content hash
- Automatically loads cached results when re-running analyses

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- National Violent Death Reporting System (NVDRS) for the data structure
- OpenAI and Ollama communities for the LLM capabilities

## Contact

For questions or support, please open an issue on GitHub.