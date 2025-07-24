# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an IPV (Intimate Partner Violence) detection system that analyzes death investigation narratives from NVDRS (National Violent Death Reporting System) using AI/LLM models to identify IPV-related indicators.

## Key Architecture

### Processing Pipeline
1. **Input**: Excel files containing CME (medical examiner) and LE (law enforcement) narratives
2. **Processing**: Batch analysis using either OpenAI API or local Ollama models
3. **Caching**: Results cached to `/cache/` directory to avoid redundant API calls
4. **Output**: Timestamped CSV files with IPV detection flags and rationales

### Main Scripts
- `R/01_detect_ipv_openai.R` - OpenAI-based processing (requires API key in .env)
- `R/02_detect_ipv_ollama.R` - Local Ollama processing (connects to http://192.168.10.21:11434)

## Development Commands

### Setup
```bash
# Install R dependencies
Rscript R/requirements.R

# Set up environment variables (for OpenAI version)
cp .env.example .env  # Then add your OPENAI_API_KEY
```

### Running the Detection
```bash
# OpenAI version
Rscript R/01_detect_ipv_openai.R

# Ollama local version
Rscript R/02_detect_ipv_ollama.R
```

### Common Tasks
- **Adjust batch size**: Modify `batch_size` variable in scripts (default: 10-20)
- **Change input file**: Update `file_path` variable to point to your Excel file
- **Monitor progress**: Check console output for batch processing status
- **Resume interrupted runs**: Scripts automatically use cached results

## Code Structure

### Project Structure
```
├── R/                      # R scripts
├── data-raw/              # Raw input data
├── data/                  # Processed data
├── output/                # Analysis results
│   ├── figures/           # Plots
│   ├── tables/            # CSV results
│   └── reports/           # Reports
├── cache/                 # API response cache
├── logs/                  # Processing logs
└── config/                # Configuration
```

### Key Functions
- `process_batch()` - Processes a batch of narratives through the AI model
- `extract_json_from_response()` - Parses AI responses into structured data
- `create_cache_key()` - Generates unique keys for caching
- `save_checkpoint()` / `load_checkpoint()` - Manages processing state

### Data Flow
1. Excel → R dataframe
2. Narratives → AI prompts (batched)
3. AI responses → Parsed JSON
4. JSON → Structured dataframe with IPV flags
5. Results → CSV/Excel output files

## Important Notes

- **API Rate Limits**: OpenAI version implements rate limiting (adjust `limit_rate()` parameters if needed)
- **Caching**: Always preserves previous results - safe to re-run scripts
- **Batch Processing**: Processes 10-20 narratives per API call for efficiency
- **Error Handling**: Scripts continue processing even if individual batches fail
- **Local Model**: Ollama version requires Ollama server running on specified IP/port