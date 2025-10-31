# Exploratory Analysis Scripts

This directory contains exploratory data analysis scripts for the IPV detection project.

## Scripts Overview

### Data Quality Analysis
- **analyze_input_data_quality.R** - Basic analysis of missing data and duplicates in the raw Excel file
- **detailed_data_quality_analysis.R** - Comprehensive analysis including narrative lengths, site/year distributions
- **comprehensive_missing_analysis.R** - Analysis including placeholder text (e.g., "No report on file")
- **find_missing_both_narratives.R** - Extract examples of cases missing both LE and CME narratives
- **find_placeholder_examples.R** - Identify and categorize placeholder text patterns

### Production Monitoring
- **check_production_progress.R** - Monitor progress of the 20k production run, including detection rates

## Usage

Run scripts from the project root directory:
```bash
Rscript scripts/exploratory/analyze_input_data_quality.R
Rscript scripts/exploratory/check_production_progress.R
```

## Key Findings

### Input Data Quality (all_suicide_nar.xlsx)
- Total records: 20,946
- Duplicates: 6 (0.03%)
- Cases with both narratives: 9,629 (45.97%)
- Cases with at least one narrative: 17,602 (84.04%)
- Cases missing both narratives: 3,344 (15.96%)

### Missing Data Patterns
- CME narratives missing: 26.27% (including placeholders)
- LE narratives missing: 43.72% (including placeholders)
- Common placeholders: "No report on file", "Record not available", "Autopsy unavailable"

### Production Run Status
- Model: mlx-community/gpt-oss-120b
- Detection rate: ~6.8% (40/588 narratives processed)
- Processing speed: ~5 seconds per narrative
